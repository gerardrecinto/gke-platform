import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const P = createRequire(import.meta.url)("./plan.js");
const G = JSON.parse(readFileSync(new URL("../tests/fixtures/golden.json", import.meta.url)));

test("allocatable equals Python", () => {
  for (const [m, want] of Object.entries(G.allocatable)) assert.deepEqual(P.allocatable(...P.MACHINES[m]), want);
});
test("hpa equals Python", () => {
  for (const [c, m, t, want] of G.hpa) assert.equal(P.hpaDesired(c, m, t, 1, 10), want);
});
test("vpa equals Python", () => {
  for (const [s, want] of G.vpa) assert.equal(P.vpaRecommend(s), want);
});
test("nodes equal Python", () => {
  for (const [[replicas, podCpu, podMem, machine], want] of G.nodes) {
    const got = P.nodesNeeded({ replicas, podCpu, podMem, machine });
    for (const k of Object.keys(want)) assert.deepEqual(got[k], want[k], `${replicas} ${podCpu} ${podMem} ${machine} ${k}`);
  }
});
