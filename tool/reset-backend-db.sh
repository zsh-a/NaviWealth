#!/usr/bin/env bash
# Reset the NaviWealth backend D1 database.
#
# Usage:
#   tool/reset-backend-db.sh [--remote] [--full] [-y]
#
#   (no flags)   wipe data on the *local* Miniflare D1 (safest default)
#   --remote     target the deployed Cloudflare D1 instead of local
#   --full       DROP every table + the d1_migrations ledger and re-apply
#                all migrations from scratch (default is data-only DELETE
#                that keeps the schema and migration history)
#   -y, --yes    skip the "are you sure?" prompt
#
# After a reset, create the first account through the app's normal
# registration screen after the backend is running.
#
# This script never edits wrangler.toml and never deletes the D1
# instance itself, so the database_id stays stable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/apps/backend"
SQL_DIR="$REPO_ROOT/tool/reset-backend-db"

DB_NAME="naviwealth"
TARGET_FLAG="--local"
TARGET_LABEL="local Miniflare D1"
MODE="data"
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      TARGET_FLAG="--remote"
      TARGET_LABEL="REMOTE Cloudflare D1 (production)"
      ;;
    --local)
      TARGET_FLAG="--local"
      TARGET_LABEL="local Miniflare D1"
      ;;
    --full)
      MODE="full"
      ;;
    --data|--data-only)
      MODE="data"
      ;;
    -y|--yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown flag: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if ! command -v wrangler >/dev/null 2>&1; then
  echo "wrangler not found in PATH. Install with: npm i -g wrangler" >&2
  exit 1
fi

if [[ "$MODE" == "data" ]]; then
  SQL_FILE="$SQL_DIR/wipe-data.sql"
  ACTION_LABEL="DELETE every app row (schema + migration history kept)"
else
  SQL_FILE="$SQL_DIR/drop-all.sql"
  ACTION_LABEL="DROP every table + d1_migrations, then re-apply migrations"
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "missing SQL file: $SQL_FILE" >&2
  exit 1
fi

cat <<EOF
About to reset the backend database.

  database : $DB_NAME
  target   : $TARGET_LABEL
  mode     : $ACTION_LABEL
  sql      : $SQL_FILE

EOF

if [[ "$TARGET_FLAG" == "--remote" && $ASSUME_YES -eq 0 ]]; then
  echo "!! REMOTE target — this destroys production data."
fi

if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p "Continue? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *)
      echo "aborted."
      exit 1
      ;;
  esac
fi

cd "$BACKEND_DIR"

echo "→ executing $SQL_FILE against $TARGET_LABEL …"
wrangler d1 execute "$DB_NAME" "$TARGET_FLAG" --file "$SQL_FILE" --yes

if [[ "$MODE" == "full" ]]; then
  echo "→ re-applying migrations …"
  wrangler d1 migrations apply "$DB_NAME" "$TARGET_FLAG"
fi

cat <<EOF

✓ done.

Next steps:
  - Start the backend and create the first account through the app's
    normal registration screen.
  - Restart the mobile app / clear its local DB so it doesn't try to
    push stale ops against an empty server (the sync engine will
    reconcile, but a clean slate avoids confusing tombstone churn).
EOF
