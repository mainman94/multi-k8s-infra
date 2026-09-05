#!/usr/bin/env bash
# Provision the dev container with the tools the repo's checks need.
# kube-linter and kubeconform have no devcontainer feature, so they are
# fetched here at pinned versions.
set -euo pipefail

KUBE_LINTER_VERSION=v0.8.3
KUBECONFORM_VERSION=v0.7.0

echo "==> installing pre-commit"
pipx install pre-commit 2>/dev/null || pip install --user --break-system-packages pre-commit
export PATH="$HOME/.local/bin:$PATH"

echo "==> installing kube-linter ${KUBE_LINTER_VERSION}"
curl -sSL "https://github.com/stackrox/kube-linter/releases/download/${KUBE_LINTER_VERSION}/kube-linter-linux.tar.gz" \
  | sudo tar xz -C /usr/local/bin kube-linter

echo "==> installing kubeconform ${KUBECONFORM_VERSION}"
curl -sSL "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" \
  | sudo tar xz -C /usr/local/bin kubeconform

echo "==> installing the git hook"
pre-commit install

echo "==> warming hook environments"
pre-commit install-hooks

cat <<'MSG'

multi-k8s-infra dev container ready.

  make help        list every target
  make preflight   the full gate: hooks + kube-linter + every kustomize build

ArgoCD applies whatever reaches main, so run preflight before you push.
MSG
