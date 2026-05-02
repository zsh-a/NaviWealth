#!/usr/bin/env bash
# Build the self-hosted Latin webfont subsets the app loads via pubspec
# fontFamily registrations + (on web) @font-face in web/index.html.
#
#   assets/fonts/inter-{regular,medium,semibold,bold}.woff2 — Inter, the
#                primary fontFamily. Tabular figures + lining figures are
#                preserved through the subset so MoneyText etc. continue to
#                render aligned digits.
#   assets/fonts/outfit-bold.woff2                          — Outfit Bold,
#                used only by the Display 2XL hero number on the dashboard.
#                A single weight is enough; the rest of the type ramp uses
#                Inter.
#
# All subsets are limited to Latin + numbers + currency / arrow / box-
# drawing punctuation — Chinese glyphs are still served by AppCnSans
# (tool/build-cn-fonts.sh). Combined budget: ≤ 200 KB.
#
# Outputs are build artifacts (gitignored, in line with tool/build-cn-fonts.sh).
# Run before `flutter run` / `flutter test` / `flutter build` once per fresh
# checkout; it's idempotent on subsequent runs.
#
# Usage: apps/mobile/tool/build-latin-fonts.sh
set -euo pipefail

cd "$(dirname "$0")/.."

CACHE_DIR=".dart_tool/latin_fonts"
ASSETS_DIR="assets/fonts"
VENV_DIR="$CACHE_DIR/venv"
SOURCE_DIR="$CACHE_DIR/src"

# Source fonts: Inter and Outfit, both shipped as variable TTFs by Google
# Fonts. Pinned by SHA-256 to survive force-pushes / branch renames.
INTER_URL="${INTER_URL:-https://raw.githubusercontent.com/google/fonts/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf}"
INTER_SHA256="${INTER_SHA256:-}"
INTER_FONT="$SOURCE_DIR/Inter[opsz,wght].ttf"

OUTFIT_URL="${OUTFIT_URL:-https://raw.githubusercontent.com/google/fonts/main/ofl/outfit/Outfit%5Bwght%5D.ttf}"
OUTFIT_SHA256="${OUTFIT_SHA256:-}"
OUTFIT_FONT="$SOURCE_DIR/Outfit[wght].ttf"

TOTAL_BUDGET_BYTES="${TOTAL_BUDGET_BYTES:-204800}"  # 200 KB total subset budget

mkdir -p "$CACHE_DIR" "$ASSETS_DIR" "$SOURCE_DIR"

# 1. Provision a Python venv with fonttools[woff] (brotli for woff2 output).
if [ ! -x "$VENV_DIR/bin/pyftsubset" ]; then
  echo "creating fonttools venv at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install --quiet 'fonttools[woff]>=4.50,<5'
fi
PYFTSUBSET="$VENV_DIR/bin/pyftsubset"
PYTHON="$VENV_DIR/bin/python"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# 2. Fetch source fonts — verify SHA-256 only when the env var is set so a
#    contributor can opt out of the pin while bumping versions.
fetch_pinned() {
  local url="$1"
  local out="$2"
  local pin="$3"
  if [ -f "$out" ] && [ -n "$pin" ]; then
    local got
    got=$(sha256_of "$out")
    if [ "$got" = "$pin" ]; then
      return 0
    fi
  fi
  echo "fetching $(basename "$out") from $url"
  curl --fail --silent --show-error --location --output "$out" "$url"
  if [ -n "$pin" ]; then
    local got
    got=$(sha256_of "$out")
    if [ "$got" != "$pin" ]; then
      echo "::error::$(basename "$out") sha256 mismatch" >&2
      echo "  expected: $pin" >&2
      echo "  got:      $got" >&2
      exit 1
    fi
  fi
}

fetch_pinned "$INTER_URL" "$INTER_FONT" "$INTER_SHA256"
fetch_pinned "$OUTFIT_URL" "$OUTFIT_FONT" "$OUTFIT_SHA256"

# 3. Subset.
#    Latin-1 + Latin Extended-A (covers EU diacritics) + digits + currency
#    + common math / arrow / punctuation — enough for every English /
#    European-language string the UI renders. The CJK side is still
#    served by AppCnSans.
LATIN_UNICODES="U+0020-007E,U+00A0-00FF,U+0100-017F,U+02B9-02FF,U+2000-206F,U+2070-209F,U+20A0-20CF,U+2190-21FF,U+2200-22FF,U+25A0-25FF"

common_args=(
  --flavor=woff2
  --with-zopfli
  --layout-features='*'
  --glyph-names
  --no-hinting
  --notdef-glyph
  --notdef-outline
  --recommended-glyphs
  --name-legacy
  --drop-tables+=DSIG
)

# pyftsubset can't pin a variation axis directly, so first instance the
# variable font to a static TTF at the requested weight via
# fonttools.varLib.instancer, then subset to Latin. Doing it in two passes
# is what produces the smallest static woff2.
instance_and_subset() {
  local source="$1"
  local axis_args="$2"  # e.g. "wght=400" or "wght=700 opsz=14"
  local out="$3"
  local label="$4"
  local tmp
  tmp=$(mktemp -t latin_font_XXXXXX.ttf)
  echo "instancing $label ($axis_args) → static TTF"
  "$PYTHON" -m fontTools.varLib.instancer \
    --output="$tmp" \
    --quiet \
    "$source" \
    $axis_args
  echo "subsetting $label → $out"
  "$PYFTSUBSET" "$tmp" \
    --unicodes="$LATIN_UNICODES" \
    --output-file="$out" \
    "${common_args[@]}"
  rm -f "$tmp"
}

# Inter ships with a wght 100-900 + opsz 14-32 axis pair — pin opsz=14 for
# UI / body sizes (the visual size that matches our 11–24px range; 32 is
# tuned for very large display copy and we already hand display-2XL to
# Outfit).
instance_and_subset "$INTER_FONT" "wght=400 opsz=14" "$ASSETS_DIR/inter-regular.woff2"  "Inter Regular"
instance_and_subset "$INTER_FONT" "wght=500 opsz=14" "$ASSETS_DIR/inter-medium.woff2"   "Inter Medium"
instance_and_subset "$INTER_FONT" "wght=600 opsz=14" "$ASSETS_DIR/inter-semibold.woff2" "Inter SemiBold"
instance_and_subset "$INTER_FONT" "wght=700 opsz=14" "$ASSETS_DIR/inter-bold.woff2"     "Inter Bold"

OUTFIT_OUT="$ASSETS_DIR/outfit-bold.woff2"
instance_and_subset "$OUTFIT_FONT" "wght=700" "$OUTFIT_OUT" "Outfit Bold"

# 4. Enforce total subset budget.
total=0
for f in \
  "$ASSETS_DIR/inter-regular.woff2" \
  "$ASSETS_DIR/inter-medium.woff2" \
  "$ASSETS_DIR/inter-semibold.woff2" \
  "$ASSETS_DIR/inter-bold.woff2" \
  "$OUTFIT_OUT"; do
  size=$(wc -c < "$f" | tr -d ' ')
  printf "  %-40s %8d bytes\n" "$(basename "$f")" "$size"
  total=$((total + size))
done

echo "total subset size: $total bytes (budget: $TOTAL_BUDGET_BYTES)"
if [ "$total" -gt "$TOTAL_BUDGET_BYTES" ]; then
  echo "::error::Latin subsets total $total bytes, exceeds budget $TOTAL_BUDGET_BYTES (200 KB)" >&2
  echo "  Trim the LATIN_UNICODES range, drop a weight, or revisit the budget in tool/build-latin-fonts.sh." >&2
  exit 1
fi
echo "ok — Latin subsets within 200 KB budget"
