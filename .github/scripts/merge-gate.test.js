"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const g = require("./merge-gate.js");

const APP = "eggenberg-talos-cluster-1/argocd-apps/pmhme/pmhme-test.yaml";
const VALUES = "eggenberg-talos-cluster-1/argocd-apps-configuration/pmhme-chart/test/values.yaml";

test("chart version bump passes", () => {
  assert.equal(g.onlyVersionBumps(["@@ -1 +1 @@\n-      targetRevision: 1.2.0\n+      targetRevision: 1.3.0"]), true);
});

test("image bump passes", () => {
  assert.equal(g.onlyVersionBumps(["-  image: ghcr.io/a/b:1.0\n+  image: ghcr.io/a/b:1.1"]), true);
});

test("an extra non-version line fails", () => {
  assert.equal(g.onlyVersionBumps(["+  replicas: 3\n+  tag: v2"]), false);
});

test("a version-shaped line with a risky key fails", () => {
  assert.equal(g.onlyVersionBumps(["+  tag: rbac-v2"]), false);
});

test("a patch without changed lines fails", () => {
  assert.equal(g.onlyVersionBumps([" context only", undefined]), false);
});

test("workflow, pre-commit, shell and docs paths are forbidden", () => {
  const { forbidden } = g.renovateHardGate([
    ".github/workflows/x.yml",
    ".pre-commit-config.yaml",
    "scripts/a.sh",
    "README.md",
    "eggenberg-talos-cluster-1/argocd-apps/a/a.yaml",
  ]);
  assert.deepEqual(forbidden, [".github/workflows/x.yml", ".pre-commit-config.yaml", "scripts/a.sh", "README.md"]);
});

test("non-yaml files and more than 30 files trip the hard gate", () => {
  assert.deepEqual(g.renovateHardGate(["Makefile"]).badExt, ["Makefile"]);
  assert.equal(g.renovateHardGate(Array.from({ length: 31 }, (_, i) => `${i}.yaml`)).tooMany, true);
  assert.equal(g.renovateHardGate(Array.from({ length: 30 }, (_, i) => `${i}.yaml`)).tooMany, false);
});

test("kargo: values file plus chart targetRevision is a plain promotion", () => {
  assert.equal(
    g.kargoRejects([
      { filename: VALUES, patch: "-    tag: a\n+    tag: b" },
      { filename: APP, patch: "@@\n-      targetRevision: 0.4.0\n+      targetRevision: 0.5.0" },
    ]),
    "",
  );
});

test("kargo: switching the Application to a branch is rejected", () => {
  assert.equal(g.kargoRejects([{ filename: APP, patch: "-      targetRevision: 0.4.0\n+      targetRevision: main" }]), APP);
});

test("kargo: any other file, or more than two, is rejected", () => {
  assert.equal(g.kargoRejects([{ filename: VALUES }, { filename: ".github/scripts/merge-gate.js" }]), ".github/scripts/merge-gate.js");
  assert.equal(g.kargoRejects([{ filename: VALUES }, { filename: VALUES }, { filename: VALUES }]), "3 files");
  assert.equal(g.kargoRejects([]), "0 files");
});
