//! Encrypted backup and restore through a real, isolated HTTP WebDAV server.
mod common;
#[path = "common/dav.rs"]
mod dav;

use common::*;
use dav::Dav;
use naviwealth_app::domain::{
    backup::{self, BackupError},
    backup_bundle::Bundle,
};

/// A bundle of the database `bytes` alone.
fn only(database: Vec<u8>) -> Bundle {
    Bundle {
        database,
        photos: Vec::new(),
    }
}
use nsh_testing::DialogAnswer;

/// Settings now carries backup as one row; its form lives on its own page.
fn open_backup(app: &mut Headless) -> Result<(), String> {
    app.press("label:Settings")?;
    app.press("label:/^Backup & restore, /")?;
    app.wait_for("text:WebDAV folder")
}

#[test]
fn incomplete_settings_explain_what_is_missing_without_saving_them() -> Result<(), String> {
    let (mut app, storage) = start(vec![], None);
    open_backup(&mut app)?;
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
    db.execute(
        "INSERT INTO body_metrics VALUES (?1, ?2, 42)",
        [
            today().to_string(),
            json!({"body_fat_percent":18.3,"muscle_percent":76.9,"water_percent":56.9,
                   "resistance_ohm":506.0,"model":"segal_3a_male_lt20"})
            .to_string(),
        ],
    )
    .unwrap();
    db.execute(
        "INSERT INTO review_notes VALUES (?1, 'Lighter dinners.', 42)",
        [today().to_string()],
    )
    .unwrap();
    // Market-cache rows: present on the device, absent from the backup.
    // Leave a full UTC day before now so the following day's 01:00 fetch
    // cannot lie in the future during early-morning test runs.
    let mut day = jiff::Timestamp::now()
        .to_zoned_datetime(jiff::tz::TimeZone::UTC)
        .date()
        .checked_sub(jiff::Span::new().days(2))
        .unwrap();
    while matches!(
        day.weekday(),
        jiff::civil::Weekday::Saturday | jiff::civil::Weekday::Sunday
    ) {
        day = day.checked_sub(jiff::Span::new().days(1)).unwrap();
    }
    let quote_day = day.to_string();
    let fetched_day = day
        .checked_add(jiff::Span::new().days(1))
        .unwrap()
        .to_string();
    db.execute(
        "INSERT INTO finance_accounts (name) VALUES ('资产:现金'),('资产:持仓·sec1')",
        [],
    )
    .unwrap();
    db.execute(
        "INSERT INTO finance_securities (id,name,name_key,account) VALUES ('sec1','ETF','etf','资产:持仓·sec1')",
        [],
    )
    .unwrap();
    db.execute(
        "INSERT INTO finance_quotes (security,day,price) VALUES ('sec1', ?1, 4500000)",
        [&quote_day],
    )
    .unwrap();
    db.execute(
        "INSERT INTO finance_security_bindings (security,market,symbol,currency) VALUES ('sec1','cn_a','510300','CNY')",
        [],
    )
    .unwrap();
    db.execute(
        "INSERT INTO finance_market_quotes (security,symbol,currency,provider,price,observed_at,fetched_at,previous_close_only,day)
         VALUES ('sec1','510300.SH','CNY','tencent',5000000,?2,?2,0,?1)",
        rusqlite::params![quote_day, format!("{quote_day}T07:00:00Z")],
    )
    .unwrap();
    db.execute(
        "INSERT INTO finance_daily_bars (market,symbol,currency,provider,day,open,high,low,close,volume,fetched_at,received_at)
         VALUES ('cn_a','510300.SH','CNY','tencent_raw',?1,4900000,5200000,4800000,5100000,12345,?2,?2)",
        rusqlite::params![quote_day, format!("{fetched_day}T01:00:00Z")],
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
    let (_, bundle) = backup::open(body, "correct horse battery").unwrap();
    assert!(
        bundle.photos.is_empty(),
        "the daily backup carries no photos"
    );
    assert!(!backup::has_photos(name));
    // Market caches ride along in no backup: they are re-fetched on demand.
    let cache_db = dir.path().join("bundle-db.sqlite");
    std::fs::write(&cache_db, &bundle.database).unwrap();
    let copy = rusqlite::Connection::open(&cache_db).unwrap();
    for table in ["finance_market_quotes", "finance_daily_bars"] {
        let n: i64 = copy
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |r| r.get(0))
            .unwrap();
        assert_eq!(n, 0, "{table} is a cache, not a record");
    }
    let manual: i64 = copy
        .query_row("SELECT COUNT(*) FROM finance_quotes", [], |r| r.get(0))
        .unwrap();
    assert_eq!(manual, 1, "manual prices are records");
    assert!(
        !bundle
            .database
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
    open_backup(app)?;
    app.press("Restore…")?;
    let name = dav.files().last_key_value().unwrap().0.clone();
    app.wait_for(&format!("id:{name} >> text:/./"))?;
    app.on_dialog(|_| DialogAnswer::Press("Restore".into()));
    app.press(&format!("id:{name} >> text:/./"))?;
    Ok(())
}

fn wait_for_restore(app: &mut Headless, outcome: &str) -> Result<(), String> {
    // The result includes a WebDAV fetch, real Argon2 decryption and SQLite validation.
    // Parallel restores on a CI runner can outlast the default five-second UI wait.
    app.wait_for_within(outcome, Duration::from_secs(30))
}

#[test]
fn encrypted_backup_creates_the_folder_and_restores_on_a_fresh_install() -> Result<(), String> {
    let dav = Dav::new();
    backed_up(&dav)?;
    let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", false);
    assert!(app.shows("Nothing recorded today"));
    restore_latest(&mut app, &dav)?;
    wait_for_restore(&mut app, "text:Backup restored")?;
    // Restore happened on the backup page, over Settings; both go.
    app.press("label:Back")?;
    app.press("label:Back")?;
    app.wait_for("Tomato pasta")?;
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert_eq!(
        stored_weights(dir.path()),
        vec![(today().to_string(), 72.4)]
    );
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let note: String = db
        .query_row("SELECT text FROM review_notes", [], |r| r.get(0))
        .unwrap();
    assert_eq!(note, "Lighter dinners.");
    let body: String = db
        .query_row("SELECT body FROM garmin_days", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&body).unwrap()["steps"],
        12345
    );
    let fat: String = db
        .query_row("SELECT body FROM body_metrics", [], |r| r.get(0))
        .unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&fat).unwrap()["body_fat_percent"],
        18.3
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
    wait_for_restore(
        &mut app,
        "text:Wrong passphrase, or the backup was changed.",
    )?;
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
    app.wait_for("label:New entry")?;
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
            backup::seal(&only(bytes), "correct horse battery", 3, 42).unwrap(),
        );
        let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", true);
        let before = stored_meals(dir.path());
        restore_latest(&mut app, &dav)?;
        wait_for_restore(
            &mut app,
            if newer {
                "text:This backup is from a newer version of the app."
            } else {
                "text:Not a readable NaviWealth backup."
            },
        )?;
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
            &only(std::fs::read(path.path()).unwrap()),
            "correct horse battery",
            3,
            42,
        )
        .unwrap(),
    );
    let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", true);
    let before = stored_meals(dir.path());
    restore_latest(&mut app, &dav)?;
    wait_for_restore(&mut app, "text:Not a readable NaviWealth backup.")?;
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
        // The automatic backup encrypts with real Argon2 before reaching
        // this server; parallel backup flows can exceed the normal UI wait.
        app.wait_for_within(
            if status == 401 {
                "text:Automatic backup on · The WebDAV account or password is wrong."
            } else if status == 503 {
                "text:Automatic backup on · The WebDAV server answered 503."
            } else {
                "text:Automatic backup on · The WebDAV server answered 302."
            },
            Duration::from_secs(30),
        )?;
        assert!(destination.requests().is_empty());
    }
    Ok(())
}

/// The app's photo folder beside its database under `dir`.
fn photo_dir(dir: &Path) -> PathBuf {
    database_in(dir).parent().unwrap().join("meal-photos")
}

#[test]
fn a_backup_made_by_hand_carries_the_photos_back_to_a_fresh_install() -> Result<(), String> {
    let dav = Dav::new();
    // A meal with a kept photo, backed up by hand.
    let dir = tempfile::tempdir().unwrap();
    let mut entries = backups(&dav, "correct horse battery", Some(today().to_string()));
    let mut meals: Value = serde_json::from_str(&pasta_today()[0].1).unwrap();
    meals["meals"][0]["photo"] = json!("m1.jpg");
    entries.push(("meals.v1".into(), meals.to_string()));
    // The app's data directory is where it put its database.
    let (app, storage) = start_in(Some(dir.path()), entries, None);
    drop(app);
    let photos = photo_dir(dir.path());
    std::fs::create_dir_all(&photos).unwrap();
    std::fs::write(photos.join("m1.jpg"), photo()).unwrap();
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    open_backup(&mut app)?;
    app.press("Save and back up")?;
    let made = app.wait_until("a backup with photos", GONE, |_| {
        dav.files().keys().any(|name| backup::has_photos(name))
    });
    assert!(
        made.is_ok(),
        "files: {:?}",
        dav.files().keys().collect::<Vec<_>>()
    );
    let (name, body) = dav.files().into_iter().next_back().unwrap();
    let (_, bundle) = backup::open(&body, "correct horse battery").unwrap();
    assert_eq!(bundle.photos, vec![("m1.jpg".to_owned(), photo())]);
    drop(app);

    let (mut app, _, fresh) = fresh_with(&dav, "correct horse battery", false);
    open_backup(&mut app)?;
    app.press("Restore…")?;
    app.wait_for(&format!("id:{name} >> text:/./"))?;
    app.wait_for("text:With photos")?;
    app.on_dialog(|_| DialogAnswer::Press("Restore".into()));
    app.press(&format!("id:{name} >> text:/./"))?;
    wait_for_restore(&mut app, "text:Backup restored")?;
    assert_eq!(
        std::fs::read(photo_dir(fresh.path()).join("m1.jpg")).unwrap(),
        photo()
    );
    Ok(())
}

#[test]
fn encrypted_backups_exclude_recognition_threads_and_local_write_guards() -> Result<(), String> {
    let dav = Dav::new();
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(
        Some(dir.path()),
        backups(&dav, "correct horse battery", Some(today().to_string())),
        None,
    );
    let database = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let private = "private-unconfirmed-transcript-evidence";
    for table in ["meal_drafts", "capture_drafts"] {
        database
            .execute(
                &format!("INSERT INTO {table}(id,created_at_ms,body) VALUES('draft',1,?1)"),
                [private],
            )
            .unwrap();
    }
    database
        .execute("INSERT INTO scale_drafts VALUES('session',?1)", [private])
        .unwrap();
    database
        .execute("INSERT INTO weight_revisions VALUES('2026-11-19',42)", [])
        .unwrap();
    open_backup(&mut app)?;
    app.press("Save and back up")?;
    app.wait_until("an encrypted backup", GONE, |_| !dav.files().is_empty())?;
    let (_, encrypted) = dav.files().into_iter().next_back().unwrap();
    let (_, bundle) = backup::open(&encrypted, "correct horse battery").unwrap();
    assert!(
        !bundle
            .database
            .windows(private.len())
            .any(|bytes| bytes == private.as_bytes())
    );
    let copy_path = dir.path().join("exported.sqlite");
    std::fs::write(&copy_path, &bundle.database).unwrap();
    let copy = rusqlite::Connection::open(copy_path).unwrap();
    for table in [
        "meal_drafts",
        "capture_drafts",
        "scale_drafts",
        "weight_revisions",
    ] {
        let exported: i64 = copy
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        let original: i64 = database
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(exported, 0, "{table} must stay out of exported backups");
        assert_eq!(original, 1, "backup must preserve the live {table}");
    }
    Ok(())
}

/// A valid database with a photo-backed meal and explicit image bytes.
fn backup_with_photo(dav: &Dav, photos: Vec<(String, Vec<u8>)>) {
    let source = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(source.path()), pasta_today(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(source.path())).unwrap();
    db.execute(
        "UPDATE meals SET body=json_set(body,'$.photo','m1.jpg')",
        [],
    )
    .unwrap();
    let meal: Meal = serde_json::from_value(stored_meals(source.path())[0].clone()).unwrap();
    let favorite = naviwealth_app::domain::favorite::Favorite::from_meal(
        &meal,
        "favorite".into(),
        Some("m1.jpg".into()),
        42,
    );
    navi_health::store::save_favorite(&db, &favorite).unwrap();
    let schema: u32 = db
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .unwrap();
    drop(db);
    let bundle = Bundle {
        database: std::fs::read(database_in(source.path())).unwrap(),
        photos,
    };
    dav.put(
        "naviwealth-2026-11-19-photos.nwbk",
        backup::seal(&bundle, "correct horse battery", schema, 42).unwrap(),
    );
}

#[test]
fn failed_photo_preparation_preserves_database_and_existing_photos() -> Result<(), String> {
    let dav = Dav::new();
    backup_with_photo(
        &dav,
        vec![("new.jpg".into(), photo()), ("blocked.jpg".into(), photo())],
    );
    let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", true);
    let before = stored_meals(dir.path());
    std::fs::create_dir_all(photo_dir(dir.path()).join("blocked.jpg")).unwrap();
    std::fs::write(photo_dir(dir.path()).join("kept.jpg"), b"kept").unwrap();
    restore_latest(&mut app, &dav)?;
    wait_for_restore(&mut app, "text:The device could not write.")?;
    assert_eq!(stored_meals(dir.path()), before);
    assert_eq!(
        std::fs::read(photo_dir(dir.path()).join("kept.jpg")).unwrap(),
        b"kept"
    );
    assert!(!photo_dir(dir.path()).join("new.jpg").exists());
    Ok(())
}

#[test]
fn restore_uses_new_references_for_conflicting_photos_and_preserves_local_files()
-> Result<(), String> {
    let dav = Dav::new();
    backup_with_photo(&dav, vec![("m1.jpg".into(), photo())]);
    let dir = tempfile::tempdir().unwrap();
    let mut entries = backups(&dav, "correct horse battery", Some(today().to_string()));
    let mut meals: Value = serde_json::from_str(&pasta_today()[0].1).unwrap();
    meals["meals"][0]["photo"] = json!("m1.jpg");
    entries.push(("meals.v1".into(), meals.to_string()));
    // The colliding photo belongs to an existing record before startup.
    // An unreferenced file added after startup races the orphan sweep.
    let photos = dir.path().join("meal-photos");
    std::fs::create_dir_all(&photos).unwrap();
    std::fs::write(photos.join("m1.jpg"), b"local photo").unwrap();
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    restore_latest(&mut app, &dav)?;
    wait_for_restore(&mut app, "text:Backup restored")?;
    let restored = stored_meals(dir.path());
    let name = restored[0]["photo"].as_str().unwrap();
    assert_ne!(name, "m1.jpg");
    assert_eq!(
        std::fs::read(photo_dir(dir.path()).join(name)).unwrap(),
        photo()
    );
    assert_eq!(
        std::fs::read(photo_dir(dir.path()).join("m1.jpg")).unwrap(),
        b"local photo"
    );
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let favorite = navi_health::store::favorites(&db).unwrap();
    assert_eq!(favorite[0].photo.as_deref(), Some(name));
    Ok(())
}

#[test]
fn rejected_database_restore_removes_only_newly_prepared_photos() -> Result<(), String> {
    let dav = Dav::new();
    backup_with_photo(&dav, vec![("m1.jpg".into(), photo())]);
    let (mut app, _, dir) = fresh_with(&dav, "correct horse battery", true);
    let before = stored_meals(dir.path());
    std::fs::create_dir_all(photo_dir(dir.path())).unwrap();
    std::fs::write(photo_dir(dir.path()).join("m1.jpg"), b"kept").unwrap();
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_restore BEFORE INSERT ON meals BEGIN SELECT RAISE(ABORT,'device cannot write'); END;").unwrap();
    restore_latest(&mut app, &dav)?;
    wait_for_restore(&mut app, "text:Not a readable NaviWealth backup.")?;
    assert_eq!(stored_meals(dir.path()), before);
    assert_eq!(
        std::fs::read(photo_dir(dir.path()).join("m1.jpg")).unwrap(),
        b"kept"
    );
    assert_eq!(std::fs::read_dir(photo_dir(dir.path())).unwrap().count(), 1);
    Ok(())
}
