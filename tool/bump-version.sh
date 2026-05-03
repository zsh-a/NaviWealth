#!/usr/bin/env bash
# Bump the version of both mobile and backend, commit the change, and create
# a release tag. The unified release workflow picks it up.
#
# Usage:
#   tool/bump-version.sh 0.2.0
#
# Build number is NOT written into source — it is derived at release time
# from `git rev-list --count <tag>` so two releases never share a number.
set -euo pipefail

usage() {
  echo "usage: $0 <semver>" >&2
  exit 64
}

[ $# -eq 1 ] || usage
semver="$1"

if ! [[ "$semver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: semver must look like X.Y.Z, got '$semver'" >&2
  exit 64
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is dirty — commit or stash first." >&2
  exit 1
fi

tag="v${semver}"

if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
  echo "error: tag $tag already exists." >&2
  exit 1
fi

# Stamp mobile version (build number stays at +1; release workflow re-stamps).
mobile_file="apps/mobile/pubspec.yaml"
sed -i.bak -E "s/^version: .*/version: ${semver}+1/" "$mobile_file"
rm "${mobile_file}.bak"

# Stamp backend version (only the first `version = ...` line).
backend_file="apps/backend/Cargo.toml"
awk -v v="$semver" '
  BEGIN { done = 0 }
  !done && /^version = "/ { sub(/"[^"]*"/, "\"" v "\""); done = 1 }
  { print }
' "$backend_file" > "${backend_file}.tmp" && mv "${backend_file}.tmp" "$backend_file"

git add "$mobile_file" "$backend_file"

if git diff --cached --quiet; then
  echo "error: version $semver is already set — nothing to commit." >&2
  exit 1
fi

git commit -m "release: $semver"
git tag -a "$tag" -m "release $semver"

echo
echo "Created commit + tag $tag."
echo "Push with:  git push origin HEAD --follow-tags"
