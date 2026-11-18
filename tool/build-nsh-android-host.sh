#!/usr/bin/env bash
# Build the mixed TSX/Rust app, then put its own libnsh.so in the BLE-capable host.
# Release output is unsigned; apply tool/sign-nsh-apk.sh with the fixed CI key.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_dir/apps/nsh-client"
host_dir="$app_dir/android"
nsh_bin="${NSH_BIN:-$(command -v nsh)}"
if [[ "$("$nsh_bin" --version)" != nsh\ 0.5.0\ * ]]; then
  echo 'NSH 0.5.0 is required; set NSH_BIN to the pinned CLI.' >&2
  exit 1
fi
mode="${1:-release}"
if [[ "$mode" != release && "$mode" != debug && "$mode" != prepare && "$mode" != runtime ]]; then
  echo 'usage: build-nsh-android-host.sh [release|debug|prepare|runtime]' >&2; exit 64
fi
staging="$app_dir/.nsh/android-host"
mkdir -p "$staging"
nsh_root="$(dirname "$(dirname "$(readlink -f "$nsh_bin")")")"
# Pair the CLI with its own mobile runtime, rather than a stale global install.
export NSH_RUNTIME="$nsh_root/runtime"
if [[ -n "${NSH_ANDROID_AAR:-}" && ! -f "$NSH_ANDROID_AAR" ]]; then
  echo 'NSH_ANDROID_AAR must name an existing matching SDK.' >&2; exit 1
fi
nsh_aar="${NSH_ANDROID_AAR:-$nsh_root/embed/android/nsh.aar}"
if [[ ! -f "$nsh_aar" ]]; then
  nsh_aar="$(find "$nsh_root" -path '*/embed/android/nsh.aar' -print -quit)"
fi
if [[ -z "$nsh_aar" || ! -f "$nsh_aar" ]]; then
  # Mobile runtime components do not include embedding SDKs. Fetch the exact
  # official release archive and verify its pinned digest before extraction.
  mkdir -p "$staging/runtime"
  archive="$staging/runtime/nsh-embed-android.zip"
  nsh_aar="$staging/runtime/nsh.aar"
  if [[ ! -f "$archive" ]]; then
    curl -fsSL --retry 3 'https://github.com/longbridge/nsh/releases/download/v0.5.0/nsh-embed-android.zip' -o "$archive.download"
    mv "$archive.download" "$archive"
  fi
  printf '4e0c943c75c4618e84a0139394719068de341f5c4386714502a2fb1cba802d7f  %s\n' "$archive" | sha256sum -c -
  python3 - "$archive" "$nsh_aar" <<'PYTHON'
import pathlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    pathlib.Path(sys.argv[2]).write_bytes(archive.read("nsh-embed-android/nsh.aar"))
PYTHON
fi
python3 - "$nsh_aar" "$host_dir/app/generated/nsh" "$app_dir/icon.png" <<'PYTHON'
import pathlib, hashlib, sys, zipfile
out = pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(sys.argv[1]) as aar:
    classes = aar.read("classes.jar")
    if hashlib.sha256(classes).hexdigest() != "dfa0632c10833d07940288ee088602e323014326190bb9470f1215ec4c78b5e5":
        raise SystemExit("The NSH Java runtime must match the pinned 0.5.0 release")
    (out / "classes.jar").write_bytes(classes)
    (out / "proguard.txt").write_bytes(aar.read("proguard.txt"))
icon = out.parent / "res/drawable-nodpi/naviwealth_icon.png"
icon.parent.mkdir(parents=True, exist_ok=True)
icon.write_bytes(pathlib.Path(sys.argv[3]).read_bytes())
PYTHON
if [[ "$mode" == runtime ]]; then exit 0; fi
if [[ -n "${NSH_MIXED_APK:-}" ]]; then
  mixed_apk="$NSH_MIXED_APK"
else
  # The directory is generated; clearing it prevents selecting an older named APK.
  rm -rf "$staging/packaged"
  (cd "$app_dir" && "$nsh_bin" package App.tsx --target android --abi arm64-v8a --icon icon.png -o "$staging/packaged")
  mixed_apk="$(find "$staging/packaged" -maxdepth 1 -name '*.apk' -print -quit)"
fi
if [[ -z "$mixed_apk" || ! -f "$mixed_apk" ]]; then
  echo 'The app-linked mixed APK is missing.' >&2; exit 1
fi
python3 - "$mixed_apk" "$nsh_aar" "$host_dir/app/generated" "$app_dir/icon.png" "$app_dir/nsh.json" <<'PYTHON'
import json, os, pathlib, re, shutil, subprocess, sys, zipfile
apk_path, aar_path, destination, icon_path, metadata_path = sys.argv[1:]
metadata = json.loads(pathlib.Path(metadata_path).read_text())
sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
if not sdk: raise SystemExit("ANDROID_HOME or ANDROID_SDK_ROOT is required")
tools = pathlib.Path(sdk) / "build-tools" / os.environ.get("ANDROID_BUILD_TOOLS_VERSION", "35.0.1")
badging = subprocess.check_output([str(tools / "aapt2"), "dump", "badging", apk_path], text=True)
package = next(line for line in badging.splitlines() if line.startswith("package:"))
for key, expected in [("name", metadata["id"]), ("versionName", metadata["version"]), ("versionCode", str(metadata["build"]))]:
    match = re.search(r"\b" + key + r"='([^']*)'", package)
    if not match or match[1] != expected: raise SystemExit("Mixed APK metadata does not match nsh.json: " + key)
out = pathlib.Path(destination)
if out.exists(): shutil.rmtree(out)
(out / "nsh").mkdir(parents=True)
with zipfile.ZipFile(aar_path) as aar:
    for name in ["classes.jar", "proguard.txt"]:
        (out / "nsh" / name).write_bytes(aar.read(name))
with zipfile.ZipFile(apk_path) as apk:
    names = [name for name in apk.namelist() if name.startswith("assets/") and not name.endswith("/")]
    names += ["lib/arm64-v8a/libnsh.so"]
    for name in names:
        parts = pathlib.PurePosixPath(name).parts
        if ".." in parts: raise SystemExit("Unsafe APK path")
        target = out / (name.replace("lib/", "jniLibs/", 1) if name.startswith("lib/") else name)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(apk.read(name))
icon = out / "res/drawable-nodpi/naviwealth_icon.png"
icon.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(icon_path, icon)
if not (out / "assets/nsh/bundle.nshc").is_file(): raise SystemExit("Expected a mixed TSX bundle, not a Rust-only APK")
PYTHON
if [[ "$mode" == prepare ]]; then exit 0; fi
if [[ "$mode" == release ]]; then
  "$host_dir/gradlew" -p "$host_dir" testReleaseUnitTest lintRelease assembleRelease
  printf 'Unsigned release APK: %s\n' "$host_dir/app/build/outputs/apk/release/app-release-unsigned.apk"
else
  "$host_dir/gradlew" -p "$host_dir" testDebugUnitTest assembleDebug
  printf 'Development APK: %s\n' "$host_dir/app/build/outputs/apk/debug/app-debug.apk"
fi
