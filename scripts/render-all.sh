#!/usr/bin/env bash
# Render every buildable kustomization into <output-dir>, one file per
# kustomization, so two revisions can be diffed against each other.
#
# Used by .github/workflows/manifest-diff.yml. Always exits 0: a base
# revision that no longer builds must not fail the diff job, and the
# kustomize-build hook already gates buildability on the PR head.
set -uo pipefail

CLUSTER_DIR=${CLUSTER_DIR:-eggenberg-talos-cluster-1}
out=${1:?usage: render-all.sh <output-dir>}
mkdir -p "$out"

command -v kubectl >/dev/null 2>&1 || {
  echo "render-all: kubectl not on PATH" >&2
  exit 0
}

while IFS= read -r kustomization; do
  if grep -qE '^kind:[[:space:]]*Component[[:space:]]*$' "$kustomization"; then
    continue
  fi
  dir=$(dirname "$kustomization")
  name=${dir//\//__}
  if ! kubectl kustomize "$dir" >"$out/$name.yaml" 2>"$out/$name.build-error"; then
    rm -f "$out/$name.yaml"
  else
    rm -f "$out/$name.build-error"
  fi
done < <(find "$CLUSTER_DIR" -name kustomization.yaml | sort)

exit 0
