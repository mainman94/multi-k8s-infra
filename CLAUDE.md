# CLAUDE.md

Talos Linux + Kubernetes homelab, managed fully via GitOps. Push to Git → ArgoCD syncs. No `kubectl apply` for app changes.

## Layout (`eggenberg-talos-cluster-1/`)

- `app-of-app/app-of-app.yaml` — root ArgoCD Application. Recursively syncs everything under `argocd-apps/` (`directory.recurse: true`).
- `argocd-apps/<name>/` — ArgoCD `Application` manifests (one dir per app). Adding a file here auto-registers it via the app-of-apps recurse — no manual wiring.
- `argocd-apps-configuration/<name>/` — Helm `values.yaml` and/or Kustomize `base/`, `overlays/`, `components/` for each app.
- `bootstrap/` — one-time cluster setup (Cilium, ArgoCD). Not synced by ArgoCD.

## App pattern (3-source Application)

Standard Helm app references chart + values + config path from this repo:

```yaml
spec:
  sources:
    - repoURL: <chart-repo>
      targetRevision: <chart-version>
      chart: <chart>
      helm:
        valueFiles:
          - $values/eggenberg-talos-cluster-1/argocd-apps-configuration/<name>/values.yaml
    - repoURL: https://github.com/mainman94/multi-k8s-infra
      targetRevision: HEAD
      ref: values
    - repoURL: https://github.com/mainman94/multi-k8s-infra
      targetRevision: HEAD
      path: "eggenberg-talos-cluster-1/argocd-apps-configuration/<name>"
```

`pmhme` (custom apps) uses Kustomize instead: `base/` + `overlays/{dev,test,production}` + `components/`. Images bumped by argocd-image-updater / Kargo — do not hand-edit image tags in overlays unless asked.

## Conventions

- Everything is YAML. Formatted by `yamlfmt` (`.yamlfmt`), linted by `kube-linter` (`.kube-linter.yaml`, excludes `dangling-service` for Rollouts-backed services).
- Validate before commit: `pre-commit run --all-files` and `/preflight`.
- Secrets via External Secrets Operator + OpenBao — never commit plaintext secrets.
- Backups: Velero + Kopia → Backblaze S3.

## Tooling notes

- No standalone `yamlfmt`/`kube-linter` on PATH — they run through `pre-commit`.
- Kustomize builds via `kubectl kustomize <dir>` (no standalone `kustomize`).
- `helm` and `kubectl` are available.
