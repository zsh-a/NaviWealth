#!/usr/bin/env bash
set -euo pipefail

readonly package_name='com.naviwealth.naviwealth'
readonly result_dir='test-results'
readonly interrupt_log="$result_dir/android-backup-process-interruption.log"
readonly evidence_json="$result_dir/android-backup-process-interruption.json"
readonly wipe_marker='backup: cleared archive tables + matching outbox rows'
readonly verify_marker='backup: interruption verification preserved account + outbox'
device_id="$(adb get-serialno | tr -d '\r')"
readonly device_id

if [[ -z "$device_id" || "$device_id" == 'unknown' ]]; then
  echo 'No Android device is available for backup interruption testing.' >&2
  exit 1
fi

mkdir -p "$result_dir"
: >"$interrupt_log"
rm -f "$evidence_json"

timeout 300 flutter test \
  integration_test/backup_process_interruption_integration_test.dart \
  -d "$device_id" \
  --dart-define=BACKUP_INTERRUPTION_PHASE=interrupt \
  --plain-name 'interrupt restore after the destructive wipe begins' \
  --no-uninstall \
  --reporter=expanded >"$interrupt_log" 2>&1 &
readonly test_pid=$!

cleanup() {
  if kill -0 "$test_pid" 2>/dev/null; then
    kill "$test_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

marker_seen=false
for _ in $(seq 1 2400); do
  if grep -Fq "$wipe_marker" "$interrupt_log"; then
    marker_seen=true
    break
  fi
  if ! kill -0 "$test_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if [[ "$marker_seen" != true ]]; then
  cat "$interrupt_log"
  echo 'Restore never reached the in-transaction destructive-wipe marker.' >&2
  exit 1
fi

app_pid_before="$(adb shell pidof "$package_name" | tr -d '\r')"
readonly app_pid_before
if [[ -z "$app_pid_before" ]]; then
  cat "$interrupt_log"
  echo 'The target app was not running when the wipe marker appeared.' >&2
  exit 1
fi

adb shell am force-stop "$package_name"

force_stop_confirmed=false
for _ in $(seq 1 100); do
  if [[ -z "$(adb shell pidof "$package_name" | tr -d '\r')" ]]; then
    force_stop_confirmed=true
    break
  fi
  sleep 0.1
done

if [[ "$force_stop_confirmed" != true ]]; then
  cat "$interrupt_log"
  echo 'The target app process survived am force-stop.' >&2
  exit 1
fi

set +e
wait "$test_pid"
readonly interrupt_status=$?
set -e
trap - EXIT

if [[ "$interrupt_status" -eq 0 ]]; then
  cat "$interrupt_log"
  echo 'Interrupt phase completed normally; force-stop arrived too late.' >&2
  exit 1
fi

flutter test \
  integration_test/backup_process_interruption_integration_test.dart \
  -d "$device_id" \
  --dart-define=BACKUP_INTERRUPTION_PHASE=verify \
  --plain-name 'fresh process observes rollback after interrupted restore' \
  --reporter=expanded 2>&1 | tee -a "$interrupt_log"

if ! grep -Fq "$verify_marker" "$interrupt_log"; then
  cat "$interrupt_log"
  echo 'Verification passed without reaching the rollback evidence marker.' >&2
  exit 1
fi

api_level="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
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
  printf '  "destructive_wipe_marker_seen": true,\n'
  printf '  "force_stop_confirmed": true,\n'
  printf '  "verification_marker_seen": true,\n'
  printf '  "interrupt_test_exit_code": %s,\n' "$interrupt_status"
  printf '  "preserved_account_count": 1,\n'
  printf '  "preserved_outbox_count": 1\n'
  printf '}\n'
} >"$evidence_json"

cat "$evidence_json"
