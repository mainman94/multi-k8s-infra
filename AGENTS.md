<!-- graft:start -->
## Graft — repo context graph

This repo is indexed in `graft/`: small linked markdown nodes that explain each
system and carry exact file:line spans, kept in sync with the code through git.

For ANY task here — understanding how something works, finding where code lives,
or scoping a change — get context from the graph before grepping or opening
source files. Re-ask freely (it's cheap) and reuse literal identifiers you
already have (symbol, error string, file name) as the query. New to this repo?
Run `graft map` first — a token-budgeted orientation (dir clusters, hubs,
hotspots), no LLM, no key.

- Run `graft ask "<your question>" --source` → ranked nodes with the relevant
  code spans inlined (each hit's ≤8-line crux by default; `--full` for whole
  definitions when the crux isn't enough). Match the tool to the task shape:
  for understanding or editing, the top node IS the answer — cite its
  `covers:` file:line spans and edit straight from `--source`. For
  exhaustive tasks ("every occurrence / every caller of this pattern"), ranked
  results are top-N, not complete — run `graft grep "<literal>"` instead
  (exhaustive over indexed files, grouped by enclosing symbol), falling back
  to raw `grep -rn` only for unindexed files.
- `graft skeleton <file>` → every definition's signature + span, ~10× cheaper
  than reading the file; use it to skim an API surface.
- `graft callers <symbol>` gives precomputed, exact edges — who calls this.
  Add `--direction out` for what it calls, or `--depth N` to walk
  transitively for the full blast radius. For structural questions, skip
  ranking and use this directly.
- Or browse: `graft/INDEX.md` lists every node; follow the links.
- Monorepos and folders of multiple repos rank fairly across sub-projects —
  hits carry `[scope/]` labels naming which one they're from. Narrow with
  `graft ask "<task>" --in <scope>/` once you know where you're working.

If a returned span is truncated ("+N more lines"), open the file at that exact
range before finalizing. Only open source files when a node genuinely lacks a
needed detail, and then at the exact file:line the node points to — never
re-read whole files.

After big code changes, refresh the graph with `graft build` (deterministic,
no API key, $0).
<!-- graft:end -->

# AGENTS

Talos Linux + Kubernetes homelab, managed fully via GitOps. Push to git →
ArgoCD syncs. No `kubectl apply` for app changes — which means whatever
reaches `main` reaches the cluster, and `make preflight` is the last gate.

## Local workflow

| Command                        | What it does                                        |
| ------------------------------ | --------------------------------------------------- |
| `make help`                    | List every target                                   |
| `make hooks`                   | Install the git pre-commit hook (do this once)      |
| `make preflight`               | The full gate: hooks + kube-linter + every kustomize build |
| `make lint`                    | All pre-commit hooks over the whole tree            |
| `make fmt`                     | Reformat YAML and shell in place                    |
| `make kustomize`               | Build every overlay and base                        |
| `make kubeconform`             | Schema validation (needs network for the CRD catalog) |
| `make build OVERLAY=production`| Render one pmhme overlay to stdout                  |

`.devcontainer/` provides kubectl, helm, kube-linter, kubeconform and the hook
toolchain if you would rather not install them locally.

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

## Automated checks

`.pre-commit-config.yaml` runs on every commit and mirrors
`.github/workflows/argocd-lint.yml`, minus kubeconform — that one fetches CRD
schemas over the network, so it stays in CI and in `make kubeconform`.

Two hooks are repo-specific:

- **`kustomize-build`** — builds every overlay and base under `pmhme/`. A
  kustomization that does not build is a manifest ArgoCD cannot sync.
  `kind: Component` kustomizations are skipped: a component resolves against
  the overlay that includes it and is not buildable alone.
- **`kube-linter`** — workload best practices, configured by
  `.kube-linter.yaml` (which excludes `dangling-service`, a false positive for
  Rollouts-backed services).

Both skip with a printed note when their binary is missing, so a checkout
without kubectl still commits — CI does not skip. Install the tools or use
the dev container.

`yamlfmt` deliberately excludes `pmhme/overlays/*/kustomization.yaml`: Kargo
rewrites those on every promotion in kyaml's indentless list style, so
formatting them just produces a diff the next promotion flips back.

## Conventions

- Everything is YAML. Formatted by `yamlfmt` (`.yamlfmt`), linted by `kube-linter` (`.kube-linter.yaml`).
- Validate before commit: `make preflight`.
- Secrets via External Secrets Operator + OpenBao — never commit plaintext secrets. `gitleaks` runs on every commit as a backstop, not as the rule.
- Backups: Velero + Kopia → Backblaze S3.

## Tooling notes

- No standalone `yamlfmt`/`kube-linter` on PATH outside the dev container — they run through `pre-commit` and `scripts/`.
- Kustomize builds via `kubectl kustomize <dir>` (no standalone `kustomize`).
- `helm` and `kubectl` are available in the dev container.
