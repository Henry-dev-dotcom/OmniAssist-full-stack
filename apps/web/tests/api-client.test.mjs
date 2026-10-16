import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { runInNewContext } from "node:vm";
import test from "node:test";

const require = createRequire(import.meta.url);
const typescript = require("typescript");
const webRoot = new URL("../", import.meta.url);

async function loadApiClient(fetchImplementation) {
  const source = await readFile(new URL("src/lib/api/client.ts", webRoot), "utf8");
  const compiled = typescript.transpileModule(source, {
    compilerOptions: { module: typescript.ModuleKind.CommonJS, target: typescript.ScriptTarget.ES2022 },
  }).outputText;
  const testModule = { exports: {} };
  const contractCodes = [
    "VALIDATION_ERROR",
    "UNAUTHENTICATED",
    "FORBIDDEN",
    "NOT_FOUND",
    "VERSION_CONFLICT",
    "IDEMPOTENCY_KEY_REUSED",
    "DOMAIN_RULE_VIOLATION",
    "RATE_LIMITED",
    "DEPENDENCY_UNAVAILABLE",
    "INTERNAL_ERROR",
  ];
  runInNewContext(compiled, {
    module: testModule,
    exports: testModule.exports,
    require: (name) => {
      if (name === "@omniassist/contracts") return { ERROR_CODES: contractCodes };
      throw new Error(`Unexpected import: ${name}`);
    },
    fetch: fetchImplementation,
    Headers,
    Blob,
    FormData,
    URL,
    URLSearchParams,
    ArrayBuffer,
    Uint8Array,
    Set,
    Error,
    JSON,
    Promise,
  });
  return testModule.exports;
}

test("API client preserves server error request IDs and safe error metadata", async () => {
  const client = await loadApiClient(async () =>
    new Response(
      JSON.stringify({
        error: {
          code: "FORBIDDEN",
          message: "You do not have access.",
          details: { workspace_id: "hidden-workspace" },
          request_id: "req-from-envelope",
          retryable: false,
        },
      }),
      { status: 403, headers: { "content-type": "application/json", "x-request-id": "req-from-header" } },
    ),
  );

  await assert.rejects(client.requestApi("/api/v1/projects"), (error) => {
    assert.equal(error.name, "ApiClientError");
    assert.equal(error.status, 403);
    assert.equal(error.code, "FORBIDDEN");
    assert.equal(error.requestId, "req-from-envelope");
    assert.equal(error.retryable, false);
    assert.deepEqual({ ...error.details }, { workspace_id: "hidden-workspace" });
    return true;
  });
});

test("API client falls back to the response request-ID header on a malformed error body", async () => {
  const client = await loadApiClient(async () =>
    new Response("not-json", { status: 502, headers: { "x-request-id": "req-header-only" } }),
  );

  await assert.rejects(client.requestApi("/api/v1/projects"), (error) => {
    assert.equal(error.code, "INTERNAL_ERROR");
    assert.equal(error.requestId, "req-header-only");
    assert.equal(error.retryable, true);
    return true;
  });
});

test("API client preserves the response request ID when the error envelope ID is null", async () => {
  const client = await loadApiClient(async () =>
    new Response(
      JSON.stringify({ error: { code: "NOT_FOUND", message: "Not found.", details: {}, request_id: null, retryable: false } }),
      { status: 404, headers: { "x-request-id": "req-header-fallback" } },
    ),
  );

  await assert.rejects(client.requestApi("/api/v1/projects/missing"), (error) => {
    assert.equal(error.requestId, "req-header-fallback");
    return true;
  });
});

test("API client returns typed success data and preserves response metadata", async () => {
  const client = await loadApiClient(async () =>
    new Response(JSON.stringify({ data: [{ id: "p-1" }], meta: { request_id: "req-success", total: 1 } }), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  );
  const result = await client.requestApi("/api/v1/projects");

  assert.deepEqual(result.data.map((project) => project.id), ["p-1"]);
  assert.equal(result.meta.request_id, "req-success");
  assert.equal(result.meta.total, 1);
});
