# CNPG Migration — contact-postgres → CloudNativePG

**Date:** 2026-07-23
**Repo:** `multi-k8s-infra` (GitOps, cluster `eggenberg-talos-cluster-1`)
**Status:** Approved (brainstorm) → ready for implementation plan

## Problem

The pmhme contact backend's Postgres is a hand-rolled single-replica `StatefulSet`
(`pmhme/base/postgres.yaml`): no failover, no PITR, backup only via Velero/kopia
filesystem snapshot (crash-consistent, not WAL-consistent). It runs in all three
overlays (dev/test/production).

## Goal

Replace it with a CloudNativePG (CNPG) `Cluster` giving:
- **HA**: 1 primary + 1 replica, streaming replication, automatic failover.
- **PITR**: continuous WAL + scheduled base backups to Backblaze B2 (Barman).
- **Operator lifecycle**: managed minor-version upgrades, reconciliation.

Password material still flows from OpenBao (ESO). contact-api changes only its
DB host. Migration is **greenfield** — contact-api recreates `contact_requests`
on boot (`CREATE TABLE IF NOT EXISTS`); existing rows are dropped. Change lands
in all three overlays on next sync.

## Decisions (locked during brainstorm)

1. **HA topology**: `instances: 2` (multi-node cluster; primary + replica on
   different nodes via pod anti-affinity).
2. **Backup**: Barman → B2 (PITR). Velero stops backing up the Postgres PVs.
3. **Data**: greenfield — no dump/restore, empty start, table auto-created.
4. **Rollout**: all three overlays cut over at once (base swap).
5. **Barman integration**: in-tree `spec.backup.barmanObjectStore` for now;
   the barman-cloud plugin (CNPG ≥1.26 direction) is the documented upgrade path.
6. **Storage**: dedicated `longhorn-cnpg` StorageClass at **replica=1** — CNPG
   replicates at the PG layer, so Longhorn's default 2× replication would be
   redundant IO/space. PG-layer redundancy replaces storage-layer redundancy.
7. **Credentials source unchanged**: reuse the ESO-managed `contact-db` secret as
   the CNPG app-user secret (password stays in OpenBao `prod/contact`, per-env
   property patch unchanged).

---

## Architecture

### Component 1 — CNPG operator (new ArgoCD app)

- `argocd-apps/cloudnative-pg/cloudnative-pg.yaml` — 3-source Helm Application,
  chart `cloudnative-pg` from `https://cloudnative-pg.github.io/charts`, namespace
  `cnpg-system`, label `category: storage`, `CreateNamespace=true`,
  `ServerSideApply=true` (CRDs are large).
- `argocd-apps-configuration/cloudnative-pg/values.yaml` — operator resource
  requests/limits; monitoring (PodMonitor) enabled with
  `additionalLabels.release: kube-prometheus-stack`.
- Cluster-scoped; installs `postgresql.cnpg.io` CRDs. Auto-registered via the
  app-of-apps recurse. No sync-wave needed (the per-env `Cluster` CRs self-heal
  and retry if they reach the API before the CRD exists).

**Interface:** provides the `Cluster` / `Backup` / `ScheduledBackup` CRDs and the
`<cluster>-rw` / `-ro` / `-r` Services + `<cluster>-app` conventions consumed by
the pmhme base.

### Component 2 — `contact-postgres` Cluster (pmhme base)

Replaces `pmhme/base/postgres.yaml` with `pmhme/base/postgres.yaml` rewritten to
a `Cluster` (keep the filename so `base/kustomization.yaml` needs no reorder; or
rename to `cluster.yaml` and update the kustomization — implementer's choice,
plan picks one). Key spec:

- `metadata.name: contact-postgres` → Services become `contact-postgres-rw`
  (primary), `contact-postgres-ro` (replicas), `contact-postgres-r` (any).
- `instances: 2`.
- `imageName: ghcr.io/cloudnative-pg/postgresql:18` (matches current 18.4).
- `storage.storageClass: longhorn-cnpg`, `storage.size: 2Gi` (matches current).
- `affinity.enablePodAntiAffinity: true`, `topologyKey: kubernetes.io/hostname`.
- `bootstrap.initdb`: `database: contact`, `owner: contact`,
  `secret: {name: contact-db}` (reuse ESO secret; CNPG reads `username`/`password`
  keys — see Component 4 note).
- `resources.requests/limits` set inline (cpu 50m/500m, memory 128Mi/512Mi —
  the current values). No VPA on the Cluster (CNPG owns pod resizing).
- `monitoring.enablePodMonitor: true` with `podMonitorMetricRelabelings`/labels so
  the PodMonitor carries `release: kube-prometheus-stack`. Replaces the
  postgres-exporter sidecar + hand-written ServiceMonitor.
- `backup.barmanObjectStore` — see Component 3.

**Removed:** the StatefulSet, the plain Service, the postgres-exporter sidecar,
the ServiceMonitor (all folded into the Cluster/PodMonitor), and the
`contact-postgres-vpa` from `base/backend-vpa.yaml`.

**Interface:** exposes `contact-postgres-rw:5432` for the app; PodMonitor for
Prometheus; Barman archive in B2 for restore.

### Component 3 — Barman backup to B2

- New ESO `ExternalSecret` `cnpg-backup-s3` (per portfolio namespace, added to
  `base/kustomization.yaml`) sourcing `prod/backblaze` (reuse velero's
  `APPLICATION_KEY_ID_K8S_BACKUP` / `APPLICATION_KEY_K8S_BACKUP`). Produces a
  secret with `ACCESS_KEY_ID` / `ACCESS_SECRET_KEY` keys in CNPG's expected shape.
- `Cluster.spec.backup.barmanObjectStore`:
  - `destinationPath: s3://pmhme-k8s-backup/cnpg/<env>` — per-env path in the
    existing velero bucket (env comes from the namespace; base uses a placeholder
    rewritten per overlay OR each overlay patches the path — plan picks the
    mechanism, mirroring the existing `NAMESPACE_PLACEHOLDER` component pattern).
  - `endpointURL: https://s3.eu-central-003.backblazeb2.com`
  - `s3Credentials` → the `cnpg-backup-s3` secret keys.
  - `wal.compression: gzip`, `data.compression: gzip`.
  - **Backblaze B2 header note:** B2 rejects AWS SDK checksum/tagging headers
    (same issue fixed for Velero with `checksumAlgorithm: ""`). Verify CNPG's
    barman-cloud S3 calls succeed against B2; if uploads 400, this is the first
    suspect. Document as a validation checkpoint in the plan.
- `ScheduledBackup` (daily) targeting the cluster; `backup.retentionPolicy: 7d`.
- **Velero exclusion:** annotate the CNPG pods so
  `defaultVolumesToFsBackup` skips their PVs (`backup.velero.io/backup-volumes-excludes`
  or the pod-level opt-out annotation). CNPG PITR becomes the DB DR path; Velero
  still backs up the surrounding namespace objects.

### Component 4 — credentials

CNPG's `bootstrap.initdb.secret` expects a secret with `username` + `password`
keys (type `kubernetes.io/basic-auth`). The current `contact-db` ESO secret has
`POSTGRES_PASSWORD` + a templated `DATABASE_URL`. Reconcile:

- Extend the `contact-db` ExternalSecret template to also emit `username: contact`
  and `password: {{ .POSTGRES_PASSWORD }}` (basic-auth keys) so CNPG can consume
  it directly, while keeping `POSTGRES_PASSWORD` + `DATABASE_URL` for contact-api.
  Set `target.template.type: kubernetes.io/basic-auth` (superset keys are fine).
- **DATABASE_URL host change**: `@contact-postgres:5432` → `@contact-postgres-rw:5432`.
- Per-env password property patch (`POSTGRES_PASSWORD_DEV/TEST/PROD`) unchanged.

contact-api (`contact-api.yaml`) is otherwise untouched — it reads `DATABASE_URL`
from `contact-db`, which now points at the CNPG primary service.

### Component 5 — network policy

Rewrite `contact-postgres-netpol` (in `base/backend-netpol.yaml`) to select CNPG
pods by `cnpg.io/cluster: contact-postgres`. Allowed edges:
- **ingress** 5432 from contact-api (mutual auth), from peer CNPG instances
  (replication — same cluster label), from cnpg-system operator; 9187 metrics
  from monitoring (no mutual auth).
- **egress** DNS (kube-dns); 5432 to peer instances (replication); **world:443
  for Barman → B2**; operator API as needed.

The contact-api egress rule's Postgres target updates to the CNPG pod selector.

### Component 6 — storage class

Add `longhorn-cnpg` StorageClass (replica=1, `longhorn` provisioner) — either in
`longhorn/values.yaml` (chart `persistence`/extra SC) or a small SC manifest under
the longhorn config dir. Not marked default (the default `longhorn` SC stays for
everything else).

---

## File change summary

| Action | File |
|---|---|
| add | `argocd-apps/cloudnative-pg/cloudnative-pg.yaml` |
| add | `argocd-apps-configuration/cloudnative-pg/values.yaml` |
| add | `longhorn-cnpg` StorageClass (longhorn config) |
| rewrite | `pmhme/base/postgres.yaml` (StatefulSet+Svc+exporter+SM → `Cluster` + `PodMonitor`) |
| add | `pmhme/base/cnpg-backup-externalsecret.yaml` (ESO `cnpg-backup-s3`) |
| edit | `pmhme/base/kustomization.yaml` (add backup ES; adjust if file renamed) |
| edit | `pmhme/base/contact-db-externalsecret.yaml` (basic-auth keys + `-rw` host) |
| edit | `pmhme/base/backend-netpol.yaml` (`contact-postgres-netpol` → CNPG labels) |
| edit | `pmhme/base/backend-vpa.yaml` (drop `contact-postgres-vpa`) |
| edit | `velero/values.yaml` (exclude CNPG PVs) OR pod annotation in Cluster |
| edit | `.github/workflows/argocd-lint.yml` (kubeconform `-skip` add `Cluster`) |

Per-env backup path (`cnpg/<env>`) mechanism: reuse the `keda-ns-scoped`-style
kustomize replacement/placeholder pattern, or a per-overlay patch. Plan decides.

## Validation (per the plan's tasks)

- `kubectl kustomize` builds clean for dev/test/production.
- Rendered `Cluster` present in all three; DATABASE_URL host is `contact-postgres-rw`.
- `contact-postgres-vpa` absent; no StatefulSet named `contact-postgres`.
- kube-linter / kubeconform pass (with `Cluster` skipped in kubeconform).
- Post-sync (operational, not in-plan): CNPG cluster reports 2 healthy instances,
  `ScheduledBackup` completes to B2 (watch for the B2 checksum-header failure),
  contact-api readiness green, a test contact submission persists and survives a
  primary failover (`kubectl cnpg promote` drill).

## Out of scope

- barman-cloud plugin migration (in-tree object store used first; plugin is the
  documented next step).
- Preserving historical `contact_requests` rows (greenfield by decision).
- Migrating any other stateful workload (Valkey, NATS) to an operator.
- Connection pooling (CNPG `Pooler`/PgBouncer) — add later if contact-api
  connection churn warrants it.

## Risks / notes

- **B2 + barman-cloud header incompatibility** is the top unknown (same family as
  the Velero `checksumAlgorithm` fix). Validate the first backup explicitly; if it
  fails, investigate barman-cloud S3 endpoint options before widening rollout.
- **CRD-before-CR ordering** on first sync: the `Cluster` CRs may reach the API
  before the operator installs the CRD; `selfHeal` + retry covers it, same as the
  kyverno-policies wave pattern (no explicit wave added unless it proves flaky).
- **Double-replication trap** avoided by the `longhorn-cnpg` replica=1 SC — call
  this out so no one "fixes" it back to the 2× default.
- **All-envs blast radius**: greenfield means each env's contact history is wiped
  on cutover. Accepted by decision (low-value contact-form data, table
  auto-created).
