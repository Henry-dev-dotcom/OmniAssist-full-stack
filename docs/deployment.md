# Deploying OmniAssist with Vercel, Render, and Neon

This is the supported hosted deployment for OmniAssist:

```text
Flutter web app  →  Vercel
FastAPI backend  →  Render
PostgreSQL       →  Neon
```

You do **not** need Docker, Caddy, Tailscale, a home PC, or a separate server for this setup.
The result is one public HTTPS URL that works in desktop browsers and can be installed as a web
app on Android and iPhone.

## 1. Create the Neon database

1. Create a Neon project and database.
2. Copy the **pooled connection string** from Neon. It normally starts with
   `postgresql://` and includes `sslmode=require`.
3. Keep this value private. It will be added only to Render as `OMNI_DATABASE_URL`.

The API converts `postgresql://` to the async PostgreSQL driver automatically, so no editing of
the Neon URL is needed.

## 2. Deploy the backend to Render

1. In Render, choose **New → Blueprint**.
2. Connect the GitHub repository `Henry-dev-dotcom/OmniAssist-full-stack`.
3. Render will read the repository's `render.yaml` and create the `omniassist-api` web service.
4. In the Render service environment variables, set:

   | Variable | Value |
   |---|---|
   | `OMNI_DATABASE_URL` | The Neon pooled connection string |
   | `OMNI_CORS_ORIGINS` | Temporary value `["https://placeholder.invalid"]` until Vercel is created |

   Render generates `OMNI_AUTH_LOCAL_SECRET` automatically from the Blueprint. Do not replace it
   with a short or guessable value.

5. Deploy the service. Render runs the Alembic migrations automatically before starting FastAPI.
6. Copy the Render service URL, for example:
   `https://omniassist-api.onrender.com`.
7. Verify the backend health endpoint in a browser:
   `https://YOUR-RENDER-SERVICE.onrender.com/api/v1/health/live`

It should return:

```json
{"status":"ok"}
```

Render's free service may sleep when unused. The first request after inactivity may be slower.

## 3. Deploy the frontend to Vercel

1. In Vercel, choose **Add New → Project**.
2. Import `Henry-dev-dotcom/OmniAssist-full-stack`.
3. Leave the project root as the repository root. The committed `vercel.json` handles the Flutter
   build and output directory.
4. Add this Vercel environment variable for **Production**, **Preview**, and **Development**:

   | Variable | Value |
   |---|---|
   | `API_BASE_URL` | `https://YOUR-RENDER-SERVICE.onrender.com/api/v1` |

5. Deploy. The build script installs Flutter stable, generates the Drift database code, and
   creates the release PWA.
6. Copy the Vercel production URL, for example:
   `https://omniassist.vercel.app`.

The frontend is compiled with the Render API URL. Do not put the Neon URL in Vercel.

## 4. Lock backend CORS to Vercel

Return to the Render service environment variables and change:

```text
OMNI_CORS_ORIGINS=["https://omniassist.vercel.app"]
```

Use your actual Vercel production URL. If you add a custom Vercel domain later, include both
origins as valid JSON:

```text
OMNI_CORS_ORIGINS=["https://omniassist.vercel.app","https://app.example.com"]
```

Redeploy or restart the Render service after changing the variable.

## 5. Create your account and install the app

1. Open the Vercel URL on a desktop browser.
2. Choose **Create an account** and create your account.
3. After your account is created, set Render's `OMNI_ALLOW_REGISTRATION` to `false` and redeploy
   so nobody else can create an account on the instance.
4. On Android, open the Vercel URL in Chrome → menu → **Install app** or **Add to Home screen**.
5. On iPhone, open the Vercel URL in Safari → Share → **Add to Home Screen**.
6. On Windows/macOS/Linux, open the URL in Chrome or Edge → **Install OmniAssist**.

The app stores data locally first, works offline after the first visit, and synchronizes with the
Render API when the connection returns. Use the same account on each device.

## 6. Optional web-push reminders

Web-push keys are not required for the core app. To enable reminders on supported browsers:

1. Generate a VAPID key pair locally using the API module:
   `uv run python -m src.infrastructure.notifications.webpush`.
2. Add the resulting values to Render as `OMNI_VAPID_PRIVATE_KEY`, `OMNI_VAPID_PUBLIC_KEY`, and
   `OMNI_VAPID_SUBJECT`.
3. Add the same public key to the frontend configuration only if the notification settings screen
   requests it; otherwise use the in-app notification center.

## 7. Updating the app

Push changes to `main`:

```bash
git add .
git commit -m "Describe the change"
git push origin main
```

Vercel rebuilds the frontend automatically. Render redeploys the backend automatically. Database
migrations run as part of the Render start command.

## Troubleshooting

- **CORS error:** confirm `OMNI_CORS_ORIGINS` is valid JSON and exactly matches the Vercel URL,
  including `https://` and excluding a trailing slash.
- **Backend unavailable:** open `/api/v1/health/live` on the Render URL. If Render is waking from
  sleep, wait for the service to become ready and retry.
- **Database error:** verify that Render uses the Neon pooled URL and that it still contains
  `sslmode=require`.
- **Flutter build failure on Vercel:** inspect the Vercel build log. The build uses Flutter stable;
  if the SDK changes incompatibly, pin a tested Flutter tag in `scripts/vercel-build.sh`.
- **Phone cannot install the app:** use the HTTPS Vercel URL, not a local IP address or `http://` URL.
