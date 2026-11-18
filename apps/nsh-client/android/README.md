# Android host for the mixed NSH client

This host adds foreground AFU-WL Bluetooth transport to the existing NSH/Rust
application. It loads the TSX bundle from APK assets. Health protocol parsing,
estimates and confirmed database writes remain in Rust.

## Build

Use NSH **0.5.0**, Android SDK/API 35, build tools 35.0.1, an Android NDK for
NSH's native build, and JDK 17. The checked Gradle wrapper pins Gradle 8.13;
AGP 8.9.2 and Kotlin 2.1.20 are pinned in the build files. Target API 35 stays
aligned with the validated NSH host; newer SDKs preinstalled on CI runners do
not change this choice. Lint excludes only `OldTargetApi`, the deliberate
phone/arm64 ABI choice and approved icon shape; all other warnings remain errors.

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
  prefers Write Without Response as used by the AFU-WL reference, falling
  back to Write Request for characteristics that only support that property.
  It resolves after the Android write callback, with at most 16 pending
  writes and an 8-second per-write deadline.

Events always contain `sessionId`. `ble.device` adds `address`, `name`, `rssi`,
`manufacturerData` (decimal company-id keys to base64 bytes), `serviceUuids`,
and `serviceData` (UUID keys to base64 bytes). Rust validates protocol metadata
before profile writes; a matching name or service alone is not sufficient.
`ble.notification` contains `dataBase64`. `ble.connection` reports
`connecting`, `ready`, `disconnected`, or `scan_stopped` with a bounded reason.
`ble.error` has bounded `code` and `message`; platform exception text and raw
health packets are never logged.

The host supports Android 8+ with foreground location permission and, on
Android 12+, Nearby devices permissions. Precise location and system Location
must be enabled for scanning: the `neverForLocation` assertion filtered this
AFU-WL-TZ-A1's advertisements on the tested phone. The app does not read
location coordinates. It never requests background
location, advertises, bonds automatically or starts a background service.
Cancellation, backgrounding, destruction and Bluetooth-off close the current
session; generation fences reject late callbacks. Permission dialogs that
complete after cancellation cannot resume an old measurement.

## Evidence boundary

Kotlin compilation, unit tests and Android lint check the host without a
physical scale. Full measurement, GATT behavior, permission revocation,
suspend/resume and upgrade data retention
still require physical-device evidence.

On a physical phone running the side-by-side debug APK, run
`adb -s <phone-serial> logcat -T 1 -v threadtime NaviScale:I '*:S'`
and measure once. This tag is emitted only by debuggable builds. It records
scan/connection timings, GATT status, and counts of notification frame types.
Scan diagnostics also include candidate manufacturer IDs, service UUIDs and
field lengths, without their payloads, to diagnose advertisement rejection.
The D5 high bit is an unverified wire marker, not proof of a stable reading.
No addresses, profile values, measurements or packet payloads are logged.

2026-11-18 scan comparison: with `neverForLocation`, multiple scans received
hundreds of unrelated advertisements but no AFU-WL-TZ-A1. Removing that flag
and granting precise location revealed the target in 49 ms, at -60 dBm.
Its identity was in seven bytes of `27AC` Service Data rather than `27AC`
Manufacturer Data. The same permissions apply to debug and release.

The subsequent DF/08 session connected and subscribed in 3.0 s, received
live D5 notifications, a stable D5 at 19.0 s, and D6 impedance at 27.0 s
from connection start. The owner confirmed that weight and body composition
appeared. This verifies one foreground measurement on this phone; numerical
comparison against the scale display/reference, lifecycle and permission
revocation, and upgrade retention still require separate acceptance.

2026-11-18 physical check: direct connect, service discovery, notification
subscription, and the profile write callback succeeded in 1.0–2.4 s. In a
full 30-second measurement window, the host received four D8 history frames
at startup and no D5 live weight or D6 impedance frames. Both builds used
Write Without Response on this scale. This verifies transport setup on the
tested phone, not successful live measurement. D8 does not create a draft.

The verified `AFU-WL-TZ-A1` advertisement now selects the DF/08 time
initialization documented by the
[ScaleMe live protocol](https://github.com/bugwz/ScaleMe/blob/81ab69c53fe3c8b057449498f82b8e68cfb5a421/ScaleMe/Infrastructure/Bluetooth/Protocols/Wolai/WolaiAFUScaleAdapter.swift).
Other verified AFU-WL models still use D0 profile/time initialization. This
change does not acknowledge or import D8 history, or send a clear command.
