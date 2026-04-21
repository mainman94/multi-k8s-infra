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

- **Cilium & Cilium Gateway** - Networking & Ingress
- **Cloudflare Tunnel** - External access
- **Cert-Manager** - SSL certificates
- **Argo Suite** - CD, Workflows, Events, Rollouts
- **Kargo** - Progressive delivery
- **Infisical** - Secret management
- **Kube-Prometheus-Stack & Loki** - Monitoring & Logging
- **Longhorn** - Distributed block storage
- **Alloy** - Telemetry collection
- **Uptime Kuma** - Uptime checks
- **PMHME** - Custom applications

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
2. Commit and push
3. ArgoCD syncs automatically

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

Using Infisical to manage secrets. Set up the operator credentials:

```bash
kubectl create secret generic universal-auth-credentials \
  -n infisical-secrets-operator \
  --from-literal=clientId=<CLIENT_ID> \
  --from-literal=clientSecret=<CLIENT_SECRET>
```

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
