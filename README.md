# Multi-K8s Homelab 🏠

My personal homelab setup managing two K3s clusters with GitOps. Everything's declarative, ArgoCD syncs it all.

## What's This?

Two K3s clusters running at home:
- **eggenberg-reverse-proxy-cluster**: Handles incoming traffic, routing, monitoring
- **strassgang-backend-cluster**: Runs backend services and storage

Everything's managed through Git. Push a change, ArgoCD deploys it. Simple.

## Structure

```
├── eggenberg-reverse-proxy-cluster/
│   ├── app-of-app/                    # ArgoCD bootstrap
│   ├── argocd-apps/                   # App definitions
│   ├── argocd-apps-configuration/     # Helm values
│   └── bootstrap/                     # Initial cluster setup
│
└── strassgang-backend-cluster/
    ├── app-of-app/
    ├── argocd-apps/
    ├── argocd-apps-configuration/
    └── bootstrap/
```

## What's Running

**Eggenberg (Reverse Proxy)**
- Traefik - ingress
- Cilium - networking
- Cloudflare Tunnel - external access
- Prometheus + Grafana - monitoring
- Longhorn - storage
- Rancher - cluster UI
- Uptime Kuma - uptime checks

**Strassgang (Backend)**
- Harbor - container registry
- Longhorn - storage
- SeaweedFS - object storage
- Tailscale - VPN
- Traefik - routing

Both use Infisical for secrets and ArgoCD for GitOps.

## Quick Setup

### Initial Cluster (K3s)

```bash
# Main node
curl -sfL https://get.k3s.io | sh -s - server \
  --flannel-backend=none \
  --disable-network-policy \
  --disable-kube-proxy \
  --disable=traefik \
  --disable=servicelb \
  --cluster-init
```

### Install Cilium (Eggenberg only)

```bash
helm repo add cilium https://helm.cilium.io
helm install cilium cilium/cilium -n kube-system -f bootstrap/cilium/values.yaml
```

### Install ArgoCD

```bash
helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
  --namespace argocd \
  --version 9.0.5 \
  -f bootstrap/argocd/values.yaml \
  --create-namespace
```

### Bootstrap Apps

```bash
kubectl apply -f app-of-app/app-of-app.yaml
```

Done. ArgoCD takes over from here.

## Making Changes

1. Edit config in `argocd-apps-configuration/<app>/values.yaml`
2. Commit and push
3. ArgoCD syncs automatically

That's it.

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

Using Infisical to manage secrets. Set up:

```bash
kubectl create secret generic universal-auth-credentials \
  -n infisical-secrets-operator \
  --from-literal=clientId=<CLIENT_ID> \
  --from-literal=clientSecret=<CLIENT_SECRET>
```

Then apply the InfisicalSecret manifests. Secrets sync automatically.

## Troubleshooting

**ArgoCD not syncing?**
```bash
kubectl get applications -A
kubectl logs -n argocd deployment/argocd-application-controller
```

**Network issues?**
```bash
kubectl get pods -n kube-system
kubectl exec -it -n kube-system ds/cilium -- cilium status
```

**Secrets not working?**
```bash
kubectl logs -n infisical-secrets-operator -l app=infisical-secrets-operator
```

---

Just a homelab. Nothing fancy. 🏡

