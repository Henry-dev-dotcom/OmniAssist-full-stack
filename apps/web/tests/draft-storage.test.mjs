import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { runInNewContext } from "node:vm";
import test from "node:test";
const require = createRequire(import.meta.url);
const ts = require("typescript");
const source = await readFile(new URL("../src/lib/drafts/storage.ts", import.meta.url), "utf8");
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
function storageHarness() {
  const data = new Map();
  let now = 1_800_000_000_000;
  const localStorage = { getItem: (key) => data.get(key) ?? null, setItem: (key, value) => data.set(key, value), removeItem: (key) => data.delete(key) };
  const testModule = { exports: {} };
  runInNewContext(js, { module: testModule, exports: testModule.exports, window: { localStorage }, Date: { now: () => now }, TextEncoder, JSON, Number });
  return { api: testModule.exports, data, advance: (ms) => { now += ms; } };
}
test("drafts persist and recover, and removal clears the browser entry", () => {
  const { api, data } = storageHarness();
  assert.equal(api.saveDraft("note", { title: "Draft" }), true);
  assert.deepEqual(JSON.parse(JSON.stringify(api.loadDraft("note"))), { title: "Draft" });
  api.removeDraft("note");
  assert.equal(api.loadDraft("note"), null);
  assert.equal(data.size, 0);
});
test("oversized drafts are refused without storing partial content", () => {
  const { api, data } = storageHarness();
  api.saveDraft("large", { body: "previous safe version" });
  assert.equal(api.saveDraft("large", { body: "x".repeat(300_000) }), false);
  assert.equal(data.size, 0);
  assert.equal(api.loadDraft("large"), null);
});
test("expired and malformed draft records are ignored and expired data is removed", () => {
  const { api, data, advance } = storageHarness();
  api.saveDraft("old", { body: "stale" });
  advance(31 * 24 * 60 * 60 * 1000);
  assert.equal(api.loadDraft("old"), null);
  assert.equal(data.size, 0);
  data.set("omniassist-draft:bad", "not-json");
  assert.equal(api.loadDraft("bad"), null);
});
