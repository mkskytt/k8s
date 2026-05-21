# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Flux CD-managed Kubernetes cluster configuration. There is no application code, build, or test suite — every file is a Kubernetes manifest (YAML) that Flux applies to the live cluster. Changes ship by committing to `main`; Flux reconciles them automatically.

The cluster runs k3s on Hetzner Cloud, provisioned by [`hetzner-k3s`](https://github.com/vitobotta/hetzner-k3s) from `cluster.yaml` at the repo root (3× cx23 masters in `nbg1`, Flannel CNI, workloads scheduled on masters). The CNI is configured at provision time — there is no Flux-managed CNI app. The Kubernetes API is reached at `https://k8s.ytt.io:6443` (DNS A record + `api_server_hostname` adds the SAN at provision time; the LB IP fronts all 3 masters).

⚠️ `cluster.yaml` contains a Hetzner API token in plaintext and is not gitignored. Don't commit it as-is; before any push, verify it isn't staged (`git status`) or move the token out of the file.

The `kubernetes.azure.com/set-kube-service-host-fqdn` annotations in `cluster/apps/grafana-alloy/helmrelease.yaml` are vestigial cargo-culted defaults from the upstream Grafana k8s-monitoring chart and have no effect outside AKS — leave them; they're harmless.

## Architecture

Three-tier Kustomization hierarchy, all driven by Flux:

1. `cluster/flux-system/gotk-sync.yaml` — top-level `flux-system` Kustomization. Watches the `main` branch of `github.com/mkskytt/k8s`, reconciles `./cluster` every 10m with SOPS decryption enabled.
2. `cluster/apps.yaml` — child `apps` Kustomization. Points at `./cluster/apps`, reconciles every 30s, prunes deleted resources, decrypts via the same `sops-age` secret.
3. `cluster/apps/<app>/kustomization.yaml` — leaf Kustomizations that list the manifests for each application.

`cluster/apps/<app>/` is the only place applications live. Every app follows the same shape:

- `namespace.yaml` — the app's namespace
- `helmrelease.yaml` — usually a `HelmRepository` + `HelmRelease` pair (Flux Helm controller). Some apps (`demo-app`, `podinfo`) ship plain `Deployment`/`Service` manifests instead, despite the filename.
- `kustomization.yaml` — lists the files above
- `*.sops.yaml` — SOPS-encrypted Secrets (optional)

To add a new app: create `cluster/apps/<name>/` with the four files above. The parent `apps` Kustomization discovers it automatically via Kustomize directory traversal — no edits to `cluster/apps.yaml` or any index file are needed.

## SOPS / Age encryption

`.sops.yaml` declares the rule: any file under `cluster/apps/` matching `*.yaml` gets the `data` and `stringData` fields encrypted with the Age recipient declared in that file. The private key lives only in the cluster as the `sops-age` secret in the `flux-system` namespace; Flux uses it at reconcile time. The matching private key for local edits is at `~/.config/sops/age/keys.txt`.

Convention: encrypted files use the `.sops.yaml` suffix (e.g. `cloudflare-api-token.sops.yaml`). The `.sops.yaml` suffix is convention only — SOPS itself decides what to encrypt based on the path/regex rule, so any `*.yaml` under `cluster/apps/` with `data`/`stringData` will be encrypted when you run `sops --encrypt`.

Edit an existing encrypted secret in place:

```bash
sops cluster/apps/<app>/<file>.sops.yaml
```

Create a new encrypted secret:

```bash
kubectl create secret generic my-secret \
    --from-literal=key=value \
    --dry-run=client -o yaml > cluster/apps/<app>/my-secret.sops.yaml
sops --encrypt --in-place cluster/apps/<app>/my-secret.sops.yaml
```

Then add it to the app's `kustomization.yaml` `resources:` list.

## Local validation (no test suite exists)

Before pushing, sanity-check that Flux will accept the changes:

```bash
# Render and validate the apps Kustomization without applying
kustomize build cluster/apps/<app>

# Validate the whole tree the way Flux will
kustomize build --enable-helm cluster

# Server-side dry run against the live cluster
kubectl apply --dry-run=server -k cluster/apps/<app>
```

There is no linter or formatter configured — match the existing two-space-indent YAML style.

## Observing Flux

```bash
flux get kustomizations              # status of all Kustomizations
flux get helmreleases -A             # status of every HelmRelease
flux logs --follow                   # live reconciliation logs
flux reconcile kustomization apps    # force immediate reconcile of cluster/apps
flux reconcile helmrelease <name> -n <ns>
```

When a change doesn't appear in-cluster after ~30s, start with `flux get kustomizations` (look for `Ready=False` / message column) before reaching for `kubectl`.

## Conventions to preserve

- **Domain**: `ytt.io`. External DNS is filtered to this zone (`cluster/apps/external-dns/helmrelease.yaml`), so any new Ingress must use a hostname under it.
- **Cloudflare Tunnel target**: tunnel ID `31e83007-176a-4a06-8363-e99d39271e55` (see `cloudflare-tunnel/helmrelease.yaml`). New public services need an entry in that HelmRelease's `ingress:` list plus an Ingress with `external-dns.alpha.kubernetes.io/target: <tunnel-id>.cfargotunnel.com` — see `cluster/apps/demo-app/ingress.yaml` for the pattern. There is no public LoadBalancer; all external traffic enters via this tunnel.
- **Pinning vs. ranges**: secret-handling charts (`external-dns`, `cloudflare-tunnel`) pin exact versions; supporting infrastructure (`keda`, `kyverno`, `grafana-k8s-monitoring`) uses `>=` ranges. Follow the existing pattern of the app you're touching rather than changing it.
- **Helm reconcile intervals**: 5m for ingress/DNS-critical releases, 30m for everything else. Sources (`HelmRepository`) poll at 10m. Don't tighten these without reason — Flux already detects Git changes within ~30s via the `apps` Kustomization.
