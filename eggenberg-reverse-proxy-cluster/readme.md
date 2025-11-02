curl -sfL https://get.k3s.io | sh -s - server \
  --flannel-backend=none \
  --disable-network-policy \
  --disable-kube-proxy \
  --disable=traefik \
  --disable=servicelb \
  --cluster-init


helm install cilium cilium/cilium -n kube-system --values values.yaml

helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd --namespace argocd --version 9.0.5 -f values.yaml --create-namespace