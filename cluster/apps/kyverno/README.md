# Kyverno

Policy engine for the cluster. Two Flux HelmReleases back it, both from the
`https://kyverno.github.io/kyverno/` chart repo:

- **`kyverno/`** (this directory) — the Kyverno engine. Chart `kyverno`
  (`>=3.3.0, <4.0.0`), running the admission, background, cleanup, and reports
  controllers.
- **`kyverno-policies/`** — the policy set. Chart `kyverno-policies`
  (`>=3.8.0, <4.0.0`), which applies the Pod Security Standards.

## What's configured here

- **Security context** — every controller runs non-root (`runAsUser: 10001`),
  read-only root filesystem, all capabilities dropped, `RuntimeDefault` seccomp.
- **Resource filters** (`config.resourceFilters`) — system and high-churn
  resources (kube-system, `Event`, `Node`, `ReplicaSet`, the various
  access-review kinds, …) are excluded so the admission controller doesn't
  process them.
- **Reports** — admission reports, background scan, and ConfigMap caching are
  on. Policy exceptions are allowed but scoped to the `kyverno` namespace.
- **Telemetry** — the chart's `serviceMonitor` and `grafana` integrations are
  off; metrics flow through grafana-alloy instead.

## Pod Security enforcement

`kyverno-policies` enforces the **baseline** Pod Security Standard
(`validationFailureAction: Enforce`). Namespaces that legitimately need extra
privileges are downgraded to **Audit** in `kyverno-policies/helmrelease.yaml`:

- `kube-system` — hcloud-csi-node, cluster-autoscaler, …
- `grafana-alloy` — log collection needs hostPath + host network
- `system-upgrade` — k3s system-upgrade-controller

When a new workload genuinely needs host access, add its namespace to that
override list rather than relaxing the policy globally.

## Conventions

- Sync interval is 30m (the repo's default for non-ingress releases); the
  `HelmRepository` polls every 10m. Git changes are still picked up within
  ~30s by the parent `apps` Kustomization.
- Policies ship via Git → Flux; there is no manual `kubectl apply` step.

## References

- [Kyverno docs](https://kyverno.io/docs/)
- [Pod Security Standards policies](https://kyverno.io/policies/pod-security/)
