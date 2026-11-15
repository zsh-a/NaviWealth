//! Update checks against the app's own public GitHub releases: a read-only
//! fetch of release metadata, no credentials, nothing sent. The newest
//! `nsh-v*` release is compared with the running version and offered as a
//! link to the release page; downloading and installing stay the owner's
//! steps. Checked at most daily on open or resume, or when asked in
//! Settings. A failed check keeps the last known answer.

use nsh_core::{platform::HttpRequest, prelude::*, storage::Storage};
use serde::{Deserialize, Serialize};

use super::{clock, tasks};

const KEY: &str = "updates.v1";
const RELEASES_URL: &str = "https://api.github.com/repos/zsh-a/NaviWealth/releases?per_page=20";
/// Only tags of the NSH client count; the repository also holds the
/// retired Flutter channel's releases.
const TAG_PREFIX: &str = "nsh-v";
/// How often a check may run on its own.
const FRESH_MS: i64 = 24 * 60 * 60 * 1000;

/// Whether the check may reach the public API; headless tests turn it off,
/// as they do for the market providers.
static LIVE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

/// Turns the public releases API on or off for this process. Headless
/// tests start with it off and switch it on when they stub the API.
pub fn set_live(live: bool) {
    LIVE.store(live, std::sync::atomic::Ordering::Relaxed);
}

/// Why a check gave nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    /// The request did not complete.
    Network,
    /// GitHub answered something unreadable.
    Unreadable,
}

/// The newest release's answer.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Release {
    /// The tag, `nsh-vX.Y.Z`.
    pub tag: String,
    /// The version the tag carries, `X.Y.Z`.
    pub version: String,
    /// When GitHub published it, in milliseconds.
    pub published_at_ms: i64,
    /// The release page, which opens outside the app.
    pub url: String,
    /// The release notes, as GitHub holds them.
    pub notes: String,
}

impl Release {
    /// Whether this release is newer than `version` (`X.Y.Z`).
    pub fn is_newer_than(&self, version: &str) -> bool {
        is_newer(&self.version, version)
    }
}

/// Where the last check stands.
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
    latest: Option<Release>,
}

#[derive(Clone, Default, PartialEq)]
struct State {
    kept: Kept,
    status: Check,
}

fn state() -> Signal<State> {
    global::<State>()
}

/// Reads the kept answer; the root calls it once.
pub fn load() {
    let kept: Kept = Storage::get_item(KEY)
        .and_then(|raw| serde_json::from_str(&raw).ok())
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

/// The running version, as the release tags carry it.
pub fn current() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// The last check's time, in milliseconds (tracked).
pub fn checked_at_ms() -> Option<i64> {
    state().with(|s| (s.kept.checked_at_ms > 0).then_some(s.kept.checked_at_ms))
}

/// The newest release found so far (tracked).
pub fn latest() -> Option<Release> {
    state().with(|s| s.kept.latest.clone())
}

/// Whether the newest release is newer than the running one (tracked).
pub fn update_available() -> bool {
    state().with(|s| {
        s.kept
            .latest
            .as_ref()
            .is_some_and(|r| r.is_newer_than(current()))
    })
}

/// What the last check came to (tracked).
pub fn status() -> Check {
    state().with(|s| s.status)
}

/// Runs a check, skipping it when `force` is false and one ran recently.
pub fn check(force: bool) {
    if !LIVE.load(std::sync::atomic::Ordering::Relaxed) {
        return;
    }
    if untracked(|| status() == Check::Running) {
        return;
    }
    if !force && fresh() {
        return;
    }
    state().update(|s| s.status = Check::Running);
    tasks::spawn_app(async move {
        let result = fetch_latest().await;
        state().update(|s| {
            s.status = match &result {
                Ok(release) => {
                    s.kept = Kept {
                        checked_at_ms: clock::now_ms(),
                        latest: Some(release.clone()),
                    };
                    persist(&s.kept);
                    Check::Idle
                }
                Err(failure) => Check::Failed(*failure),
            };
        });
    });
}

fn fresh() -> bool {
    state().with_untracked(|s| clock::now_ms() - s.kept.checked_at_ms < FRESH_MS)
}

async fn fetch_latest() -> Result<Release, Failure> {
    let request = HttpRequest::get(RELEASES_URL).header("Accept", "application/json");
    let response = fetch(request).await.map_err(|_| Failure::Network)?;
    let body = String::from_utf8_lossy(&response.body);
    match response.status() {
        200 => parse_releases(&body).ok_or(Failure::Unreadable),
        status => {
            log::warn!("updates: releases API answered {status}");
            Err(Failure::Unreadable)
        }
    }
}

/// The newest `nsh-v*` release in a GitHub releases listing, skipping the
/// retired Flutter channel and anything unfinished.
fn parse_releases(body: &str) -> Option<Release> {
    let releases: Vec<serde_json::Value> = serde_json::from_str(body).ok()?;
    let mut newest: Option<Release> = None;
    for value in &releases {
        let tag = value.get("tag_name")?.as_str()?.to_owned();
        if !tag.starts_with(TAG_PREFIX) {
            continue;
        }
        if value
            .get("draft")
            .and_then(|d| d.as_bool())
            .unwrap_or(false)
            || value
                .get("prerelease")
                .and_then(|p| p.as_bool())
                .unwrap_or(false)
        {
            continue;
        }
        let version = tag[TAG_PREFIX.len()..].to_owned();
        if parse_version(&version).is_none() {
            continue;
        }
        let published_at_ms = value
            .get("published_at")
            .and_then(|p| p.as_str())
            .and_then(|p| p.parse::<jiff::Timestamp>().ok())
            .map(|t| t.as_millisecond())
            .unwrap_or(0);
        let notes = value
            .get("body")
            .and_then(|b| b.as_str())
            .unwrap_or_default()
            .to_owned();
        let url = format!("https://github.com/zsh-a/NaviWealth/releases/tag/{tag}");
        let release = Release {
            tag,
            version,
            published_at_ms,
            url,
            notes,
        };
        let newer = newest
            .as_ref()
            .is_none_or(|kept| release.published_at_ms > kept.published_at_ms);
        if newer {
            newest = Some(release);
        }
    }
    newest
}

/// Whether `a` (`X.Y.Z`) is newer than `b`; anything unreadable is not.
fn is_newer(a: &str, b: &str) -> bool {
    match (parse_version(a), parse_version(b)) {
        (Some(a), Some(b)) => a > b,
        _ => false,
    }
}

/// `X.Y.Z` as `(major, minor, patch)`.
fn parse_version(version: &str) -> Option<(u32, u32, u32)> {
    let mut parts = version.split('.');
    let major = parts.next()?.parse::<u32>().ok()?;
    let minor = parts.next()?.parse::<u32>().ok()?;
    let patch = parts.next()?.parse::<u32>().ok()?;
    parts.next().is_none().then_some((major, minor, patch))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_compare_part_by_part() {
        assert!(is_newer("0.10.0", "0.9.0"));
        assert!(is_newer("0.9.1", "0.9.0"));
        assert!(is_newer("1.0.0", "0.99.99"));
        assert!(!is_newer("0.9.0", "0.9.0"));
        assert!(!is_newer("0.9.0", "0.10.0"));
        assert!(!is_newer("not-a-version", "0.9.0"));
    }

    #[test]
    fn releases_pick_the_newest_nsh_one_and_skip_other_channels() {
        let body = serde_json::json!([
            {
                "tag_name": "v0.9.34",
                "prerelease": false,
                "draft": false,
                "published_at": "2026-11-14T00:00:00Z",
                "body": "flutter channel"
            },
            {
                "tag_name": "nsh-v0.8.0",
                "prerelease": false,
                "draft": false,
                "published_at": "2026-11-14T05:00:00Z",
                "body": "older"
            },
            {
                "tag_name": "nsh-v0.9.0",
                "prerelease": true,
                "draft": false,
                "published_at": "2026-11-14T06:00:00Z",
                "body": "not finished"
            },
            {
                "tag_name": "nsh-v0.10.0",
                "prerelease": false,
                "draft": false,
                "published_at": "2026-11-14T07:00:00Z",
                "body": "the newest"
            }
        ])
        .to_string();
        let newest = parse_releases(&body).unwrap();
        assert_eq!(newest.tag, "nsh-v0.10.0");
        assert_eq!(newest.version, "0.10.0");
        assert_eq!(
            newest.url,
            "https://github.com/zsh-a/NaviWealth/releases/tag/nsh-v0.10.0"
        );
        assert_eq!(newest.notes, "the newest");
        assert!(newest.is_newer_than(current()));
        assert!(
            parse_releases("[]").is_none(),
            "no NSH release means no answer"
        );
    }

    #[test]
    fn a_broken_listing_is_not_an_answer() {
        assert!(parse_releases("not json").is_none());
    }

    #[test]
    fn the_running_version_reads_like_a_tag() {
        let version = current();
        assert!(parse_version(version).is_some(), "{version} parses");
    }
}
