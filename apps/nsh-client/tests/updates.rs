//! The update check in Settings, against a stubbed official NSH update manifest.

mod common;

use common::*;
use naviwealth_app::set_live_updates;
use nsh_core::{Points, Size};
use nsh_testing::StubRoute;
use std::sync::Mutex;

fn newer_version() -> String {
    let version = env!("CARGO_PKG_VERSION");
    let mut parts = version.split('.');
    let major = parts.next().unwrap();
    let minor = parts.next().unwrap();
    let patch = parts.next().unwrap().parse::<u32>().unwrap();
    format!("{major}.{minor}.{}", patch + 1)
}

const MANIFEST_URL: &str =
    "https://github.com/zsh-a/NaviWealth/releases/latest/download/latest.json";

fn manifest(version: &str) -> serde_json::Value {
    serde_json::json!({
        "id": "com.naviwealth.app",
        "version": version,
        "notes": "A newer release, with notes worth reading.",
        "platforms": { "android": {
            "url": format!("https://github.com/zsh-a/NaviWealth/releases/tag/nsh-v{version}")
        }}
    })
}

#[test]
fn settings_offers_a_newer_release_with_its_page() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let answer = Arc::new(Mutex::new(raw(
        200,
        &manifest(&newer_version()).to_string(),
    )));
    let reply = answer.clone();
    let network = Arc::new(StubNetwork::new([(
        format!("GET {MANIFEST_URL}"),
        StubRoute::Handler(Arc::new(move |_, send| {
            send.send(reply.lock().unwrap().clone());
        })),
    )]));
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), Some(network.clone()));
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
    let requests = network.requests();
    assert_eq!(requests.len(), 1);
    assert_eq!(requests[0].url, MANIFEST_URL);
    assert!(
        requests[0]
            .headers
            .iter()
            .all(|(name, _)| !name.eq_ignore_ascii_case("authorization"))
    );

    // A failed refresh leaves the prior checked manifest available, including
    // its release link and notes, and does not mark the failure as a new check.
    let kept = storage.entries();
    assert!(kept.contains_key("updates.v2"));
    *answer.lock().unwrap() = raw(503, "temporarily unavailable");
    app.press("Check for updates")?;
    app.wait_for("text:The check failed. Showing the last answer.")?;
    app.wait_for("text:Open the release page")?;
    assert_eq!(storage.entries().get("updates.v2"), kept.get("updates.v2"));

    // Restart offline: the last valid manifest still offers the release and
    // no request is needed to read it from local preferences.
    drop(app);
    let before_restart = network.requests().len();
    let (mut app, _) = start_in(
        Some(dir.path()),
        kept.into_iter().collect(),
        Some(network.clone()),
    );
    app.set_viewport(Size::new(Points(360.0), Points(2400.0)))?;
    set_live_updates(true);
    app.press("label:Settings")?;
    app.press(&format!(
        "label:Update, v{current} · Update available · v{}",
        newer_version()
    ))?;
    app.wait_for("text:Open the release page")?;
    assert_eq!(network.requests().len(), before_restart);

    // A successful current-version manifest clears an earlier update. It is
    // still a completed check, not the initial Never checked state.
    *answer.lock().unwrap() = raw(200, &manifest(current).to_string());
    app.press("Check for updates")?;
    app.wait_for(&format!("text:Up to date · v{current}"))?;
    app.wait_for_gone("text:Open the release page", GONE)?;
    Ok(())
}
