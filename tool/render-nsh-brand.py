#!/usr/bin/env python3
"""Export the Folio app icon from its SVG master; requires ImageMagick 7.

Run from any directory. The release PNG is apps/nsh-client/icon.png;
the generated icon SVG lives beside the master. Review artifacts go to
the gitignored .impeccable directory.
"""

from __future__ import annotations

import copy
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "apps/nsh-client/brand"
RELEASE_ICON = BRAND.parent / "icon.png"
REVIEW = ROOT / ".impeccable/review/folio-refined"
INK = "#1C1D1A"
PAPER = "#F4F3EF"
MUTED = "#696A66"
SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)


def main() -> None:
    magick = shutil.which("magick")
    if magick is None:
        raise SystemExit("Install ImageMagick 7 (magick) to render the SVG master.")
    source = ET.parse(BRAND / "folio.svg").getroot()
    master = source.find(f"{{{SVG_NS}}}g[@id='mark']")
    if master is None:
        raise SystemExit("folio.svg is missing its mark group.")
    REVIEW.mkdir(parents=True, exist_ok=True)

    def mark(color: str, transform: str = "") -> str:
        group = copy.deepcopy(master)
        group.attrib.pop("id", None)
        group.set("fill", color)
        if transform:
            group.set("transform", transform)
        return ET.tostring(group, encoding="unicode")

    def svg(body: str, width: int = 256, height: int = 256) -> str:
        return (
            f'<svg xmlns="{SVG_NS}" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}">{body}</svg>\n'
        )

    def render(path: Path, output: Path, size: int | None = None) -> None:
        command = [magick, "-background", "none"]
        if size is not None:
            command += ["-density", str(96 * size / 256)]
        command += [str(path)]
        if size is not None:
            command += ["-resize", f"{size}x{size}"]
        command += ["-strip", f"PNG32:{output}"]
        subprocess.run(command, check=True)

    # Center the silhouette optically one point above its bounding-box center.
    # The icon uses the same master, at 86% scale, with a complete opaque
    # square background. Rounded/circular shapes below are mask previews only.
    icon_transform = "translate(17.92 16.92) scale(.86)"
    icon = svg(
        f'<rect width="256" height="256" fill="{INK}"/>'
        + mark(PAPER, icon_transform)
    )
    icon_path = BRAND / "icon-folio.svg"
    icon_path.write_text(icon, encoding="utf-8")
    render(icon_path, RELEASE_ICON, 1024)

    def label(x: int, y: int, text: str, size: int = 16, color: str = MUTED) -> str:
        return (
            f'<text x="{x}" y="{y}" fill="{color}" font-size="{size}" '
            f'font-family="Adwaita Sans, Source Han Sans CN, sans-serif">{text}</text>'
        )

    parts = [f'<rect width="1400" height="1020" fill="{PAPER}"/>']
    parts += [label(72, 89, "Folio", 44, INK), label(73, 124, "页间 · 标准图形")]
    parts += [f'<rect x="720" y="170" width="608" height="460" fill="{INK}"/>']
    for cx, color in ((370, INK), (1024, PAPER)):
        parts += [mark(color, f"translate({cx - 128 * 1.9} 155) scale(1.9)")]
    parts += [label(72, 664, "墨色 / 暖白"), label(744, 664, "暖白 / 墨色")]
    parts += [f'<path d="M 72 709 H 1328" stroke="#D0CFC8"/>']
    parts += [label(72, 752, "应用图标", 16), label(598, 752, "实际尺寸", 16)]
    for x, color, foreground, circle in (
        (72, INK, PAPER, False),
        (204, "#FFFFFF", INK, False),
        (336, INK, PAPER, True),
    ):
        parts += [f'<g transform="translate({x} 785) scale(.375)">']
        if circle:
            parts += [f'<circle cx="128" cy="128" r="128" fill="{color}"/>']
        else:
            parts += [f'<rect width="256" height="256" rx="58" fill="{color}"/>']
        parts += [mark(foreground, icon_transform), "</g>"]

    for x, size in ((598, 64), (718, 48), (822, 32), (910, 24), (990, 16)):
        # Render at the actual export size as well, so the review is not
        # limited to a large, antialiased presentation of a tiny mark.
        render(icon_path, REVIEW / f"icon-{size}.png", size)
        parts += [
            f'<g transform="translate({x} {833 - size / 2}) scale({size / 256})">',
            f'<rect width="256" height="256" rx="58" fill="{INK}"/>',
            mark(PAPER, icon_transform),
            "</g>",
            label(x, 917, str(size), 14),
        ]
    parts += [label(72, 978, "同一矢量原稿 · 平行留白 · 浅深底与圆形裁切预览", 15)]
    preview = REVIEW / "preview.svg"
    preview.write_text(svg("".join(parts), 1400, 1020), encoding="utf-8")
    render(preview, REVIEW / "preview.png")
    print(f"SVG master: {BRAND / 'folio.svg'}")
    print(f"Release icon: {RELEASE_ICON}")
    print(f"Preview: {REVIEW / 'preview.png'}")


if __name__ == "__main__":
    main()
