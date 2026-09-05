#!/usr/bin/env bash
# Run kube-linter over the cluster manifests, using .kube-linter.yaml.
# Used by pre-commit, `make kube-lint` and scripts/preflight.sh.
set -uo pipefail

CLUSTER_DIR=${CLUSTER_DIR:-eggenberg-talos-cluster-1}

if ! command -v kube-linter >/dev/null 2>&1; then
  echo "kube-lint: kube-linter not on PATH — skipped." >&2
  echo "  Install it, or open the repo in .devcontainer, to get this check." >&2
  echo "  CI runs it regardless (.github/workflows/argocd-lint.yml)." >&2
  exit 0
fi

exec kube-linter lint --config .kube-linter.yaml "$CLUSTER_DIR/"
