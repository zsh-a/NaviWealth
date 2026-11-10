//! Runs the NaviWealth client on the machine's native backend (desktop).
//! Built by default; pass `--no-default-features` for lib-only or
//! headless/web builds (Linux needs GTK 4.14+ for the desktop runner).

#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

#[cfg(feature = "desktop")]
fn main() -> impl std::process::Termination {
    use nsh_core::prelude::*;

    #[cfg(all(target_os = "linux", not(target_os = "android")))]
    use nsh_platform_linux as platform;
    #[cfg(target_os = "macos")]
    use nsh_platform_macos as platform;
    #[cfg(target_os = "windows")]
    use nsh_platform_windows as platform;

    env_logger::init();
    platform::run_app(
        platform::AppSource::Rust(platform::Root::of::<naviwealth_client::App>()),
        platform::AppOptions {
            title: "NaviWealth".to_owned(),
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            app_id: "com.naviwealth.client".to_owned(),
            size: (420, 860),
            ..Default::default()
        },
    )
}

#[cfg(not(feature = "desktop"))]
fn main() {
    eprintln!("desktop runner requires the `desktop` feature (default on)");
}
