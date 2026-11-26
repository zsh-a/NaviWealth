//! Read-only update checks using NSH's official release manifest and
//! validation. The owner follows the Android release link to install; checks
//! run at most daily on open/resume or explicitly from Settings. A failed
//! request retains the last checked manifest.

use nsh_core::{platform::HttpRequest, prelude::*, storage::Storage};
use nsh_updater::{Available, Config, Manifest};
use serde::{Deserialize, Serialize};

use super::{clock, tasks};

const KEY: &str = "updates.v2";
const FRESH_MS: i64 = 24 * 60 * 60 * 1000;
// Desktop runs exercise the Android app; no desktop release is offered.
const PLATFORM: &str = "android";
static LIVE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

/// Enables public manifest requests. Headless tests enable them only with a stub.
pub fn set_live(live: bool) {
    LIVE.store(live, std::sync::atomic::Ordering::Relaxed);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    Network,
    Unreadable,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Check {
    #[default]
    Idle,
    Running,
    Failed(Failure),
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
struct Kept {
    checked_at_ms: i64,
    manifest: Option<String>,
}

#[derive(Clone, Default, PartialEq)]
struct State {
    kept: Kept,
    status: Check,
}

fn state() -> Signal<State> {
    global::<State>()
}

/// The same source and app identity that the CLI packages into the Android host.
fn config() -> Config {
    let app: serde_json::Value =
        serde_json::from_str(include_str!("../../nsh.json")).expect("valid packaged app metadata");
    let mut source = app["updater"].clone();
    source["id"] = app["id"].clone();
    source["version"] = current().into();
    Config::parse(&serde_json::to_vec(&source).expect("serializable update configuration"))
        .expect("valid packaged update configuration")
}

/// Reads the checked manifest; version comparison runs again against this build.
pub fn load() {
    let kept: Kept = Storage::get_item(KEY)
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .filter(|kept: &Kept| {
            kept.manifest
                .as_deref()
                .is_some_and(|body| check_manifest(&config(), body.as_bytes()).is_ok())
        })
        .unwrap_or_default();
    state().set(State {
        kept,
        status: Check::Idle,
    });
}

fn persist(kept: &Kept) {
    if let Ok(json) = serde_json::to_string(kept) {
        let _ = Storage::set_item(KEY, json);
    }
}

pub fn current() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

pub fn checked_at_ms() -> Option<i64> {
    state().with(|s| (s.kept.checked_at_ms > 0).then_some(s.kept.checked_at_ms))
}

/// NSH selects the Android link and compares versions, including after an upgrade.
pub fn latest() -> Option<Available> {
    state().with(|s| {
        check_manifest(&config(), s.kept.manifest.as_deref()?.as_bytes())
            .ok()
            .flatten()
    })
}

pub fn status() -> Check {
    state().with(|s| s.status)
}

pub fn check(force: bool) {
    if !LIVE.load(std::sync::atomic::Ordering::Relaxed)
        || untracked(|| status() == Check::Running)
        || (!force && fresh())
    {
        return;
    }
    state().update(|s| s.status = Check::Running);
    tasks::spawn_app(async move {
        let result = fetch_latest().await;
        state().update(|s| {
            s.status = match result {
                Ok(manifest) => {
                    s.kept = Kept {
                        checked_at_ms: clock::now_ms(),
                        manifest: Some(manifest),
                    };
                    persist(&s.kept);
                    Check::Idle
                }
                Err(failure) => Check::Failed(failure),
            };
        });
    });
}

fn fresh() -> bool {
    state().with_untracked(|s| clock::now_ms() - s.kept.checked_at_ms < FRESH_MS)
}

async fn fetch_latest() -> Result<String, Failure> {
    let config = config();
    let request = HttpRequest::get(config.manifest_url()).header("Accept", "application/json");
    let response = fetch(request).await.map_err(|_| Failure::Network)?;
    if response.status() != 200 {
        log::warn!("updates: manifest answered {}", response.status());
        return Err(Failure::Unreadable);
    }
    check_manifest(&config, &response.body)?;
    String::from_utf8(response.body).map_err(|_| Failure::Unreadable)
}

fn check_manifest(config: &Config, bytes: &[u8]) -> Result<Option<Available>, Failure> {
    let manifest: Manifest = serde_json::from_slice(bytes).map_err(|_| Failure::Unreadable)?;
    // NSH permits an app to move to a different id. This app does not, and
    // shares its repository with catalog releases, so enforce that boundary.
    if manifest.id != config.id || !manifest.platforms.contains_key(PLATFORM) {
        return Err(Failure::Unreadable);
    }
    config
        .check(bytes, None, PLATFORM)
        .map_err(|_| Failure::Unreadable)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest(id: &str, version: &str, url: &str) -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "id": id,
            "version": version,
            "notes": "Release notes",
            "platforms": { "android": { "url": url } }
        }))
        .unwrap()
    }

    #[test]
    fn official_manifest_checks_the_app_platform_and_newer_version() {
        let mut config = config();
        config.version = "0.9.0".into();
        let body = manifest(
            &config.id,
            "0.10.0",
            "https://github.com/zsh-a/NaviWealth/releases/tag/nsh-v0.10.0",
        );
        let release = check_manifest(&config, &body).unwrap().unwrap();
        assert_eq!(release.version, "0.10.0");
        assert_eq!(release.notes.as_deref(), Some("Release notes"));
        config.version = "0.10.0".into();
        assert!(check_manifest(&config, &body).unwrap().is_none());
        config.version = "0.11.0".into();
        assert!(check_manifest(&config, &body).unwrap().is_none());
    }

    #[test]
    fn foreign_catalog_malformed_and_insecure_manifests_are_rejected() {
        let config = config();
        for body in [
            manifest("catalog", "99.0.0", "https://example.com/catalog"),
            manifest(&config.id, "99.0.0", "http://example.com/app"),
            manifest(&config.id, "invalid", "https://example.com/app"),
            br#"{"id":"com.naviwealth.app","version":"99.0.0","platforms":{}}"#.to_vec(),
            b"not json".to_vec(),
        ] {
            assert_eq!(check_manifest(&config, &body), Err(Failure::Unreadable));
        }
    }

    #[test]
    fn the_packaged_source_uses_github_latest_without_the_api() {
        assert_eq!(
            config().manifest_url(),
            "https://github.com/zsh-a/NaviWealth/releases/latest/download/latest.json"
        );
    }
}
