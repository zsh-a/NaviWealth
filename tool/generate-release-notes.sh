#!/usr/bin/env bash
# Generate a structured GitHub Release body for NaviWealth.
#
# Usage:
#   tool/generate-release-notes.sh <tag> <semver> <build-number> <api-url> <output>
set -euo pipefail

usage() {
  echo "usage: $0 <tag> <semver> <build-number> <api-url> <output>" >&2
  exit 64
}

[ $# -eq 5 ] || usage

release_tag="$1"
semver="$2"
build_number="$3"
api_url="$4"
output="$5"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if ! [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: release tag must look like vX.Y.Z, got '$release_tag'" >&2
  exit 64
fi

if ! [[ "$semver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: semver must look like X.Y.Z, got '$semver'" >&2
  exit 64
fi

repo_path="${GITHUB_REPOSITORY:-}"
if [ -z "$repo_path" ]; then
  origin="$(git config --get remote.origin.url || true)"
  case "$origin" in
    git@github.com:*)
      repo_path="${origin#git@github.com:}"
      repo_path="${repo_path%.git}"
      ;;
    https://github.com/*)
      repo_path="${origin#https://github.com/}"
      repo_path="${repo_path%.git}"
      ;;
  esac
fi

server_url="${GITHUB_SERVER_URL:-https://github.com}"
if [ -n "$repo_path" ]; then
  repo_url="${server_url}/${repo_path}"
else
  repo_url="https://github.com"
fi

if git rev-parse --verify "refs/tags/$release_tag" >/dev/null 2>&1; then
  target_commit="$(git rev-list -n 1 "$release_tag")"
  previous_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "${target_commit}^" 2>/dev/null || true)"
else
  target_commit="$(git rev-parse HEAD)"
  previous_tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$target_commit" 2>/dev/null || true)"
fi

if [ -n "$previous_tag" ]; then
  commit_range="${previous_tag}..${target_commit}"
  compare_url="${repo_url}/compare/${previous_tag}...${release_tag}"
  compare_label="${previous_tag}...${release_tag}"
else
  commit_range="$target_commit"
  compare_url="${repo_url}/commits/${release_tag}"
  compare_label="$release_tag"
fi

short_sha="$(git rev-parse --short "$target_commit")"
release_date="$(date -u +%Y-%m-%d)"
apk_name="naviwealth-android-arm64-v${semver}+${build_number}.apk"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

features="$tmp_dir/features.md"
fixes="$tmp_dir/fixes.md"
uiux="$tmp_dir/uiux.md"
maintenance="$tmp_dir/maintenance.md"
other="$tmp_dir/other.md"
: > "$features"
: > "$fixes"
: > "$uiux"
: > "$maintenance"
: > "$other"

commit_count=0
while IFS=$'\x1f' read -r hash subject author; do
  [ -n "$hash" ] || continue
  commit_count=$((commit_count + 1))
  short="${hash:0:7}"
  line="- ${subject} ([${short}](${repo_url}/commit/${hash}))"
  lower="$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    feat:*|feat\(*|feature:*|feature\(*|add\ *|implement\ *|enable\ *)
      echo "$line" >> "$features"
      ;;
    fix:*|fix\(*|bugfix:*|repair\ *|resolve\ *)
      echo "$line" >> "$fixes"
      ;;
    ui:*|ux:*|style:*|polish\ *|optimize\ *|compact\ *|modernize\ *|redesign\ *|improve\ *ui*)
      echo "$line" >> "$uiux"
      ;;
    ci:*|build:*|chore:*|docs:*|test:*|tests:*|refactor:*|release:*|lint\ *|update\ ci*)
      echo "$line" >> "$maintenance"
      ;;
    *)
      echo "$line" >> "$other"
      ;;
  esac
done < <(git log --no-merges --reverse --format='%H%x1f%s%x1f%an' "$commit_range")

areas_file="$tmp_dir/areas.md"
: > "$areas_file"
mobile_count=0
finance_count=0
health_count=0
knowledge_count=0
execution_count=0
backend_count=0
ci_count=0
tooling_count=0
docs_count=0
if [ -n "$previous_tag" ]; then
  git diff --name-only "$previous_tag" "$target_commit" > "$tmp_dir/changed-files.txt"
else
  git show --pretty='' --name-only "$target_commit" > "$tmp_dir/changed-files.txt"
fi

while IFS= read -r path; do
  [ -n "$path" ] || continue
  area=""
  case "$path" in
    apps/mobile/lib/features/execution/*)
      area="ExecutionOS"
      ;;
    apps/mobile/lib/features/knowledge/*)
      area="KnowledgeOS"
      ;;
    apps/mobile/lib/features/health/*)
      area="HealthOS"
      ;;
    apps/mobile/lib/features/finance/*|apps/mobile/lib/features/accounts/*|apps/mobile/lib/features/assets/*|apps/mobile/lib/features/investment/*|apps/mobile/lib/features/options_income/*)
      area="FinanceOS"
      ;;
    apps/mobile/*)
      area="Mobile app"
      ;;
    apps/backend/*)
      area="Backend"
      ;;
    .github/*)
      area="CI/CD"
      ;;
    docs/*)
      area="Documentation"
      ;;
    tool/*)
      area="Tooling"
      ;;
  esac
  case "$area" in
    "Mobile app") mobile_count=$((mobile_count + 1)) ;;
    "FinanceOS") finance_count=$((finance_count + 1)) ;;
    "HealthOS") health_count=$((health_count + 1)) ;;
    "KnowledgeOS") knowledge_count=$((knowledge_count + 1)) ;;
    "ExecutionOS") execution_count=$((execution_count + 1)) ;;
    "Backend") backend_count=$((backend_count + 1)) ;;
    "CI/CD") ci_count=$((ci_count + 1)) ;;
    "Tooling") tooling_count=$((tooling_count + 1)) ;;
    "Documentation") docs_count=$((docs_count + 1)) ;;
  esac
done < "$tmp_dir/changed-files.txt"

write_area() {
  local area="$1"
  local count="$2"
  if [ "$count" -gt 0 ]; then
    if [ "$count" -eq 1 ]; then
      echo "- ${area}: 1 changed file" >> "$areas_file"
    else
      echo "- ${area}: ${count} changed files" >> "$areas_file"
    fi
  fi
}

write_area "Mobile app" "$mobile_count"
write_area "FinanceOS" "$finance_count"
write_area "HealthOS" "$health_count"
write_area "KnowledgeOS" "$knowledge_count"
write_area "ExecutionOS" "$execution_count"
write_area "Backend" "$backend_count"
write_area "CI/CD" "$ci_count"
write_area "Tooling" "$tooling_count"
write_area "Documentation" "$docs_count"

write_section() {
  local title="$1"
  local file="$2"
  if [ -s "$file" ]; then
    {
      echo
      echo "### ${title}"
      cat "$file"
    } >> "$output"
  fi
}

mkdir -p "$(dirname "$output")"
{
  echo "## Overview"
  echo
  echo "- Version: \`${semver}\`"
  echo "- Build: \`${build_number}\`"
  echo "- Commit: [\`${short_sha}\`](${repo_url}/commit/${target_commit})"
  echo "- Released: ${release_date} UTC"
  echo "- Compare: [\`${compare_label}\`](${compare_url})"
  echo
  echo "## Install"
  echo
  echo "- Android arm64 APK: \`${apk_name}\`"
  echo "- Web PWA: deployed from this workflow when Cloudflare Pages credentials are configured"
  echo "- API endpoint baked into clients: \`${api_url}\`"
  echo
  echo "## Release Validation"
  echo
  echo "- Mobile version stamped as \`${semver}+${build_number}\`"
  echo "- Securities catalog refreshed before the mobile build"
  echo "- CN and Latin font subsets generated"
  echo "- Drift web assets materialized"
  echo "- Android APK and Flutter web release bundle built from [\`${short_sha}\`](${repo_url}/commit/${target_commit})"
  echo
  echo "## Impact Areas"
  echo
  if [ -s "$areas_file" ]; then
    cat "$areas_file"
  else
    echo "- No source areas changed since the previous release."
  fi
  echo
  echo "## What's Changed"
} > "$output"

write_section "Features" "$features"
write_section "Fixes" "$fixes"
write_section "UI and UX" "$uiux"
write_section "Maintenance" "$maintenance"
write_section "Other Changes" "$other"

if [ "$commit_count" -eq 0 ]; then
  {
    echo
    echo "- No commits were detected in this release range."
  } >> "$output"
fi

{
  echo
  echo "## Full Changelog"
  echo
  echo "[${compare_label}](${compare_url})"
} >> "$output"

echo "Release notes written to $output (range=$commit_range)"
