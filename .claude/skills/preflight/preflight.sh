#!/usr/bin/env bash
# Preflight validation for the Talos GitOps repo. Non-fatal per-check; exits 1 if any fail.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

fail=0
hr() { printf '\n=== %s ===\n' "$1"; }

hr "pre-commit (yamlfmt + hooks)"
if command -v pre-commit >/dev/null 2>&1; then
  pre-commit run --all-files || fail=1
else
  echo "pre-commit MISSING — skipped"
fi

hr "kube-linter"
if command -v kube-linter >/dev/null 2>&1; then
  kube-linter lint eggenberg-talos-cluster-1/ || fail=1
else
  echo "kube-linter not on PATH — skipped (install: brew install kube-linter)"
fi

hr "kustomize build (overlays + bases)"
while IFS= read -r k; do
  d=$(dirname "$k")
  # kind: Component is not buildable standalone (it resolves against the overlay
  # that includes it); only build overlays + bases.
  if grep -qE '^kind:[[:space:]]*Component[[:space:]]*$' "$k"; then
    continue
  fi
  if ! kubectl kustomize "$d" >/dev/null 2>&1; then
    echo "BUILD FAILED: $d"
    fail=1
  fi
done < <(find eggenberg-talos-cluster-1 -name kustomization.yaml)
[ "$fail" -eq 0 ] && echo "all kustomize builds OK"

hr "result"
if [ "$fail" -eq 0 ]; then echo "PREFLIGHT PASSED"; else echo "PREFLIGHT FAILED"; fi
exit "$fail"
