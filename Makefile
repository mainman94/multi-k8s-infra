# multi-k8s-infra — Talos + Kubernetes homelab, applied by ArgoCD.
#
# There is no `kubectl apply` step for app changes: push to git, ArgoCD syncs.
# That makes `make preflight` the last gate before the cluster sees a change.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

CLUSTER_DIR := eggenberg-talos-cluster-1
export CLUSTER_DIR

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: tools
tools: ## Install the pinned toolchain from mise.toml
	@command -v mise >/dev/null || { echo "mise not on PATH — see https://mise.jdx.dev or .devcontainer" >&2; exit 1; }
	mise install

.PHONY: hooks
hooks: ## Install the git pre-commit hook
	pre-commit install

.PHONY: preflight
preflight: ## Full gate: hooks + kube-linter + every kustomize build
	scripts/preflight.sh

.PHONY: lint
lint: ## Run every pre-commit hook over the whole tree
	pre-commit run --all-files

.PHONY: fmt
fmt: ## Reformat YAML and shell in place
	pre-commit run yamlfmt --all-files || true
	pre-commit run shfmt-src --all-files || true

.PHONY: kustomize
kustomize: ## Build every overlay and base
	scripts/kustomize-build.sh

.PHONY: kube-lint
kube-lint: ## kube-linter over the cluster manifests
	scripts/kube-lint.sh

.PHONY: kubeconform
kubeconform: ## Schema-validate manifests against upstream + CRD catalog (needs network)
	scripts/kubeconform.sh

.PHONY: build
build: ## Render one overlay to stdout, e.g. make build OVERLAY=production
	@test -n "$(OVERLAY)" || { echo "error: OVERLAY is not set — e.g. make build OVERLAY=production" >&2; exit 1; }
	kubectl kustomize $(CLUSTER_DIR)/argocd-apps-configuration/pmhme/overlays/$(OVERLAY)

.PHONY: apps
apps: ## List every registered ArgoCD application
	@ls -1 $(CLUSTER_DIR)/argocd-apps

.PHONY: diff
diff: ## Show what a running ArgoCD would see as drift (needs cluster access)
	@command -v argocd >/dev/null || { echo "argocd CLI not on PATH" >&2; exit 1; }
	argocd app diff app-of-app

.PHONY: images
images: ## List every image the repo's own apps run (from rendered overlays)
	@scripts/list-images.sh

.PHONY: scan
scan: ## trivy config scan of the cluster manifests (advisory)
	@command -v trivy >/dev/null || { echo "trivy not on PATH — see .devcontainer" >&2; exit 1; }
	trivy config $(CLUSTER_DIR)

.PHONY: scan-strict
scan-strict: ## Same scan, but fail on any finding
	@command -v trivy >/dev/null || { echo "trivy not on PATH — see .devcontainer" >&2; exit 1; }
	trivy config --exit-code 1 $(CLUSTER_DIR)

# Five of these live in the private Gitea registry behind Cloudflare, which
# only resolves from inside the network — so this is a local target, not a CI
# job. See the note in AGENTS.md.
.PHONY: scan-images
scan-images: ## CVE scan every image the repo's own apps run (advisory)
	@command -v trivy >/dev/null || { echo "trivy not on PATH — see .devcontainer" >&2; exit 1; }
	@scripts/list-images.sh | while read -r image; do \
		echo "==> $$image"; \
		trivy image --quiet --scanners vuln --ignore-unfixed \
			--severity CRITICAL,HIGH "$$image" || true; \
	done

.PHONY: update-hooks
update-hooks: ## Bump pinned hook revisions
	pre-commit autoupdate
