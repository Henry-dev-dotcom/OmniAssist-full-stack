import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { runInNewContext } from "node:vm";
import test from "node:test";

const webRoot = new URL("../", import.meta.url);
const readWebFile = (path) => readFile(new URL(path, webRoot), "utf8");

function createWorkerHarness({ fetchResponse } = {}) {
  const listeners = new Map();
  const cacheWrites = [];
  let cacheOpens = 0;
  const cache = {
    addAll: async () => undefined,
    match: async () => undefined,
    put: async (...args) => cacheWrites.push(args),
  };
  const caches = {
    open: async () => {
      cacheOpens += 1;
      return cache;
    },
    keys: async () => [],
    delete: async () => true,
    match: async (key) => (key === "/offline.html" ? new Response("offline shell") : undefined),
  };
  const self = {
    location: { origin: "https://omniassist.test" },
    addEventListener: (name, listener) => listeners.set(name, listener),
    skipWaiting: async () => undefined,
    clients: { claim: async () => undefined },
  };
  const networkFetch = fetchResponse ?? (async () => new Response("public asset"));
  const sourcePromise = readWebFile("public/sw.js");

  return sourcePromise.then((source) => {
    runInNewContext(source, { self, caches, fetch: networkFetch, URL, Response, Promise });
    return { listeners, cacheWrites, get cacheOpens() { return cacheOpens; } };
  });
}

function dispatchFetch(listener, request) {
  let responsePromise;
  listener({
    request,
    respondWith: (promise) => {
      responsePromise = Promise.resolve(promise);
    },
  });
  return responsePromise;
}

test("manifest has installable standard and maskable icon sizes", async () => {
  const manifest = JSON.parse(await readWebFile("public/manifest.webmanifest"));
  const icons = manifest.icons;
  assert.ok(icons.some((icon) => icon.sizes === "192x192" && icon.purpose === "any"));
  assert.ok(icons.some((icon) => icon.sizes === "512x512" && icon.purpose === "any"));
  assert.ok(icons.some((icon) => icon.sizes === "512x512" && icon.purpose === "maskable"));
  for (const icon of icons) {
    await readFile(new URL(`public${icon.src}`, webRoot));
  }
});

test("service worker leaves private API requests to the network without opening a cache", async () => {
  const worker = await createWorkerHarness();
  const request = {
    method: "GET",
    url: "https://omniassist.test/api/v1/projects",
    mode: "cors",
    headers: new Headers(),
  };
  const response = dispatchFetch(worker.listeners.get("fetch"), request);

  assert.equal(response, undefined);
  assert.equal(worker.cacheOpens, 0);
  assert.equal(worker.cacheWrites.length, 0);
});

test("service worker bypasses credentialed requests even on a static path", async () => {
  const worker = await createWorkerHarness();
  const request = {
    method: "GET",
    url: "https://omniassist.test/_next/static/private.js",
    mode: "same-origin",
    headers: new Headers({ authorization: "Bearer secret" }),
  };
  const response = dispatchFetch(worker.listeners.get("fetch"), request);

  assert.equal(response, undefined);
  assert.equal(worker.cacheOpens, 0);
  assert.equal(worker.cacheWrites.length, 0);
});

test("service worker never caches navigation responses", async () => {
  const worker = await createWorkerHarness({
    fetchResponse: async () =>
      new Response("user-specific html", { headers: { "cache-control": "private, no-store" } }),
  });
  const request = {
    method: "GET",
    url: "https://omniassist.test/",
    mode: "navigate",
    headers: new Headers(),
  };
  const response = await dispatchFetch(worker.listeners.get("fetch"), request);

  assert.equal(await response.text(), "user-specific html");
  assert.equal(worker.cacheWrites.length, 0);
});

test("service worker returns the offline page when a navigation fetch fails", async () => {
  const worker = await createWorkerHarness({ fetchResponse: async () => { throw new Error("offline"); } });
  const request = {
    method: "GET",
    url: "https://omniassist.test/",
    mode: "navigate",
    headers: new Headers(),
  };
  const response = await dispatchFetch(worker.listeners.get("fetch"), request);

  assert.equal(await response.text(), "offline shell");
});
