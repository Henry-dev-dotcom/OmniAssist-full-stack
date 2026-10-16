#!/usr/bin/env bash
set -Eeuo pipefail

# Vercel's image does not include Flutter. Install the current stable SDK in the build cache,
# generate Drift code, and produce the static PWA that Vercel serves.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="${HOME}/flutter"
API_BASE_URL="${API_BASE_URL:?Set API_BASE_URL to the public Render API URL, ending in /api/v1}"

if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  rm -rf "$FLUTTER_DIR"
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$FLUTTER_DIR/bin/cache/dart-sdk/bin:$PATH"
flutter config --no-analytics
flutter precache --web

cd "$ROOT/apps/client"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build web --release --no-web-resources-cdn \
  --dart-define="API_BASE_URL=${API_BASE_URL}"
