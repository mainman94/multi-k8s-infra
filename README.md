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
  --version 9.0.5 \
  -f eggenberg-talos-cluster-1/bootstrap/argocd/values.yaml \
  --create-namespace
```

### Bootstrap Apps

```bash
kubectl apply -f eggenberg-talos-cluster-1/app-of-app/app-of-apps.yaml
```

Done. ArgoCD takes over from here.

## Making Changes

1. Edit config in `eggenberg-talos-cluster-1/argocd-apps-configuration/<app>/values.yaml`
2. Validate first: `pre-commit run --all-files` (yamlfmt) and `/preflight` (kube-lint + `kubectl kustomize` build of every overlay)
3. Commit and push
4. ArgoCD syncs automatically

Custom apps (`pmhme`) use Kustomize (`base/` + `overlays/{dev,test,production}` + `components/`) instead of raw Helm values. Never `kubectl apply` app changes, and don't hand-edit image tags managed by argocd-image-updater / Kargo.

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
