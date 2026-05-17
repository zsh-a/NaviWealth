#!/usr/bin/env python3
"""Build the character set used to subset the CN web font.

Two tiers are emitted:

  base — characters the app actually renders on first paint:
         * every CJK code point that appears literally in lib/ (Dart + ARB),
           excluding model-facing / web-dead trees (see
           _FIRST_PAINT_EXCLUDE_PREFIXES) — those never paint on web
         * ASCII printable + Latin-1 currency / sign characters we use
         * CJK symbols and punctuation (U+3000–U+303F)
         * halfwidth / fullwidth forms (U+FF00–U+FFEF)
         * arrows + bullets used by delta_text / chips
         The base file must stay within the first-paint budget enforced by
         build-cn-fonts.sh (rationale in docs/web-bundle.md); everything
         shipped here loads on the first HTTP request.

  ext  — coverage padding for user-entered text and server payloads.
         GB 2312 Level-1 + Level-2 (≈6763 hanzi) minus what is already in
         `base`. Loaded lazily via a second @font-face block with a
         broader unicode-range — the browser only fetches it when a glyph
         outside `base` is required (server message, free-text input,
         transaction memo, etc.).

The script writes one code point per line as `U+XXXX` so pyftsubset can
consume it via `--unicodes-file=`.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

NON_ASCII_RE = re.compile(r"[^\x00-\x7F]")
DART_BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
DART_LINE_COMMENT_RE = re.compile(r"//.*")

# Characters always shipped in the base subset, even if they don't appear
# in the source tree. Keep this list short — it is the safety net for
# strings produced at runtime (server errors, formatted numbers, etc.).
_ALWAYS_INCLUDE: list[int] = (
    # ASCII printable
    list(range(0x20, 0x7F))
    # Runtime punctuation / signs that may come from formatters, server
    # messages, or platform widgets rather than literal app strings.
    + [
        0x00A0,  # non-breaking space
        0x00A5,  # ¥
        0x00B0,  # °
        0x00B1,  # ±
        0x00B7,  # ·
        0x00D7,  # ×
        0x2013,  # –
        0x2014,  # —
        0x2018,  # ‘
        0x2019,  # ’
        0x201C,  # “
        0x201D,  # ”
        0x2022,  # •
        0x2026,  # …
        0x2030,  # ‰
        0x20AC,  # €
      ]
    # Arrows + geometric shapes used by delta_text (↑ ↓ ▲ ▼ ● ○)
    + [0x2190, 0x2191, 0x2192, 0x2193, 0x25B2, 0x25BC, 0x25CF, 0x25CB]
    # Common CJK punctuation that can appear in backend / platform strings.
    + [0x3001, 0x3002, 0x300A, 0x300B, 0xFF0C, 0xFF1A, 0xFF1B, 0xFF1F]
    # Material DatePicker / time-picker CJK chars not always in source scan:
    # weekday headers (二四五六), 星 (星期), 昨 (昨天)
    + [0x4E8C, 0x56DB, 0x4E94, 0x516D, 0x661F, 0x6628]
)


# Source trees whose Chinese text is NOT first-paint web UI and therefore
# must not inflate the `base` (first-paint) subset:
#
#   core/ai/runtime/device/  The device LLM runtime is !kIsWeb-gated — web
#                            has no AI (see docs/ai-architecture.md §4.6).
#                            Its tool descriptions / system prompt are
#                            model-facing strings, and on the web build this
#                            font ships to they are dead code: those glyphs
#                            can never paint on web.
#   core/ai/regression/      AI eval / regression corpus fixtures — test
#                            data, never rendered as UI on any platform.
#
# Anything these legitimately render on native (the *deferred* /ai route) is
# still covered by the lazy `ext` tier, so excluding them here costs at most
# a one-time FOUT on first AI use on native — never tofu, never a web cost.
_FIRST_PAINT_EXCLUDE_PREFIXES: tuple[str, ...] = (
    "core/ai/runtime/device/",
    "core/ai/regression/",
)


def _gb2312_codepoints() -> set[int]:
    """All hanzi in GB 2312 (Level-1 + Level-2, ≈6763 chars).

    Built from the codecs module so we don't bake a 50 KB literal list
    into source. Skips control / Latin / Greek / Cyrillic rows of
    GB 2312 since Noto Sans SC already covers them via `_ALWAYS_INCLUDE`.
    """
    pts: set[int] = set()
    for hi in range(0xB0, 0xF7 + 1):  # hanzi rows only
        for lo in range(0xA1, 0xFE + 1):
            try:
                ch = bytes([hi, lo]).decode("gb2312")
            except UnicodeDecodeError:
                continue
            pts.add(ord(ch))
    return pts


def _strip_dart_comments(text: str) -> str:
    """Best-effort comment stripper for font scanning.

    The font subset only needs characters the app can render. Chinese text in
    Dart comments can be useful for maintainers, but shipping those glyphs in
    the first-paint web font bloats the bundle. ARB / JSON / YAML / Markdown
    are scanned as-is because they commonly contain user-facing copy.
    """
    text = DART_BLOCK_COMMENT_RE.sub("", text)
    return "\n".join(DART_LINE_COMMENT_RE.sub("", line) for line in text.splitlines())


def scan_codebase(root: pathlib.Path) -> set[int]:
    """Return every renderable non-ASCII code point that appears in source."""
    found: set[int] = set()
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix not in {".dart", ".arb", ".json", ".yaml", ".yml", ".md"}:
            continue
        rel = path.relative_to(root).as_posix()
        # Skip generated files — they're derived from the .arb scan anyway.
        if "/gen/" in rel or rel.endswith(".g.dart") or rel.endswith(".freezed.dart"):
            continue
        # Skip model-facing / web-dead trees — not first-paint web UI.
        if rel.startswith(_FIRST_PAINT_EXCLUDE_PREFIXES):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if path.suffix == ".dart":
            text = _strip_dart_comments(text)
        for ch in NON_ASCII_RE.findall(text):
            found.add(ord(ch))
    return found


def write_unicodes(path: pathlib.Path, codepoints: set[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii") as fh:
        for cp in sorted(codepoints):
            fh.write(f"U+{cp:04X}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lib-root", required=True, help="apps/mobile/lib (the directory to scan)")
    parser.add_argument("--out-base", required=True, help="path to write base unicode list")
    parser.add_argument("--out-ext", required=True, help="path to write ext unicode list")
    args = parser.parse_args()

    lib_root = pathlib.Path(args.lib_root).resolve()
    if not lib_root.is_dir():
        print(f"error: lib root {lib_root} not found", file=sys.stderr)
        return 1

    scanned = scan_codebase(lib_root)
    base = set(_ALWAYS_INCLUDE) | scanned
    ext = _gb2312_codepoints() - base

    write_unicodes(pathlib.Path(args.out_base), base)
    write_unicodes(pathlib.Path(args.out_ext), ext)

    print(
        f"scanned {len(scanned)} non-ASCII chars from {lib_root}\n"
        f"base set: {len(base)} code points\n"
        f"ext  set: {len(ext)} code points",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
