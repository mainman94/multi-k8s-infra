curl -sfL https://get.k3s.io | sh -s - server \
  --flannel-backend=none \
  --disable-network-policy \
  --disable-kube-proxy \
  --disable=traefik \
  --disable=servicelb \
  --cluster-init


helm install cilium cilium/cilium -n kube-system --values values.yaml

helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd --namespace argocd --version 9.0.5 -f values.yaml --create-namespace


curl -sfL https://get.k3s.io | sh -s - agent \
  --server https://192.168.0.50:6443 \
  --token TOKEN

longhorn
sudo apt install open-iscsi -y

kured
apt install unattended-upgrades apt-listchanges apt-config-auto-update
