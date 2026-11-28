//! Backups to the user's own WebDAV folder: once a day when the app starts
//! or comes back, or when asked, the database is copied, encrypted with
//! the user's passphrase off the engine thread, and put as
//! `naviwealth-<day>-<timestamp>.nwbk`. The snapshot carries no market
//! caches: provider quotes and daily bars are re-fetched on demand, so a
//! restored install rebuilds them from each holding's first trade. A backup made by hand also carries
//! the meal photos (`…-photos.nwbk`); the daily one does not, so it stays
//! small. Restoring gets one, decrypts it, replaces meals, favorites,
//! notes, weights, Garmin days and the ledger in one transaction and writes back the
//! photos it carries (photos already on the device stay). Keys, passwords and the passphrase never enter a backup;
//! the password and passphrase are kept under their own storage entries.

use nsh_core::{prelude::*, storage::Storage};
use serde::{Deserialize, Serialize};

use super::{
    body_metrics, clock, db, favorites, finance, garmin, meals, notes, photos,
    webdav::{DavError, Folder},
    weights,
};
use crate::domain::{
    backup::{self, BackupError},
    backup_bundle::Bundle,
};

const KEY: &str = "backup.v1";
const KEY_PASSWORD: &str = "secret.webdav-password.v1";
const KEY_PASSPHRASE: &str = "secret.backup-passphrase.v1";

/// Why a backup or restore did not happen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Failure {
    NotConfigured,
    Network,
    Unauthorized,
    Server(u16),
    WrongPassphrase,
    Busy,
    NotABackup,
    Newer,
    Storage,
    /// A backup file needs a passphrase of at least 8 characters, typed or kept.
    NoPassphrase,
    /// The device offers neither a share sheet nor a save dialog.
    Unavailable,
}

impl From<DavError> for Failure {
    fn from(error: DavError) -> Self {
        match error {
            DavError::Network => Failure::Network,
            DavError::Unauthorized => Failure::Unauthorized,
            DavError::Status(status) => Failure::Server(status),
        }
    }
}

impl From<BackupError> for Failure {
    fn from(error: BackupError) -> Self {
        match error {
            BackupError::WrongPassphrase => Failure::WrongPassphrase,
            BackupError::Newer => Failure::Newer,
            BackupError::ShortPassphrase => Failure::NotConfigured,
            BackupError::NotABackup | BackupError::Random => Failure::NotABackup,
        }
    }
}

/// What the backup is doing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Status {
    #[default]
    Idle,
    Running,
    Failed(Failure),
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
struct Kept {
    folder: Folder,
    last_backup_ms: Option<i64>,
    last_backup_day: Option<String>,
    /// When a backup file was last handed to the share sheet or saved.
    #[serde(default)]
    last_export_ms: Option<i64>,
}

#[derive(Clone, Default, PartialEq)]
struct State {
    kept: Kept,
    passphrase: String,
    status: Status,
}

fn state() -> Signal<State> {
    global::<State>()
}

/// Reads the configuration; the root calls it once.
pub fn load() {
    let mut kept: Kept = Storage::get_item(KEY)
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();
    kept.folder.password = Storage::get_item(KEY_PASSWORD).unwrap_or_default();
    let passphrase = Storage::get_item(KEY_PASSPHRASE).unwrap_or_default();
    state().set(State {
        kept,
        passphrase,
        status: Status::Idle,
    });
}

fn persist(kept: &Kept) {
    if let Ok(json) = serde_json::to_string(kept) {
        let _ = Storage::set_item(KEY, json);
    }
}

/// Whether backups can run (tracked).
pub fn configured() -> bool {
    state().with(|s| {
        s.kept.folder.is_complete() && s.passphrase.chars().count() >= backup::MIN_PASSPHRASE
    })
}

/// The folder as kept, with its password (untracked), for the form.
pub fn folder() -> Folder {
    state().with_untracked(|s| s.kept.folder.clone())
}

/// Whether a passphrase is kept (tracked).
pub fn has_passphrase() -> bool {
    state().with(|s| !s.passphrase.is_empty())
}

/// What the backup is doing (tracked).
pub fn status() -> Status {
    state().with(|s| s.status)
}

/// When the last backup was put (tracked).
pub fn last_backup_ms() -> Option<i64> {
    state().with(|s| s.kept.last_backup_ms)
}

/// When a backup file was last exported (tracked).
pub fn last_export_ms() -> Option<i64> {
    state().with(|s| s.kept.last_export_ms)
}

/// The kept passphrase, when it is long enough to seal (untracked).
pub(super) fn kept_passphrase() -> Option<String> {
    state().with_untracked(|s| {
        (s.passphrase.chars().count() >= backup::MIN_PASSPHRASE).then(|| s.passphrase.clone())
    })
}

/// Keeps `passphrase` for every later backup, WebDAV and file alike.
pub(super) fn keep_passphrase(passphrase: String) {
    let _ = Storage::set_item(KEY_PASSPHRASE, passphrase.clone());
    state().update(|s| s.passphrase = passphrase);
}

/// Notes that a backup file left the app.
pub(super) fn exported(at_ms: i64) {
    state().update(|s| {
        s.kept.last_export_ms = Some(at_ms);
        persist(&s.kept);
    });
}

/// Marks a backup file operation as running, so WebDAV work waits for it;
/// the status it replaced comes back from [`release`]. `None` when busy.
pub(super) fn claim() -> Option<Status> {
    let previous = state().with_untracked(|s| s.status);
    if previous == Status::Running {
        return None;
    }
    state().update(|s| s.status = Status::Running);
    Some(previous)
}

/// Ends a file operation: the WebDAV status it replaced stands again.
pub(super) fn release(previous: Status) {
    state().update(|s| s.status = previous);
}

/// Keeps the folder and, when given, a new passphrase.
pub fn configure(folder: Folder, passphrase: Option<String>) {
    if status() == Status::Running {
        return;
    }
    let _ = Storage::set_item(KEY_PASSWORD, folder.password.clone());
    if let Some(passphrase) = &passphrase {
        let _ = Storage::set_item(KEY_PASSPHRASE, passphrase.clone());
    }
    state().update(|s| {
        let changed = s.kept.folder != folder;
        s.kept.folder = folder;
        if changed {
            // A new folder gets today's backup too.
            s.kept.last_backup_day = None;
        }
        if let Some(passphrase) = passphrase {
            s.passphrase = passphrase;
        }
        s.status = Status::Idle;
        persist(&s.kept);
    });
}

fn begin() -> Result<(Folder, String), Failure> {
    let ready = untracked(configured);
    state().with_untracked(|s| {
        if s.status == Status::Running {
            Err(Failure::Busy)
        } else if !ready {
            Err(Failure::NotConfigured)
        } else {
            Ok((s.kept.folder.clone(), s.passphrase.clone()))
        }
    })
}

fn finish(result: Result<(), Failure>) -> Result<(), Failure> {
    state().update(|s| {
        s.status = match result {
            Ok(()) => Status::Idle,
            Err(failure) => Status::Failed(failure),
        }
    });
    result
}

/// Backs up when configured: always when `force`, else once a day.
pub async fn backup_now(force: bool) -> Result<(), Failure> {
    let today = clock::today().to_string();
    let due = force
        || state().with_untracked(|s| s.kept.last_backup_day.as_deref() != Some(today.as_str()));
    if !due {
        return Ok(());
    }
    let (folder, passphrase) = begin()?;
    state().update(|s| s.status = Status::Running);
    let result = async {
        let database = db::snapshot().map_err(|error| {
            log::error!("backup: no snapshot: {error}");
            Failure::Storage
        })?;
        let photos = if force {
            photos::read_for_backup().await
        } else {
            Vec::new()
        };
        let with_photos = !photos.is_empty();
        let now = clock::now_ms();
        let bundle = Bundle { database, photos };
        let sealed = background(async move { backup::seal(&bundle, &passphrase, db::SCHEMA, now) })
            .await
            .map_err(|_| Failure::Storage)??;
        folder
            .put(&backup::file_name(&today, now, with_photos), sealed)
            .await?;
        state().update(|s| {
            s.kept.last_backup_ms = Some(clock::now_ms());
            s.kept.last_backup_day = Some(today.clone());
            persist(&s.kept);
        });
        Ok(())
    }
    .await;
    finish(result)
}

/// The backups in the folder, newest first.
pub async fn list() -> Result<Vec<String>, Failure> {
    let folder = folder();
    if !folder.is_complete() {
        return Err(Failure::NotConfigured);
    }
    Ok(folder.list().await?)
}

/// Replaces Health and ledger records with backup `name`, and writes back
/// the photos it carries. Older Health-only backups leave the ledger intact.
pub async fn restore(name: String) -> Result<(), Failure> {
    let (folder, passphrase) = begin()?;
    state().update(|s| s.status = Status::Running);
    let result = async {
        let file = folder.get(&name).await?;
        let (_, bundle) = background(async move { backup::open(&file, &passphrase) })
            .await
            .map_err(|_| Failure::Storage)??;
        apply(bundle).await
    }
    .await;
    finish(result)
}

/// Puts an opened backup in place: its photos are prepared, the records
/// replaced in one transaction, then every in-memory view reloads. A
/// failure before the replacement leaves the device as it was.
pub(super) async fn apply(bundle: Bundle) -> Result<(), Failure> {
    let photos = photos::prepare_restore(bundle.photos)
        .await
        .map_err(|error| {
            log::error!("backup: could not prepare restored photos: {error}");
            Failure::Storage
        })?;
    super::assistant::stop_for_restore();
    db::replace_with(&bundle.database, photos.restored()).map_err(|error| match error {
        db::RestoreError::Newer => Failure::Newer,
        db::RestoreError::Unreadable => Failure::NotABackup,
        db::RestoreError::Storage => Failure::Storage,
    })?;
    photos.commit();
    super::capture::load().map_err(|_| Failure::Storage)?;
    super::assistant::load().map_err(|_| Failure::Storage)?;
    meals::load().map_err(|_| Failure::Storage)?;
    favorites::load().map_err(|_| Failure::Storage)?;
    notes::load();
    weights::load();
    body_metrics::load();
    garmin::load();
    finance::load().map_err(|_| Failure::Storage)?;
    super::statement_import::load().map_err(|_| Failure::Storage)?;
    super::catalog::load().map_err(|_| Failure::Storage)?;
    super::market::load().map_err(|_| Failure::Storage)?;
    super::history::clear_attempts();
    super::valuation::invalidate();
    state().update(|s| {
        s.kept.last_backup_day = Some(clock::today().to_string());
        persist(&s.kept);
    });
    Ok(())
}
