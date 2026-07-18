#!/usr/bin/env bash
set -euo pipefail

readonly result_dir='test-results'
readonly event_json="$result_dir/android-integration.json"
readonly integration_log="$result_dir/android-integration.log"
readonly evidence_json="$result_dir/android-database-encryption.json"
device_id="${1:-$(adb get-serialno | tr -d '\r')}"
readonly device_id

if [[ -z "$device_id" || "$device_id" == 'unknown' ]]; then
  echo 'No Android device is available for integration testing.' >&2
  exit 1
fi

mkdir -p "$result_dir"
rm -f "$event_json" "$integration_log" "$evidence_json"

flutter test integration_test/ \
  -d "$device_id" \
  --reporter=expanded \
  --file-reporter="json:$event_json" 2>&1 | tee "$integration_log"

readonly required_markers=(
  'database-encryption: sqlcipher available'
  'database-encryption: encrypted header verified'
  'database-encryption: correct key reopen verified'
  'database-encryption: wrong key rejected'
  'database-encryption: plaintext migration verified'
  'database-encryption: android keystore key persisted'
  'database-encryption: missing keystore key failed closed'
  'database-encryption: restored keystore key reopened'
  'backup: encrypted restore completed on file database'
  'backup: failed restore rollback persisted after reopen'
)

for marker in "${required_markers[@]}"; do
  if ! grep -Fq "$marker" "$integration_log"; then
    echo "Android integration passed without required evidence: $marker" >&2
    exit 1
  fi
done

api_level="$(adb -s "$device_id" shell getprop ro.build.version.sdk | tr -d '\r')"
readonly api_level
readonly git_sha="${GITHUB_SHA:-local}"
verified_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
readonly verified_at

{
  printf '{\n'
  printf '  "schema_version": 1,\n'
  printf '  "outcome": "passed",\n'
  printf '  "platform": "android",\n'
  printf '  "api_level": "%s",\n' "$api_level"
  printf '  "git_sha": "%s",\n' "$git_sha"
  printf '  "verified_at": "%s",\n' "$verified_at"
  printf '  "sqlcipher_available": true,\n'
  printf '  "encrypted_header_verified": true,\n'
  printf '  "correct_key_reopen_verified": true,\n'
  printf '  "wrong_key_rejected": true,\n'
  printf '  "plaintext_migration_verified": true,\n'
  printf '  "android_keystore_persistence_verified": true,\n'
  printf '  "missing_keystore_key_failed_closed": true,\n'
  printf '  "backup_restore_verified": true,\n'
  printf '  "failed_restore_rollback_verified": true\n'
  printf '}\n'
} >"$evidence_json"

cat "$evidence_json"
