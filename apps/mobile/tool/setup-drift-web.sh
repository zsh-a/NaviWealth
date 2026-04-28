#!/usr/bin/env bash
# Materialize the two web assets drift's WasmDatabase needs at runtime:
#
#   apps/mobile/web/sqlite3.wasm        — sqlite3 compiled to WebAssembly
#   apps/mobile/web/drift_worker.dart.js — drift's worker entrypoint, JS-compiled
#
# These are build artifacts (not source) and are .gitignored. Run this once
# locally before `flutter run -d chrome` / `flutter build web`, and once per
# CI web build. Idempotent — re-running only re-fetches if the version
# pinned in pubspec.lock changed.
#
# Usage: apps/mobile/tool/setup-drift-web.sh
set -euo pipefail

cd "$(dirname "$0")/.."

WEB_DIR="web"
CACHE_DIR=".dart_tool/drift_web"
WASM_PATH="$WEB_DIR/sqlite3.wasm"
WORKER_SRC="$WEB_DIR/drift_worker.dart"
WORKER_OUT="$WEB_DIR/drift_worker.dart.js"

mkdir -p "$CACHE_DIR"

# Resolve the sqlite3 dart package version from pubspec.lock so the wasm we
# fetch always matches the dart bindings. Falls back to a known-good pin if
# the lockfile is missing (e.g. fresh checkout without `flutter pub get`).
SQLITE_VERSION="$(awk '
  /^  sqlite3:/ { in_pkg = 1; next }
  in_pkg && /^    version:/ { gsub(/[" ]/, "", $2); print $2; exit }
' pubspec.lock 2>/dev/null || true)"
SQLITE_VERSION="${SQLITE_VERSION:-2.9.4}"

WASM_URL="https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE_VERSION}/sqlite3.wasm"

mkdir -p "$WEB_DIR"

# Re-download only when the pinned version changed. The stamp lives in
# .dart_tool/ (already gitignored + outside web/) so it doesn't leak into
# `flutter build web` output, which copies everything under web/ verbatim.
WASM_STAMP="$CACHE_DIR/sqlite3.wasm.version"
if [ ! -f "$WASM_PATH" ] || [ "$(cat "$WASM_STAMP" 2>/dev/null || echo)" != "$SQLITE_VERSION" ]; then
  echo "fetching sqlite3.wasm $SQLITE_VERSION → $WASM_PATH"
  curl --fail --silent --show-error --location --output "$WASM_PATH" "$WASM_URL"
  echo "$SQLITE_VERSION" > "$WASM_STAMP"
else
  echo "sqlite3.wasm $SQLITE_VERSION already present"
fi

if [ ! -f "$WORKER_SRC" ]; then
  echo "error: $WORKER_SRC missing — drift worker source is required" >&2
  exit 1
fi

echo "compiling $WORKER_SRC → $WORKER_OUT"
dart compile js -O4 -o "$WORKER_OUT" "$WORKER_SRC"
# `dart compile js` also emits a .deps file we don't need shipped.
rm -f "$WORKER_OUT.deps"

echo "drift web assets ready in $WEB_DIR/"
