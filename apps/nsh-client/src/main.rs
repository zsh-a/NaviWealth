//! Runs the app directly on the machine's desktop backend (`cargo run`).

#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

#[cfg(target_os = "linux")]
use nsh_platform_linux as platform;
#[cfg(target_os = "macos")]
use nsh_platform_macos as platform;
#[cfg(target_os = "windows")]
use nsh_platform_windows as platform;

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
fn main() -> impl std::process::Termination {
    env_logger::init();
    platform::run_app(
        platform::AppSource::Rust(platform::Root::of::<nsh_app_naviwealth_health::App>()),
        platform::AppOptions {
            title: "NaviWealth Health".to_owned(),
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            app_id: "com.naviwealth.health.nsh".to_owned(),
            // A phone-sized window: the layout this client is designed for.
            size: (390, 844),
            ..Default::default()
        },
    )
}

#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
compile_error!("Run this binary on macOS, Windows or Linux; use nsh run for iOS and Android.");
