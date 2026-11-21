//! Backup files on the device: export through the share sheet or a save
//! dialog, and restore from a picked file without any WebDAV folder.
mod common;

use common::*;
use naviwealth_app::domain::{backup, backup_bundle::Bundle};
use nsh_core::share::ShareOutcome;
use nsh_testing::DialogAnswer;

const PASSPHRASE: &str = "correct horse battery";
const KEPT: &str = "secret.backup-passphrase.v1";

fn open_backup(app: &mut Headless) -> Result<(), String> {
    app.press("label:Settings")?;
    app.press("label:/^Backup & restore, /")?;
    app.wait_for("Export backup file")
}

fn kept(passphrase: &str) -> Vec<(String, String)> {
    vec![(KEPT.into(), passphrase.into())]
}

fn pick_backup(app: &mut Headless, bytes: Vec<u8>) {
    app.on_pick(move |request| {
        assert!(matches!(request, nsh_core::picker::Pick::Files(_)));
        vec![PickedFile::new(
            "naviwealth.nwbk",
            "application/octet-stream",
            ImageData::new(bytes.clone()),
        )]
    });
}

/// Waits for work that ends without anything new on screen.
fn eventually(what: &str, done: impl Fn() -> bool) {
    for _ in 0..200 {
        if done() {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("{what} did not happen");
}

fn last_export(storage: &MemoryStorage) -> Option<i64> {
    let kept: Value = serde_json::from_str(storage.entries().get("backup.v1")?).ok()?;
    kept["last_export_ms"].as_i64()
}

fn exports(dir: &Path) -> Vec<PathBuf> {
    let mut files: Vec<_> = std::fs::read_dir(dir.join("exports"))
        .map(|entries| entries.flatten().map(|e| e.path()).collect())
        .unwrap_or_default();
    files.sort();
    files
}

#[test]
fn a_shared_backup_file_restores_on_a_fresh_install_without_webdav() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let mut entries = pasta_today();
    entries.extend(kept(PASSPHRASE));
    let (mut app, storage) = start_in(Some(dir.path()), entries, None);
    app.on_share(ShareOutcome::shared(Some("Files".into())))?;
    open_backup(&mut app)?;
    assert!(app.shows("No backup file exported yet"));
    app.press("Export backup file")?;
    app.wait_for("text:Backup file exported")?;

    let shares = app.screen().shares().to_vec();
    assert_eq!(shares.len(), 1);
    let path = PathBuf::from(&shares[0].files[0]);
    assert_eq!(exports(dir.path()), vec![path.clone()]);
    let name = path.file_name().unwrap().to_string_lossy().into_owned();
    assert_eq!(shares[0].title.as_deref(), Some(name.as_str()));
    assert!(name.starts_with(&format!("naviwealth-{}-", today())));
    let file = std::fs::read(&path).unwrap();
    assert!(file.starts_with(b"NWBK"));
    assert!(
        !file
            .windows(b"Tomato pasta".len())
            .any(|w| w == b"Tomato pasta")
    );
    backup::open(&file, PASSPHRASE).expect("the kept passphrase opens it");
    assert!(storage.entries()["backup.v1"].contains("last_export_ms"));
    app.wait_for("text:/^Last exported: /")?;
    // The settings row says when, with automatic backups off.
    app.press("label:Back")?;
    app.wait_for("label:/^Backup & restore, Automatic backup off · Last exported: /")?;
    drop(app);

    // A fresh install: no WebDAV, no kept passphrase.
    let fresh = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(fresh.path()), Vec::new(), None);
    assert!(app.shows("Nothing recorded today"));
    open_backup(&mut app)?;
    app.type_text("label:Backup passphrase", PASSPHRASE)?;
    pick_backup(&mut app, file);
    app.on_dialog(|_| DialogAnswer::Press("Restore".into()));
    app.press("Restore from file…")?;
    app.wait_for("text:Backup restored")?;
    assert_eq!(stored_meals(fresh.path()).len(), 1);
    // The passphrase that opened it protects the next backups.
    assert_eq!(storage.entries()[KEPT], PASSPHRASE);
    app.press("label:Back")?;
    app.press("label:Back")?;
    app.wait_for("Tomato pasta")?;
    Ok(())
}

#[test]
fn without_a_passphrase_nothing_is_sealed_shared_or_picked() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    app.on_share(ShareOutcome::shared(None))?;
    let picks = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let seen = picks.clone();
    app.on_pick(move |_| {
        seen.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        Vec::new()
    });
    open_backup(&mut app)?;
    app.press("Export backup file")?;
    app.wait_for("text:Enter a backup passphrase of at least 8 characters above.")?;
    app.type_text("label:Backup passphrase", "short")?;
    app.press("Restore from file…")?;
    app.wait_for("text:Enter a backup passphrase of at least 8 characters above.")?;
    assert!(app.screen().shares().is_empty());
    assert!(exports(dir.path()).is_empty());
    assert_eq!(picks.load(std::sync::atomic::Ordering::Relaxed), 0);
    Ok(())
}

#[test]
fn a_wrong_passphrase_or_malformed_file_keeps_current_records() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let mut entries = pasta_today();
    entries.extend(kept("another passphrase"));
    let (mut app, storage) = start_in(Some(dir.path()), entries, None);
    let before = stored_meals(dir.path());
    assert_eq!(before.len(), 1);
    open_backup(&mut app)?;
    app.on_dialog(|_| DialogAnswer::Press("Restore".into()));

    let bundle = Bundle {
        database: b"not a database".to_vec(),
        photos: Vec::new(),
    };
    let other = backup::seal(&bundle, PASSPHRASE, 1, 42).unwrap();
    pick_backup(&mut app, other);
    app.press("Restore from file…")?;
    app.wait_for("text:Wrong passphrase, or the backup was changed.")?;
    assert_eq!(stored_meals(dir.path()), before);

    pick_backup(&mut app, b"plain bytes".to_vec());
    app.press("Restore from file…")?;
    app.wait_for("text:Not a readable NaviWealth backup.")?;
    assert_eq!(stored_meals(dir.path()), before);

    // The right passphrase typed for one file never replaces the kept one,
    // and an unreadable database inside still changes nothing.
    let sealed = backup::seal(&bundle, PASSPHRASE, 1, 42).unwrap();
    app.type_text("label:Backup passphrase", PASSPHRASE)?;
    pick_backup(&mut app, sealed);
    app.press("Restore from file…")?;
    app.wait_for("text:Not a readable NaviWealth backup.")?;
    assert_eq!(stored_meals(dir.path()), before);
    assert_eq!(storage.entries()[KEPT], "another passphrase");
    Ok(())
}

#[test]
fn desktops_save_a_copy_and_only_the_newest_export_stays() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let saved = dir.path().join("saved.nwbk");
    let mut entries = pasta_today();
    entries.extend(kept(PASSPHRASE));
    let (mut app, storage) = start_in(Some(dir.path()), entries, None);
    app.on_pick_save_path(Some(saved.clone()))?;
    open_backup(&mut app)?;
    app.press("Export backup file")?;
    app.wait_for("text:Backup file exported")?;
    let first = exports(dir.path());
    assert_eq!(first.len(), 1);
    assert_eq!(
        std::fs::read(&saved).unwrap(),
        std::fs::read(&first[0]).unwrap()
    );
    // The same day, a moment later: a new name replaces the old file.
    std::thread::sleep(Duration::from_millis(5));
    let exported_at = last_export(&storage).expect("the saved copy counts");
    app.on_pick_save_path(None)?;
    app.press("Export backup file")?;
    eventually("the second export", || exports(dir.path()) != first);
    let second = exports(dir.path());
    assert_eq!(second.len(), 1);
    // Cancelling the dialog is no export and no failure.
    std::thread::sleep(Duration::from_millis(100));
    assert!(!app.shows("text:The device could not write."));
    assert_eq!(last_export(&storage), Some(exported_at));
    Ok(())
}

#[test]
fn a_dismissed_share_sheet_is_not_an_export() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let mut entries = pasta_today();
    entries.extend(kept(PASSPHRASE));
    let (mut app, storage) = start_in(Some(dir.path()), entries, None);
    app.on_share(ShareOutcome::dismissed())?;
    open_backup(&mut app)?;
    app.press("Export backup file")?;
    eventually("the share sheet", || !exports(dir.path()).is_empty());
    std::thread::sleep(Duration::from_millis(100));
    app.wait_for("No backup file exported yet")?;
    assert_eq!(app.screen().shares().len(), 1);
    assert!(!app.shows("text:Backup file exported"));
    assert_eq!(last_export(&storage), None);
    Ok(())
}
