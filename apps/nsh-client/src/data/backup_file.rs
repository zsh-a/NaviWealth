//! Backup files the owner keeps themselves, so recovery never depends on a
//! WebDAV folder. An export seals the same bundle as a WebDAV backup with
//! the backup passphrase, writes it to the app's own `exports` folder and
//! hands it to the system share sheet (Android: Files, a drive, a chat), or
//! to a save dialog where there is no share sheet (desktop development).
//! Only the newest export stays in that folder. A picked file restores
//! exactly as a WebDAV backup does: it is opened first, and a wrong
//! passphrase or a malformed file leaves the device untouched.
//!
//! The passphrase is the one typed on the backup page, else the kept one.
//! A typed passphrase that sealed an export becomes the kept one; one that
//! opened a restored file is kept only when none was kept before (a fresh
//! install), never replacing the passphrase later backups use.

use std::path::{Path, PathBuf};

use nsh_core::{
    file_dialog::SaveDialog,
    prelude::*,
    share::{ShareAction, ShareRequest},
};

use super::{
    backup::{self, Failure},
    clock, db, photos,
};
use crate::domain::{
    backup::{self as sealed, MIN_PASSPHRASE},
    backup_bundle::Bundle,
};

/// The folder under the app's data directory that holds the newest export.
const DIR: &str = "exports";

/// A sealed backup written on the device, ready to hand over.
#[derive(Debug, Clone, PartialEq)]
pub struct Export {
    pub name: String,
    pub path: PathBuf,
}

/// How handing a backup file over ended.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Delivered {
    /// The share sheet reports the owner chose a target.
    Shared,
    /// The save dialog's file was written.
    Saved,
    /// The owner closed the share sheet or the save dialog.
    Dismissed,
}

fn dir() -> PathBuf {
    data_dir().unwrap_or_else(std::env::temp_dir).join(DIR)
}

/// The passphrase a file operation uses: the one `typed`, else the kept
/// one; [`Failure::NoPassphrase`] when neither is long enough.
pub fn passphrase(typed: &str) -> Result<String, Failure> {
    if typed.is_empty() {
        return backup::kept_passphrase().ok_or(Failure::NoPassphrase);
    }
    if typed.chars().count() >= MIN_PASSPHRASE {
        Ok(typed.to_owned())
    } else {
        Err(Failure::NoPassphrase)
    }
}

/// Seals the database (and meal photos `with_photos`) into the exports
/// folder, replacing the previous export.
pub async fn export(typed: String, with_photos: bool) -> Result<Export, Failure> {
    let passphrase = passphrase(&typed)?;
    let previous = backup::claim().ok_or(Failure::Busy)?;
    let result = async {
        let database = db::snapshot().map_err(|error| {
            log::error!("backup file: no snapshot: {error}");
            Failure::Storage
        })?;
        let photos = if with_photos {
            photos::read_for_backup().await
        } else {
            Vec::new()
        };
        let now = clock::now_ms();
        let name = sealed::file_name(&clock::today().to_string(), now, !photos.is_empty());
        let bundle = Bundle { database, photos };
        let (folder, path) = (dir(), dir().join(&name));
        let target = path.clone();
        background(async move {
            let bytes = sealed::seal(&bundle, &passphrase, db::SCHEMA, now)?;
            replace_exports(&folder, &target, &bytes).map_err(|error| {
                log::error!("backup file: could not write the export: {error}");
                Failure::Storage
            })
        })
        .await
        .map_err(|_| Failure::Storage)??;
        Ok(Export { name, path })
    }
    .await;
    backup::release(previous);
    if result.is_ok() && !typed.is_empty() {
        backup::keep_passphrase(typed);
    }
    result
}

/// Writes `bytes` as the only export: under a temporary name first, renamed
/// into place, then every other file in the folder is removed.
fn replace_exports(folder: &Path, path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    std::fs::create_dir_all(folder)?;
    let partial = path.with_extension("partial");
    std::fs::write(&partial, bytes)?;
    std::fs::rename(&partial, path)?;
    for entry in std::fs::read_dir(folder)?.flatten() {
        if entry.path() != path {
            let _ = std::fs::remove_file(entry.path());
        }
    }
    Ok(())
}

/// Hands `export` to the share sheet, or to a save dialog where there is
/// none. A share or save that went through is remembered as the last export.
pub async fn deliver(export: Export) -> Result<Delivered, Failure> {
    let delivered = if share_available().await {
        let request = ShareRequest::new()
            .title(export.name.clone())
            .file(export.path.clone());
        match share(request).await {
            Ok(outcome) if outcome.action == ShareAction::Dismissed => Delivered::Dismissed,
            Ok(_) => Delivered::Shared,
            Err(error) => {
                log::warn!("backup file: share failed: {}", error.message);
                return Err(Failure::Unavailable);
            }
        }
    } else {
        let dialog = SaveDialog::new().file_name(export.name.clone());
        match pick_save_path(dialog).await {
            Ok(Some(target)) => {
                let source = export.path.clone();
                background(async move { std::fs::copy(source, target).map(drop) })
                    .await
                    .map_err(|_| Failure::Storage)?
                    .map_err(|error| {
                        log::error!("backup file: could not save the copy: {error}");
                        Failure::Storage
                    })?;
                Delivered::Saved
            }
            Ok(None) => Delivered::Dismissed,
            Err(error) => {
                log::warn!("backup file: no save dialog: {error}");
                return Err(Failure::Unavailable);
            }
        }
    };
    if delivered != Delivered::Dismissed {
        backup::exported(clock::now_ms());
    }
    Ok(delivered)
}

/// Restores the backup `file` (its bytes, as picked). It is decrypted and
/// checked before anything on the device changes.
pub async fn restore(file: Vec<u8>, typed: String) -> Result<(), Failure> {
    let passphrase = passphrase(&typed)?;
    let previous = backup::claim().ok_or(Failure::Busy)?;
    let result = async {
        let (_, bundle) = background(async move { sealed::open(&file, &passphrase) })
            .await
            .map_err(|_| Failure::Storage)??;
        backup::apply(bundle).await
    }
    .await;
    backup::release(previous);
    if result.is_ok() && !typed.is_empty() && backup::kept_passphrase().is_none() {
        backup::keep_passphrase(typed);
    }
    result
}
