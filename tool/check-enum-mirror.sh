#!/usr/bin/env bash
# Wave 42 — verify the AI wire-contract enums on the mobile (Dart) and
# backend (Rust) sides have identical variant sets.
#
# The two repos manually mirror each enum (Dart `enum X { a, b }` ↔
# Rust `pub enum X { A, B }` with `#[serde(rename_all = "snake_case")]`).
# CLAUDE.md §Contract Drift Prevention promises this; today it's
# enforced by code review. This script makes it mechanical.
#
# Convention:
#   - Dart enums in `apps/mobile/lib/core/ai/contracts/*.dart` whose
#     name matches a Rust `pub enum` in
#     `apps/backend/src/ai/context/*.rs` with the
#     `#[serde(rename_all = "snake_case")]` attribute are compared.
#   - Variant names are normalised to lowercase for comparison
#     (Rust's `RenameAll::SnakeCase` lowercases simple identifiers).
#   - Symmetric difference → exit 1 with a diff.
#
# Limitations (intentionally simple, expand only when bitten):
#   - PascalCase Rust variants only (e.g. `OneWord`, not `XMLData`).
#   - One-line enums OK; multi-line OK; ignores derived helpers like
#     `extension XWire on X`.
#   - We compare *only* enums whose name appears in both repos; enums
#     unique to one side are left alone (intentional — some enums are
#     mobile-only e.g. UI modes).
#
# Exit codes:
#   0  — every shared enum has matching variant sets
#   1  — at least one mismatch
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DART_DIR="${REPO_ROOT}/apps/mobile/lib/core/ai/contracts"
RUST_DIR="${REPO_ROOT}/apps/backend/src/ai/context"

if [[ ! -d "${DART_DIR}" || ! -d "${RUST_DIR}" ]]; then
  echo "::error::contract dirs missing — looked in ${DART_DIR} and ${RUST_DIR}"
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

dart_enums="${tmpdir}/dart_enums.txt"
rust_enums="${tmpdir}/rust_enums.txt"
: > "${dart_enums}"
: > "${rust_enums}"

# ── Extract Dart enums ────────────────────────────────────────────
# Match `enum NAME { v1, v2, ... }` (single- or multi-line).
# awk state machine: when we see `enum`, capture body until matching `}`.
for f in "${DART_DIR}"/*.dart; do
  awk '
    /^enum [A-Za-z_][A-Za-z0-9_]*/ {
      name=$2
      sub(/\{.*/, "", name)
      gsub(/[ \t]/, "", name)
      body=$0
      # If both braces on the same line — done in one pass.
      if (body ~ /\{.*\}/) {
        sub(/^.*\{/, "", body)
        sub(/\}.*/, "", body)
        gsub(/[ \t,\r\n]+/, " ", body)
        print name "|" tolower(body)
        gathering=0
        next
      }
      # Otherwise start gathering until we see "}".
      if (body ~ /\{/) {
        sub(/^.*\{/, "", body)
      } else {
        body=""
      }
      gathering=1
      next
    }
    gathering==1 {
      line=$0
      # Strip line / block comments before adding to body.
      sub(/\/\/.*/, "", line)
      sub(/\/\*.*\*\//, "", line)
      if (line ~ /\}/) {
        sub(/\}.*/, "", line)
        body=body " " line
        gsub(/[ \t,\r\n]+/, " ", body)
        print name "|" tolower(body)
        gathering=0
        next
      }
      body=body " " line
    }
  ' "${f}" >> "${dart_enums}"
done

# ── Extract Rust enums with #[serde(rename_all = "snake_case")] ──
# Two-line look-back: when we see the rename_all attr, the next line
# starting `pub enum NAME {` is a candidate. Body collected until `}`.
for f in "${RUST_DIR}"/*.rs; do
  awk '
    /serde\(rename_all = "snake_case"\)/ {
      pending=1
      next
    }
    pending==1 && /^pub enum [A-Za-z_][A-Za-z0-9_]*/ {
      name=$3
      sub(/\{.*/, "", name)
      gsub(/[ \t]/, "", name)
      pending=0
      body=$0
      if (body ~ /\{.*\}/) {
        sub(/^.*\{/, "", body)
        sub(/\}.*/, "", body)
        gsub(/[ \t,\r\n]+/, " ", body)
        print name "|" tolower(body)
        gathering=0
        next
      }
      if (body ~ /\{/) {
        sub(/^.*\{/, "", body)
      } else {
        body=""
      }
      gathering=1
      next
    }
    gathering==1 {
      line=$0
      # Strip line / block comments before adding to body.
      sub(/\/\/.*/, "", line)
      sub(/\/\*.*\*\//, "", line)
      if (line ~ /\}/) {
        sub(/\}.*/, "", line)
        body=body " " line
        gsub(/[ \t,\r\n]+/, " ", body)
        print name "|" tolower(body)
        gathering=0
        next
      }
      body=body " " line
    }
  ' "${f}" >> "${rust_enums}"
done

# ── Compare shared enums ──────────────────────────────────────────
exit_code=0
shared_count=0

# For each Dart enum, find the matching Rust enum (by name).
while IFS='|' read -r name body; do
  rust_body="$(grep "^${name}|" "${rust_enums}" | head -1 | cut -d'|' -f2- || true)"
  if [[ -z "${rust_body}" ]]; then
    continue  # enum only on Dart side — not a wire contract
  fi
  shared_count=$((shared_count + 1))

  # Variant sets — only keep tokens that look like identifiers
  # (drops doc comments / stray words / punctuation that snuck past
  # the awk extractor when variants have inline `///` rustdoc).
  dart_vars="$(echo "${body}" \
    | tr ' ' '\n' \
    | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*$' \
    | sort -u)"
  rust_vars="$(echo "${rust_body}" \
    | tr ' ' '\n' \
    | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*$' \
    | sort -u)"

  only_dart="$(comm -23 <(echo "${dart_vars}") <(echo "${rust_vars}"))"
  only_rust="$(comm -13 <(echo "${dart_vars}") <(echo "${rust_vars}"))"

  if [[ -n "${only_dart}" || -n "${only_rust}" ]]; then
    echo "::error::enum '${name}' variant sets diverge:"
    [[ -n "${only_dart}" ]] && echo "  only on Dart:" && echo "${only_dart}" | sed 's/^/    - /'
    [[ -n "${only_rust}" ]] && echo "  only on Rust:" && echo "${only_rust}" | sed 's/^/    - /'
    exit_code=1
  fi
done < "${dart_enums}"

if [[ ${exit_code} -eq 0 ]]; then
  echo "✅ ${shared_count} shared enum(s) — all variant sets agree."
fi

exit ${exit_code}
