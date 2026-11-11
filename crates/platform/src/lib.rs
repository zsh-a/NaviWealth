//! Platform adaptation seams for the NaviWealth Rust client. Pure-Rust
//! first: real iOS (Keychain, HealthKit) and Android (Keystore, Health
//! Connect) implementations land here with the platform runners in the
//! intelligence-and-release phase; desktops, web and tests use the stubs.

use std::path::PathBuf;

/// Where the app keeps its database and key files, per platform.
/// Android must be called on the nsh engine thread after host setup.
pub fn app_data_dir(app_id: &str) -> std::io::Result<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        let home = std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_default();
        Ok(home
            .join("Library")
            .join("Application Support")
            .join(app_id))
    }
    #[cfg(target_os = "linux")]
    {
        let base = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")))
            .unwrap_or_else(|| PathBuf::from("."));
        Ok(base.join(app_id))
    }
    #[cfg(target_os = "windows")]
    {
        let base = std::env::var_os("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_default();
        Ok(base.join(app_id))
    }
    #[cfg(target_os = "ios")]
    {
        // Provided by the platform runner at launch; deterministic default
        // for early bring-up.
        Ok(PathBuf::from("nsh").join(app_id))
    }
    #[cfg(target_os = "android")]
    {
        android_app_data_dir(nsh::app_data_root(), app_id)
    }
}

// The host root already includes `nsh`; never resolve mobile storage against cwd.
#[cfg(any(target_os = "android", test))]
fn android_app_data_dir(root: Option<PathBuf>, app_id: &str) -> std::io::Result<PathBuf> {
    let root = root.filter(|root| root.is_absolute()).ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "Android private data directory is unavailable",
        )
    })?;
    Ok(root.join(app_id))
}

/// Health platform integration seam (HealthKit / Health Connect). Web has
/// no health integration by design.
pub trait HealthPlatform: Send + Sync {
    fn is_available(&self) -> bool;
    /// Request read authorization; returns granted state. Real
    /// implementations surface the system permission sheet.
    fn request_authorization(&self) -> Result<bool, String>;
}

/// Stub for desktops/web/tests: unavailable, never granted.
pub struct StubHealthPlatform;

impl HealthPlatform for StubHealthPlatform {
    fn is_available(&self) -> bool {
        false
    }

    fn request_authorization(&self) -> Result<bool, String> {
        Err("health integration is unavailable on this platform".to_owned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn android_storage_uses_host_absolute_path() {
        let root = PathBuf::from("/data/user/10/com.naviwealth.client/files/nsh");
        assert_eq!(
            android_app_data_dir(Some(root.clone()), "com.naviwealth.client").unwrap(),
            root.join("com.naviwealth.client"),
        );
    }

    #[test]
    fn android_storage_refuses_missing_or_relative_host_root() {
        for root in [None, Some(PathBuf::from("files/nsh"))] {
            assert!(android_app_data_dir(root, "com.naviwealth.client").is_err());
        }
    }

    #[test]
    fn stub_health_is_unavailable() {
        let health = StubHealthPlatform;
        assert!(!health.is_available());
        assert!(health.request_authorization().is_err());
    }
}

/// Android document import/export backed by the system file picker.
#[cfg(target_os = "android")]
pub use nsh::documents;
