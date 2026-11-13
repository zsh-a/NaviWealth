//! Backups to the user's own WebDAV folder: once a day when the app starts
//! or comes back, or when asked, the database is copied, encrypted with
//! the user's passphrase off the engine thread, and put as
//! `naviwealth-<day>-<timestamp>.nwbk`. Restoring
//! gets one, decrypts it and replaces meals, weights and Garmin days in one
//! transaction. Keys, passwords and the passphrase never enter a backup;
//! the password and passphrase are kept under their own storage entries.

use nsh_core::{prelude::*, storage::Storage};
use serde::{Deserialize, Serialize};

use super::{
    clock, db, garmin, meals,
    webdav::{DavError, Folder},
    weights,
};
use crate::domain::backup::{self, BackupError};

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
        let now = clock::now_ms();
        let sealed =
            background(async move { backup::seal(&database, &passphrase, db::SCHEMA, now) })
                .await
                .map_err(|_| Failure::Storage)??;
        folder.put(&backup::file_name(&today, now), sealed).await?;
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

/// Replaces meals, weights and Garmin days with the backup `name`.
pub async fn restore(name: String) -> Result<(), Failure> {
    let (folder, passphrase) = begin()?;
    state().update(|s| s.status = Status::Running);
    let result = async {
        let file = folder.get(&name).await?;
        let (_, database) = background(async move { backup::open(&file, &passphrase) })
            .await
            .map_err(|_| Failure::Storage)??;
        db::replace_with(&database).map_err(|error| match error {
            db::RestoreError::Newer => Failure::Newer,
            db::RestoreError::Unreadable => Failure::NotABackup,
            db::RestoreError::Storage => Failure::Storage,
        })?;
        meals::load();
        weights::load();
        garmin::load();
        state().update(|s| {
            s.kept.last_backup_day = Some(clock::today().to_string());
            persist(&s.kept);
        });
        Ok(())
    }
    .await;
    finish(result)
}
