# Local Development Guide

Rust environment setup for the native client and domain crates.

## Rust environment (native client and domain crates)

The repository defaults to the rolling `nightly` channel in
`rust-toolchain.toml`, matching the NSH client. It installs rustfmt and
Clippy using the minimal profile; the NSH client's own file carries the
Android targets (`aarch64-linux-android` for devices, the emulator's
`x86_64-linux-android` for debugging).
CI uses
these files too. Run `rtk rustup update nightly` to refresh nightly locally;
keep the root and NSH channel settings aligned. For an exact compiler
reproduction, record `rustc -Vv` and select the corresponding dated nightly
with `cargo +nightly-YYYY-MM-DD`. `rust-version` in package manifests is a
minimum supported version, not the selected development channel.
Third-party submodules retain their own toolchain files.

From the repository root:

```bash
rtk rustup toolchain install
rtk rustup show active-toolchain
rtk git submodule update --init --recursive
rtk cargo fmt --manifest-path crates/navi-finance/Cargo.toml --all -- --check
rtk cargo clippy --manifest-path crates/navi-finance/Cargo.toml --all-targets --locked -- -D warnings
rtk cargo test --manifest-path crates/navi-finance/Cargo.toml --locked
```

Repeat the last three commands for `crates/navi-health/Cargo.toml`,
`crates/navi-storage/Cargo.toml` and `apps/nsh-client/Cargo.toml`. These are
independent Cargo workspaces; there is no root `Cargo.toml`. Relevant pushes
and PRs run the domain checks plus `nsh checks` (client Rust, mixed TSX
flows, Android JVM tests and lint). The signed APK workflow remains manually
dispatched. Keep each workspace's
`Cargo.lock` committed and use `--locked` for checks. Dependency updates are
explicit `cargo update` changes reviewed with their lockfile diffs.

The NSH Linux host needs Clang/libclang, GTK 4 and GStreamer development
packages (Ubuntu: `clang libclang-dev libgtk-4-dev libgstreamer1.0-dev
libgstreamer-plugins-base1.0-dev`). Android packaging additionally needs Java
17, the Android SDK, NDK and NSH CLI; see the pinned versions in
`.github/workflows/nsh-client.yml`.

### NSH Android debugging from WSL2 (emulator on Windows)

The supported debugging topology cross-compiles in WSL2 and runs the emulator
— and therefore the adb server — on Windows. WSL reaches that adb server over
WSL2 mirrored networking loopback (`wslinfo --networking-mode` must print
`mirrored`).

One-time setup:

- Windows: Android Studio → Device Manager → create an AVD with an API 35+
  **Google APIs x86_64** image (not a Google Play image: it hides adb root)
  and start it before the first adb call from WSL.
- WSL: JDK 17 and an Android SDK with `cmdline-tools/latest`,
  `platform-tools`, `platforms;android-35`, `build-tools;35.0.1` and
  `ndk;27.2.12479018` — mirror the versions pinned in
  `.github/workflows/nsh-client.yml`. This workstation installs them in user
  space without sudo (JDK at `~/sdk/jdk-17.0.21+9`, SDK at
  `~/sdk/android-sdk`). Export `JAVA_HOME`, `ANDROID_HOME`,
  `ANDROID_SDK_ROOT`, `ANDROID_NDK_HOME` and add `$JAVA_HOME/bin`,
  `$ANDROID_HOME/platform-tools` and `$ANDROID_HOME/cmdline-tools/latest/bin`
  to `PATH` in `~/.zshenv`.
- `nsh component add android` installs the NSH Android runtime.
- `apps/nsh-client/rust-toolchain.toml` carries `aarch64-linux-android`
  (devices) and `x86_64-linux-android` (emulator); the repository root keeps
  no cross-compilation targets.

Daily loop from `apps/nsh-client/`:

```sh
adb devices                                       # lists emulator-5554 over loopback
nsh run --target android                          # generic development host; no BLE handlers
bash ../../tool/build-nsh-android-host.sh debug   # app-owned BLE host; arm64, side-by-side .bledev
adb logcat
```

Rules and known pitfalls:

- The adb server must live on Windows. Under mirrored networking a WSL-side
  `adb start-server` hangs indefinitely, and a stuck WSL adb server blocks the
  Windows one from binding 5037. Start the emulator first; if a WSL adb server
  lingers, kill it with `pgrep -x adb | xargs -r kill`. The explicit
  client form `adb -H 127.0.0.1 -P 5037 devices` bypasses server spawning.
- Non-interactive shells do not source `~/.zshenv`; scripts must export the
  Android/Java variables themselves. Symptom: `apksigner: exec: java: not
  found` right after a successful `libnsh.so` build.
- The app-owned BLE host script first invokes pinned NSH 0.5.0 packaging,
  then Gradle; generic `nsh run` / `nsh package` hosts omit BLE handlers. NSH configures the
  NDK linker and cc environment. Bare `cargo check --target
  x86_64-linux-android` fails in cc-rs with `failed to find tool
  "x86_64-linux-android-clang"`.
- The app-owned host is `arm64-v8a`-only. An x86_64 emulator needs arm64
  translation support; check `ro.product.cpu.abilist` before installing.
  The `.bledev` debug package keeps existing production app data separate.
- Emulator evidence covers UI and flow debugging. Roadmap items marked as
  physical-device verification (permissions, real TLS, upgrade/migration) still
  need hardware.

`.cargo/config.toml` provides backtraces and debug logs for first-party crates
while respecting existing `RUST_BACKTRACE` and `RUST_LOG` environment values.
Development and test builds retain line tables to limit disk usage. For
debugger variable inspection, set `CARGO_PROFILE_DEV_DEBUG=2`; for compiler
diagnostics, use `rtk cargo build -vv --manifest-path <path>`. Release profiles
remain owned by each application manifest.

Cargo discovers configuration from the command's current directory, not the
`--manifest-path` directory. Toolchain selection also follows the
current directory; enter a third-party submodule to use its own pin.
Avoid global target/linker flags or `target-cpu=native` in shared config;
let NSH configure Android linking and Cargo select parallelism. Optional
machine-specific caches can be enabled with `RUSTC_WRAPPER=sccache` after
installing sccache. See the official [Cargo configuration reference](https://doc.rust-lang.org/cargo/reference/config.html)
and [rustup toolchain selection](https://rust-lang.github.io/rustup/overrides.html).
