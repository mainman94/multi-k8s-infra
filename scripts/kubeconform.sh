#!/usr/bin/env bash
# Schema-validate every manifest in the repo against the upstream Kubernetes
# schemas plus the datreeio CRD catalog.
#
# Used by `make kubeconform` and .github/workflows/argocd-lint.yml, so the
# flags live in one place instead of drifting between the two.
#
# Deliberately NOT passing -ignore-missing-schemas: that turned "I have no
# schema for this kind" into a silent pass, which is the opposite of what a
# schema check is for. Every CRD this repo uses — including Kargo's Warehouse
# and CNPG's Cluster, which were previously in an explicit -skip list — has a
# schema in the catalog. If a new CRD genuinely has none, add it to SKIP_KINDS
# below with a comment saying why, rather than blanketing the whole run.
set -uo pipefail

CLUSTER_DIR=${CLUSTER_DIR:-.}

# Kustomization/Component are kustomize build inputs, not cluster resources;
# they are excluded by filename below and listed here as a backstop for any
# that appear inline in a multi-document file.
SKIP_KINDS=${SKIP_KINDS:-Kustomization,Component}

CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

if ! command -v kubeconform >/dev/null 2>&1; then
  echo "kubeconform: not on PATH — skipped." >&2
  echo "  Run make tools (mise.toml pins it), or open the repo in .devcontainer." >&2
  exit 0
fi

# -strict rejects fields the schema does not define, which is what catches a
# misspelled key that would otherwise be silently ignored by the API server.
find "$CLUSTER_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) \
  -not -path './.github/*' \
  -not -path './.claude/*' \
  -not -name 'values.yaml' \
  -not -name 'kustomization.yaml' \
  -not -name '.kube-linter.yaml' \
  -not -name '.pre-commit-config.yaml' \
  -not -name 'mise.toml' \
  -not -name 'image-updater-dev.yaml' \
  -not -name '*-patch.yaml' \
  -print0 | xargs -0 kubeconform \
    -verbose \
    -strict \
    -summary \
    -skip "$SKIP_KINDS" \
    -schema-location default \
    -schema-location "$CATALOG"
