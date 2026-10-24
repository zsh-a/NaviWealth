#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../apps/mobile"

for name in RELEASE_VERSION RELEASE_BUILD_NUMBER GITHUB_SHA GITHUB_REPOSITORY \
  KEYSTORE_BASE64 KEYSTORE_FILE KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::$name is required for a signed Android release" >&2
    exit 1
  fi
done

trap 'rm -f "$KEYSTORE_FILE"' EXIT
printf '%s' "$KEYSTORE_BASE64" | base64 --decode > "$KEYSTORE_FILE"
api_url="$(tr -d '\r\n' < ../backend/.api-base-url)"
args=(
  --release
  --build-name="$RELEASE_VERSION"
  --build-number="$RELEASE_BUILD_NUMBER"
  --target-platform=android-arm64
  --android-project-arg=naviwealth-arm64-only=true
  --dart-define="API_BASE_URL=$api_url"
  --dart-define="GIT_SHA=$GITHUB_SHA"
  --dart-define="NATIVE_UPDATE_MANIFEST_URL=${GITHUB_SERVER_URL:-https://github.com}/$GITHUB_REPOSITORY/releases/latest/download/latest.json"
)

for artifact in apk appbundle; do
  flutter build "$artifact" "${args[@]}"
done
