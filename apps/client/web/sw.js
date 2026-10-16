// OmniAssist offline shell. After the first visit the app opens without a network;
// its data already lives in the browser database. API calls are never cached.
const CACHE = 'omniassist-shell-v2';
// Everything the first screen needs, so the very next launch works offline.
const SHELL = ['./', 'index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json',
  'sqlite3.wasm', 'drift_worker.js', 'favicon.png', 'icons/Icon-192.png',
  'canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm',
  'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm',
  'assets/FontManifest.json', 'assets/AssetManifest.bin.json',
  'assets/fonts/MaterialIcons-Regular.otf', 'assets/fonts/fallback/Roboto-Regular.ttf'];
// Font and engine hosts Flutter web may load from; cached so text renders offline.
const STATIC_HOSTS = ['fonts.gstatic.com', 'fonts.googleapis.com', 'www.gstatic.com'];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  // One by one: a file missing from this build must not block the rest.
  event.waitUntil(caches.open(CACHE).then((c) =>
    Promise.all(SHELL.map((url) => c.add(url).catch(() => {})))));
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const sameOrigin = url.origin === self.location.origin;
  if (!sameOrigin && !STATIC_HOSTS.includes(url.hostname)) return;  // the API stays live

  if (!sameOrigin) {
    // Versioned static files: cache first.
    event.respondWith(caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      if (res.ok) caches.open(CACHE).then((c) => c.put(req, res.clone()));
      return res;
    })));
    return;
  }
  // The app itself: network first so updates show at once; the cache answers offline.
  event.respondWith(fetch(req).then((res) => {
    if (res.ok) {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(req, copy));
    }
    return res;
  }).catch(async () => {
    const hit = await caches.match(req, { ignoreSearch: true });
    if (hit) return hit;
    if (req.mode === 'navigate') return caches.match('index.html');
    return Response.error();
  }));
});
