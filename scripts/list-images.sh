#!/usr/bin/env bash
# Every container image the repo's own apps run, taken from the rendered
# overlays rather than grepped out of the sources — an overlay's kustomize
# image transformers are what decide the final tag.
#
# Helm-chart apps are not covered: their images come from the chart's own
# defaults, which are not in this repo.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

CLUSTER_DIR=${CLUSTER_DIR:-eggenberg-talos-cluster-1}

for overlay in "$CLUSTER_DIR"/argocd-apps-configuration/pmhme/overlays/*/; do
  kubectl kustomize "$overlay"
done |
  grep -oE '^[[:space:]]+image:[[:space:]]*\S+' |
  sed -e 's/.*image:[[:space:]]*//' -e 's/"//g' |
  sort -u
