# Portfolio Infra Pipeline Implementation Plan (Parts 2–5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the new portfolio (frontend + 3 backend services on `ghcr.io/mainman94/*`, private) flow dev→test→prod in the `multi-k8s-infra` GitOps repo: backend runs in all 3 envs, image-updater drives dev, Kargo drives test/prod, dev/test notifications hit in-cluster sinks.

**Architecture:** Kustomize base holds the full app+backend stack; overlays set per-env image tags + config; a shared kustomize Component injects notification sinks into dev/test only; Infisical templates ghcr pull secrets + per-env backend secrets; argocd-image-updater (dev) and Kargo Warehouse/Stages (test/prod) track the four ghcr images independently.

**Tech Stack:** Kustomize (`kubectl kustomize`), Cilium CNP, Gateway API HTTPRoute, Argo Rollouts, Kargo, argocd-image-updater, Infisical, Mailpit, traefik/whoami.

## Global Constraints

- Images (private): `ghcr.io/mainman94/{pmhme,contact-api,notifier-telegram,notifier-email}`. Overlays set `newTag` only; base references the ghcr name directly (NO `dockerha08` / `newName` remap anywhere).
- All four image names must agree across: base manifests, overlay `images:` entries, image-updater aliases, Kargo Warehouse subscriptions, Kargo stage `kustomize-set-image`.
- Backend (postgres, nats, contact-api, notifier-telegram, notifier-email) + its netpols live in `base/` so dev/test/prod each get a full stack. Namespaces are PSS `restricted` — every workload runs non-root, drops ALL caps, `readOnlyRootFilesystem`, `seccompProfile: RuntimeDefault`.
- Public contact path: HTTPRoute rule `/api/contact` → `contact-api:8080` (same namespace, no ReferenceGrant). `/internal/*` is never routed.
- dev/test notifier egress goes to in-cluster sinks (Mailpit for SMTP, traefik/whoami for the Telegram API); prod keeps real endpoints. Sinks live ONLY in dev/test (via a kustomize Component); prod must contain neither sink.
- Seed image tag is `0.1.3` for all four (matches the Part-1 CI seed).
- Validation per task: `kubectl kustomize <overlay>` builds clean for all of dev/test/production; `kubeconform -ignore-missing-schemas -skip InfisicalSecret,Warehouse,CiliumNetworkPolicy,Rollout,AnalysisTemplate` on changed rendered output; `grep -rn dockerha08` over `pmhme/` returns nothing after Task 1.
- New Infisical inputs the user must add (out of band, noted in Task 3): `GHCR_PULL_SECRET` (a full `.dockerconfigjson` string for `ghcr.io`) and `GHCR_PULL_TOKEN` (a raw GitHub PAT with `read:packages`). Existing `CONTACT_*` keys are reused for all three envs.
- Repo path prefix for all files below: `eggenberg-talos-cluster-1/argocd-apps-configuration/`. Abbreviated as `…/` in task file lists.
- Starting state (already on branch `feat/portfolio-delivery-pipeline`, uncommitted WIP): backend manifests exist in `pmhme/backend/`, referenced only by the production overlay; `infisicalsecret.yaml` already has a prod-only `contact-backend-secrets` block; overlays still carry the `dockerha08/pmhme`→ghcr `newName` remap.

---

### Task 1: Backend into base + frontend image to ghcr + /api/contact route

**Files:**
- Move: `…/pmhme/backend/{postgres,nats,contact-api,notifier-telegram,notifier-email}.yaml` → `…/pmhme/base/`
- Move+rename: `…/pmhme/backend/netpol.yaml` → `…/pmhme/base/backend-netpol.yaml`
- Delete: `…/pmhme/backend/kustomization.yaml` and the now-empty `…/pmhme/backend/` dir
- Modify: `…/pmhme/base/kustomization.yaml`, `…/pmhme/base/rollout.yaml`, `…/pmhme/base/httproute.yaml`
- Modify: `…/pmhme/overlays/{dev,test,production}/kustomization.yaml`

**Interfaces:**
- Produces: a `base/` that renders the full app+backend stack with image `ghcr.io/mainman94/pmhme`; overlays that set `newTag` for all 4 ghcr images. Later tasks (image-updater, Kargo) write these overlay `newTag` values.

- [ ] **Step 1: Move backend files into base via git**

```bash
cd /Users/philipp/work/multi-k8s-infra/eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme
git add backend/   # stage the untracked WIP so git mv works cleanly
for f in postgres nats contact-api notifier-telegram notifier-email; do
  git mv backend/$f.yaml base/$f.yaml
done
git mv backend/netpol.yaml base/backend-netpol.yaml
git rm backend/kustomization.yaml
rmdir backend 2>/dev/null || true
ls base/ backend 2>&1 | head -40
```
Expected: backend manifests now under `base/`; `backend/` gone.

- [ ] **Step 2: Add backend resources to base kustomization**

Edit `…/pmhme/base/kustomization.yaml` — append to the `resources:` list (after the existing entries) so it reads exactly:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
# Standard labels on all resources and pod templates (not selectors).
# app.kubernetes.io/name feeds the alloy->Loki "app" log label.
labels:
  - pairs:
      app.kubernetes.io/name: pmhme-portfolio
      app.kubernetes.io/part-of: pmhme
    includeTemplates: true
resources:
  - configmap.yaml
  - rollout.yaml
  - service.yaml
  - service-preview.yaml
  - servicemonitor.yaml
  - httproute.yaml
  - analysis-template.yaml
  - pdb.yaml
  - networkpolicy.yaml
  - cilium-mtls-policy.yaml
  - postgres.yaml
  - nats.yaml
  - contact-api.yaml
  - notifier-telegram.yaml
  - notifier-email.yaml
  - backend-netpol.yaml
```

- [ ] **Step 3: Point the base frontend image at ghcr**

In `…/pmhme/base/rollout.yaml`, change the container image line from `image: dockerha08/pmhme:latest` to:

```yaml
          image: ghcr.io/mainman94/pmhme:latest
```
(Leave everything else in rollout.yaml unchanged. The tag `latest` is overridden per-env by the overlay `images:` `newTag`.)

- [ ] **Step 4: Add the /api/contact route to the base HTTPRoute**

Replace the `rules:` section of `…/pmhme/base/httproute.yaml` so the file reads exactly:

```yaml
# yamllint disable rule:line-length
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: portfolio-route
spec:
  parentRefs:
    - name: public
      namespace: cilium
      sectionName: https
  hostnames:
    - hauptmann.dev
  rules:
    # Public contact form submissions go to the contact-api (same namespace).
    # Only /api/contact is exposed; /internal/* is never routed.
    - matches:
        - path:
            type: PathPrefix
            value: /api/contact
      backendRefs:
        - name: contact-api
          port: 8080
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: portfolio-service
          port: 80
          # yamllint enable rule:line-length
```

- [ ] **Step 5: Rewrite the three overlay `images:` blocks + drop the prod backend include**

For `…/pmhme/overlays/dev/kustomization.yaml` set the `images:` block to (replacing the single `dockerha08/pmhme` remap):

```yaml
images:
  - name: ghcr.io/mainman94/pmhme
    newTag: 0.1.3
  - name: ghcr.io/mainman94/contact-api
    newTag: 0.1.3
  - name: ghcr.io/mainman94/notifier-telegram
    newTag: 0.1.3
  - name: ghcr.io/mainman94/notifier-email
    newTag: 0.1.3
```

Apply the SAME `images:` block to `…/pmhme/overlays/test/kustomization.yaml`.

For `…/pmhme/overlays/production/kustomization.yaml`: apply the same 4-entry `images:` block AND remove `- ../../backend` from `resources:` (backend is in base now). Keep the `replicas: 3` Rollout patch, the httproute-patch, and the configmap-patch. The prod `resources:` becomes:

```yaml
resources:
  - namespace.yaml
  - ../../base
```

- [ ] **Step 6: Validate all three overlays build and backend is present everywhere**

```bash
cd /Users/philipp/work/multi-k8s-infra
for e in dev test production; do
  echo "== $e =="
  kubectl kustomize eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays/$e \
    | grep -E "^kind:|name: (contact-api|contact-nats|contact-postgres|notifier-|portfolio-route|portfolio-app)$" | sort -u
done
```
Expected: each env lists Deployment/StatefulSet/Service for contact-api, contact-nats, contact-postgres, notifier-telegram, notifier-email, plus the Rollout and HTTPRoute.

- [ ] **Step 7: Confirm image names + no Docker Hub + /api/contact wired**

```bash
cd /Users/philipp/work/multi-k8s-infra
grep -rn "dockerha08" eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/ && echo "BAD: dockerha08 remains" || echo "no dockerha08 (good)"
kubectl kustomize eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays/production \
  | grep -A3 "value: /api/contact"
```
Expected: `no dockerha08 (good)`; the `/api/contact` match block present with `contact-api` backend.

- [ ] **Step 8: Commit**

```bash
git add -A eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme
git commit -m "feat(pmhme): move backend into base (all envs), frontend image to ghcr, /api/contact route"
```

---

### Task 2: dev/test notification sink (kustomize Component)

**Files:**
- Create: `…/pmhme/components/notification-sink/kustomization.yaml`
- Create: `…/pmhme/components/notification-sink/mailpit.yaml`
- Create: `…/pmhme/components/notification-sink/telegram-sink.yaml`
- Create: `…/pmhme/components/notification-sink/notifier-sink-patch.yaml`
- Create: `…/pmhme/components/notification-sink/sink-netpol.yaml`
- Modify: `…/pmhme/overlays/dev/kustomization.yaml`, `…/pmhme/overlays/test/kustomization.yaml`

**Interfaces:**
- Consumes: the base `notifier-email` / `notifier-telegram` Deployments (patches their env).
- Produces: in dev/test only, `mailpit` (SMTP :1025) and `telegram-sink` (HTTP :80→8080) Services; notifier env redirected to them; egress CNPs allowing notifier→sink.

- [ ] **Step 1: Create the Mailpit sink manifest**

Create `…/pmhme/components/notification-sink/mailpit.yaml`:

```yaml
# SMTP sink for dev/test: catches mail, nothing leaves the cluster.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mailpit
  labels:
    app: mailpit
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mailpit
  template:
    metadata:
      labels:
        app: mailpit
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: mailpit
          image: docker.io/axllent/mailpit:v1.21
          env:
            - name: MP_SMTP_BIND_ADDR
              value: "0.0.0.0:1025"
            - name: MP_UI_BIND_ADDR
              value: "0.0.0.0:8025"
          ports:
            - containerPort: 1025
              name: smtp
            - containerPort: 8025
              name: ui
          readinessProbe:
            tcpSocket:
              port: smtp
            initialDelaySeconds: 3
            periodSeconds: 10
          resources:
            requests:
              cpu: "10m"
              memory: "32Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
---
apiVersion: v1
kind: Service
metadata:
  name: mailpit
  labels:
    app: mailpit
spec:
  selector:
    app: mailpit
  ports:
    - name: smtp
      port: 1025
      targetPort: smtp
      protocol: TCP
```

- [ ] **Step 2: Create the Telegram sink manifest**

Create `…/pmhme/components/notification-sink/telegram-sink.yaml`:

```yaml
# Telegram API sink for dev/test: a static-200 responder. The telegram
# notifier only checks the HTTP status, never parses the body.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: telegram-sink
  labels:
    app: telegram-sink
spec:
  replicas: 1
  selector:
    matchLabels:
      app: telegram-sink
  template:
    metadata:
      labels:
        app: telegram-sink
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: whoami
          image: docker.io/traefik/whoami:v1.10
          args:
            - "--port=8080"
          ports:
            - containerPort: 8080
              name: http
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 3
            periodSeconds: 10
          resources:
            requests:
              cpu: "10m"
              memory: "16Mi"
            limits:
              cpu: "50m"
              memory: "64Mi"
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
---
apiVersion: v1
kind: Service
metadata:
  name: telegram-sink
  labels:
    app: telegram-sink
spec:
  selector:
    app: telegram-sink
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

- [ ] **Step 3: Create the notifier env patches**

Create `…/pmhme/components/notification-sink/notifier-sink-patch.yaml`:

```yaml
# Redirect notifier egress to the in-cluster sinks. SMTP_USER empty => the
# email notifier uses an unauthenticated relay (Mailpit). TELEGRAM_API_BASE
# points the telegram notifier at the static-200 sink.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notifier-email
spec:
  template:
    spec:
      containers:
        - name: notifier-email
          env:
            - name: SMTP_HOST
              value: mailpit
            - name: SMTP_PORT
              value: "1025"
            - name: SMTP_USER
              value: ""
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notifier-telegram
spec:
  template:
    spec:
      containers:
        - name: notifier-telegram
          env:
            - name: TELEGRAM_API_BASE
              value: http://telegram-sink
```

> Note: a strategic-merge patch merges env by `name`, so these entries override the base values (which use `secretKeyRef`) with literals. The remaining base env vars are untouched.

- [ ] **Step 4: Create the sink egress network policies**

Create `…/pmhme/components/notification-sink/sink-netpol.yaml`:

```yaml
# yamllint disable rule:line-length
# Allow notifier->sink egress in dev/test. Base backend-netpol already permits
# DNS + nats + contact-api egress; these add the sink targets. (The base
# world egress for real Telegram/SMTP simply goes unused in dev/test.)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: notifier-email-sink-egress
spec:
  endpointSelector:
    matchLabels:
      app: notifier-email
  egress:
    - toEndpoints:
        - matchLabels:
            app: mailpit
      toPorts:
        - ports:
            - port: "1025"
              protocol: TCP
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: notifier-telegram-sink-egress
spec:
  endpointSelector:
    matchLabels:
      app: notifier-telegram
  egress:
    - toEndpoints:
        - matchLabels:
            app: telegram-sink
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
# yamllint enable rule:line-length
```

- [ ] **Step 5: Create the Component kustomization**

Create `…/pmhme/components/notification-sink/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component
resources:
  - mailpit.yaml
  - telegram-sink.yaml
  - sink-netpol.yaml
patches:
  - path: notifier-sink-patch.yaml
```

- [ ] **Step 6: Wire the component into dev and test overlays**

Add to `…/pmhme/overlays/dev/kustomization.yaml` and `…/pmhme/overlays/test/kustomization.yaml` (after the `resources:` block, top-level key):

```yaml
components:
  - ../../components/notification-sink
```
Do NOT add it to the production overlay.

- [ ] **Step 7: Validate sinks present in dev/test, absent in prod**

```bash
cd /Users/philipp/work/multi-k8s-infra
P=eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays
echo "== dev sinks =="; kubectl kustomize $P/dev | grep -E "name: (mailpit|telegram-sink)$" | sort -u
echo "== dev notifier-email SMTP_HOST =="; kubectl kustomize $P/dev | grep -A1 "name: SMTP_HOST"
echo "== prod must have NO sinks =="; kubectl kustomize $P/production | grep -E "mailpit|telegram-sink" && echo "BAD: sink in prod" || echo "no sinks in prod (good)"
```
Expected: dev shows mailpit + telegram-sink and `SMTP_HOST` value `mailpit`; prod prints `no sinks in prod (good)`.

- [ ] **Step 8: Commit**

```bash
git add -A eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme
git commit -m "feat(pmhme): dev/test notification sink component (mailpit + telegram-sink)"
```

---

### Task 3: Infisical — ghcr pull secrets + Kargo cred + per-env backend secrets

**Files:**
- Modify: `…/infisical/infisicalsecret.yaml`

**Interfaces:**
- Produces: `docker-pull-secret` (ghcr) in `portfolio`/`portfolio-dev`/`portfolio-test`; `ghcr-pull-pat` in `argocd`; `ghcr-creds` (Kargo image cred) in `pmhme-portfolio`; `contact-backend-secrets` in all three portfolio namespaces. Consumed by Task 4 (image-updater pullSecret) and Task 5 (Kargo Warehouse).

- [ ] **Step 1: Repoint the three portfolio pull secrets to ghcr**

In `…/infisical/infisicalsecret.yaml`, for each of the three `docker-pull-secret` entries (namespaces `portfolio`, `portfolio-dev`, `portfolio-test`), change the template data line from the Docker Hub source to ghcr:

```yaml
        data:
          .dockerconfigjson: "{{ .GHCR_PULL_SECRET.Value }}"
```
(Keep `secretType: kubernetes.io/dockerconfigjson` and `creationPolicy: managed` unchanged on each.)

- [ ] **Step 2: Add the image-updater ghcr pull secret in argocd ns**

Add a new managed-secret block (alongside the existing `argocd`-namespace secrets):

```yaml
    - secretName: ghcr-pull-pat
      secretNamespace: argocd
      secretType: kubernetes.io/dockerconfigjson
      creationPolicy: "managed"
      template:
        includeAllSecrets: false
        data:
          .dockerconfigjson: "{{ .GHCR_PULL_SECRET.Value }}"
```

- [ ] **Step 3: Replace the Kargo Docker Hub cred with a ghcr cred**

Find the `dockerhub-creds` block (namespace `pmhme-portfolio`, label `kargo.akuity.io/cred-type: image`) and replace it entirely with:

```yaml
    - secretName: ghcr-creds
      secretNamespace: pmhme-portfolio
      creationPolicy: "managed"
      template:
        metadata:
          labels:
            kargo.akuity.io/cred-type: image
          annotations:
            kargo.akuity.io/cred-repo-is-regex: "true"
        includeAllSecrets: false
        data:
          repoURL: "ghcr.io/mainman94/.*"
          username: mainman94
          password: "{{ .GHCR_PULL_TOKEN.Value }}"
```

- [ ] **Step 4: Template contact-backend-secrets into dev and test**

The prod-only `contact-backend-secrets` block (namespace `portfolio`) already exists. Add two more identical blocks differing only by `secretNamespace: portfolio-dev` and `secretNamespace: portfolio-test`. Each block is exactly (changing only the namespace):

```yaml
    - secretName: contact-backend-secrets
      secretNamespace: portfolio-dev
      creationPolicy: "managed"
      template:
        includeAllSecrets: false
        data:
          POSTGRES_PASSWORD: "{{ .CONTACT_POSTGRES_PASSWORD.Value }}"
          DATABASE_URL: "postgres://contact:{{ .CONTACT_POSTGRES_PASSWORD.Value }}@contact-postgres:5432/contact"
          TELEGRAM_BOT_TOKEN: "{{ .CONTACT_TELEGRAM_BOT_TOKEN.Value }}"
          TELEGRAM_CHAT_ID: "{{ .CONTACT_TELEGRAM_CHAT_ID.Value }}"
          SMTP_HOST: "{{ .CONTACT_SMTP_HOST.Value }}"
          SMTP_PORT: "{{ .CONTACT_SMTP_PORT.Value }}"
          SMTP_USER: "{{ .CONTACT_SMTP_USER.Value }}"
          SMTP_PASS: "{{ .CONTACT_SMTP_PASS.Value }}"
          SMTP_FROM: "{{ .CONTACT_SMTP_FROM.Value }}"
          CONTACT_TO_EMAIL: "{{ .CONTACT_TO_EMAIL.Value }}"
```
(Then the same block again with `secretNamespace: portfolio-test`. The sinks in dev/test intercept egress, so reusing the real `CONTACT_*` values is safe — Telegram/SMTP never receive traffic there.)

- [ ] **Step 5: Validate YAML**

```bash
cd /Users/philipp/work/multi-k8s-infra
python3 -c "import yaml,sys; list(yaml.safe_load_all(open('eggenberg-talos-cluster-1/argocd-apps-configuration/infisical/infisicalsecret.yaml'))); print('yaml ok')"
grep -c "secretName: contact-backend-secrets" eggenberg-talos-cluster-1/argocd-apps-configuration/infisical/infisicalsecret.yaml
grep -nE "ghcr-pull-pat|ghcr-creds|GHCR_PULL_SECRET|GHCR_PULL_TOKEN|dockerhub-creds" eggenberg-talos-cluster-1/argocd-apps-configuration/infisical/infisicalsecret.yaml
```
Expected: `yaml ok`; `contact-backend-secrets` count = 3; `ghcr-pull-pat`, `ghcr-creds`, `GHCR_PULL_SECRET`, `GHCR_PULL_TOKEN` present; `dockerhub-creds` ABSENT.

- [ ] **Step 6: Commit**

```bash
git add eggenberg-talos-cluster-1/argocd-apps-configuration/infisical/infisicalsecret.yaml
git commit -m "feat(infisical): ghcr pull secrets + Kargo ghcr cred + contact secrets for dev/test"
```

> **Out-of-band (user action, document in report):** add Infisical keys `GHCR_PULL_SECRET` (full `.dockerconfigjson` for `ghcr.io`, e.g. `{"auths":{"ghcr.io":{"auth":"<base64 user:PAT>"}}}`) and `GHCR_PULL_TOKEN` (raw GitHub PAT with `read:packages`) in project `homelab-graz` / env `prod`. Until both exist, the managed secrets render empty and pulls/Kargo discovery fail.

---

### Task 4: argocd-image-updater — four ghcr aliases for dev

**Files:**
- Modify: `eggenberg-talos-cluster-1/argocd-apps/pmhme/image-updater-dev.yaml`

**Interfaces:**
- Consumes: `ghcr-pull-pat` secret in `argocd` (Task 3); writes `newTag` for the four images in the dev overlay (Task 1).

- [ ] **Step 1: Rewrite the ImageUpdater with four ghcr aliases**

Replace `eggenberg-talos-cluster-1/argocd-apps/pmhme/image-updater-dev.yaml` with:

```yaml
# yamllint disable rule:line-length
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: portfolio-updater-dev
  namespace: argocd
spec:
  applicationRefs:
    - namePattern: pmhme-portfolio-dev
      images:
        - alias: pmhme
          imageName: ghcr.io/mainman94/pmhme
          commonUpdateSettings:
            updateStrategy: semver
            allowTags: regexp:^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$
            forceUpdate: false
            pullSecret: pullsecret:argocd/ghcr-pull-pat
        - alias: contact-api
          imageName: ghcr.io/mainman94/contact-api
          commonUpdateSettings:
            updateStrategy: semver
            allowTags: regexp:^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$
            forceUpdate: false
            pullSecret: pullsecret:argocd/ghcr-pull-pat
        - alias: notifier-telegram
          imageName: ghcr.io/mainman94/notifier-telegram
          commonUpdateSettings:
            updateStrategy: semver
            allowTags: regexp:^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$
            forceUpdate: false
            pullSecret: pullsecret:argocd/ghcr-pull-pat
        - alias: notifier-email
          imageName: ghcr.io/mainman94/notifier-email
          commonUpdateSettings:
            updateStrategy: semver
            allowTags: regexp:^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$
            forceUpdate: false
            pullSecret: pullsecret:argocd/ghcr-pull-pat
  writeBackConfig:
    method: "git:secret:argocd/git-credentials"
    gitConfig:
      repository: "https://github.com/mainman94/multi-k8s-infra"
      branch: "main"
      writeBackTarget: "kustomization:/eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays/dev"
      # yamllint enable rule:line-length
```

- [ ] **Step 2: Validate YAML + image names**

```bash
cd /Users/philipp/work/multi-k8s-infra
python3 -c "import yaml; yaml.safe_load(open('eggenberg-talos-cluster-1/argocd-apps/pmhme/image-updater-dev.yaml')); print('yaml ok')"
grep -c "ghcr.io/mainman94/" eggenberg-talos-cluster-1/argocd-apps/pmhme/image-updater-dev.yaml
grep -n "dockerha08" eggenberg-talos-cluster-1/argocd-apps/pmhme/image-updater-dev.yaml || echo "no dockerha08 (good)"
```
Expected: `yaml ok`; ghcr count = 4; `no dockerha08 (good)`.

- [ ] **Step 3: Commit**

```bash
git add eggenberg-talos-cluster-1/argocd-apps/pmhme/image-updater-dev.yaml
git commit -m "feat(image-updater): track four ghcr images for dev"
```

---

### Task 5: Kargo — Warehouse + test/prod stages for four ghcr images

**Files:**
- Modify: `…/kargo/pmhme-portfolio/warehouse.yaml`
- Modify: `…/kargo/pmhme-portfolio/stage-test.yaml`
- Modify: `…/kargo/pmhme-portfolio/stage-prod.yaml`

**Interfaces:**
- Consumes: `ghcr-creds` in `pmhme-portfolio` (Task 3); writes `newTag` for the four images in the test/production overlays (Task 1).

- [ ] **Step 1: Rewrite the Warehouse with four ghcr image subscriptions**

Replace `…/kargo/pmhme-portfolio/warehouse.yaml` with:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: pmhme-portfolio
  namespace: pmhme-portfolio
spec:
  subscriptions:
    - git:
        repoURL: https://github.com/mainman94/multi-k8s-infra.git
        branch: main
        commitSelectionStrategy: NewestFromBranch
        includePaths:
          - eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays/dev/kustomization.yaml
    - image:
        repoURL: ghcr.io/mainman94/pmhme
        imageSelectionStrategy: SemVer
        allowTags: '^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$'
        discoveryLimit: 5
    - image:
        repoURL: ghcr.io/mainman94/contact-api
        imageSelectionStrategy: SemVer
        allowTags: '^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$'
        discoveryLimit: 5
    - image:
        repoURL: ghcr.io/mainman94/notifier-telegram
        imageSelectionStrategy: SemVer
        allowTags: '^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$'
        discoveryLimit: 5
    - image:
        repoURL: ghcr.io/mainman94/notifier-email
        imageSelectionStrategy: SemVer
        allowTags: '^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-zA-Z0-9.-]+)?(?:\+[a-zA-Z0-9.-]+)?$'
        discoveryLimit: 5
```

- [ ] **Step 2: Update the test stage to set all four images**

In `…/kargo/pmhme-portfolio/stage-test.yaml`, replace the single `imageRepo` var and the `kustomize-set-image` step's `images:` list so all four images are set. The `vars:` block keeps `gitRepo`, `repoPath`, `overlayPath` (value `…/overlays/test`), `appName` (`pmhme-portfolio-test`) and DROPS the single `imageRepo` var. Replace the `kustomize-set-image` step config with:

```yaml
        - uses: kustomize-set-image
          as: update-image
          config:
            path: ${{ vars.repoPath }}/${{ vars.overlayPath }}
            images:
              - image: ghcr.io/mainman94/pmhme
                tag: ${{ quote(imageFrom("ghcr.io/mainman94/pmhme").Tag) }}
              - image: ghcr.io/mainman94/contact-api
                tag: ${{ quote(imageFrom("ghcr.io/mainman94/contact-api").Tag) }}
              - image: ghcr.io/mainman94/notifier-telegram
                tag: ${{ quote(imageFrom("ghcr.io/mainman94/notifier-telegram").Tag) }}
              - image: ghcr.io/mainman94/notifier-email
                tag: ${{ quote(imageFrom("ghcr.io/mainman94/notifier-email").Tag) }}
```

In the same file, update the `yaml-parse` step's `deployedTag` expression to read the frontend image (the `/version` check is the frontend's tag):

```yaml
                fromExpression: filter(images, {.name == "ghcr.io/mainman94/pmhme"})[0].newTag
```
Leave the `git-clone`, `git-commit`, `git-push`, the `http` smoke (`https://dev.hauptmann.dev/`), `argocd-update`, and `version-check` (`https://dev.hauptmann.dev/version`) steps unchanged.

- [ ] **Step 3: Update the prod stage to set all four images**

Apply the SAME two changes to `…/kargo/pmhme-portfolio/stage-prod.yaml`: drop the single `imageRepo` var, replace the `kustomize-set-image` `images:` list with the same four-image block from Step 2 (its `overlayPath` is `…/overlays/production`), and update the `yaml-parse` `deployedTag` expression to `filter(images, {.name == "ghcr.io/mainman94/pmhme"})[0].newTag`. Leave the remaining steps (git-clone/commit/push, argocd-update, the `https://hauptmann.dev/version` version-check) unchanged.

- [ ] **Step 4: Validate YAML + image agreement**

```bash
cd /Users/philipp/work/multi-k8s-infra
for f in warehouse stage-test stage-prod; do
  python3 -c "import yaml; list(yaml.safe_load_all(open('eggenberg-talos-cluster-1/argocd-apps-configuration/kargo/pmhme-portfolio/$f.yaml'))); print('$f yaml ok')"
done
grep -rn "dockerha08" eggenberg-talos-cluster-1/argocd-apps-configuration/kargo/ && echo "BAD" || echo "no dockerha08 (good)"
grep -c "ghcr.io/mainman94/" eggenberg-talos-cluster-1/argocd-apps-configuration/kargo/pmhme-portfolio/warehouse.yaml
```
Expected: three `yaml ok`; `no dockerha08 (good)`; warehouse ghcr count = 4.

- [ ] **Step 5: Commit**

```bash
git add eggenberg-talos-cluster-1/argocd-apps-configuration/kargo/pmhme-portfolio
git commit -m "feat(kargo): warehouse + test/prod stages track four ghcr images"
```

---

### Task 6: Whole-pipeline validation pass

**Files:** none (verification only)

- [ ] **Step 1: All overlays build + kubeconform**

```bash
cd /Users/philipp/work/multi-k8s-infra
P=eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays
for e in dev test production; do
  echo "== $e =="
  kubectl kustomize $P/$e > /tmp/render-$e.yaml && echo "build ok" || echo "BUILD FAILED"
  kubeconform -ignore-missing-schemas -skip InfisicalSecret,Warehouse,CiliumNetworkPolicy,Rollout,AnalysisTemplate,ServiceMonitor /tmp/render-$e.yaml && echo "kubeconform ok"
done
```
Expected: each env `build ok` + `kubeconform ok`.

- [ ] **Step 2: Cross-file image-name agreement**

```bash
cd /Users/philipp/work/multi-k8s-infra
echo "overlays:"; grep -rh "ghcr.io/mainman94/" eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays/*/kustomization.yaml | grep name: | sort -u
echo "image-updater:"; grep "imageName:" eggenberg-talos-cluster-1/argocd-apps/pmhme/image-updater-dev.yaml | sort -u
echo "warehouse:"; grep "repoURL: ghcr" eggenberg-talos-cluster-1/argocd-apps-configuration/kargo/pmhme-portfolio/warehouse.yaml | sort -u
echo "no docker hub anywhere in pmhme/kargo/image-updater:"; grep -rn "dockerha08" eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme eggenberg-talos-cluster-1/argocd-apps-configuration/kargo eggenberg-talos-cluster-1/argocd-apps/pmhme || echo "clean"
```
Expected: the same four `ghcr.io/mainman94/{pmhme,contact-api,notifier-telegram,notifier-email}` names in all three places; `clean`.

- [ ] **Step 3: Sinks dev/test only; prod real**

```bash
cd /Users/philipp/work/multi-k8s-infra
P=eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme/overlays
kubectl kustomize $P/test | grep -q telegram-sink && echo "test has sink (good)" || echo "BAD"
kubectl kustomize $P/production | grep -qE "mailpit|telegram-sink" && echo "BAD sink in prod" || echo "prod has no sink (good)"
```
Expected: `test has sink (good)`; `prod has no sink (good)`.

- [ ] **Step 4: kube-linter (best-effort, matches CI)**

```bash
cd /Users/philipp/work/multi-k8s-infra
kube-linter lint --config .kube-linter.yaml /tmp/render-production.yaml 2>&1 | tail -20 || true
```
Expected: review output; pre-existing/ignored checks only. Note any new findings in the report.

---

## Self-Review

**Spec coverage (design Parts 2–5):**
- Part 2 (backend→base, ghcr image, /api/contact, netpols in base) → Task 1. ✔
- Part 5 (dev/test sinks, overlay-scoped, prod untouched) → Task 2. ✔
- Part 4 (ghcr pull secrets ×3 ns, image-updater cred, Kargo cred, contact-backend-secrets dev/test) → Task 3. ✔
- Part 3 image-updater (4 ghcr aliases, dev) → Task 4. ✔
- Part 3 Kargo (Warehouse 4 subs + git, stages set 4 images, frontend version-check kept) → Task 5. ✔
- Cross-cutting validation (build, image-name agreement, no Docker Hub, sink placement) → Task 6. ✔

**Placeholder scan:** none — every step has concrete file content or a runnable command.

**Consistency:** image names `ghcr.io/mainman94/{pmhme,contact-api,notifier-telegram,notifier-email}` identical across Tasks 1, 4, 5; secret names (`docker-pull-secret`, `ghcr-pull-pat`, `ghcr-creds`, `contact-backend-secrets`) consistent between Task 3 (produces) and Tasks 4/5 (consume); `notifier-email`/`notifier-telegram` Deployment + container names in the Task 2 patch match the base manifests from Task 1.

**Notes for executor:**
- `kubectl kustomize` is the build tool (no standalone `kustomize` binary here).
- Components require kustomize `v1alpha1 kind: Component`; `kubectl kustomize` supports it.
- Task 3 needs the two new Infisical keys to exist before ArgoCD sync will produce working secrets; this is the documented user action, not a code step.
- Do not merge/sync to the cluster as part of this plan — it ends at a validated branch. Cutover ordering (Infisical keys + secrets first, then app sync) is an operational step for after merge.
