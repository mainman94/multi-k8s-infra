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
| `make tools`                   | Install the pinned toolchain from `mise.toml`       |
| `make hooks`                   | Install the git pre-commit hook (do this once)      |
| `make preflight`               | The full gate: hooks + kube-linter + every kustomize build |
| `make lint`                    | All pre-commit hooks over the whole tree            |
| `make fmt`                     | Reformat YAML and shell in place                    |
| `make kustomize`               | Build every overlay and base                        |
| `make kubeconform`             | Schema validation (needs network for the CRD catalog) |
| `make build OVERLAY=production`| Render one pmhme overlay to stdout                  |
| `make scan`                    | trivy config scan of the cluster manifests          |
| `make scan-images`             | CVE scan the images the repo's own apps run         |

`.devcontainer/` provides helm; everything else comes from mise.

**Tool versions live in `mise.toml` and nowhere else** — kubectl (which
carries kustomize), kube-linter, kubeconform, python, pre-commit, actionlint,
shellcheck and trivy. The dev container's post-create runs `mise install`, and
CI installs from the same file with `jdx/mise-action`. CI used to pin kubectl
v1.34.1 and kube-linter v0.8.3 in workflow env blocks while the dev container
installed `latest` of both, so a kustomize or lint behaviour change would land
in CI first and nobody's local run. Renovate bumps the pins.

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

Two more hooks cover the workflows: **`actionlint`** (schema, expressions and
the shell in `run:` blocks) and **`zizmor`** (CI/CD security patterns). zizmor
earns its place here because of `renovate-ai-automerge.yml`: a
`pull_request_target` workflow holding write permissions. Its ignore, with the
reasoning, is in `.github/zizmor.yml` — that workflow never checks the PR out
and gates on the head branch living in this repository, which is what makes
the trigger safe. Every action reference is pinned to a **commit SHA** with
the tag in a trailing comment; Renovate keeps the digests current.

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

## Scanning

Two workflows, deliberately split:

- **`argocd-lint.yml`** — schema and security: kubeconform, kube-linter,
  checkov (soft_fail). kubeconform runs `scripts/kubeconform.sh`, the same
  thing `make kubeconform` runs, so the flags cannot drift between them.
- **`ci.yml`** — the repo's own hooks, which is where the kustomize builds
  live. Nothing in CI checked those before, so a base or overlay that did not
  build reached `main` and ArgoCD found out first.
- **`manifest-diff.yml`** — renders every kustomization at the base and at the
  PR head and posts the difference as a PR comment. `preflight` proves the
  overlays still build; this shows what merging would actually change in the
  cluster, which is the thing a review should be reading.

**kubeconform no longer passes on missing schemas.** It ran with
`-ignore-missing-schemas` and an explicit `-skip InfisicalSecret,Warehouse,Cluster`,
which meant any kind the catalog did not know about was silently accepted —
the opposite of what a schema check is for. Every CRD this repo uses has a
schema in the datreeio catalog (Warehouse and Cluster included; InfisicalSecret
is gone since the move to external-secrets), so the run is now `-strict` with
no blanket ignore. A genuinely schema-less CRD goes in `SKIP_KINDS` in
`scripts/kubeconform.sh` with a comment saying why.

The one thing strict validation does need care with: a CRD can mark a field
`required` *and* give it a default, as Kargo's Warehouse does with `interval`.
The API server fills the default in, so the cluster accepts the manifest and a
static validator cannot. Write the documented default explicitly (that is what
`interval: 5m0s` in `warehouse.yaml` is) rather than skipping the kind.

Locally, `make scan` adds a trivy config pass over the manifests — a
different rule set from checkov, and worth running before a change that
touches securityContext or RBAC.

**Image CVE scanning is a local target, not a CI job.** `make scan-images`
sweeps the ten images the repo's own apps run, taken from the rendered
overlays rather than grepped out of sources, since an overlay's image
transformers decide the final tag. Five of them live in the private Gitea
registry behind Cloudflare, which only resolves from inside the network — a
GitHub-hosted runner cannot pull them, so a CI job would fail on half its
input. Helm-chart apps are not covered either: their images come from each
chart's defaults, which are not in this repo.

## Agent tooling

`.claude/` is checked in, so every agent working here starts from the same
setup:

- **`agents/manifest-reviewer.md`** — reviews changed manifests for security,
  resource hygiene and the conventions below. Worth asking for by name before
  pushing anything that changes a workload.
- **`skills/preflight/SKILL.md`** — runs `make preflight` and reports what
  failed.
- **`skills/new-argo-app/`** — scaffolds a new ArgoCD application from
  `templates/`, which keeps the 3-source Application pattern intact.
- **`hooks/guard-secrets.sh`** (PreToolUse) blocks a write that would commit a
  plaintext secret; **`hooks/format-yaml.sh`** (PostToolUse) formats what was
  just written, so `yamlfmt` in CI does not fail on whitespace.

The hooks fire automatically from `settings.json`; the agent and skills are
invoked deliberately.

## Merge requirements

Three checks are required on a pull request: `pre-commit`,
`Schema Validation (kubeconform)` and `Best Practices (kube-linter)`. The names
are the **job names** — the ruleset in the `homelab` repo matches on those, so
renaming a job in `ci.yml` or `argocd-lint.yml` without updating the ruleset
leaves every PR permanently `blocked` waiting for a check that no longer
reports under that name.

`manifest-diff.yml` and the checkov job are deliberately not required.
`manifest-diff.yml` is path-filtered, and a required check from a path-filtered
workflow never reports on a PR outside those paths — which blocks the PR
forever rather than passing it.

## Conventions

- Everything is YAML. Formatted by `yamlfmt` (`.yamlfmt`), linted by `kube-linter` (`.kube-linter.yaml`).
- Validate before commit: `make preflight`.
- Secrets via External Secrets Operator + OpenBao — never commit plaintext secrets. `gitleaks` runs on every commit as a backstop, not as the rule.
- Backups: Velero + Kopia → Backblaze S3.

## Tooling notes

- No standalone `yamlfmt`/`kube-linter` on PATH outside the dev container — they run through `pre-commit` and `scripts/`.
- Kustomize builds via `kubectl kustomize <dir>` (no standalone `kustomize`).
- `helm` and `kubectl` are available in the dev container.
