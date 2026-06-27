# Portfolio Delivery Pipeline — Design

**Date:** 2026-06-27
**Repos:** `multi-k8s-infra` (GitOps) + `portfolio` (app + backend services CI)
**Status:** Approved (brainstorm) → ready for implementation plan

## Problem

The new portfolio is a monorepo with a frontend (`pmhme`) plus three backend services
(`contact-api`, `notifier-telegram`, `notifier-email`). The portfolio CI now publishes **all
images to `ghcr.io/mainman94/*`**, but the infra repo is still wired for the old world:

- The contact backend (contact-api, notifiers, NATS, Postgres) exists **only in the production
  overlay**, so it bypasses dev→test→prod entirely.
- argocd-image-updater and the Kargo Warehouse still track the dead `dockerha08/pmhme` image.
- Pull secrets / Kargo creds still point at Docker Hub, not ghcr (which is **private**).
- The four images are versioned in lockstep by a single repo-wide CI tag; we want **independent
  per-service versions**.

## Goal

Every change to the new portfolio — frontend or any backend service — flows
**dev → test → prod**, with **argocd-image-updater driving dev** and **Kargo driving test and
prod**, each service versioned independently. dev/test exercise the backend against **sinks** so
no real notifications leave those environments.

## Decisions (locked during brainstorm)

1. Backend runs in **all three envs** → move it into `pmhme/base/`.
2. **Independent per-image** versioning (not lockstep).
3. ghcr packages are **private** → GitHub-PAT pull secrets / registry creds everywhere.
4. **Per-service tag prefixes** in CI: each service bumps from its own path history.
5. dev/test notifiers target **in-cluster sinks**; prod uses real creds.

---

## Part 1 — Per-service versioning (portfolio repo CI)

Replace the single repo-wide `mathieudutour/github-tag-action` step with **per-service**
versioning. Each service has an independent semver series tracked via a **prefixed git tag**;
the **docker image tag is the stripped semver** so the infra-side regex stays plain semver.

| Service | Bump trigger path | Git tag series | Image | Image tags |
|---|---|---|---|---|
| frontend | everything **not** under `services/` (`src/`, `public/`, `Dockerfile`, `package.json`, `bun.lock`, …) | `pmhme-vX.Y.Z` | `ghcr.io/mainman94/pmhme` | `X.Y.Z`, `latest` |
| contact-api | `services/contact-api/**` | `contact-api-vX.Y.Z` | `ghcr.io/mainman94/contact-api` | `X.Y.Z`, `latest` |
| notifier-telegram | `services/notifier-telegram/**` | `notifier-telegram-vX.Y.Z` | `ghcr.io/mainman94/notifier-telegram` | `X.Y.Z`, `latest` |
| notifier-email | `services/notifier-email/**` | `notifier-email-vX.Y.Z` | `ghcr.io/mainman94/notifier-email` | `X.Y.Z`, `latest` |

**Behavior:**
- Per-service bump = conventional-commit rules (`feat`→minor, `fix`→patch, `BREAKING CHANGE`→major,
  default patch) applied to commits touching **that service's path** since **that service's** last
  `<svc>-v*` tag. Frontend path = repo minus `services/`.
- **Build + push only the services whose path changed** since their last tag. Unchanged services are
  not rebuilt; their previous image tag remains the newest.
- The image tag pushed is the prefix-stripped `X.Y.Z` (plus `latest`) on each image's own ghcr repo.
- `VERSION` build-arg per image = that service's new `X.Y.Z`.
- The frontend `/version` endpoint continues to return the frontend's `X.Y.Z` (drives the Kargo
  `version-check`).

**Implementation note (for the plan):** `mathieudutour/github-tag-action` does not filter commits by
path. The per-service bump is computed manually: find the service's last `<svc>-v*` tag, run
`git log <lasttag>..HEAD -- <path>` to collect commit subjects, classify the highest bump, compute
the next version, create the prefixed tag, push the image. CI jobs: one bump+build per service
(matrix over the 4 services, each gated by "did this path change since its last tag").

## Part 2 — Infra manifest layout (`multi-k8s-infra`)

`argocd-apps-configuration/pmhme/`:

- **Move backend into `base/`**: `postgres.yaml`, `nats.yaml`, `contact-api.yaml`,
  `notifier-telegram.yaml`, `notifier-email.yaml`, `netpol.yaml` (the per-workload Cilium policies),
  added to `base/kustomization.yaml`. Delete the separate `backend/` dir and the prod-only
  `- ../../backend` include.
- **netpols ship in base from the start** (complete, default-deny) — not staged later — because all
  three envs are fresh GitOps deploys.
- **Frontend base image → `ghcr.io/mainman94/pmhme`** (drop `dockerha08/pmhme:latest` and the
  `newName: ghcr.io/mainman94/pmhme` remap from every overlay). Backend base images already use
  `ghcr.io/mainman94/<svc>` (no tag).
- **Base HTTPRoute gains a rule**: path `/api/contact` → `contact-api:8080`; `/` stays →
  `portfolio-service`. `/internal/*` gets **no** route (cluster-only; enforced by netpol).
- **Overlays** (`dev`, `test`, `production`) each carry an `images:` block with **4 entries setting
  `newTag` only**, all `ghcr.io/mainman94/<svc>`. These are the write targets for
  image-updater (dev) and Kargo (test/prod). Overlays keep: namespace (PSS `restricted`),
  `STAGE`/`LOG_LEVEL` configmap patch, hostname patch (`dev.`/`test.`/root), prod `replicas: 3`.

**Image name agreement (must match exactly everywhere):** base manifests, overlay `images:` entries,
image-updater aliases, Kargo Warehouse subscriptions, Kargo stage `kustomize-set-image` — all
`ghcr.io/mainman94/{pmhme,contact-api,notifier-telegram,notifier-email}`.

## Part 3 — Promotion wiring

### Dev — argocd-image-updater (`argocd-apps/pmhme/image-updater-dev.yaml`)
- 4 image aliases, each `imageName: ghcr.io/mainman94/<svc>`, `updateStrategy: semver`,
  `allowTags: regexp:^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$`,
  `pullSecret: pullsecret:argocd/ghcr-pull-pat`.
- `writeBackConfig` unchanged (git write-back via `argocd/git-credentials`),
  `writeBackTarget: kustomization:.../overlays/dev`.
- A push that bumps only one service updates only that one `newTag` in the dev overlay → the
  `pmhme-portfolio-dev` Argo CD app syncs that change.

### Test + Prod — Kargo
- **Warehouse** (`kargo/pmhme-portfolio/warehouse.yaml`): **4 image subscriptions**
  (`ghcr.io/mainman94/<svc>`, `imageSelectionStrategy: SemVer`, plain-semver `allowTags`,
  `discoveryLimit`) **+** the existing git subscription on
  `.../overlays/dev/kustomization.yaml`. Freight bundles the newest tag of each of the 4 images;
  versions may differ. Reads ghcr via the Kargo image cred (Part 4).
- **Stages** (`stage-test.yaml`, `stage-prod.yaml`): `kustomize-set-image` lists **all 4 images**,
  each tag from `imageFrom(<repo>).Tag`; one `git-commit` / `git-push`; then `argocd-update` +
  the existing frontend smoke (`GET /`) and `version-check` (`GET /version` equals the frontend's
  deployed tag). Backend correctness is gated by readiness probes + Argo CD app health (no
  per-service HTTP check in this iteration). `imageRepo` var becomes the set of 4 repos.
- Chain unchanged: `Warehouse → test (auto-promote) → prod (auto-promote from test freight)`.
  dev validates first because image-updater writes the dev overlay and the Warehouse git
  subscription ties freight to that dev-overlay state.

## Part 4 — Secrets / Infisical (`infisical/infisicalsecret.yaml`)

- **ghcr pull secret** (`kubernetes.io/dockerconfigjson`, from a GitHub PAT with `read:packages`)
  templated into `portfolio`, `portfolio-dev`, `portfolio-test`, secret name kept as
  `docker-pull-secret` (manifests keep `imagePullSecrets: [docker-pull-secret]`; only contents
  change from Docker Hub to ghcr).
- **image-updater ghcr creds**: add a `ghcr-pull-pat` dockerconfigjson secret in the `argocd`
  namespace, referenced by the image-updater `pullSecret` (replaces the Docker Hub `docker-pull-pat`
  usage for this updater).
- **Kargo Warehouse ghcr cred**: replace the `dockerhub-creds` secret in `pmhme-portfolio` with a
  `ghcr-creds` image cred — `repoURL: ghcr.io/mainman94/*` (Kargo matches by repoURL prefix, so one
  entry covers all 4 images), `username: mainman94`, `password` = the PAT, label
  `kargo.akuity.io/cred-type: image`. (Rename for honesty; drop the old Docker Hub entry.)
- **contact-backend-secrets** templated into `portfolio-dev` and `portfolio-test` in addition to
  `portfolio`. In dev/test the Telegram/SMTP keys may be **dummy placeholders**; only
  `CONTACT_POSTGRES_PASSWORD` (and the derived `DATABASE_URL`) must be real per env. Real Telegram/
  SMTP creds only need to resolve for prod.

**New Infisical inputs:** one GHCR-capable PAT (reuse `ARGOCD_IMAGER_UPDATER_GIT_PAT` if it carries
`read:packages`, else add `GHCR_PULL_TOKEN`). Existing `CONTACT_*` keys already resolve for prod;
dev/test can reuse them or use throwaway values for the notifier creds.

## Part 5 — Sink for dev/test (overlay-scoped)

The backend (including both notifiers) lives in `base`; the **dev and test overlays** redirect
notifier egress to in-cluster sinks so nothing leaves those environments. **Prod is untouched** and
uses the real secrets/endpoints. No notifier code change (both services already support this:
email uses unauthenticated SMTP when `SMTP_USER` is empty — the code names Mailpit explicitly; the
telegram client only checks HTTP status, never parses the body).

Per dev/test overlay, add as resources + patches:
- **`mailpit`** Deployment + Service, SMTP `:1025` (optional web UI `:8025`) — catches email.
- **`telegram-sink`** Deployment + Service, static-200 responder (`traefik/whoami`) — absorbs the
  Telegram `sendMessage` POST.
- **Patch `notifier-email`**: `SMTP_HOST=mailpit`, `SMTP_PORT=1025`, `SMTP_USER=""` (remove those
  three `secretKeyRef`s; `SMTP_FROM` / `CONTACT_TO_EMAIL` stay, dummy-fine).
- **Patch `notifier-telegram`**: `TELEGRAM_API_BASE=http://telegram-sink` (bot token / chat id stay
  as dummy secret values).
- **Two companion CiliumNetworkPolicies** (dev/test only) allowing `notifier-telegram → telegram-sink`
  and `notifier-email → mailpit` egress. The base notifiers' `world` egress (443/587/465/25) goes
  unused in dev/test (left in place to keep overlays small).

Sinks and their netpols are PSS-`restricted`-compatible (runAsNonRoot, drop ALL, seccomp
RuntimeDefault, readOnlyRootFilesystem where the image allows).

---

## Components & boundaries

- **portfolio CI** — owns version computation + image publishing. Interface to infra = ghcr image
  tags (plain semver per repo). Independent of how infra promotes.
- **base kustomize** — the full app+backend stack, env-agnostic. Interface = image names + the
  `/api/contact` route + the contact-backend-secrets / docker-pull-secret contracts.
- **overlays** — env specialization: namespace, config, hostname, image tags, and (dev/test) sinks.
- **image-updater** — dev promotion: ghcr semver → dev overlay tags.
- **Kargo** — test/prod promotion: ghcr semver (+ dev git state) → test then prod overlay tags, with
  smoke/version gates.
- **Infisical** — secret material: ghcr pull creds, Kargo image cred, per-env backend secrets.

## Out of scope (this iteration)

- Per-service external version endpoints / per-service Kargo HTTP checks (backend gated by probes +
  app health only).
- JetStream/persistence for NATS (at-most-once is acceptable, unchanged).
- Migrating any non-portfolio app off Docker Hub.

## Risks / notes

- **Image-name drift** across the six locations is the main footgun — call it out explicitly in the
  plan and verify with `kustomize build` per overlay + a grep for stray `dockerha08`.
- **Private ghcr before creds exist** = `ImagePullBackOff`. Order the plan so Infisical ghcr secrets
  land (and sync) before the apps point at ghcr.
- **CI per-service bump logic** is the largest single change; it lives in the portfolio repo and can
  be implemented/tested independently of the infra changes (the two halves meet only at the agreed
  tag scheme).
- Implementation may split into **two plans** (portfolio CI; infra pipeline) that share this spec.
