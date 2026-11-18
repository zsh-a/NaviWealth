//! The update check in Settings, against a stubbed public releases API.

mod common;

use common::*;
use naviwealth_app::set_live_updates;
use nsh_core::{Points, Size};

fn newer_version() -> String {
    let version = env!("CARGO_PKG_VERSION");
    let mut parts = version.split('.');
    let major = parts.next().unwrap();
    let minor = parts.next().unwrap();
    let patch = parts.next().unwrap().parse::<u32>().unwrap();
    format!("{major}.{minor}.{}", patch + 1)
}

fn releases() -> serde_json::Value {
    serde_json::json!([
        {
            // The retired Flutter channel: not the app's releases.
            "tag_name": "v0.9.34",
            "prerelease": false,
            "draft": false,
            "published_at": "2026-11-14T00:00:00Z",
            "body": "flutter"
        },
        {
            // Always newer than the running build, including after release bumps.
            "tag_name": format!("nsh-v{}", newer_version()),
            "prerelease": false,
            "draft": false,
            "published_at": "2026-11-14T07:00:00Z",
            "body": "A newer release, with notes worth reading."
        },
        {
            "tag_name": "nsh-v0.9.0",
            "prerelease": false,
            "draft": false,
            "published_at": "2026-11-13T13:00:00Z",
            "body": "the running one"
        }
    ])
}

#[test]
fn settings_offers_a_newer_release_with_its_page() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let network = Arc::new(StubNetwork::new([(
        "GET https://api.github.com/repos/zsh-a/NaviWealth/releases*".to_owned(),
        raw(200, &releases().to_string()),
    )]));
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(network));
    // A tall viewport keeps the whole settings page laid out, so the
    // check button is pressable where it sits.
    app.set_viewport(Size::new(Points(360.0), Points(2400.0)))?;
    // The auto-check stays off in tests; the owner asks for this one.
    set_live_updates(true);
    app.press("label:Settings")?;
    let current = env!("CARGO_PKG_VERSION");
    app.wait_for(&format!("text:v{current} · Never checked"))?;
    app.press(&format!("label:Update, v{current} · Never checked"))?;
    app.press("Check for updates")?;
    app.wait_for(&format!("text:Update available · v{}", newer_version()))?;
    app.wait_for(&format!(
        "text:v{current} · Update available · v{}",
        newer_version()
    ))?;
    app.wait_for("text:A newer release, with notes worth reading.")?;
    app.wait_for("text:Open the release page")?;
    Ok(())
}
