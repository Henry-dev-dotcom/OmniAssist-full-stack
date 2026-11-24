import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { runInNewContext } from "node:vm";
import test from "node:test";

const require = createRequire(import.meta.url);
const typescript = require("typescript");
const webRoot = new URL("../", import.meta.url);

async function loadApiClient(fetchImplementation, environment = {}, browser = {}) {
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
    process: { env: environment },
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
    ...browser,
  });
  return testModule.exports;
}

test("production API URLs use the configured public endpoint", async () => {
  const client = await loadApiClient(async () => new Response(null), {
    NODE_ENV: "production",
    NEXT_PUBLIC_API_URL: "https://omniassist-api.example.com/api/v1/",
  });
  assert.equal(client.apiUrl("/projects"), "https://omniassist-api.example.com/api/v1/projects");
});

test("production API requests fail clearly when NEXT_PUBLIC_API_URL is missing", async () => {
  const client = await loadApiClient(async () => new Response(null), { NODE_ENV: "production" });
  assert.throws(() => client.apiUrl("/projects"), /NEXT_PUBLIC_API_URL must be configured/);
});

test("development API URL keeps the localhost default", async () => {
  const client = await loadApiClient(async () => new Response(null), { NODE_ENV: "development" });
  assert.equal(client.apiUrl("/projects"), "http://localhost:8000/api/v1/projects");
});

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

function fakeBrowser(session) {
  const store = new Map(Object.entries({
    omniassist_session: JSON.stringify(session),
    omniassist_access_token: session.access_token,
  }));
  const location = { pathname: "/app/today", assigned: null, assign(url) { this.assigned = url; } };
  const document = { cookie: "omniassist_session=1" };
  const localStorage = {
    getItem: (key) => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => store.set(key, String(value)),
    removeItem: (key) => store.delete(key),
  };
  return { store, location, document, globals: { window: { localStorage, location }, document, navigator: {} } };
}

const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const expired = () => json(401, { error: { code: "UNAUTHENTICATED", message: "Your session is invalid or has expired.", details: {}, request_id: "r", retryable: false } });

test("an expired access token is renewed once and the requests are retried", async () => {
  const browser = fakeBrowser({ access_token: "old", refresh_token: "refresh-1", display_name: "Ama" });
  const calls = [];
  const client = await loadApiClient(async (url, init) => {
    const auth = new Headers(init.headers).get("authorization");
    calls.push(`${String(url).split("/api/v1")[1]} ${auth ?? ""}`);
    if (String(url).endsWith("/auth/refresh")) return json(200, { data: { access_token: "new", refresh_token: "refresh-2" }, meta: {} });
    return auth === "Bearer new" ? json(200, { data: "ok", meta: {} }) : expired();
  }, { NODE_ENV: "development" }, browser.globals);

  const [a, b] = await Promise.all([client.apiRequest("/tasks"), client.apiRequest("/projects")]);
  assert.equal(a.data, "ok");
  assert.equal(b.data, "ok");
  assert.equal(calls.filter((c) => c.startsWith("/auth/refresh")).length, 1, "a refresh token works once, so only one renewal");
  const saved = JSON.parse(browser.store.get("omniassist_session"));
  assert.equal(saved.refresh_token, "refresh-2");
  assert.equal(saved.display_name, "Ama", "fields the refresh does not return are kept");
  assert.equal(browser.store.get("omniassist_access_token"), "new");
});

test("when renewal fails the person is signed out and sent to sign in", async () => {
  const browser = fakeBrowser({ access_token: "old", refresh_token: "revoked" });
  const client = await loadApiClient(async () => expired(), { NODE_ENV: "development" }, browser.globals);

  await assert.rejects(client.apiRequest("/tasks"), (error) => error.code === "UNAUTHENTICATED");
  assert.equal(browser.store.has("omniassist_session"), false);
  assert.equal(browser.store.has("omniassist_access_token"), false);
  assert.match(browser.document.cookie, /max-age=0/);
  assert.equal(browser.location.assigned, "/signin");
});

test("other errors are not treated as an expired session", async () => {
  const browser = fakeBrowser({ access_token: "old", refresh_token: "refresh-1" });
  let refreshes = 0;
  const client = await loadApiClient(async (url) => {
    if (String(url).endsWith("/auth/refresh")) refreshes += 1;
    return json(403, { error: { code: "FORBIDDEN", message: "No.", details: {}, request_id: "r", retryable: false } });
  }, { NODE_ENV: "development" }, browser.globals);

  await assert.rejects(client.apiRequest("/tasks"), (error) => error.code === "FORBIDDEN");
  assert.equal(refreshes, 0);
  assert.equal(browser.location.assigned, null);
});
