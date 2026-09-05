## What

<!-- One or two sentences. -->

## Why

<!-- The problem this solves. Link the issue if there is one. -->

## Checklist

<!-- ArgoCD syncs whatever reaches main, so this is the last gate. -->

- [ ] `make preflight` passes (hooks, kube-linter, every kustomize build)
- [ ] New app: manifest added under `argocd-apps/<name>/` — the app-of-apps
      recurses, so there is no manual wiring to do
- [ ] Secrets go through External Secrets + OpenBao; nothing plaintext
- [ ] Image tags in `pmhme` overlays left to argocd-image-updater / Kargo,
      unless a hand-edit is the point of this PR
