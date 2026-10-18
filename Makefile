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
	prek install

.PHONY: preflight
preflight: lint ## Full gate: hooks + kube-linter + every kustomize build

.PHONY: lint
lint: ## Run every pre-commit hook over the whole tree
	prek run --all-files

.PHONY: fmt
fmt: ## Reformat YAML and shell in place
	prek run yamlfmt --all-files || true
	prek run shfmt-src --all-files || true

.PHONY: kustomize
kustomize: ## Build every overlay and base
	scripts/kustomize-build.sh

.PHONY: kube-lint
kube-lint: ## kube-linter over the cluster manifests
	scripts/kube-lint.sh

.PHONY: kubeconform
kubeconform: ## Schema-validate manifests against upstream + CRD catalog (needs network)
	scripts/kubeconform.sh

.PHONY: diff
diff: ## Show what a running ArgoCD would see as drift (needs cluster access)
	@command -v argocd >/dev/null || { echo "argocd CLI not on PATH" >&2; exit 1; }
	argocd app diff app-of-app

.PHONY: scan
scan: ## trivy config scan of the cluster manifests (advisory)
	@command -v trivy >/dev/null || { echo "trivy not on PATH — see .devcontainer" >&2; exit 1; }
	trivy config $(CLUSTER_DIR)

.PHONY: update-hooks
update-hooks: ## Bump pinned hook revisions
	prek update
