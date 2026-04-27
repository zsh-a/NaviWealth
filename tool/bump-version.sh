#!/usr/bin/env bash
# Bump the version of either the mobile app or the backend, commit the
# change, and create a release tag. The release workflow picks it up.
#
# Usage:
#   tool/bump-version.sh mobile  0.2.0
#   tool/bump-version.sh backend 0.2.0
#
# Build number is NOT written into source — it is derived at release time
# from `git rev-list --count <tag>` so two releases never share a number.
set -euo pipefail

usage() {
  echo "usage: $0 <mobile|backend> <semver>" >&2
  exit 64
}

[ $# -eq 2 ] || usage
kind="$1"
semver="$2"

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

case "$kind" in
  mobile)
    file="apps/mobile/pubspec.yaml"
    # build number stays at +1 in source; release workflow re-stamps it.
    sed -i.bak -E "s/^version: .*/version: ${semver}+1/" "$file"
    rm "${file}.bak"
    tag="mobile-v${semver}"
    ;;
  backend)
    file="apps/backend/Cargo.toml"
    # only the first `version = ...` (the [package] one) is replaced.
    awk -v v="$semver" '
      BEGIN { done = 0 }
      !done && /^version = "/ { sub(/"[^"]*"/, "\"" v "\""); done = 1 }
      { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    tag="backend-v${semver}"
    ;;
  *)
    usage
    ;;
esac

if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
  echo "error: tag $tag already exists." >&2
  exit 1
fi

git add "$file"
git commit -m "release($kind): $semver"
git tag -a "$tag" -m "$kind $semver"

echo
echo "Created commit + tag $tag."
echo "Push with:  git push origin HEAD --follow-tags"
