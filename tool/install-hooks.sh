#!/usr/bin/env bash
# Install repo git hooks. Re-run after cloning or after hooks change.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
src="$repo_root/tool/hooks"
dst="$repo_root/.git/hooks"

mkdir -p "$dst"
for hook in "$src"/*; do
  name="$(basename "$hook")"
  ln -sf "../../tool/hooks/$name" "$dst/$name"
  chmod +x "$hook"
  echo "installed: $name -> tool/hooks/$name"
done
