const CACHE_NAME = "omniassist-static-v4";
const OFFLINE_PAGE = "/offline.html";
const PRECACHE_URLS = [
  OFFLINE_PAGE,
  "/manifest.webmanifest",
  "/icons/icon.svg",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/icon-512-maskable.png",
];
const STATIC_PREFIXES = ["/_next/static/", "/icons/"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter((name) => name.startsWith("omniassist-static-") && name !== CACHE_NAME)
            .map((name) => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Never intercept API calls or requests carrying bearer credentials.
  if (url.pathname === "/api" || url.pathname.startsWith("/api/")) return;
  if (request.headers.has("authorization")) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(async () => {
        const offline = await caches.match(OFFLINE_PAGE);
        return offline ?? new Response("You are offline.", { status: 503 });
      }),
    );
    return;
  }

  const isPublicStaticAsset =
    STATIC_PREFIXES.some((prefix) => url.pathname.startsWith(prefix)) ||
    url.pathname === "/manifest.webmanifest";
  if (!isPublicStaticAsset) return;

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      const cached = await cache.match(request);
      if (cached) return cached;

      const response = await fetch(request);
      const cacheControl = response.headers.get("cache-control") ?? "";
      const isPrivate = /\b(private|no-store|no-cache)\b/i.test(cacheControl);
      const canCache =
        response.ok &&
        response.type === "basic" &&
        !isPrivate &&
        !response.headers.has("set-cookie");

      if (canCache) await cache.put(request, response.clone());
      return response;
    })(),
  );
});

// Reminders sent by the API (Web Push). The payload is { title, tag, url }; the API encrypts it
// to this device, so the push service never sees it.
self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { title: event.data ? event.data.text() : "" };
  }
  const url = typeof data.url === "string" && data.url.startsWith("/") ? data.url : "/app/today?notifications=open";
  event.waitUntil(
    self.registration.showNotification(data.title || "OmniAssist reminder", {
      body: "Open OmniAssist to see the details.",
      tag: data.tag || undefined,
      icon: "/icons/icon-192.png",
      badge: "/icons/icon-192.png",
      data: { url },
    }),
  );
});

// Tapping a reminder focuses an open OmniAssist window, or opens one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = event.notification.data?.url || "/app/today?notifications=open";
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      const open = windows.find((client) => new URL(client.url).origin === self.location.origin);
      if (open) {
        await open.navigate(url);
        return open.focus();
      }
      return self.clients.openWindow(url);
    })(),
  );
});
