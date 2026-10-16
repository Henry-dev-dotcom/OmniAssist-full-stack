#!/usr/bin/env bash
set -Eeuo pipefail

# Start OmniAssist for personal use on macOS or Linux.
# Requirements: PostgreSQL, uv, and (only with --build) Flutter.
# Usage: ./scripts/start-omniassist.sh [--build] [--port 8000] [--bind-all]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$ROOT/apps/api"
CLIENT="$ROOT/apps/client"
ENV_FILE="$API/.env"
PORT=8000
BUILD=0
HOST=127.0.0.1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build|-b) BUILD=1; shift ;;
    --port) PORT="${2:?--port needs a value}"; shift 2 ;;
    --bind-all) HOST=0.0.0.0; shift ;;
    --help|-h)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '[OmniAssist] %s\n' "$*"; }
fail() { echo "[OmniAssist] ERROR: $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || fail "Missing $ENV_FILE. Copy infra/env/.env.example to apps/api/.env first."
command -v uv >/dev/null 2>&1 || fail "uv is required: https://docs.astral.sh/uv/"

if [[ "$BUILD" == 1 ]]; then
  command -v flutter >/dev/null 2>&1 || fail "Flutter is required for --build: https://docs.flutter.dev/get-started/install"
  say "Building the installable web app..."
  (
    cd "$CLIENT"
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter build web --release --no-web-resources-cdn
  )
fi

WEB_DIR="$CLIENT/build/web"
[[ -f "$WEB_DIR/index.html" ]] || fail "Web app is not built. Run $0 --build first."

say "Applying database migrations..."
(
  cd "$API"
  uv run alembic upgrade head
)

export OMNI_WEB_DIR="$WEB_DIR"
trap 'status=$?; trap - EXIT; [[ -n "${WORKER_PID:-}" ]] && kill "$WORKER_PID" 2>/dev/null || true; exit "$status"' EXIT INT TERM

if grep -Eq '^OMNI_VAPID_PRIVATE_KEY=.+$' "$ENV_FILE"; then
  say "Starting reminder worker..."
  (cd "$API" && uv run python -m src.workers.reminder_worker) &
  WORKER_PID=$!
fi

say "Ready: http://localhost:$PORT"
say "Press Ctrl+C to stop OmniAssist."
(cd "$API" && uv run uvicorn src.main:app --host "$HOST" --port "$PORT" --proxy-headers)
