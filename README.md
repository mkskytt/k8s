# ytt.io — Kubernetes cluster

GitOps configuration for my Kubernetes cluster: [k3s](https://k3s.io/) on
Hetzner Cloud, managed by [Flux CD](https://fluxcd.io/). This describes one
specific cluster — it is **not** a reusable template, so the hostnames, domain,
and infrastructure IDs in here are the real values for this setup.

## Stack

- **k3s on Hetzner Cloud**, provisioned by [hetzner-k3s](https://github.com/vitobotta/hetzner-k3s)
  from `cluster.yaml` — 3× cx23 masters in `nbg1` plus a 1× cx23 worker in
  `fsn1` (for a cross-zone Postgres replica), Flannel CNI, workloads scheduled
  on the masters. The API is fronted by a Hetzner load balancer at
  `k8s.ytt.io:6443`; SSH and the API are firewalled to a single admin IP.
- **Flux CD** reconciles everything under `cluster/` from the `main` branch.
- **SOPS + age** for encrypted secrets.
- **external-dns + Cloudflare** manage DNS on the `ytt.io` zone.
- **Cloudflare Tunnel** provides ingress — there is no public load balancer.
- **Grafana Alloy** ships metrics, logs, traces, and profiles to Grafana Cloud.
- **CloudNativePG** runs PostgreSQL.
- **Kyverno** enforces the baseline Pod Security Standards cluster-wide.
- **motorinfo** — a demo web + API app backed by a CNPG database, served at
  `motorinfo.ytt.io`.

## Layout

```
cluster/
├── flux-system/            # Flux components + sync (bootstrap-managed)
├── apps/                   # One directory per application
│   ├── cloudflare-tunnel/  # Ingress via Cloudflare Tunnel
│   ├── cnpg/               # CloudNativePG operator
│   ├── external-dns/       # Cloudflare DNS sync
│   ├── grafana-alloy/      # Telemetry → Grafana Cloud
│   ├── kyverno/            # Policy engine
│   ├── kyverno-policies/   # Baseline Pod Security Standards
│   └── motorinfo/          # Demo app (web + API + database)
└── apps.yaml               # The `apps` Kustomization
```

`CLAUDE.md` documents the Kustomization hierarchy and the day-to-day
conventions in more detail.

## How changes ship

Commit to `main`. Flux detects the change within ~30s and reconciles the
cluster — there is no manual `kubectl apply`.

```bash
flux get kustomizations          # reconciliation status
flux get helmreleases -A
flux logs --follow
flux reconcile kustomization apps
```

## Secrets

Secrets are encrypted with SOPS/age (the rule lives in `.sops.yaml`). Each
`*.sops.yaml` is named after the Secret it contains. The private key exists
only in the cluster (the `sops-age` secret in `flux-system`) and locally at
`~/.config/sops/age/keys.txt`; Flux decrypts at reconcile time.

```bash
# edit an existing secret in place
sops cluster/apps/<app>/<secret>.sops.yaml

# create a new one
kubectl create secret generic <name> --from-literal=key=value \
    --dry-run=client -o yaml > cluster/apps/<app>/<name>.sops.yaml
sops --encrypt --in-place cluster/apps/<app>/<name>.sops.yaml
# then add it to that app's kustomization.yaml
```

## Validation

There is no test suite — sanity-check manifests before pushing:

```bash
kustomize build --enable-helm cluster        # render the whole tree
kubectl apply --dry-run=server -k cluster/apps/<app>
```

## Adding an app

Create `cluster/apps/<name>/` with `namespace.yaml`, `helmrelease.yaml` (or
plain manifests), `kustomization.yaml`, and any `*.sops.yaml`. The `apps`
Kustomization discovers it automatically via directory traversal — no index
file to update.

## Rebuilding from scratch

The cluster is created from `cluster.yaml`:

```bash
hetzner-k3s create --config cluster.yaml
```

⚠️ `cluster.yaml` is committed to a **public** repo, so the Hetzner API token
and the SSH/API `allowed_networks` are placeholders
(`<YOUR_HETZNER_API_TOKEN>`, `<YOUR_ADMIN_IP>/32`). Fill them in locally and
never commit the real values.

Flux is then bootstrapped against this repo (one-time), after loading the age
key into the cluster:

```bash
kubectl create namespace flux-system
kubectl create secret generic sops-age -n flux-system --from-file=age.agekey=<your-age-key>
flux bootstrap github --owner=mkskytt --repository=k8s --branch=main --path=./cluster --personal
```
