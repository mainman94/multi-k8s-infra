#!/usr/bin/env bash
# PostToolUse: auto-format edited YAML in the GitOps tree via pre-commit's yamlfmt.
# Reads hook JSON on stdin; no-op for non-yaml or files outside the cluster tree.
set -uo pipefail
f=$(jq -r '.tool_input.file_path // empty')
[ -z "$f" ] && exit 0
case "$f" in
  *eggenberg-talos-cluster-1/*.yaml|*eggenberg-talos-cluster-1/*.yml) ;;
  *) exit 0 ;;
esac
command -v pre-commit >/dev/null 2>&1 || exit 0
cd "$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null)" || exit 0
pre-commit run yamlfmt --files "$f" >/dev/null 2>&1 || true
exit 0
