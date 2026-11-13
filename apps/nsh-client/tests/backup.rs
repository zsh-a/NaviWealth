//! Encrypted backup and restore through a real, isolated HTTP WebDAV server.
mod common;
#[path = "common/dav.rs"]
mod dav;

use common::*;
use dav::Dav;
use nsh_app_naviwealth_health::domain::backup::{self, BackupError};
use nsh_testing::DialogAnswer;

#[test]
fn incomplete_settings_explain_what_is_missing_without_saving_them() -> Result<(), String> {
    let (mut app, storage) = start(vec![], None);
    app.press("label:Settings")?;
    app.press("Save and back up")?;
    app.wait_for(
        "text:Fill in the folder, account, password and a passphrase of at least 8 characters.",
    )?;
    assert!(!storage.entries().contains_key("backup.v1"));
    Ok(())
}

fn backups(dav: &Dav, passphrase: &str, last_day: Option<String>) -> Vec<(String, String)> {
    vec![
        (
            "backup.v1".into(),
            json!({"folder":{"url":dav.url,"username":"tester"},
            "last_backup_ms":null,"last_backup_day":last_day})
            .to_string(),
        ),
        ("secret.webdav-password.v1".into(), "secret-pass".into()),
        ("secret.backup-passphrase.v1".into(), passphrase.into()),
    ]
}

fn wait_backup(storage: &MemoryStorage) {
    for _ in 0..200 {
        if storage.entries()["backup.v1"].contains(&today().to_string()) {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("backup did not finish");
}

fn backed_up(dav: &Dav) -> Result<Vec<u8>, String> {
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), pasta_today(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute(
        "INSERT INTO weights VALUES (?1, 72.4, 42)",
        [today().to_string()],
    )
    .unwrap();
    db.execute(
        "INSERT INTO garmin_days VALUES (?1, ?2, 42)",
        [
            today().to_string(),
            json!({"day":today().to_string(),"steps":12345}).to_string(),
        ],
    )
    .unwrap();
    drop(db);
    let mut entries = backups(dav, "correct horse battery", None);
    entries.extend(account(false));
    let (mut app, storage) = start_in(Some(dir.path()), entries, None);
    app.wait_for("Tomato pasta")?;
    wait_backup(&storage);
    let files = dav.files();
    let (name, body) = files.last_key_value().unwrap();
    assert!(name.starts_with(&format!("naviwealth-{}-", today())));
    assert!(body.starts_with(b"NWBK"));
    assert!(
        !body
            .windows(b"Tomato pasta".len())
            .any(|w| w == b"Tomato pasta")
    );
    let (_, database) = backup::open(body, "correct horse battery").unwrap();
    assert!(
        !database
            .windows(b"sk-test-key".len())
            .any(|w| w == b"sk-test-key")
    );
    let requests = dav.requests();
    assert_eq!(
        requests
            .iter()
            .map(|r| r.method.as_str())
            .collect::<Vec<_>>(),
        ["PUT", "MKCOL", "PUT"]
    );
    assert_eq!(requests.last().unwrap().body, *body);
    // Restart on the same day: no redundant backup.
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.wait_for("Tomato pasta")?;
    std::thread::sleep(Duration::from_millis(100));
    assert_eq!(dav.requests().len(), requests.len());
    Ok(body.clone())
}

fn fresh_with(
    dav: &Dav,
    passphrase: &str,
    existing: bool,
) -> (Headless, Arc<MemoryStorage>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let mut entries = backups(dav, passphrase, Some(today().to_string()));
    if existing {
        entries.extend(pasta_today());
    }
    let (app, storage) = start_in(Some(dir.path()), entries, None);
    (app, storage, dir)
}

fn restore_latest(app: &mut Headless, dav: &Dav) -> Result<(), String> {
    app.press("label:Settings")?;
    app.press("Restore…")?;
    let name = dav.files().last_key_value().unwrap().0.clone();
    app.wait_for(&format!("text:{name}"))?;
    app.on_dialog(|_| DialogAnswer::Press("Restore".into()));
    app.press(&format!("text:{name}"))?;
    Ok(())
}

#[test]
fn encrypted_backup_creates_the_folder_and_restores_on_a_fresh_install() -> Result<(), String> {
    let dav = Dav::new();
    backed_up(&dav)?;
    let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", false);
    assert!(app.shows("No meals logged today"));
    restore_latest(&mut app, &dav)?;
    app.wait_for("text:Backup restored")?;
    app.press("label:Back")?;
    app.wait_for("Tomato pasta")?;
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert_eq!(
        stored_weights(dir.path()),
        vec![(today().to_string(), 72.4)]
    );
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let body: String = db
        .query_row("SELECT body FROM garmin_days", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&body).unwrap()["steps"],
        12345
    );
    assert!(
        dav.requests()
            .iter()
            .any(|r| r.method == "PROPFIND" && r.headers.to_ascii_lowercase().contains("depth: 1"))
    );
    Ok(())
}

#[test]
fn a_wrong_passphrase_keeps_existing_records() -> Result<(), String> {
    let dav = Dav::new();
    backed_up(&dav)?;
    let (mut app, _, dir) = fresh_with(&dav, "another passphrase", true);
    let before = stored_meals(dir.path());
    restore_latest(&mut app, &dav)?;
    app.wait_for("text:Wrong passphrase, or the backup was changed.")?;
    assert_eq!(stored_meals(dir.path()), before);
    Ok(())
}

#[test]
fn resuming_on_a_new_day_backs_up_once_even_when_settings_closes() -> Result<(), String> {
    use nsh_core::{platform::Lifecycle, time::Clock};
    let dav = Dav::new();
    let dir = tempfile::tempdir().unwrap();
    let storage = MemoryStorage::new(backups(
        &dav,
        "correct horse battery",
        Some(today().to_string()),
    ));
    let mut config = EngineConfig::new(Root::of::<App>());
    let now = std::time::SystemTime::now();
    config.clock = Clock::manual(now);
    config.storage = Some(storage.clone());
    config.data_dir = Some(dir.path().to_path_buf());
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Log a meal")?;
    app.press("label:Settings")?;
    app.set_environment("background", |e| e.lifecycle = Lifecycle::Background)?;
    app.set_system_time(now + Duration::from_secs(24 * 3600))?;
    app.set_environment("resume", |e| e.lifecycle = Lifecycle::Active)?;
    app.press("label:Back")?;
    let tomorrow = today().plus_days(1).to_string();
    for _ in 0..200 {
        if storage.entries()["backup.v1"].contains(&tomorrow) {
            break;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    assert!(storage.entries()["backup.v1"].contains(&tomorrow));
    assert_eq!(dav.files().len(), 1);
    assert!(
        dav.files()
            .keys()
            .all(|name| name.starts_with(&format!("naviwealth-{tomorrow}-")))
    );
    app.set_environment("background", |e| e.lifecycle = Lifecycle::Background)?;
    app.set_environment("resume", |e| e.lifecycle = Lifecycle::Active)?;
    assert_eq!(dav.files().len(), 1);
    Ok(())
}

#[test]
fn corrupted_and_newer_databases_leave_existing_records_untouched() -> Result<(), String> {
    for version in [0, 3, 999] {
        let newer = version == 999;
        let dav = Dav::new();
        let path = tempfile::NamedTempFile::new().unwrap();
        let db = rusqlite::Connection::open(path.path()).unwrap();
        db.execute_batch(if newer { "PRAGMA user_version=999;" } else if version == 0 { "CREATE TABLE unrelated(id TEXT);" } else {
            // Copying meals would succeed before the missing weights table fails.
            "PRAGMA user_version=3; CREATE TABLE meals(id TEXT, day TEXT, logged_at_ms INTEGER, body TEXT);"
        }).unwrap();
        drop(db);
        let bytes = std::fs::read(path.path()).unwrap();
        dav.put(
            "naviwealth-2026-11-13.nwbk",
            backup::seal(&bytes, "correct horse battery", 3, 42).unwrap(),
        );
        let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", true);
        let before = stored_meals(dir.path());
        restore_latest(&mut app, &dav)?;
        app.wait_for(if newer {
            "text:This backup is from a newer version of the app."
        } else {
            "text:Not a readable NaviWealth backup."
        })?;
        assert_eq!(stored_meals(dir.path()), before);
    }
    assert_eq!(
        backup::open(b"not a backup", "password"),
        Err(BackupError::NotABackup)
    );
    Ok(())
}

#[test]
fn failure_while_copying_rows_rolls_back_the_whole_restore() -> Result<(), String> {
    let dav = Dav::new();
    let path = tempfile::NamedTempFile::new().unwrap();
    let db = rusqlite::Connection::open(path.path()).unwrap();
    // The source is readable and its records valid, but duplicate ids
    // violate the destination's primary key after its DELETE has run.
    db.execute_batch(
        "PRAGMA user_version=3;
        CREATE TABLE meals(id TEXT, day TEXT, logged_at_ms INTEGER, body TEXT);
        CREATE TABLE weights(day TEXT, kg REAL, logged_at_ms INTEGER);
        CREATE TABLE garmin_days(day TEXT, body TEXT, fetched_at_ms INTEGER);",
    )
    .unwrap();
    let value: Value = serde_json::from_str(&pasta_today()[0].1).unwrap();
    let meal = &value["meals"][0];
    for _ in 0..2 {
        db.execute(
            "INSERT INTO meals VALUES (?1, ?2, ?3, ?4)",
            rusqlite::params![
                meal["id"].as_str().unwrap(),
                meal["day"].as_str().unwrap(),
                meal["logged_at_ms"].as_i64().unwrap(),
                meal.to_string(),
            ],
        )
        .unwrap();
    }
    drop(db);
    dav.put(
        "naviwealth-2026-11-13.nwbk",
        backup::seal(
            &std::fs::read(path.path()).unwrap(),
            "correct horse battery",
            3,
            42,
        )
        .unwrap(),
    );
    let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", true);
    let before = stored_meals(dir.path());
    restore_latest(&mut app, &dav)?;
    app.wait_for("text:Not a readable NaviWealth backup.")?;
    assert_eq!(stored_meals(dir.path()), before);
    Ok(())
}

#[test]
fn dav_authentication_errors_and_redirects_are_visible_without_sending_credentials_onward()
-> Result<(), String> {
    for status in [401, 503, 302] {
        let dav = Dav::new();
        let destination = Dav::new();
        if status == 302 {
            dav.redirect(destination.url.clone());
        } else {
            dav.status(status);
        }
        let dir = tempfile::tempdir().unwrap();
        let (mut app, _) = start_in(
            Some(dir.path()),
            backups(&dav, "correct horse battery", None),
            None,
        );
        app.press("label:Settings")?;
        app.wait_for(if status == 401 {
            "text:The WebDAV account or password is wrong."
        } else if status == 503 {
            "text:The WebDAV server answered 503."
        } else {
            "text:The WebDAV server answered 302."
        })?;
        assert!(destination.requests().is_empty());
    }
    Ok(())
}
