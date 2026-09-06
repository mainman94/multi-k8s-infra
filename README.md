# Talos Homelab 🏠

My personal homelab setup managing a Talos Linux cluster with GitOps. Everything's declarative, ArgoCD syncs it all.

## What's This?

A Kubernetes cluster running on Talos Linux:
- **eggenberg-talos-cluster-1**: Primary cluster for workloads, monitoring, and storage.

Everything's managed through Git. Push a change, ArgoCD deploys it. Simple.

## Structure

```
├── eggenberg-talos-cluster-1/
│   ├── app-of-app/                    # ArgoCD bootstrap
│   ├── argocd-apps/                   # App definitions
│   ├── argocd-apps-configuration/     # Helm values
│   └── bootstrap/                     # Initial cluster setup (Cilium, ArgoCD)
├── scripts/                           # What `make` and CI both run
├── docs/                              # Design specs and plans
├── Makefile                           # `make help` lists every target
└── mise.toml                          # The toolchain — one source of truth
```

## What's Running

**Networking & ingress**
- **Cilium & Cilium Gateway** - CNI (kube-proxy replacement), Gateway API, L2 announcements, SPIRE mTLS, Hubble
- **Cloudflare Tunnel** - External access (`*.hauptmann.dev`)
- **Cert-Manager** - SSL certificates
- **ExternalDNS** - Cloudflare DNS records driven by Gateway API HTTPRoutes

**Delivery & GitOps**
- **Argo Suite** - CD, Workflows, Events, Rollouts (blue/green + canary)
- **Kargo** - Progressive delivery (dev → test → prod)
- **argocd-image-updater** - Dev-overlay image bumps
- **External Secrets Operator + OpenBao** - Secret management

**Observability**
- **Kube-Prometheus-Stack** - Metrics, Grafana, Alertmanager
- **Loki + Alloy** - Log aggregation & collection
- **Tempo** - Distributed tracing (OTLP)
- **Uptime Kuma** - Uptime checks

**Security & policy**
- **Kyverno** - Admission policies (pod-security, resource/image hygiene — Audit mode)
- **Trivy Operator** - Vulnerability & config scanning

**Storage, scaling & resilience**
- **Longhorn** - Distributed block storage (default `longhorn` SC)
- **KEDA** - Event-driven autoscaling
- **Vertical Pod Autoscaler** - Right-sizing pod requests
- **Spegel** - P2P image cache
- **Velero + Kopia** - Backups to Backblaze S3 (daily)

**Apps**
- **PMHME** - Custom portfolio app + contact backend (`hauptmann.dev`)

## Quick Setup

### Initial Cluster (Talos)

The cluster is provisioned using Talos Linux. Ensure your `talosconfig` is correctly set up.

### Install ArgoCD

```bash
helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
  --namespace argocd \
  --version 10.2.0 \
  -f eggenberg-talos-cluster-1/bootstrap/argocd/values.yaml \
  --create-namespace
```

### Bootstrap Apps

```bash
kubectl apply -f eggenberg-talos-cluster-1/app-of-app/app-of-apps.yaml
```

Done. ArgoCD takes over from here.

## Making Changes

1. `make tools` once — installs the pinned toolchain (kubectl, kustomize,
   kubeconform, kube-linter, trivy, pre-commit, …) from `mise.toml`. CI installs
   from the same file, so a local run and a CI run agree on versions.
2. Edit config in `eggenberg-talos-cluster-1/argocd-apps-configuration/<app>/values.yaml`
3. `make preflight` — the hooks, kube-linter, and a `kubectl kustomize` build of
   every overlay. **This is the last gate before the cluster sees the change**:
   there is no `kubectl apply` step to catch a mistake, ArgoCD just syncs it.
4. Commit and push
5. ArgoCD syncs automatically

`make help` lists the rest; `make kubeconform` schema-validates against the
upstream and CRD catalogs (needs network), `make scan` runs the trivy config
scan, `make images` lists every image the repo's own apps actually run.

Custom apps (`pmhme`) use Kustomize (`base/` + `overlays/{dev,test,production}` + `components/`) instead of raw Helm values. Never `kubectl apply` app changes, and don't hand-edit image tags managed by argocd-image-updater / Kargo.

### What a pull request runs

Three checks must pass before a PR can merge:

| Check | What it catches |
| --- | --- |
| `pre-commit` | yamlfmt, shellcheck/shfmt, gitleaks, actionlint + zizmor over the workflows |
| `Schema Validation (kubeconform)` | manifests that no longer match their (C)RD schema |
| `Best Practices (kube-linter)` | missing resource limits, root containers, and friends |

kubeconform runs `-strict` **without** `-ignore-missing-schemas`: an unknown
kind is a failure, not a skip, so a typo'd `apiVersion` cannot slip through as
"no schema found". CRDs come from the datree CRDs-catalog. If a new operator's
CRD is not in the catalog, add its schema location to `scripts/kubeconform.sh`
rather than reaching for `-ignore-missing-schemas`.

Two more workflows run but are deliberately **not** required, because both are
path-filtered — a required check that never reports would block every PR that
does not touch its paths:

- `manifest-diff.yml` renders every overlay at the base and at the head of the
  PR and posts the diff as a comment, so a Helm value change shows up as the
  Kubernetes objects it actually produces. On a fork PR it renders but does not
  comment.
- `argocd-lint.yml` validates the ArgoCD Application definitions.

## License and security

MIT (`LICENSE`). To report a vulnerability, see `SECURITY.md` — please do not
open a public issue for one.

## Access Stuff

**ArgoCD:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

**Grafana:**
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80
```

## Secrets

Secrets are managed by External Secrets Operator against OpenBao at
`https://vault.hauptmann.dev`. Never commit plaintext secrets.

## Troubleshooting

**ArgoCD not syncing?**
```bash
kubectl get applications -A
kubectl logs -n argocd deployment/argocd-application-controller
```

**Network issues (Cilium)?**
```bash
kubectl get pods -n kube-system
kubectl exec -it -n kube-system ds/cilium -- cilium status
```

---

Just a homelab. Nothing fancy. 🏡
