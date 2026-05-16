#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_JSON="$(mktemp)"
MOBILE_JSON="$(mktemp)"
trap 'rm -f "$BACKEND_JSON" "$MOBILE_JSON"' EXIT

(cd "$ROOT/apps/backend" && cargo run --quiet --bin tool_descriptor_dump) \
  > "$BACKEND_JSON"
(cd "$ROOT/apps/mobile" && dart run tool/dump_tool_descriptors.dart) \
  | awk 'BEGIN { found = 0 } {
      if (!found) {
        start = index($0, "[")
        if (start > 0) {
          print substr($0, start)
          found = 1
        }
      } else {
        print
      }
    }' > "$MOBILE_JSON"

diff -u "$BACKEND_JSON" "$MOBILE_JSON"
