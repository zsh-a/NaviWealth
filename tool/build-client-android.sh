#!/usr/bin/env bash
# Build the Rust client with its vendored Java document bridge and native runtime.
# Prerequisites: Android SDK platform 35, build-tools 35+, JDK 17+, nsh 0.5.0,
# Rust Android targets and the NDK toolchain environment used by client-android CI.
# Optional: NAVIWEALTH_ANDROID_KEYSTORE / NAVIWEALTH_ANDROID_KEY_ALIAS and
# NSH_KEYSTORE_PASSWORD select a release signing key. NSH_KEY_PASSWORD optionally
# supplies a distinct private-key password. Otherwise this is debug signed.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_dir" ]]; then echo "ANDROID_HOME or ANDROID_SDK_ROOT is required" >&2; exit 1; fi
android_jar="$sdk_dir/platforms/android-${NAVIWEALTH_ANDROID_SDK_PLATFORM:-35}/android.jar"
build_tools="${NAVIWEALTH_ANDROID_BUILD_TOOLS:-$(find "$sdk_dir/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)}"
for file in "$android_jar" "$build_tools/d8" "$build_tools/zipalign" "$build_tools/apksigner"; do
    if [[ ! -f "$file" ]]; then echo "Required Android tool missing: $file" >&2; exit 1; fi
done
for command_name in javac jar keytool nsh python3; do
    command -v "$command_name" >/dev/null || { echo "$command_name is required" >&2; exit 1; }
done
case "$(nsh --version)" in
    "nsh 0.5.0"*) ;;
    *) echo "The vendored Android runtime requires nsh 0.5.0" >&2; exit 1 ;;
esac
for arg in "$@"; do
    if [[ "$arg" == "--run" ]]; then echo "Install the resulting APK after this script finishes; --run is not supported" >&2; exit 1; fi
done
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/classes" "$work_dir/dex"
python3 - "$repo_dir" "$work_dir/sources" <<'PY_SOURCES'
import pathlib,sys
sources=sorted((pathlib.Path(sys.argv[1])/'third_party/nsh-platform-android/java').rglob('*.java'))
pathlib.Path(sys.argv[2]).write_text('\n'.join('"'+str(path).replace('\\','\\\\').replace('"','\\"')+'"' for path in sources))
PY_SOURCES
javac -source 8 -target 8 -Xlint:-options -classpath "$android_jar" -d "$work_dir/classes" "@$work_dir/sources"
jar cf "$work_dir/classes.jar" -C "$work_dir/classes" .
"$build_tools/d8" --release --min-api 28 --lib "$android_jar" --output "$work_dir/dex" "$work_dir/classes.jar"
keystore="${NAVIWEALTH_ANDROID_KEYSTORE:-$repo_dir/apps/client/.nsh/signing/debug.keystore}"
key_alias="${NAVIWEALTH_ANDROID_KEY_ALIAS:-androiddebugkey}"
export NSH_KEYSTORE_PASSWORD="${NSH_KEYSTORE_PASSWORD:-android}"
export NSH_KEY_PASSWORD="${NSH_KEY_PASSWORD:-$NSH_KEYSTORE_PASSWORD}"
if [[ ! -f "$keystore" ]]; then
    if [[ -n "${NAVIWEALTH_ANDROID_KEYSTORE:-}" ]]; then echo "Signing keystore does not exist" >&2; exit 1; fi
    mkdir -p "$(dirname "$keystore")"
    keytool -genkeypair -noprompt -keystore "$keystore" -storepass:env NSH_KEYSTORE_PASSWORD \
        -keypass:env NSH_KEYSTORE_PASSWORD -alias "$key_alias" -keyalg RSA -keysize 2048 \
        -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
out_dir="${NAVIWEALTH_APK_DIR:-$repo_dir/apps/client/.nsh/out}"
# Keep the intermediate signer isolated from the final release key. Its intermediate APK is re-signed below,
# so keep the real release key out of that stage and support distinct key passwords.
packaging_keystore="$work_dir/packaging.keystore"
keytool -genkeypair -noprompt -keystore "$packaging_keystore" -storepass android \
    -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 \
    -validity 1 -dname "CN=Build Intermediate" >/dev/null 2>&1
cd "$repo_dir/apps/client"
NSH_KEYSTORE_PASSWORD=android NSH_KEY_PASSWORD=android \
    nsh package --target android --out "$out_dir" --keystore "$packaging_keystore" \
    --key-alias androiddebugkey "$@"
apk_name="$(python3 -c 'import json;print(json.load(open("nsh.json"))["name"]+".apk")')"
apk_path="$out_dir/$apk_name"
python3 - "$apk_path" "$work_dir/unsigned.apk" "$work_dir/dex" <<'PY_APK'
import pathlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as source,zipfile.ZipFile(sys.argv[2],'w') as target:
    for entry in source.infolist():
        name=entry.filename
        signature=name.startswith('META-INF/') and (name.endswith(('.RSA','.DSA','.EC','.SF')) or name=='META-INF/MANIFEST.MF')
        if signature or (name.startswith('classes') and name.endswith('.dex')):continue
        target.writestr(entry,source.read(name))
    for dex in sorted(pathlib.Path(sys.argv[3]).glob('classes*.dex')):
        target.write(dex,dex.name,compress_type=zipfile.ZIP_DEFLATED)
PY_APK
"$build_tools/zipalign" -P 16 -f 4 "$work_dir/unsigned.apk" "$work_dir/aligned.apk"
"$build_tools/apksigner" sign --ks "$keystore" --ks-key-alias "$key_alias" \
    --ks-pass env:NSH_KEYSTORE_PASSWORD --key-pass env:NSH_KEY_PASSWORD \
    --out "$apk_path" "$work_dir/aligned.apk"
"$build_tools/apksigner" verify "$apk_path"
echo "Android APK with system backup document picker: $apk_path"
