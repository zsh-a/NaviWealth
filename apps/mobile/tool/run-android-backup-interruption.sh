#!/usr/bin/env bash
set -euo pipefail

readonly package_name='com.naviwealth.naviwealth'
readonly result_dir='test-results'
readonly interrupt_log="$result_dir/android-backup-process-interruption.log"
readonly wipe_marker='backup: cleared archive tables + matching outbox rows'

mkdir -p "$result_dir"
: >"$interrupt_log"

timeout 300 flutter test \
  integration_test/backup_process_interruption_integration_test.dart \
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

adb shell am force-stop "$package_name"

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
  --dart-define=BACKUP_INTERRUPTION_PHASE=verify \
  --plain-name 'fresh process observes rollback after interrupted restore' \
  --reporter=expanded 2>&1 | tee -a "$interrupt_log"
