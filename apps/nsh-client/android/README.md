# Android host for the mixed NSH client

This host adds foreground AFU-WL Bluetooth transport to the existing NSH/Rust
application. It loads the TSX bundle from APK assets. Health protocol parsing,
estimates and confirmed database writes remain in Rust.

## Build

Use NSH **0.5.0**, Android SDK/API 35, build tools 35.0.1, an Android NDK for
NSH's native build, and JDK 17. The checked Gradle wrapper pins Gradle 8.13;
AGP 8.9.2 and Kotlin 2.1.20 are pinned in the build files.

From the repository root:

```sh
./tool/build-nsh-android-host.sh runtime
./apps/nsh-client/android/gradlew -p apps/nsh-client/android testDebugUnitTest lintRelease
./tool/build-nsh-android-host.sh debug
./tool/build-nsh-android-host.sh release
```

`runtime` prepares the Java SDK and icon for Kotlin compilation/tests without
building the mixed native library. `prepare` builds the mixed APK and extracts
inputs without running Gradle. `NSH_BIN` selects the CLI; `NSH_MIXED_APK` can
reuse a previously built mixed APK; `NSH_ANDROID_AAR` can select the matching
SDK. The script installs the CLI-matched Android runtime when it is missing,
before pinning the runtime path, and verifies the exact 0.5.0 Java SDK digest. The default embedding
SDK download also verifies its pinned official release archive checksum.

Only **classes.jar** and the consumer rules are taken from the embedding AAR.
Its prebuilt `libnsh.so` is never shipped: the application-linked library comes
from the mixed app's own NSH package. Generated files live under `.nsh/` and
`android/app/generated/`; both are ignored. The app id, version and build are
read from `nsh.json`. The default NSH private storage path is retained.

The release APK is unsigned and non-debuggable:
`app/build/outputs/apk/release/app-release-unsigned.apk`. Apply the existing
`tool/sign-nsh-apk.sh` in CI using the fixed repository release key. A debug APK
uses the local Android debug key and the separate `com.naviwealth.app.bledev`
application id, preserving any installed release and its data.
Building this host does not publish or install anything.

## Hardware contract

All operations are registered before loading the bundle:

- `ble.status {}` returns availability, Bluetooth state and permission state.
- `ble.scan.start {sessionId, timeoutMs?}` requests permissions after an owner
  action, starts a bounded scan (default 10 seconds, maximum 30), and returns
  `{started:true}`. `ble.scan.stop {sessionId}` cancels it.
- `ble.connect {sessionId,address}` stops scanning and resolves
  `{connected:true}` only after GATT discovery and notification subscription.
- `ble.disconnect {sessionId}` cancels permission continuations and connection.
- `ble.write {sessionId,dataBase64}` queues one 1–20 byte AFU-WL frame. It
  resolves after the Android write callback, with at most 16 pending writes
  and an 8-second per-write deadline.

Events always contain `sessionId`. `ble.device` adds `address`, `name`, `rssi`,
`manufacturerData` (decimal company-id keys to base64 bytes), `serviceUuids`,
and `serviceData` (UUID keys to base64 bytes). Rust validates protocol metadata
before profile writes; a matching name or service alone is not sufficient.
`ble.notification` contains `dataBase64`. `ble.connection` reports
`connecting`, `ready`, `disconnected`, or `scan_stopped` with a bounded reason.
`ble.error` has bounded `code` and `message`; platform exception text and raw
health packets are never logged.

The host supports Android 8+ with location permission through Android 11 and
Nearby devices permissions on Android 12+. It never requests background
location, advertises, bonds automatically or starts a background service.
Cancellation, backgrounding, destruction and Bluetooth-off close the current
session; generation fences reject late callbacks. Permission dialogs that
complete after cancellation cannot resume an old measurement.

## Evidence boundary

Kotlin compilation, unit tests and Android lint check the host without a
physical scale. Real-device scanning, `neverForLocation` filtering, GATT
behavior, permission revocation, suspend/resume and upgrade data retention
still require physical-device evidence.
