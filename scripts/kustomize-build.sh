#!/usr/bin/env bash
# Build every Kustomize overlay and base under the cluster directory.
#
# `kind: Component` kustomizations are skipped: a component resolves against
# the overlay that includes it and is not buildable on its own.
#
# Used by pre-commit and `make kustomize`.
set -uo pipefail

CLUSTER_DIR=${CLUSTER_DIR:-eggenberg-talos-cluster-1}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kustomize-build: kubectl not on PATH — install it." >&2
  echo "  Install kubectl, or open the repo in .devcontainer, to run this check." >&2
  exit 1
fi

# Inside a git hook, GIT_DIR/GIT_INDEX_FILE point at this repository; the git
# clone kustomize runs for a remote base inherits them and checks out into
# our index instead of its own. Drop every repo-local git variable.
while IFS= read -r var; do unset "$var"; done < <(git rev-parse --local-env-vars)

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
