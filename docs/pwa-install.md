# Install OmniAssist as a PWA

Use the deployed **HTTPS** address. A development server or plain HTTP address generally cannot be installed as a service-worker-backed app. Visit once while online so the browser can load the app shell and register the service worker. Account data and API-backed screens still require a connection; only the generic offline page and public static assets are cached. Experiment form drafts are local to that browser, limited to 256 KiB per draft, and expire after 30 days. Browser-local storage is not client-side encrypted; avoid leaving sensitive drafts on a shared device.

## Android (Chrome)

1. Open the deployed HTTPS URL in Chrome and sign in.
2. Open Chrome’s menu and choose **Install app** (or **Add to Home screen**, depending on Chrome version).
3. Confirm the install prompt; open OmniAssist from the home screen/app list.
4. To verify offline fallback, load OmniAssist once, then use Chrome DevTools → **Network → Offline** and reload a page. The generic offline page should appear; private API content must not be served from cache.

## iPhone and iPad (Safari)

1. Open the deployed HTTPS URL in Safari and sign in.
2. Tap **Share** → **Add to Home Screen** → **Add**.
3. Launch OmniAssist from the Home Screen. Safari controls the available install and background behavior; do not expect Android-style install prompts or unrestricted background sync.
4. To verify offline fallback, load the app shell while online, enable Airplane Mode, and reload. The generic offline page should appear. Core API data and writes remain online-first.

## Release checklist

- The manifest is reachable and has 192 px and 512 px icons, including a maskable icon.
- `/sw.js` registers on production HTTPS and has a root scope.
- `offline.html` is available after first load.
- Private API calls, credentialed fetches, and navigation responses are never cached.
- Run the production PWA browser test in CI. Repeat the steps on physical Android Chrome and iOS Safari before release; automated Chromium checks cannot emulate every OS prompt, browser policy, or Home Screen behavior.
