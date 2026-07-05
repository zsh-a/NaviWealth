#!/bin/sh
set -e

BASEDIR=$(dirname "$0")

# Workaround for https://github.com/dart-lang/pub/issues/4010
BASEDIR=$(cd "$BASEDIR" ; pwd -P)

# Remove XCode SDK from path. Otherwise this breaks tool compilation when building iOS project
NEW_PATH=`echo $PATH | tr ":" "\n" | grep -v "Contents/Developer/" | tr "\n" ":"`

export PATH=${NEW_PATH%?} # remove trailing :

# Cargo builds host proc-macro crates while cross-compiling the Rust library.
# Xcode injects deployment-target variables for the app target; with recent
# macOS/Xcode beta toolchains those variables can leak into host crate builds
# and make proc-macro crates such as `time_macros` undiscoverable. Preserve the
# app target's minimum macOS version for target-specific flags, but keep Cargo's
# ambient host environment clean.
SAVED_MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET
unset MACOSX_DEPLOYMENT_TARGET
unset IPHONEOS_DEPLOYMENT_TARGET
unset TVOS_DEPLOYMENT_TARGET
unset WATCHOS_DEPLOYMENT_TARGET

if [[ "$PLATFORM_NAME" == "macosx" && -n "$SAVED_MACOSX_DEPLOYMENT_TARGET" ]]; then
  MACOS_MIN_FLAG="-mmacosx-version-min=$SAVED_MACOSX_DEPLOYMENT_TARGET"
  for rust_target in aarch64-apple-darwin x86_64-apple-darwin
  do
    env_target=$(echo "$rust_target" | tr '[:lower:]-' '[:upper:]_')
    cc_target=$(echo "$rust_target" | tr '-' '_')
    rustflags_key="CARGO_TARGET_${env_target}_RUSTFLAGS"
    cflags_key="CFLAGS_${cc_target}"
    cxxflags_key="CXXFLAGS_${cc_target}"
    export "$rustflags_key=${!rustflags_key:+${!rustflags_key} }-C link-arg=$MACOS_MIN_FLAG"
    export "$cflags_key=${!cflags_key:+${!cflags_key} }$MACOS_MIN_FLAG"
    export "$cxxflags_key=${!cxxflags_key:+${!cxxflags_key} }$MACOS_MIN_FLAG"
  done
fi

# Platform name (macosx, iphoneos, iphonesimulator)
export CARGOKIT_DARWIN_PLATFORM_NAME=$PLATFORM_NAME

# Arctive architectures (arm64, armv7, x86_64), space separated.
export CARGOKIT_DARWIN_ARCHS=$ARCHS

# Current build configuration (Debug, Release)
export CARGOKIT_CONFIGURATION=$CONFIGURATION

# Path to directory containing Cargo.toml.
export CARGOKIT_MANIFEST_DIR=$PODS_TARGET_SRCROOT/$1

# Temporary directory for build artifacts.
export CARGOKIT_TARGET_TEMP_DIR=$TARGET_TEMP_DIR

# Output directory for final artifacts.
export CARGOKIT_OUTPUT_DIR=$PODS_CONFIGURATION_BUILD_DIR/$PRODUCT_NAME

# Directory to store built tool artifacts.
export CARGOKIT_TOOL_TEMP_DIR=$TARGET_TEMP_DIR/build_tool

# Directory inside root project. Not necessarily the top level directory of root project.
export CARGOKIT_ROOT_PROJECT_DIR=$SRCROOT

FLUTTER_EXPORT_BUILD_ENVIRONMENT=(
  "$PODS_ROOT/../Flutter/ephemeral/flutter_export_environment.sh" # macOS
  "$PODS_ROOT/../Flutter/flutter_export_environment.sh" # iOS
)

for path in "${FLUTTER_EXPORT_BUILD_ENVIRONMENT[@]}"
do
  if [[ -f "$path" ]]; then
    source "$path"
  fi
done

sh "$BASEDIR/run_build_tool.sh" build-pod "$@"

# Make a symlink from built framework to phony file, which will be used as input to
# build script. This should force rebuild (podspec currently doesn't support alwaysOutOfDate
# attribute on custom build phase)
ln -fs "$OBJROOT/XCBuildData/build.db" "${BUILT_PRODUCTS_DIR}/cargokit_phony"
ln -fs "${BUILT_PRODUCTS_DIR}/${EXECUTABLE_PATH}" "${BUILT_PRODUCTS_DIR}/cargokit_phony_out"
