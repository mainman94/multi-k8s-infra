// Pure checks behind the bot merge gates (renovate-ai-automerge.yml,
// kargo-automerge.yml). The workflows fetch the PR files and act on the
// result; everything that decides lives here and is tested in
// merge-gate.test.js. The workflows load this file from the base commit, so a
// PR cannot change the rules that judge it.
"use strict";

const VERSION_LINE = [
  /^[+-]\s*-?\s*(version|appversion|tag|imagetag|targetrevision|digest)\s*:\s*["']?[^"'\s]+["']?\s*$/i,
  /^[+-]\s*image\s*:\s*[^"'\s]+:[^"'\s]+["']?\s*$/i,
];
const RISKY =
  /(clusterrole|clusterrolebinding|rolebinding|serviceaccount|networkpolicy|ingress|hostnetwork|privileged|allowprivilegeescalation|capabilities|securitycontext|runasuser|runasnonroot|podsecurity|webhook|rbac)/i;

// Renovate hard gate: which changed paths a bot bump may touch at all.
// .pre-commit-config.yaml passes the YAML-only check but pins hooks that
// execute arbitrary code in CI, so it is treated like a workflow edit.
function renovateHardGate(paths) {
  const badExt = paths.filter((p) => !p.endsWith(".yaml") && !p.endsWith(".yml"));
  const forbidden = paths.filter(
    (p) =>
      p.startsWith(".github/") ||
      p === ".pre-commit-config.yaml" ||
      p.endsWith(".md") ||
      p.endsWith(".sh") ||
      p.endsWith(".json") ||
      p.endsWith(".tf"),
  );
  return { badExt, forbidden, tooMany: paths.length > 30 };
}

// Changed lines of a set of unified-diff patches, without the file headers.
function diffLines(patches) {
  return patches
    .flatMap((p) => (p || "").split("\n"))
    .filter(
      (line) =>
        (line.startsWith("+") || line.startsWith("-")) && !line.startsWith("+++") && !line.startsWith("---"),
    );
}

// True when every changed line is a version/tag/digest line and none of them
// touches a security-relevant key.
function onlyVersionBumps(patches) {
  const lines = diffLines(patches);
  return (
    lines.length > 0 &&
    lines.every((line) => VERSION_LINE.some((re) => re.test(line))) &&
    !lines.some((line) => RISKY.test(line.slice(1)))
  );
}

const KARGO_VALUES = /^eggenberg-talos-cluster-1\/argocd-apps-configuration\/pmhme-chart\/[^/]+\/values\.yaml$/;
const KARGO_APP = /^eggenberg-talos-cluster-1\/argocd-apps\/pmhme\/pmhme-[^/]+\.yaml$/;

// The Application also has a targetRevision for the values source (main);
// only the chart version may change, never a branch name.
function onlyChartVersion(patch) {
  return patch
    .split("\n")
    .filter((l) => /^[+-]/.test(l))
    .every((l) => /^[+-]\s+targetRevision: \S+$/.test(l) && !/: (main|HEAD)$/.test(l));
}

// Kargo promotion: the stage values file and the Application's chart
// targetRevision line, at most two files. Returns why it is not a plain
// promotion, or "" when it is.
function kargoRejects(files) {
  const bad = files.filter(
    (f) => !(KARGO_VALUES.test(f.filename) || (KARGO_APP.test(f.filename) && f.patch && onlyChartVersion(f.patch))),
  );
  if (files.length === 0 || files.length > 2 || bad.length) {
    return bad.map((f) => f.filename).join(", ") || `${files.length} files`;
  }
  return "";
}

module.exports = { renovateHardGate, onlyVersionBumps, kargoRejects };
