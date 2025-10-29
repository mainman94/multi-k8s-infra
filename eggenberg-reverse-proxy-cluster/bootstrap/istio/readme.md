helm install istio-base istio/base -n istio-system --create-namespace --wait
helm install istiod istio/istiod -n istio-system --wait -f istiod-values.yaml
helm install istio-cni istio/cni -n istio-system --wait -f cni-values.yaml
helm install ztunnel istio/ztunnel -n istio-system --wait -f ztunnel-values.yaml