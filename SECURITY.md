# Security Policy

## What this repository is

GitOps configuration for a private Talos Kubernetes cluster. ArgoCD applies
whatever reaches `main` — so this repository *is* the cluster's configuration,
and a manifest merged here is a change to a running system.

## Reporting

Report privately via GitHub's
[security advisories](https://github.com/mainman94/multi-k8s-infra/security/advisories/new).
Please do not open a public issue for anything exploitable.

The cases worth a private report: a **secret committed by mistake**, a
manifest that exposes a workload it should not (an HTTPRoute onto the public
gateway, a NetworkPolicy hole), or a privilege escalation through a
ServiceAccount or RBAC binding defined here.

## What is already covered

- **No secrets are stored in this repository.** Every credential is an
  `ExternalSecret` pointing into OpenBao; the reference layer is all that is
  committed. `gitleaks` runs as a pre-commit hook and in CI.
- **Kyverno** enforces baseline pod security and blocks `latest` tags;
  **Falco** watches runtime behaviour; **trivy-operator** scans running
  workloads.
- **kubeconform runs `-strict` with no `-ignore-missing-schemas`**, so an
  unknown kind or a misspelled field fails rather than passing silently.
- **kube-linter and checkov** run on every pull request, and all three are
  required status checks on `main`.
- **Every action reference is pinned to a commit SHA**, and `zizmor` audits
  the workflows — including `renovate-ai-automerge.yml`, which uses
  `pull_request_target` deliberately and never checks the pull request out.

## Vulnerabilities in the deployed applications

Report those upstream to the project concerned. Report here only what this
repository adds: the manifests, the ArgoCD wiring, and the policies.
