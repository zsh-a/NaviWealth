"""Resolve tagged Android releases and package their public artifacts.

Web and backend deployments belong to main. This tool never creates tags or
falls back to a branch when a release tag is missing.
"""

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

VERSION_TAG = re.compile(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")
CHANGE_TYPE = re.compile(r"^([a-z]+)(?:\([^)]*\))?!?:", re.IGNORECASE)
SECTIONS = {
    "feat": "Features",
    "feature": "Features",
    "fix": "Fixes",
    "bugfix": "Fixes",
    "ui": "UI and UX",
    "ux": "UI and UX",
    "style": "UI and UX",
    **dict.fromkeys(
        ("ci", "build", "chore", "docs", "test", "tests", "refactor", "release"),
        "Maintenance",
    ),
}


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


@dataclass(frozen=True)
class Release:
    tag: str
    sha: str
    build: int

    @property
    def version(self) -> str:
        return self.tag[1:]

    @property
    def artifact_stem(self) -> str:
        return f"naviwealth-android-arm64-{self.tag}+{self.build}"


def resolve_release(root: Path, tag: str, expected_sha: str | None = None) -> Release:
    if not VERSION_TAG.fullmatch(tag):
        raise ValueError("Release ref must be an existing vX.Y.Z tag")
    sha = git(root, "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
    if git(root, "rev-parse", "HEAD") != sha or (
        expected_sha is not None and expected_sha != sha
    ):
        raise ValueError("Release tag, checked-out source, and event SHA must match")
    return Release(tag, sha, int(git(root, "rev-list", "--count", sha)))


def previous_release(root: Path, release: Release, published_tags: list[str]) -> str:
    # Only published ancestors count. Failed candidate tags must not hide changes.
    for tag in published_tags:
        if not VERSION_TAG.fullmatch(tag) or tag == release.tag:
            continue
        result = subprocess.run(
            [
                "git",
                "merge-base",
                "--is-ancestor",
                f"refs/tags/{tag}",
                f"{release.sha}^",
            ],
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return tag
    return ""


def changes_since(root: Path, release: Release, previous: str) -> list[tuple[str, str]]:
    revision = f"{previous}..{release.sha}" if previous else release.sha
    output = git(root, "log", "--no-merges", "--reverse", "--format=%H%x00%s", revision)
    return [tuple(line.split("\0", 1)) for line in output.splitlines() if line]


def render_notes(
    release: Release,
    previous: str,
    changes: list[tuple[str, str]],
    repository_url: str,
    api_url: str,
) -> str:
    compare_label = f"{previous}...{release.tag}" if previous else release.tag
    compare_url = (
        f"{repository_url}/compare/{compare_label}"
        if previous
        else f"{repository_url}/commits/{release.tag}"
    )
    lines = [
        "## Overview",
        "",
        f"- Version: `{release.version}`",
        f"- Build: `{release.build}`",
        f"- Commit: [`{release.sha[:7]}`]({repository_url}/commit/{release.sha})",
        f"- Released: {datetime.now(timezone.utc):%Y-%m-%d} UTC",
        f"- Compare: [`{compare_label}`]({compare_url})",
        "",
        "## Install",
        "",
        f"- Android arm64 APK: `{release.artifact_stem}.apk`",
        f"- Android App Bundle: `{release.artifact_stem}.aab`",
        f"- API endpoint: `{api_url}`",
        "",
        "## Release Validation",
        "",
        "- Signed APK/AAB passed native payload, 16 KiB alignment, and catalog checks",
        "",
        "## What's Changed",
    ]
    sections: dict[str, list[str]] = {
        name: []
        for name in ("Features", "Fixes", "UI and UX", "Maintenance", "Other Changes")
    }
    for sha, subject in changes:
        match = CHANGE_TYPE.match(subject)
        section = (
            SECTIONS.get(match[1].lower(), "Other Changes")
            if match
            else "Other Changes"
        )
        sections[section].append(
            f"- {subject} ([{sha[:7]}]({repository_url}/commit/{sha}))"
        )
    for title, entries in sections.items():
        if entries:
            lines.extend(["", f"### {title}", "", *entries])
    if not changes:
        lines.extend(["", "- No commits were detected in this release range."])
    lines.extend(["", "## Full Changelog", "", f"[{compare_label}]({compare_url})", ""])
    return "\n".join(lines)


def update_manifest(
    release: Release, apk: Path, changes: list[tuple[str, str]], repository_url: str
) -> dict:
    with apk.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    return {
        "schemaVersion": 1,
        "platform": "android",
        "channel": "github",
        "versionName": release.version,
        "versionCode": release.build,
        "apkUrl": f"{repository_url}/releases/download/{release.tag}/{apk.name}",
        "sha256": digest,
        "size": apk.stat().st_size,
        "mandatory": False,
        "releaseNotes": list(dict.fromkeys(subject for _, subject in changes))[:8]
        or ["See the GitHub Release notes for this version."],
    }


def package_release(
    root: Path, release: Release, output: Path, repository: str, server_url: str
) -> None:
    artifacts = {
        "apk": root / "apps/mobile/build/app/outputs/flutter-apk/app-release.apk",
        "aab": root / "apps/mobile/build/app/outputs/bundle/release/app-release.aab",
    }
    for artifact in artifacts.values():
        if not artifact.is_file():
            raise ValueError(f"Missing release artifact: {artifact}")
    published = json.loads(
        subprocess.run(
            [
                "gh",
                "release",
                "list",
                "--repo",
                repository,
                "--exclude-drafts",
                "--exclude-pre-releases",
                "--limit",
                "100",
                "--json",
                "tagName",
            ],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    previous = previous_release(root, release, [item["tagName"] for item in published])
    changes = changes_since(root, release, previous)
    repository_url = f"{server_url.rstrip('/')}/{repository}"
    api_url = (root / "apps/backend/.api-base-url").read_text().strip()
    output.mkdir(parents=True, exist_ok=True)
    for extension, source in artifacts.items():
        shutil.copyfile(source, output / f"{release.artifact_stem}.{extension}")
    (output / "release-notes.md").write_text(
        render_notes(release, previous, changes, repository_url, api_url),
        encoding="utf-8",
    )
    manifest = update_manifest(
        release, output / f"{release.artifact_stem}.apk", changes, repository_url
    )
    (output / "latest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    metadata = commands.add_parser(
        "metadata", help="Verify the event's tag and emit CI outputs"
    )
    metadata.add_argument("--ref", required=True)
    metadata.add_argument("--sha", required=True)
    package = commands.add_parser(
        "package", help="Package verified Android artifacts for GitHub"
    )
    package.add_argument("--tag", required=True)
    package.add_argument("--output", required=True, type=Path)
    package.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    package.add_argument(
        "--server-url",
        default=os.environ.get("GITHUB_SERVER_URL", "https://github.com"),
    )
    args = parser.parse_args()
    root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel"))
    if args.command == "metadata":
        if not args.ref.startswith("refs/tags/"):
            raise ValueError("Select an existing vX.Y.Z tag to run a release")
        release = resolve_release(root, args.ref.removeprefix("refs/tags/"), args.sha)
        print(
            f"semver={release.version}\nrelease_tag={release.tag}\nbuild_number={release.build}\ncommit_sha={release.sha}"
        )
    else:
        if not args.repository:
            parser.error("--repository or GITHUB_REPOSITORY is required")
        package_release(
            root,
            resolve_release(root, args.tag),
            args.output,
            args.repository,
            args.server_url,
        )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        sys.exit(1)
