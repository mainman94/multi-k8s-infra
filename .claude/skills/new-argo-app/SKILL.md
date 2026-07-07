---
name: new-argo-app
description: Scaffold a new ArgoCD Application plus its configuration directory following this repo's GitOps conventions. Use when adding a new Helm app to the cluster.
disable-model-invocation: true
---

# new-argo-app

Scaffold a new app in the Talos GitOps repo. The root `app-of-app` recursively syncs
`eggenberg-talos-cluster-1/argocd-apps/`, so **creating the Application file is all that's
needed to register it** — no manual wiring.

## Inputs to collect

- `name` — app / dir name (kebab-case)
- `namespace` — target namespace (default: same as `name`)
- `chart` + `repoURL` + `targetRevision` (chart version) — from the Helm chart
- `category` label (optional, e.g. `monitoring`, `networking`)

## Steps

1. Create the Application manifest at
   `eggenberg-talos-cluster-1/argocd-apps/<name>/<name>.yaml` from
   `templates/application.yaml`, substituting the inputs.
2. Create the config dir with a starter values file at
   `eggenberg-talos-cluster-1/argocd-apps-configuration/<name>/values.yaml` from
   `templates/values.yaml`. Set sane resource requests/limits (kube-linter flags missing ones).
3. If the chart needs Kustomize instead of raw Helm values, mirror the `pmhme` layout
   (`base/` + `overlays/` + `components/`) and point the third source `path` at the base.
4. Run `/preflight` (or `pre-commit run --all-files`) to format + lint before committing.
5. Remind the user: commit + push → ArgoCD syncs. Do not `kubectl apply`.

## Notes

- Keep the 3-source pattern (chart + `ref: values` + config `path`) — see template.
- Never pin image tags that argocd-image-updater / Kargo manages.
- Secrets go through Infisical, never inline.
