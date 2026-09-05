#!/usr/bin/env bash
# Build every Kustomize overlay and base under the cluster directory.
#
# `kind: Component` kustomizations are skipped: a component resolves against
# the overlay that includes it and is not buildable on its own.
#
# Used by pre-commit, `make kustomize` and scripts/preflight.sh.
set -uo pipefail

CLUSTER_DIR=${CLUSTER_DIR:-eggenberg-talos-cluster-1}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kustomize-build: kubectl not on PATH — skipped." >&2
  echo "  Install kubectl, or open the repo in .devcontainer, to get this check." >&2
  exit 0
fi

status=0
built=0

while IFS= read -r kustomization; do
  if grep -qE '^kind:[[:space:]]*Component[[:space:]]*$' "$kustomization"; then
    continue
  fi
  dir=$(dirname "$kustomization")
  if ! err=$(kubectl kustomize "$dir" 2>&1 >/dev/null); then
    printf 'kustomize build failed: %s\n' "$dir" >&2
    printf '%s\n' "$err" | sed 's/^/  /' >&2
    status=1
  fi
  built=$((built + 1))
done < <(find "$CLUSTER_DIR" -name kustomization.yaml | sort)

if [ "$status" -eq 0 ]; then
  printf 'kustomize: %d builds OK\n' "$built"
fi

exit "$status"
