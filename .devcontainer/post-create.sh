#!/usr/bin/env bash
# Provision the dev container. Every tool the repo's checks need — kubectl
# (which carries kustomize), kube-linter, kubeconform, python, pre-commit,
# actionlint, shellcheck, trivy — is pinned in mise.toml, so this installs
# mise and lets it do the rest. CI installs from the same file, which is what
# keeps a local `make preflight` honest.
set -euo pipefail

echo "==> installing mise"
curl -fsSL https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

# Activate for interactive shells so the pinned binaries are on PATH.
for shell in bash zsh; do
  rc="$HOME/.${shell}rc"
  [ -f "$rc" ] || continue
  grep -q "mise activate" "$rc" || echo "eval \"\$(mise activate $shell)\"" >> "$rc"
done

echo "==> installing the pinned toolchain"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mise trust
mise install

echo "==> installing the git hook"
mise exec -- pre-commit install

echo "==> warming hook environments"
mise exec -- pre-commit install-hooks

cat <<'MSG'

multi-k8s-infra dev container ready.

  make help        list every target
  make preflight   the full gate: hooks + kube-linter + every kustomize build

Tool versions come from mise.toml — the same file CI installs from.

ArgoCD applies whatever reaches main, so run preflight before you push.
MSG
