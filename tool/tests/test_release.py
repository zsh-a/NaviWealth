"""Release provenance, published changelog boundaries, and artifact integrity."""

import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_ROOT.parent))

from tool.release import (  # noqa: E402
    changes_since,
    git,
    package_release,
    previous_release,
    render_notes,
    resolve_release,
    update_manifest,
)


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        git(self.root, "init", "--initial-branch=main")
        git(self.root, "config", "user.name", "Release Test")
        git(self.root, "config", "user.email", "release@example.invalid")
        self.commit("feat: establish finance data")
        git(self.root, "tag", "v0.1.0")
        self.commit("fix: preserve backup rollback")
        git(self.root, "tag", "v0.1.1")  # Failed, unpublished candidate.
        self.commit("refactor!: simplify CI")
        git(self.root, "tag", "-a", "v0.2.0", "-m", "Android release")
        self.sha = git(self.root, "rev-parse", "HEAD")
        self.release = resolve_release(self.root, "v0.2.0", self.sha)

    def commit(self, subject):
        with (self.root / "history.txt").open("a") as history:
            history.write(subject + "\n")
        git(self.root, "add", ".")
        git(self.root, "commit", "-m", subject)

    def cli(self, *args):
        return subprocess.run(
            [sys.executable, str(TOOL_ROOT / "release.py"), *args],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def test_metadata_peels_annotated_tag_and_counts_its_commits(self):
        result = self.cli("metadata", "--ref", "refs/tags/v0.2.0", "--sha", self.sha)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            dict(line.split("=", 1) for line in result.stdout.splitlines()),
            {
                "semver": "0.2.0",
                "release_tag": "v0.2.0",
                "build_number": "3",
                "commit_sha": self.sha,
            },
        )

    def test_metadata_rejects_branch_dispatch(self):
        result = self.cli("metadata", "--ref", "refs/heads/main", "--sha", self.sha)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("existing vX.Y.Z tag", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_release_rejects_missing_malformed_or_different_source(self):
        for tag in ("v9.9.9", "v01.2.0", "0.2.0", "v0.2.0-beta.1"):
            with (
                self.subTest(tag=tag),
                self.assertRaises((ValueError, subprocess.CalledProcessError)),
            ):
                resolve_release(self.root, tag)
        with self.assertRaisesRegex(ValueError, "must match"):
            resolve_release(self.root, "v0.2.0", "0" * 40)
        self.commit("fix: later branch change")
        with self.assertRaisesRegex(ValueError, "must match"):
            resolve_release(self.root, "v0.2.0")

    def test_changelog_includes_changes_from_unpublished_candidate(self):
        previous = previous_release(self.root, self.release, ["v0.2.0", "v0.1.0"])
        self.assertEqual(previous, "v0.1.0")
        changes = changes_since(self.root, self.release, previous)
        self.assertEqual(
            [subject for _, subject in changes],
            [
                "fix: preserve backup rollback",
                "refactor!: simplify CI",
            ],
        )
        notes = render_notes(
            self.release,
            previous,
            changes,
            "https://github.com/owner/app",
            "https://api.invalid",
        )
        self.assertIn("### Maintenance\n\n- refactor!: simplify CI", notes)
        self.assertIn("compare/v0.1.0...v0.2.0", notes)
        self.assertNotIn("Web PWA", notes)

    def test_unrelated_published_tag_cannot_be_changelog_boundary(self):
        git(self.root, "checkout", "-b", "unrelated", "v0.1.0")
        self.commit("fix: unrelated release")
        git(self.root, "tag", "v0.1.8")
        git(self.root, "checkout", "main")
        self.assertEqual(
            previous_release(self.root, self.release, ["v0.1.8", "v0.1.0"]), "v0.1.0"
        )

    def test_first_published_release_includes_entire_history(self):
        self.assertEqual(previous_release(self.root, self.release, []), "")
        self.assertEqual(len(changes_since(self.root, self.release, "")), 3)

    def test_manifest_uses_real_apk_bytes_and_change_summaries(self):
        apk = self.root / f"{self.release.artifact_stem}.apk"
        contents = b"signed APK bytes"
        apk.write_bytes(contents)
        changes = [(self.sha, f"fix: 修复 {index}") for index in range(10)]
        manifest = update_manifest(
            self.release, apk, changes + changes, "https://github.com/owner/app"
        )
        self.assertEqual(manifest["sha256"], hashlib.sha256(contents).hexdigest())
        self.assertEqual(manifest["size"], len(contents))
        self.assertEqual(manifest["versionCode"], 3)
        self.assertEqual(
            manifest["apkUrl"],
            f"https://github.com/owner/app/releases/download/v0.2.0/{apk.name}",
        )
        self.assertEqual(
            manifest["releaseNotes"], [f"fix: 修复 {index}" for index in range(8)]
        )

    def test_package_copies_both_artifacts_and_generates_consistent_manifest(self):
        paths = (
            "apps/mobile/build/app/outputs/flutter-apk/app-release.apk",
            "apps/mobile/build/app/outputs/bundle/release/app-release.aab",
        )
        for relative in paths:
            source = self.root / relative
            source.parent.mkdir(parents=True)
            source.write_bytes(relative.encode())
        api_url = self.root / "apps/backend/.api-base-url"
        api_url.parent.mkdir(parents=True)
        api_url.write_text("https://api.invalid\n")
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        gh = bin_dir / "gh"
        gh.write_text("#!/bin/sh\nprintf '%s' '[{\"tagName\":\"v0.1.0\"}]'\n")
        gh.chmod(0o755)
        output = self.root / "release output"
        with patch.dict(
            os.environ, {"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"}
        ):
            package_release(
                self.root, self.release, output, "owner/app", "https://github.com/"
            )
        self.assertEqual(
            {path.name for path in output.iterdir()},
            {
                f"{self.release.artifact_stem}.apk",
                f"{self.release.artifact_stem}.aab",
                "latest.json",
                "release-notes.md",
            },
        )
        for relative, extension in zip(paths, ("apk", "aab")):
            self.assertEqual(
                (output / f"{self.release.artifact_stem}.{extension}").read_bytes(),
                relative.encode(),
            )
        manifest = json.loads((output / "latest.json").read_text())
        self.assertEqual(
            manifest["releaseNotes"],
            ["fix: preserve backup rollback", "refactor!: simplify CI"],
        )

    def test_missing_artifact_fails_before_creating_package(self):
        output = self.root / "release"
        with self.assertRaisesRegex(ValueError, "Missing release artifact"):
            package_release(
                self.root, self.release, output, "owner/app", "https://github.com"
            )
        self.assertFalse(output.exists())


class AndroidBuildTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        flutter = self.root / "flutter"
        flutter.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, sys\n"
            "assert pathlib.Path(os.environ['KEYSTORE_FILE']).read_bytes() == b'keystore'\n"
            "with open(os.environ['BUILD_LOG'], 'a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "sys.exit(int(os.environ.get('BUILD_FAILURE', '0')))\n"
        )
        flutter.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.root}{os.pathsep}{os.environ['PATH']}",
            "RELEASE_VERSION": "0.2.0",
            "RELEASE_BUILD_NUMBER": "3",
            "GITHUB_SHA": "a" * 40,
            "GITHUB_REPOSITORY": "owner/app",
            "KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
            "KEYSTORE_FILE": str(self.root / "release signing.keystore"),
            "KEYSTORE_PASSWORD": "test",
            "KEY_ALIAS": "test",
            "KEY_PASSWORD": "test",
            "BUILD_LOG": str(self.root / "build.jsonl"),
        }

    def build(self):
        return subprocess.run(
            ["bash", str(TOOL_ROOT / "build-android-release.sh")],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_builds_apk_and_bundle_with_identical_version_and_payload_flags(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = [
            json.loads(line)
            for line in Path(self.env["BUILD_LOG"]).read_text().splitlines()
        ]
        self.assertEqual(
            [args[:2] for args in commands], [["build", "apk"], ["build", "appbundle"]]
        )
        self.assertEqual(commands[0][2:], commands[1][2:])
        for flag in (
            "--build-name=0.2.0",
            "--build-number=3",
            "--target-platform=android-arm64",
            "--android-project-arg=naviwealth-arm64-only=true",
        ):
            self.assertIn(flag, commands[0])
        self.assertFalse(Path(self.env["KEYSTORE_FILE"]).exists())

    def test_failed_build_stops_before_bundle_and_removes_keystore(self):
        self.env["BUILD_FAILURE"] = "42"
        self.assertEqual(self.build().returncode, 42)
        self.assertEqual(len(Path(self.env["BUILD_LOG"]).read_text().splitlines()), 1)
        self.assertFalse(Path(self.env["KEYSTORE_FILE"]).exists())

    def test_missing_signing_credentials_fail_before_running_flutter(self):
        self.env.pop("KEY_PASSWORD")
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("KEY_PASSWORD is required", result.stderr)
        self.assertFalse(Path(self.env["BUILD_LOG"]).exists())


if __name__ == "__main__":
    unittest.main()
