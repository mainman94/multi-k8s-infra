# Multi-K8s Infra 🚀✨

Welcome to Multi-K8s Infra! 🚀🛸

This repository provides infrastructure-as-code (IaC) manifests and configuration for managing multiple Kubernetes clusters using GitOps principles. It is designed to support scalable, reproducible, and secure cluster deployments for various environments and use cases. Everything here is built to help you launch your clusters into orbit! 🛰️🌟

## Structure 🗂️

The repository is organized into separate directories for each cluster:

🪐 **Clusters:**

   - **eggenberg-rancher-cluster/**: Manifests and configuration for the Eggenberg Rancher-managed cluster.
   - **eggenberg-reverse-proxy-cluster/**: Manifests and configuration for the Eggenberg Reverse Proxy cluster.
   - **straga-cluster/**: Manifests and configuration for the Straga cluster.

Each cluster directory contains:
   - `app-of-app/`: ArgoCD App-of-Apps manifest for bootstrapping applications. 🚀
   - `argocd-apps/`: Application manifests for various tools and services (e.g., ArgoCD, Traefik, Cilium, Infisical, etc.). 🧩
   - `argocd-apps-configuration/`: Configuration files and secrets for deployed applications. 🔐
   - `bootstrap/`: Initial bootstrap manifests and values for cluster setup. 🏁

## Features 🌟

 - **GitOps Workflow**: All cluster and application changes are managed via Git, enabling version control and auditability. 📝
 - **ArgoCD Integration**: Uses ArgoCD for continuous delivery and automated synchronization of cluster state. 🤖
 - **Modular Design**: Each cluster and application is managed independently, allowing for flexible deployments and updates. 🧱
 - **Support for Multiple Tools**: Includes manifests for networking (Cilium), ingress (Traefik), secrets management (Infisical, Sealed Secrets), monitoring (Kube Prometheus Stack, Uptime Kuma), and more. 🛠️

## Getting Started 🚦

1. **Clone the repository**:
   ```bash
   git clone https://github.com/mainman94/multi-k8s-infra.git
   cd multi-k8s-infra
   ```
2. **Review cluster directories** and select the desired cluster to deploy or manage. 🧐
3. **Apply bootstrap manifests** to initialize the cluster (see the `bootstrap/` directory in each cluster folder). 🏁
4. **Configure ArgoCD** using the `app-of-app/app-of-app.yaml` manifest. 🤖
5. **Manage applications** via ArgoCD, using the manifests in `argocd-apps/` and configuration in `argocd-apps-configuration/`. 🚀

## Prerequisites 🧑‍💻

 - Kubernetes clusters (provisioned via Rancher, cloud provider, or bare metal)
 - kubectl
 - ArgoCD
 - Access to required secrets and configuration files

## License 📄

This project is licensed under the MIT License.

---

Ready for lift-off? 🚀🛸✨