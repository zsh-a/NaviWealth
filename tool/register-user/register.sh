#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Build if binary doesn't exist or source is newer
if [ ! -f "$SCRIPT_DIR/target/release/register-user" ] || \
   [ "$SCRIPT_DIR/src/main.rs" -nt "$SCRIPT_DIR/target/release/register-user" ] || \
   [ "$SCRIPT_DIR/Cargo.toml" -nt "$SCRIPT_DIR/target/release/register-user" ]; then
    echo "Building register-user..."
    cargo build --release --manifest-path "$SCRIPT_DIR/Cargo.toml" --quiet
fi

exec "$SCRIPT_DIR/target/release/register-user" "$@"
