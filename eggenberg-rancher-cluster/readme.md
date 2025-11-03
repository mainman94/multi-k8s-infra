curl -sfL https://get.k3s.io | sh -s - server \
  --cluster-init \
  --disable=traefik


helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd --namespace argocd --version 9.0.5 -f values.yaml --create-namespace