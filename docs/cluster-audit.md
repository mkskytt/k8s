# Cluster Audit

This is the final audit of the Flux CD-managed k3s cluster (`github.com/mkskytt/k8s`, manifests under `cluster/apps/`). Findings were adversarially verified against both the Git manifests and the live cluster; refuted findings (most of which were chart-default false positives or severity inflation on compressible-CPU concerns) are documented in the appendix and excluded from the body. The headline result is a **live outage**: the public `motorinfo.ytt.io` web tier has zero serving backends due to a missing `motorinfo-db` secret reference, and a separate, total loss of CVE scanning visibility — Trivy is running but produces no vulnerability reports. Beyond those, the dominant theme is an in-progress, ingress-only `default-deny` NetworkPolicy rollout that has not yet reached several workload namespaces and never scoped egress, plus a pod-security posture where the strict (`restricted`) controls every manifest carries are only audited, not enforced. Everything else is defense-in-depth hardening or cosmetic consistency.

| Severity | Confirmed findings |
|----------|-----------------|
| Critical | 1 |
| High     | 1 |
| Medium   | 5 |
| Low      | 7 |
| Info     | 8 |

Counts are of confirmed findings (post-merge, post-severity-adjustment). The two confirmed Low CPU-limit findings (emqx + motorinfo) are presented as a single combined entry in the body, so the Low row counts 7 findings across 6 `###` sections.

## Top priorities

1. **[Critical] `motorinfo.ytt.io` is fully down** — all `motorinfo-web` pods fail readiness (DB connection string missing); the web Service has zero ready endpoints and the tunnel cannot route.
2. **[High] CVE scanning is non-functional** — Trivy node-collector is blocked by the cluster's own Kyverno enforce policies *and* image scans fail on a broken `trivy-db` mirror path; the cluster has no live crit/high CVE visibility despite the operator running.
3. **[Medium] Workload namespaces lack default-deny ingress** — `cnpg-system`, `kyverno`, `trivy-system`, `system-upgrade` have no NetworkPolicy; the DB operator and cluster-wide admission webhooks are the priority gaps.
4. **[Medium] No default-deny egress anywhere** — every NetworkPolicy is ingress-only; egress was never scoped, leaving an open exfil/C2 path from every pod.
5. **[Medium] `grafana-alloy` NetworkPolicy is effectively a no-op** — its only policy selects no pods (label mismatch) and there is no default-deny, so all collectors accept ingress from anywhere.
6. **[Medium] Pod-security `restricted` controls are audited, not enforced** — Kyverno enforces only `baseline`; the `runAsNonRoot`/RO-rootfs/drop-ALL/seccomp posture in manifests is voluntary and a regression would be admitted.

## Findings by severity

### Critical: motorinfo public web tier is fully down (0/2 ready, zero serving backends)

**Scope/location:** `cluster/apps/motorinfo/deployment-web.yaml` (envFrom, ~lines 89–91); live `ns/motorinfo` `deploy/motorinfo-web`, Service `motorinfo-web`, Ingress `motorinfo.ytt.io`.

**Detail:** All `motorinfo-web` pods are NotReady; the Service's EndpointSlice has 3 addresses all `ready=false`, so the v1 Endpoints object is empty — zero serving backends. The Cloudflare Tunnel ingress for the web host therefore cannot route. Root cause (confirmed in pod logs): the .NET app's `db` health check fails with `Database connection string is missing`, so `/health/ready` (used by both startupProbe and readinessProbe) returns HTTP 503 forever; after the startupProbe exhausts its budget the container is killed and restarts (CrashLoopBackOff, 50+ restarts). The verifiable trigger is config drift: `deployment-web.yaml` has `envFrom: [secretRef: pyroscope-auth]` only, whereas the healthy `deployment-api.yaml` has `envFrom: [secretRef: motorinfo-db, secretRef: pyroscope-auth]` — the web deployment is missing the `motorinfo-db` secretRef. The `motorinfo-db` secret exists in-namespace and the DB cluster (3/3) and API (2/2) are healthy; the failure is isolated to web configuration. Compounding the outage, three stale ReplicaSets (revisions 20/21/22) each hold one never-ready pod (`ProgressDeadlineExceeded`); because no new pod ever becomes Ready, the controller never scales the old ReplicaSets to zero. The `motorinfo-web` PDB (`minAvailable: 1`) reports **0 allowed disruptions**, and the three never-ready pods sit on all three master nodes — so the PDB will **block voluntary node drains/upgrades across the entire control plane** until readiness is restored.

**Mitigating control:** None. The Cloudflare-tunnel-only model is the single path to a dead Service, not a mitigation; the PDB cannot help because no pod ever becomes ready.

**Recommendation:** Treat as an active outage. Choose between: (a) if the web image legitimately needs DB access, add `- secretRef: { name: motorinfo-db }` to `deployment-web.yaml`'s `envFrom` to mirror the API (the `motorinfo-db` secret already exists, so this is immediately viable); or (b) if web should *not* talk to the DB directly (it has `ApiBaseUrl` → `motorinfo-api`), remove the `db` health check from the web image's `/health/ready` set — this is an image regression. Confirm which via the app's health-check registration. Once a pod goes Ready, the Deployment controller automatically scales the stale ReplicaSets to zero and the PDB drain-block clears — no manual ReplicaSet deletion needed.

---

### High: Trivy CVE scanning is non-functional — node scans blocked by Kyverno, image scans blocked by a broken DB mirror

**Scope/location:** `ns/trivy-system deploy/trivy-operator`; ClusterPolicies `disallow-host-namespaces` / `disallow-host-path` (Enforce); `cluster/apps/kyverno-policies/helmrelease.yaml` (override list); `cluster/apps/trivy-operator/helmrelease.yaml:66-67` (`dbRepository`).

**Detail:** The operator pod runs Healthy but produces no CVE visibility — a false-healthy detective-control failure with **two independent root causes**, both confirmed live:

1. **Node-level scanning is blocked at admission.** The Trivy node-collector Jobs require `hostPID`/`hostPath` and are repeatedly denied by `validate.kyverno.svc-fail` via `disallow-host-namespaces` and `disallow-host-path` (both Enforce). `trivy-system` is *not* in the `kyverno-policies` `validationFailureActionOverrides` list (only `kube-system`, `grafana-alloy`, `system-upgrade` are), and there are 0 PolicyExceptions cluster-wide. Additionally the `trivy-system` namespace carries native PSA `enforce=baseline`, a *second* independent admission blocker on the resulting Pod. Result: 0 node-collector Jobs, 0 `infraassessmentreports`/`clusterinfraassessmentreports`.
2. **Image-level scanning fails at runtime.** The `scan-vulnerabilityreport` Jobs are admitted fine but FATAL on DB download: `mirror.gcr.io/ghcr.io/aquasecurity/trivy-db:2: MANIFEST_UNKNOWN`. A registry-mirror prefix mangles the HelmRelease's `dbRepository: ghcr.io/aquasecurity/trivy-db` into a non-existent path. Result: **0 `vulnerabilityreports` cluster-wide.**

(Config/RBAC audit scanning *does* work — 64 `configauditreports`, RBAC assessment reports exist — so the operator is not wholly dead; it is specifically CVE/vulnerability scanning that is broken.)

**Mitigating control:** None for CVE visibility. Config-audit working does not mitigate the missing CVE data.

**Recommendation:** Address **both** causes — fixing only one leaves CVE scanning dead. (1) For node scanning: add a narrowly scoped Kyverno PolicyException matching `trivy-system` + the node-collector job/pod labels, exempting only `disallow-host-namespaces` and `disallow-host-path` (verified both are required), **and** relax the `trivy-system` namespace PSA `enforce` label (e.g. to `privileged`) so the resulting hostPID/hostPath Pod is also admitted. Verify `infraassessmentreports` appear (not `vulnerabilityreports`). (2) For image scanning: fix the `trivy-db`/`trivy-java-db` repository path so it resolves (remove the erroneous `mirror.gcr.io/` prefix); verify `vulnerabilityreports` populate. Re-run the CVE audit only once reports exist. (Cross-reference: the "too strict" half of the *blunt-enforcement-granularity* Medium below is this same node-collector block.)

---

### Medium: Workload namespaces lack a default-deny ingress NetworkPolicy

**Scope/location:** `cluster/apps/cnpg/`, `cluster/apps/kyverno/`, `cluster/apps/trivy-operator/` (no `networkpolicy.yaml`); live namespaces `cnpg-system`, `kyverno`, `trivy-system`, and `system-upgrade` (the last not Flux-managed). Merges the per-app surveys (cnpg, kyverno, trivy), the cross-lens entries, and the live-cluster coverage check.

**Detail:** The repo has an active, internally consistent per-app default-deny-ingress convention (`podSelector: {}`, `policyTypes: [Ingress]` + scoped allow rules) live in `emqx`, `motorinfo`, `external-dns`, `cloudflare-tunnel`, and `flux-system`, on the current `default-deny-netpols` branch. k3s/Flannel (kube-router) does enforce NetworkPolicy, so the existing policies are effective — and the absence of one means all pod ingress is allowed. Four workload namespaces are not yet covered. There is **no mitigating control**: the 12 Kyverno ClusterPolicies are all PSS pod-restriction rules (none generate NetworkPolicies), there is no cluster-wide default-deny, and namespace PSA labels govern pod security, not network. Priority targets are **`kyverno`** (holds cluster-wide admission-control authority; reachable webhook ports) and **`cnpg-system`** (the CloudNativePG operator coordinating the motorinfo Postgres credentials). Exposure is lateral-movement-only (no public route into these namespaces, no public LoadBalancer), which caps this at medium.

**Mitigating control:** None.

**Recommendation:** Extend the existing `emqx`/`motorinfo` per-app `networkpolicy.yaml` template (default-deny-ingress + scoped allows) to `cnpg-system`, `kyverno`, and `trivy-system`. Two specifics the convention's pure default-deny does *not* cover: for **kyverno**, the validating webhook is `failurePolicy: Fail`, so a naive default-deny that blocks the kube-apiserver from reaching the admission service will halt all pod creation cluster-wide — the apiserver runs host-network on the masters (a node IP, not matchable by namespaceSelector), so the allow rule must use an `ipBlock` for the control-plane CIDR and target the pod port (`9443`/`https`), not the Service port `443`; prefer the chart's native `networkPolicy.enabled` value over a hand-rolled file. For **cnpg-system**, pair the default-deny with an allow for the apiserver→`cnpg-webhook-service` (`443`→`9443`). `system-upgrade` is provisioned by hetzner-k3s (not under `cluster/apps/`), so any policy there must be applied via the provisioning layer or a dedicated Flux Kustomization; it exposes no Services, so it is the lowest priority of the four.

---

### Medium: No default-deny egress anywhere in the cluster — open exfil/C2 path from every pod

**Scope/location:** Cluster-wide; all NetworkPolicies in `cluster/apps/` (`cloudflare-tunnel`, `external-dns`, `emqx`, `motorinfo`, `grafana-alloy`) declare only `policyTypes: [Ingress]`. Merges the per-app egress findings and the cross-lens entry.

**Detail:** Verified against manifests and live cluster: every app NetworkPolicy is ingress-only. The only resource with `Egress` in `policyTypes` is `flux-system`'s generated `allow-egress`, whose rule is `egress: - {}` (explicit allow-all, not a deny). Because no pod is selected by any egress-restricting policy, the CNI applies default allow-all egress: any compromised pod can reach the internet, the Kubernetes API, the Cloudflare API, the S3 backup-credentials endpoint, or any in-cluster service. This is the systemic gap that would turn an in-cluster compromise into data exfiltration / command-and-control. There is no mitigating control and no documented decision deferring egress scope — the `default-deny-netpols` rollout is ingress-only by design so far. The severity is medium (not high): missing egress segmentation is the default state of most clusters and is a defense-in-depth layer, not a directly exploitable exposure.

**Mitigating control:** None.

**Recommendation:** Decide explicitly whether egress segmentation is in scope. If yes, add a per-namespace default-deny-egress NetworkPolicy (`podSelector: {}`, `policyTypes: [Egress]`) plus targeted allows: DNS to kube-dns (UDP/TCP 53), the API server, and each app's known external endpoints (Cloudflare edge for cloudflared, Cloudflare API for external-dns, S3 for CNPG backups, OTLP receiver for motorinfo). Note k3s's kube-router backend cannot express FQDN-based egress allowlists, so Cloudflare-edge targets must be CIDR-based or left broad. If egress is intentionally out of scope, document that decision so the ingress-only posture is a deliberate choice rather than an oversight.

---

### Medium: grafana-alloy has a NetworkPolicy but no default-deny — and its one policy is a silent no-op

**Scope/location:** `cluster/apps/grafana-alloy/networkpolicy.yaml` (namespace `grafana-alloy`).

**Detail:** `grafana-alloy` appears in the "has netpol" column but is actually an ingress gap, and worse than a simple omission. Its only policy, `allow-otlp-receiver`, has a `podSelector` of `{app.kubernetes.io/name: alloy, app.kubernetes.io/instance: grafana-k8s-monitoring-alloy-receiver}`, but the live receiver pods carry `app.kubernetes.io/name=alloy-receiver` — **the selector matches zero pods**, so the policy is inert (the file's own comment warned of exactly this). Because a NetworkPolicy only constrains the pods it selects and there is no default-deny, *every* pod in the namespace (alloy-metrics, alloy-singleton, alloy-logs, alloy-receiver, kube-state-metrics, opencost, kepler, node-exporter) accepts ingress from anywhere in the cluster. This is the least-constrained workload namespace.

**Mitigating control:** None.

**Recommendation:** Add a default-deny-ingress NetworkPolicy (`podSelector: {}`, `policyTypes: [Ingress]`) to the namespace, then keep `allow-otlp-receiver` plus explicit allows for the collectors that legitimately receive traffic. **Fix the receiver selector** against the live pod labels (`kubectl -n grafana-alloy get pod -l app.kubernetes.io/name=alloy-receiver`) so the allow rule is not a no-op.

---

### Medium: Kyverno enforces only BASELINE PSS — the restricted-grade controls every manifest relies on are unenforced

**Scope/location:** `cluster/apps/kyverno-policies/helmrelease.yaml` (`podSecurityStandard: baseline`, `validationFailureAction: Enforce`); live ClusterPolicies and per-namespace PSA labels.

**Detail:** Confirmed live: the 12 Enforce-mode ClusterPolicies are exactly the BASELINE set (disallow-capabilities/host-namespaces/host-path/host-ports/host-process/privileged/proc-mount/selinux, restrict-apparmor/seccomp/sysctls; `disallow-latest-tag` is Audit-only). No RESTRICTED-grade controls exist: no `require-run-as-nonroot`, no `restrict-volume-types`, no drop-ALL enforcement, and `restrict-seccomp` only blocks `Unconfined` (it permits the field to be unset — the baseline rule, not restricted). Consequently the `runAsNonRoot` / `readOnlyRootFilesystem` / drop-ALL / `seccompProfile: RuntimeDefault` posture in `motorinfo`, `cloudflare-tunnel`, and (via chart defaults) `cnpg`/`external-dns` is **voluntary** — warned and audited (every app namespace carries `warn=restricted`, `audit=restricted`) but not enforced by Kyverno or PSA (`enforce=baseline`). A regression dropping drop-ALL or RO-rootfs from a manifest would be admitted. Note current workloads do *not* uniformly meet restricted (cnpg, external-dns, emqx do not), so the manifests' restricted posture is aspirational, not universal.

**Mitigating control:** `warn=restricted` + `audit=restricted` PSA labels are detective controls (a regression is warned at apply time and audited), and the GitOps model means every manifest change is a reviewable Git diff before Flux applies it. These reduce but do not eliminate the regression risk — they do not block admission. The Enforce-mode baseline policies do cover the actual container-escape boundary (privileged, host namespaces/path/ports/proc, Unconfined seccomp, capability limits), so there is no current live exposure.

**Recommendation:** Decide on a target standard and make enforcement match it. If `restricted` is the goal, set `podSecurityStandard: restricted` (or flip namespace `enforce=restricted`) **only after** remediating the outliers (`emqx`, `trivy-operator` — see Lows below) and adding scoped exceptions for host-access infra (`grafana-alloy`, trivy node-collector, `kube-system`) — flipping first will reject those exact workloads at admission. If `baseline` is intentionally the floor, document that the restricted-grade manifest fields are best-effort/audited.

---

### Medium: Pod-security enforcement is toggled at blunt namespace granularity — simultaneously too loose and too strict

**Scope/location:** `cluster/apps/kyverno-policies/helmrelease.yaml` (`validationFailureActionOverrides`); live PolicyExceptions (none).

**Detail:** The only enforcement lever in use is whole-namespace Audit overrides (`kube-system`, `grafana-alloy`, `system-upgrade`), and there are 0 PolicyExceptions cluster-wide, so exemptions are all-or-nothing per namespace. This produces opposite errors: **too loose** in `grafana-alloy`, where the override exempts *every* workload including non-host-access ones (`kube-state-metrics`, `opencost`, both verified to have no host access and to pass baseline); and **too strict** in `trivy-system`, which is not exempted at all, hard-blocking the node-collector (this is the node-scanning half of the Trivy High above — cross-referenced, not re-counted). The same blunt mechanism causes over-exemption in one place and an unintended outage of a security control in another.

**Mitigating control:** None.

**Recommendation:** Adopt workload-scoped Kyverno PolicyExceptions (match by namespace + pod/job labels + specific policy names) for the genuinely host-privileged components (alloy/kepler/node-exporter daemonsets, `hcloud-csi-node`, `system-upgrade`, trivy node-collector), then narrow or remove the broad namespace-level Audit overrides. This restores enforcement for the non-privileged workloads currently riding the blanket exemptions.

---

### Low: Missing CPU limits on motorinfo and emqx containers (deliberate, low-impact)

**Scope/location:** `cluster/apps/motorinfo/deployment-web.yaml:92-97`, `deployment-api.yaml:87-92`; `cluster/apps/emqx/helmrelease.yaml:57-62`. Merges the two confirmed CPU-limit findings.

**Detail:** `motorinfo-web`/`-api` (50m CPU request) and emqx (100m CPU request) set memory limits but no CPU limit. The framing of the original findings ("runaway process starves neighbors / cluster instability") overstates the risk: CPU is compressible — without a limit a container is throttled to its request-weighted CFS share under contention, never OOM-killed; the incompressible resource that can destabilize a node (memory) *is* limited in all three. Omitting CPU limits while setting requests is a widely-endorsed practice (avoids CFS throttling latency). No LimitRange or resource-enforcing Kyverno policy exists, so nothing injects a default.

**Mitigating control:** Memory limits are set (cap the OOM/eviction risk); CPU requests are set (guarantee scheduling share).

**Recommendation:** Optional. If predictable CPU caps are desired on the shared cx23 nodes, add `limits.cpu` (e.g. 500m); otherwise accept the current pattern as intentional. Not a defect.

---

### Low: motorinfo images pinned by short commit SHA, not SHA256 digest

**Scope/location:** `cluster/apps/motorinfo/deployment-web.yaml:35`, `deployment-api.yaml:35`.

**Detail:** Both use tag `7de15f6` (short commit SHA), which is registry-mutable. The repo's own Kyverno `disallow-latest-tag` policy explicitly permits "pin to a tag OR digest," so a pinned commit tag satisfies convention. Realistic exploit requires compromising the single-owner private GHCR repo, at which point a digest pin would only fail-closed, not prevent pipeline compromise. `imagePullPolicy: IfNotPresent` reduces silent-retag exposure on cached nodes.

**Mitigating control:** None technical (`disallow-latest-tag` does not address tag mutability), but repo convention permits tag pinning.

**Recommendation:** For maximum immutability/reproducibility, pin by `@sha256:` digest. Hardening nicety, not required.

---

### Low: external-dns runs a single replica with no PDB or anti-affinity

**Scope/location:** `cluster/apps/external-dns/helmrelease.yaml` (no `replicaCount`, defaults to 1; no PDB/affinity).

**Detail:** Single-replica SPOF, unlike emqx/cloudflare-tunnel/cnpg which set replicas + anti-affinity + PDB. Severity is low, not medium: external-dns is a control-plane reconciler, not in the request path — existing Cloudflare DNS records and live tunnel traffic are unaffected if the pod dies; only *new/changed* record syncs pause until reschedule (self-healing in seconds). The naive fix is also subtly wrong: this chart config has no leader election, so 2–3 active replicas would race to write the same Cloudflare zone, and a PDB on a single-replica Deployment blocks drains.

**Mitigating control:** None, but DNS records persist independent of the pod.

**Recommendation:** Low priority. If HA is desired, use replicas *with* leader election; do not slap a PDB on a singleton.

---

### Low: cnpg-system and trivy-system namespaces have no NetworkPolicy

**Scope/location:** `cluster/apps/cnpg/`, `cluster/apps/trivy-operator/` (cross-lens entries; subset of the workload-namespace Medium above, retained here at their individually-verified low severity for the non-priority operators).

**Detail:** Both operator namespaces lack a default-deny-ingress policy. These were graded low individually because the operators expose minimal, non-credential-bearing inbound surface (cnpg: webhook 443→9443, metrics 8080 with PodMonitor disabled; trivy: a port-80 ClusterIP, no scrape annotation) and exposure is lateral-only. Notably, an ingress policy on `cnpg-system` does *not* close the motorinfo-db "trusted namespace" path — that trust lives in motorinfo's `allow-db` ingress rule, governing egress from cnpg-system's side.

**Mitigating control:** None.

**Recommendation:** Covered by the workload-namespace Medium remediation; add a plain default-deny-ingress matching the external-dns/cloudflare-tunnel pattern. Consistency/defense-in-depth.

---

### Low: trivy-operator pod-level securityContext lacks runAsNonRoot and seccompProfile

**Scope/location:** `cluster/apps/trivy-operator/helmrelease.yaml` (no securityContext in values); live operator pod (pod-level securityContext `{}`).

**Detail:** The container securityContext is good by chart default (`allowPrivilegeEscalation=false`, drop ALL, `readOnlyRootFilesystem=true`), but the pod-level securityContext is empty — no `runAsNonRoot`, no `seccompProfile: RuntimeDefault` at pod level. It would not satisfy the restricted standard's pod-level requirements without relying on container inheritance. Low because the container context already drops caps and blocks privilege escalation, and it is cluster-internal.

**Mitigating control:** Hardened container-level securityContext (chart default).

**Recommendation:** Set `podSecurityContext.runAsNonRoot: true` and `podSecurityContext.seccompProfile.type: RuntimeDefault` in the trivy-operator values to complete the posture and survive a restricted-enforce flip. (Separate from the node-collector host-access exception in the Trivy High.)

---

### Low: grafana-alloy runs clustered collectors but defines no PodDisruptionBudget

**Scope/location:** `cluster/apps/grafana-alloy/helmrelease.yaml` (`alloy-metrics` clustered preset); `cluster/apps/grafana-alloy/` (no PDB).

**Detail:** `alloy-metrics` runs multi-replica (clustered) yet there is no PDB, while every other multi-replica app in the repo ships one. Lower than a correctness defect: collector counts are chart-managed rather than an explicit replica pin, and telemetry collection is best-effort (a brief gap during a drain is non-fatal).

**Mitigating control:** None.

**Recommendation:** Optionally add a PDB for the clustered `alloy-metrics` collector to match the repo-wide convention, or explicitly accept the gap given telemetry is best-effort.

---

### Info: cluster.yaml contains a plaintext Hetzner API token (known/documented)

**Scope/location:** `cluster.yaml` (repo root).

**Detail:** Per CLAUDE.md this is a known, intentionally-not-gitignored provisioning file (not a live-cluster object). Documented, accepted risk.

**Recommendation:** Keep verifying it is never staged before any push (`git status`), as the repo docs require. Optionally move the token to an env var / secret store.

---

### Info: flux-system is not default-deny (vendor-managed allow-all egress)

**Scope/location:** `cluster/flux-system/gotk-components.yaml`.

**Detail:** `flux-system` carries three NetworkPolicies, but `allow-egress` is `egress: - {}` (allow-all) with intra-namespace ingress — the upstream Flux default, not a deny posture. The file is generated and marked "DO NOT EDIT."

**Recommendation:** Accepted gap; do not hand-edit `gotk-components.yaml`. If egress hardening becomes a goal, manage Flux's policies via the supported bootstrap/network-policy customization.

---

### Info: kube-system and empty system namespaces are uncovered (expected)

**Scope/location:** `kube-system`, `default`, `kube-public`, `kube-node-lease`.

**Detail:** No NetworkPolicies. `default`/`kube-public`/`kube-node-lease` host no workloads. `kube-system` runs host-access infra (hcloud-csi-node, hcloud-ccm, cluster-autoscaler, coredns) by design; a blanket default-deny risks severing CNI/DNS/CSI.

**Recommendation:** Out of scope for the default-deny rollout. Only `coredns` is worth protecting eventually, with carefully validated allow rules.

---

### Info: No healthChecks in the flux-system / apps Kustomizations

**Scope/location:** `cluster/flux-system/gotk-sync.yaml`, `cluster/apps.yaml`.

**Detail:** Neither Kustomization defines a `healthChecks` block (nor `wait`/`timeout`). This adds readiness *gating*, not error *detection* — Flux already reports `Ready=False` on apply/build/decrypt errors regardless. `gotk-sync.yaml` is Flux-generated ("DO NOT EDIT"), so the original "add to both" recommendation is partly misguided.

**Mitigating control:** Per-HelmRelease install/upgrade remediation (commit 867b431) + the Helm controller's built-in resource-wait/remediation + Flux's Ready-condition reporting.

**Recommendation:** Optional hardening for the `apps` Kustomization only; do not hand-edit `gotk-sync.yaml`.

---

### Info: No cluster-wide default-deny NetworkPolicy baseline

**Scope/location:** Cluster-wide (the systemic framing of the per-namespace ingress gaps).

**Detail:** Confirmed there is no cluster-wide default-deny and no Kyverno policy that generates one; segmentation is purely per-namespace. The original finding mis-cited `flux-system`'s `allow-egress` as "allow-all-from-pods" — an empty `podSelector: {}` peer with no `namespaceSelector` matches same-namespace pods only, so `flux-system` is actually one of the more locked-down namespaces. Blast radius is small: all sensitive/public/data namespaces already have per-namespace default-deny-ingress, and public traffic enters only via the tunnel.

**Mitigating control:** Per-namespace default-deny-ingress on all sensitive namespaces + tunnel-only ingress. Partial — does not cover system/operator namespaces or egress.

**Recommendation:** Track via the workload-namespace and egress Medium items above; a Kyverno `generate` policy could enforce a default-deny baseline cluster-wide if desired.

---

### Info: cloudflare-tunnel is the only app that sets a CPU limit (minor drift)

**Scope/location:** `cluster/apps/cloudflare-tunnel/helmrelease.yaml:61-67`.

**Detail:** Every other app sets memory limits only and omits CPU limits intentionally; cloudflare-tunnel's lone `limits.cpu: 100m` is a minor consistency drift, not a defect.

**Recommendation:** Optionally drop `limits.cpu` for consistency, unless the CPU cap is intentional for this DNS-edge workload.

---

### Info: chart.spec.interval present only on range-versioned charts (verified coherent, not drift)

**Scope/location:** `cluster/apps/{cnpg,grafana-alloy,kyverno,kyverno-policies,trivy-operator}/helmrelease.yaml`.

**Detail:** `chart.spec.interval: 12h` appears on exactly the 5 range-versioned charts and is absent on the 3 exact-pinned charts. An exact pin has no newer matching version to discover, so omitting the poll override is correct. Recorded as examined-and-sound.

**Recommendation:** No action.

---

### Info: Convention checks that passed (no drift) + SOPS encryption verified

**Scope/location:** `cluster/apps/*`; `cluster/apps/**/*.sops.yaml`.

**Detail:** Verified with no drift: secret-handling charts pin exact versions and supporting-infra uses ranges per convention; install/upgrade remediation (`retries: 3`) is present on all 8 HelmReleases; reconcile intervals match (5m DNS-critical, 30m others, 10m HelmRepository); all Ingress hosts are under `ytt.io` with the correct tunnel-target annotation; every `kustomization.yaml` resources list matches files on disk. All 8 `*.sops.yaml` files contain `ENC[AES256_GCM...]` markers (none slipped through as plaintext); single shared age recipient per convention; no unencrypted Secret data in the tree.

**Recommendation:** No action.

## Coverage matrix

Built from the verified live reality (chart defaults that the refuted findings confirmed are reflected as ✅, not the original claims). Legend: ✅ present/correct · ⚠️ present but partial/ineffective · ❌ absent · — not applicable.

| App | Default-deny ingress | Default-deny egress | Resource limits | Non-root / RO-fs | PDB | Image pinning |
|-----|:---:|:---:|:---:|:---:|:---:|:---:|
| cloudflare-tunnel | ✅ | ❌ | ✅ (cpu+mem) | ✅ | ✅ (minAvail 2) | ✅ (chart 0.3.2 + tag 2026.5.0) |
| external-dns | ✅ | ❌ | ⚠️ (mem only) | ✅ (chart) | ❌ (1 replica) | ✅ (1.21.1 exact) |
| emqx | ✅ | ❌ | ⚠️ (mem only) | ⚠️ (runAsNonRoot only; no drop-ALL/RO-fs/seccomp) | ✅ (minAvail 2) | ✅ (5.8.9 exact) |
| motorinfo | ✅ | ❌ | ⚠️ (mem only) | ✅ (explicit, full restricted) | ✅ (web/api minAvail 1) | ⚠️ (short commit SHA) |
| grafana-alloy | ⚠️ (no default-deny; sole netpol is a no-op) | ❌ | ⚠️ (chart defaults; collectors uncapped) | ⚠️ (host-access by design; no PSA labels) | ❌ (clustered, no PDB) | ⚠️ (chart-managed, no digests) |
| cnpg | ❌ | ❌ | ⚠️ (mem only) | ✅ (chart) | ✅ (minAvail 1) | ✅ (>=0.28.0 range, per convention) |
| kyverno | ❌ | ❌ | ⚠️ (mem only) | ✅ (non-root, RO-fs, drop ALL, seccomp) | ✅ (chart default, minAvail 1) | ✅ (>=3.3.0 range) |
| kyverno-policies | — | — | — | — | — | ✅ (>=3.8.0 range) |
| trivy-operator | ❌ | ❌ | ⚠️ (operator mem only; scan jobs cpu+mem) | ⚠️ (container hardened; pod-level lacks runAsNonRoot/seccomp) | — (1 replica, appropriate) | ⚠️ (DB repos untagged by design; scanner pinned 0.69.3) |

## Appendix: dismissed/downgraded findings

The following were **refuted** by adversarial verification and excluded from the body. The recurring patterns: (a) findings flagged a values-file omission without checking the secure chart default that actually applies, and (b) "missing CPU limit" severity inflation treating compressible CPU as an OOM/eviction risk.

**Chart-default false positives (the workload is actually fine):**

- **Kyverno "no PDB for admission controller" (claimed High):** The chart auto-creates `kyverno-admission-controller` PDB (`minAvailable: 1`) when replicas > 1 — confirmed live (`ALLOWED DISRUPTIONS 1`, Helm/Flux-managed). The proposed manual PDB would collide with it.
- **Kyverno "no health probes" (claimed High):** The admission and cleanup controllers (the only ones backing `failurePolicy: Fail` webhooks) have liveness/readiness/startup probes from the chart, confirmed live. Only background/reports controllers lack probes, and they are off the admission path.
- **Kyverno "no anti-affinity / both pods could co-locate" (claimed Medium):** Chart sets `podAntiAffinity` (preferred, `kubernetes.io/hostname`) by default; the two admission pods are observed on distinct nodes. The finding's own proposed fix equals the existing chart behavior.
- **Kyverno cross-lens "2 replicas but no PDB + no anti-affinity" (claimed High):** Same as above — both protections exist by chart default; refuted on both prongs.
- **trivy-operator "no securityContext, runs as root with full privilege escalation" (claimed High):** Chart default sets `allowPrivilegeEscalation=false`, drop ALL, `readOnlyRootFilesystem=true`, `privileged=false` on both operator and scan jobs — confirmed live. Privilege escalation is already blocked. (Residual pod-level `runAsNonRoot` gap captured as the confirmed Low.)
- **trivy-operator "no probes" (claimed Medium):** Operator has liveness (`/healthz/`) and readiness (`/readyz/`) probes by chart default, confirmed live. Only a startupProbe is absent, immaterial given the liveness initial-delay budget.
- **trivy-operator "missing CPU limits for operator and scanner" (claimed Medium):** Scanner jobs *are* CPU-limited (`trivy.resources.limits.cpu: 500m`, preserved by Helm deep-merge — confirmed in the live ConfigMap), which is the primary CPU consumer. Only the lightweight operator pod is uncapped.
- **trivy-operator "single replica, non-HA" (claimed High):** Architecturally single-active (Recreate strategy / leader-elected background controller); scan results persist as CRs and the pod self-reschedules. Matches the repo's convention (kyverno background controllers also run 1 replica). The proposed 2-replica fix would not deliver HA.
- **trivy-operator "no PDB" (claimed Medium):** A PDB with `minAvailable: 1` on a single-replica Deployment yields `disruptionsAllowed = 0`, which would *block* the drains it claims to protect — an anti-pattern.
- **trivy "DB images lack version tags / pull :latest" (claimed High):** `dbRepository`/`javaDbRepository` resolve to the internal DB *schema* version (e.g. `:2`), never `:latest`; the chart exposes no tag knob, and the DB is a deliberately-mutable CVE feed that pinning would freeze. Category error. (The *actual* DB problem — the broken `mirror.gcr.io/ghcr.io/...` path — is captured in the Trivy High.)
- **grafana-alloy "no resource limits / probes / PDB" (claimed Medium):** Chart sets readiness probes on all alloy collectors and liveness+readiness on the telemetry backends, confirmed live; uncapped collector memory is a deliberate chart default; the proposed PDB is incoherent for DaemonSet-shaped collectors.
- **grafana-alloy "no PSA labels on namespace" (claimed Medium):** PSS is centralized in Kyverno; `grafana-alloy` is explicitly in the `validationFailureActionOverrides` Audit list (documented: log collection needs hostPath + host network). The optional `enforce=baseline` fix would break the collectors. (Residual: no *restricted* warn/audit visibility — captured as the confirmed Low.)
- **Kyverno cross-lens "enforce policies block legitimate host-access infra on reschedule" (claimed High):** Refuted — `disallow-host-path`/`disallow-host-namespaces` carry `validationFailureActionOverrides` → Audit for `kube-system`, `grafana-alloy`, `system-upgrade`, where all cited workloads live; a server-side dry-run admitted a hostPath pod in `kube-system`. No reschedule risk for those workloads. (The genuinely non-exempted case — `trivy-system` node-collector — is the Trivy High.)

**Missing-CPU-limit / resource findings refuted (compressible CPU, deliberate convention):**

- **cnpg "CPU limits not specified" (claimed Medium):** Repo-wide convention (memory-limit-only); CPU is compressible and cannot starve neighbors below their requests; adding a CPU limit would introduce CFS throttling. Info.
- **external-dns "missing CPU limit" (claimed High):** Same compressible-CPU reasoning; memory limit (the real node-protection control) is present; the proposed 200m cap would only throttle a tiny reconcile controller. Info.
- **motorinfo-db "CPU limit not defined for CNPG cluster" (claimed High):** Mirrors the CNPG operator's own resource pattern; memory limit caps the OOM risk; CPU throttle, not starvation. Info.
- **Kyverno "missing CPU limits on all controllers" (claimed High):** Matches the upstream chart default (memory-only limits by design); memory limits are set; a CPU limit on the latency-sensitive admission webhook would *harm* reliability via throttling. Low.

**Other refuted:**

- **motorinfo "ghcr-pull imagePullSecret referenced but not defined" (claimed Medium):** The secret *exists* in the namespace (created out-of-band); pods pull images successfully, no ImagePullBackOff events. The only residual is a GitOps-drift reproducibility note (secret not in the repo), info-level.
- **kyverno-policies "missing namespace.yaml" (claimed Medium):** Adding it would emit a duplicate `Namespace/kyverno` into the aggregated `apps` build (the sibling `kyverno` app owns it), breaking reconciliation cluster-wide — the proposed fix is actively harmful. Correct as-is.
- **"inconsistent chart version pinning format" — `0.3.2` quoted vs `1.21.1` unquoted (claimed Medium):** Both are exact pins (convention satisfied); `0.3.2` parses as a string regardless of quoting, so no "YAML drift" path exists; the suggested fix points toward the less-robust style. Cosmetic. Info.
