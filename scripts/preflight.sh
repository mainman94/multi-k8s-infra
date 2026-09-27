#!/usr/bin/env bash
# Preflight validation for the Talos GitOps repo: run everything a change has
# to pass, report every failure rather than stopping at the first.
#
# Invoked by `make preflight` and by the /preflight skill.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

fail=0
hr() { printf '\n=== %s ===\n' "$1"; }

hr "pre-commit (formatting, schema, hygiene)"
if command -v prek >/dev/null 2>&1; then
  prek run --all-files || fail=1
else
  echo "prek MISSING — skipped (install: mise install)"
fi

hr "kube-linter"
scripts/kube-lint.sh || fail=1

hr "kustomize build (overlays + bases)"
scripts/kustomize-build.sh || fail=1

hr "result"
if [ "$fail" -eq 0 ]; then echo "PREFLIGHT PASSED"; else echo "PREFLIGHT FAILED"; fi
exit "$fail"
