# Deploying OmniAssist

> Running it only for yourself? You don't need any of this: see [personal-setup.md](personal-setup.md).

## One machine with HTTPS (recommended for the MVP)

Needs a Linux server with Docker, a domain name pointing at it, and ports 80 and 443 open.
Phones only install the app from an `https://` site; Caddy gets the certificate by itself.

```
git clone https://github.com/Henry-dev-dotcom/OmniAssist-full-stack.git && cd OmniAssist-full-stack
cp infra/deployment/.env.prod.example infra/deployment/.env.prod   # set DOMAIN and two secrets

# Build the web app for your domain (on any machine with Flutter, then copy apps/client/build):
cd apps/client
flutter pub get && dart run build_runner build --delete-conflicting-outputs
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=https://YOUR_DOMAIN/api/v1
cd ../..

docker compose -f infra/deployment/docker-compose.prod.yml --env-file infra/deployment/.env.prod up -d --build
```

The API container applies database migrations when it starts. Open `https://YOUR_DOMAIN`.

Production refuses to start without `OMNI_DATABASE_URL`, `OMNI_CORS_ORIGINS` and a real
`OMNI_AUTH_LOCAL_SECRET` (32+ characters). To use a hosted sign-in provider instead, set
`OMNI_AUTH_PROVIDER=oidc` and the `OMNI_AUTH_*` values in decision 0001.

## Installing on phones

Open the site in the phone's browser, then:
- **Android (Chrome):** menu → *Install app* (or *Add to Home screen*).
- **iOS (Safari):** Share → *Add to Home Screen*.

The installed app opens offline after the first visit and syncs when the connection returns.

**Reminder notifications** (optional, decision 0006): generate a key pair once, put it in
`.env.prod` as `VAPID_PRIVATE_KEY` / `VAPID_PUBLIC_KEY`, and restart. Each user then turns on
*Settings → Reminder notifications on this device*. On iPhone this works after *Add to Home
Screen*.

```
docker compose -f infra/deployment/docker-compose.prod.yml --env-file infra/deployment/.env.prod   run --rm api uv run --no-sync python -m src.infrastructure.notifications.webpush
```

## Native builds (optional)

The same code builds native apps; they need each platform's toolchain:
- Android: Android Studio SDK, then `flutter build appbundle --dart-define=API_BASE_URL=...`.
- iOS: a Mac with Xcode, then `flutter build ipa --dart-define=API_BASE_URL=...`.
- Windows / Linux: `flutter create --platforms=windows,linux .` once, then `flutter build windows`
  or `flutter build linux` (Linux package format is still open, Spec 10.2).

Native builds need a notification plugin for OS reminders; the web app uses the in-app
notification center.

## Backups

See [operations.md](operations.md).
