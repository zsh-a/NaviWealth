#!/usr/bin/env bash
# Apply the repository's fixed Android release key to an NSH package.
# Passwords are read by the signing tools from the environment, not argv.
set +x
set -euo pipefail
umask 077

if [[ $# -ne 2 ]]; then
  echo 'usage: sign-nsh-apk.sh <packaged.apk> <release.apk>' >&2
  exit 64
fi

apk_input="$1"
apk_output="$2"
for name in ANDROID_HOME KEYSTORE_BASE64 KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::$name is required for a signed NSH release" >&2
    exit 1
  fi
done
if [[ ! -s "$apk_input" || -e "$apk_output" ]]; then
  echo '::error::A packaged APK and a new output path are required' >&2
  exit 1
fi

tools="$ANDROID_HOME/build-tools/${ANDROID_BUILD_TOOLS_VERSION:-35.0.1}"
signing_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/naviwealth-signing.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "$signing_dir"
  if [[ $status -ne 0 ]]; then
    rm -f "$apk_output"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$KEYSTORE_BASE64" | base64 --decode > "$signing_dir/release.keystore"
keytool -exportcert -keystore "$signing_dir/release.keystore" \
  -alias "$KEY_ALIAS" -storepass:env KEYSTORE_PASSWORD \
  -file "$signing_dir/certificate.der"
expected="$(sha256sum "$signing_dir/certificate.der" | cut -d ' ' -f 1)"

mkdir -p "$(dirname "$apk_output")"
"$tools/apksigner" sign \
  --ks "$signing_dir/release.keystore" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass env:KEYSTORE_PASSWORD \
  --key-pass env:KEY_PASSWORD \
  --out "$apk_output" \
  "$apk_input"

verification="$("$tools/apksigner" verify --verbose --print-certs "$apk_output")"
actual="$(printf '%s\n' "$verification" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
if [[ -z "$actual" || "$actual" != "$expected" ]]; then
  echo '::error::APK certificate does not match the fixed release keystore' >&2
  exit 1
fi
if printf '%s\n' "$verification" | grep -qi 'Android Debug'; then
  echo '::error::A debug certificate cannot be published as a release' >&2
  exit 1
fi
printf '%s\n' "$verification"
echo "Verified fixed release certificate SHA-256: $actual"
