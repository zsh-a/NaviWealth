//! Garmin through the Personal API: connecting a key and its days.

mod common;

use common::*;

#[test]
fn disconnect_during_a_root_pull_does_not_restore_the_key_or_import_late_rows() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let stub = garmin_cn_with_delay(Duration::from_millis(250));
    let (mut app, storage) = start_in(Some(dir.path()), vec![], Some(stub.clone()));
    app.press("label:Settings")?;
    app.type_text("text:Paste your Garmin key", "GCDC-test-key")?;
    app.press("Connect")?;
    app.wait_for("text:Connected · garmin.cn")?;
    // Let the root pull start, then revoke the connection before it returns.
    for _ in 0..50 {
        if stub.requests().iter().any(|r| r.method == "GET") {
            break;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    assert!(stub.requests().iter().any(|r| r.method == "GET"));
    app.press("Disconnect")?;
    app.wait_for("text:Connect")?;
    std::thread::sleep(Duration::from_secs(1));
    assert!(!storage.entries().contains_key("secret.garmin-key.v1"));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let count: i64 = db
        .query_row("SELECT COUNT(*) FROM garmin_days", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0);
    Ok(())
}

#[test]
fn a_garmin_key_connects_in_its_region_and_brings_todays_numbers() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let stub = garmin_cn();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), Some(stub.clone()));
    app.press("label:Settings")?;
    app.wait_for("Personal API key")?;
    app.type_text("text:Paste your Garmin key", "GCDC-test-key")?;
    app.press("Connect")?;
    app.wait_for("text:Connected · garmin.cn")?;
    assert_eq!(
        storage
            .entries()
            .get("secret.garmin-key.v1")
            .map(String::as_str),
        Some("GCDC-test-key")
    );
    app.press("label:Back")?;
    app.wait_for("text:7h 32m")?;
    let data: Vec<_> = stub
        .requests()
        .into_iter()
        .filter(|r| r.method == "GET")
        .collect();
    assert_eq!(data.len(), 3, "daily, sleep and HRV");
    assert!(data.iter().all(|r| {
        r.url.starts_with(GARMIN_CN)
            && r.headers
                .iter()
                .any(|(n, v)| n.eq_ignore_ascii_case("authorization") && v == "Bearer aaa.bbb.ccc")
    }));

    app.wait_for("text:Score 89")?;
    app.wait_for("text:44 bpm")?;
    app.wait_for("text:75 ms")?;
    app.wait_for("text:13,794")?;
    drop(app);

    // Kept: a restart within 30 minutes shows them without asking Garmin.
    let quiet = Arc::new(StubNetwork::new([] as [(String, StubResponse); 0]));
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(quiet.clone()),
    );
    app.wait_for("text:7h 32m")?;
    assert!(quiet.requests().is_empty());
    Ok(())
}

#[test]
fn a_garmin_key_neither_region_knows_is_refused_and_not_kept() -> Result<(), String> {
    let gone = r#"{"message":"does not exist","error":"NotFoundException"}"#;
    let stub = Arc::new(StubNetwork::new([
        (
            format!("POST {GARMIN_COM}/personalapitoken-service/*"),
            raw(404, gone),
        ),
        (
            format!("POST {GARMIN_CN}/personalapitoken-service/*"),
            raw(404, gone),
        ),
    ]));
    let (mut app, storage) = start(Vec::new(), Some(stub));
    app.press("label:Settings")?;
    app.type_text("text:Paste your Garmin key", "GCDC-old")?;
    app.press("Connect")?;
    app.wait_for("text:Garmin did not accept the key. It may have expired; create a new one.")?;
    assert!(!storage.entries().contains_key("secret.garmin-key.v1"));
    Ok(())
}
