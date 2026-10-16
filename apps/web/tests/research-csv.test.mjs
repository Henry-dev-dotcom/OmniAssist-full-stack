import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { runInNewContext } from "node:vm";
import test from "node:test";
const require = createRequire(import.meta.url);
const ts = require("typescript");
const source = await readFile(new URL("../src/lib/research/csv.ts", import.meta.url), "utf8");
const js = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
const mod = { exports: {} };
runInNewContext(js, { module: mod, exports: mod.exports, TextEncoder, Set });
const { previewCsv } = mod.exports;
test("CSV parser handles escaped quotes, commas and CRLF", () => {
  const result = previewCsv('title,notes\r\n"A, study","Said ""yes"""\r\n');
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { headers: ["title", "notes"], rows: [["A, study", 'Said "yes"']], errors: [] });
});
test("CSV preview reports missing titles and malformed row widths before import", () => {
  const result = previewCsv("title,doi\n,10.1/example\nGood\n");
  assert.ok(result.errors.some((error) => error.includes("title is required")));
  assert.ok(result.errors.some((error) => error.includes("expected 2 columns")));
});
test("CSV parser rejects unclosed quotes and oversized files", () => {
  assert.match(previewCsv('title\n"unfinished').errors[0], /unclosed/);
  assert.match(previewCsv("x".repeat(1_000_001)).errors[0], /1 MB/);
});

test("CSV preview accepts custom headers for the user mapping step", () => {
  const result = previewCsv("citation,identifier,abstract\nA paper,10.1/example,Short abstract\n");
  assert.deepEqual(JSON.parse(JSON.stringify(result)), { headers: ["citation", "identifier", "abstract"], rows: [["A paper", "10.1/example", "Short abstract"]], errors: [] });
});
