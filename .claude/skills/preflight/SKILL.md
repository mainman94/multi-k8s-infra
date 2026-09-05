---
name: preflight
description: Validate GitOps manifests before commit — format check, kube-lint, and kustomize build of all overlays. Use before committing or opening a PR in this repo.
---

# preflight

Run repo validation and report failures concisely.

## Steps

1. Run `make preflight`.
2. Summarize: what passed, what failed, and the exact file:line of each failure.
3. If `yamlfmt` reports formatting diffs, offer to apply them (`make fmt`).
4. Do not commit if anything fails unless the user explicitly accepts.

## What it checks

- `pre-commit run --all-files` — yamlfmt formatting + any other configured hooks.
- `kube-linter lint` — if the binary is available (else skipped with a note).
- `kubectl kustomize` build of every `overlays/*` and `base/` dir — catches broken Kustomize.
