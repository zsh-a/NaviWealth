//! Content another app shares to NaviWealth through Android's share sheet.
//! The Kotlin host copies each item into the app-private
//! `naviwealth-incoming` folder, and the TSX entry forwards the copies once
//! ([`crate::incoming`]). Images, with any shared text, start an unsent
//! capture draft: nothing reaches a model until the owner sends it, after the
//! usual consent. A statement file (CSV, XLSX or CMB text) opens the
//! deterministic statement review, never replacing one in progress.
//! Anything else is declined with a notice.
//! Every copy is read at most once and then removed.

use std::path::{Path, PathBuf};

use nsh_core::prelude::*;
use serde::Deserialize;

use super::{capture, photos, statement_import, tasks};
use crate::domain::capture::MAX_ATTACHMENTS;

/// The host's folder for shared copies; nothing outside it is read.
pub const FOLDER: &str = "naviwealth-incoming";
/// The largest copy read.
const MAX_BYTES: u64 = 25 * 1024 * 1024;
/// Shared text beyond this is dropped.
const MAX_TEXT: usize = 4000;
/// Statement file extensions the import reads.
const STATEMENTS: [&str; 3] = ["csv", "xlsx", "txt"];

/// What the host copied from one share.
#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
pub struct Shared {
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub files: Vec<SharedFile>,
}

/// One copied item: its private path and the sender's name and type.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct SharedFile {
    pub path: PathBuf,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub mime: String,
}

/// What the home shows for a share.
#[derive(Debug, Clone, PartialEq)]
pub enum Opened {
    /// The unsent capture draft holding the shared images and text.
    Capture(String),
    /// The statement review, with the shared file open in it.
    Statement,
    /// A review was already in progress; it is kept and the file declined
    /// with a notice.
    StatementBusy,
    /// Nothing usable was shared.
    Unsupported,
}

#[derive(Clone, Default, PartialEq)]
struct Request(Option<Opened>);

/// The newest share waiting for the home (tracked).
pub fn request() -> Option<Opened> {
    global::<Request>().with(|r| r.0.clone())
}

/// The home has shown the request.
pub fn clear() {
    global::<Request>().set(Request(None));
}

/// Opens an already-persisted assistant proposal in the ordinary capture review.
pub fn show_capture(id: String) {
    global::<Request>().set(Request(Some(Opened::Capture(id))));
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Kind {
    Image,
    Statement,
    Other,
}

fn kind(file: &SharedFile) -> Kind {
    if file.mime.to_ascii_lowercase().starts_with("image/") {
        return Kind::Image;
    }
    let extension = Path::new(&file.name)
        .extension()
        .or_else(|| file.path.extension())
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase)
        .unwrap_or_default();
    if STATEMENTS.contains(&extension.as_str()) {
        Kind::Statement
    } else {
        Kind::Other
    }
}

/// Whether `path` names a plain file directly inside the host's folder.
fn inside_folder(path: &Path) -> bool {
    path.is_absolute()
        && path.parent().and_then(Path::file_name) == Some(FOLDER.as_ref())
        && path.file_name().and_then(|n| n.to_str()).is_some_and(|n| {
            !n.starts_with('.')
                && n.chars()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        })
}

/// Reads one copy and removes it: `None` for a path outside the folder, a
/// link, an unreadable file or one over [`MAX_BYTES`].
fn take(path: &Path) -> Option<Vec<u8>> {
    if !inside_folder(path) {
        log::warn!("incoming: refused a path outside the share folder");
        return None;
    }
    let file = std::fs::symlink_metadata(path)
        .ok()
        .filter(|m| m.is_file() && m.len() <= MAX_BYTES);
    let bytes = file.and_then(|_| std::fs::read(path).ok());
    let _ = std::fs::remove_file(path);
    bytes
}

/// Receives one share. The work runs under the app root and ends with a
/// request for the home ([`request`]).
pub fn receive(shared: Shared) {
    tasks::spawn_app(async move {
        let opened = open(shared).await;
        global::<Request>().set(Request(Some(opened)));
    });
}

async fn open(shared: Shared) -> Opened {
    let text: String = shared.text.trim().chars().take(MAX_TEXT).collect();
    let (mut images, mut statements) = (Vec::new(), Vec::new());
    for file in shared.files {
        match kind(&file) {
            Kind::Image if images.len() < MAX_ATTACHMENTS => images.push(file),
            Kind::Statement => statements.push(file),
            // Declined copies are removed too.
            _ => drop(take(&file.path)),
        }
    }
    if images.is_empty() && text.is_empty() {
        return open_statement(statements).await;
    }
    for file in &statements {
        drop(take(&file.path));
    }
    open_capture(text, images).await
}

/// The first statement file opens the review; any others are removed. A
/// review in progress is never replaced.
async fn open_statement(files: Vec<SharedFile>) -> Opened {
    if !files.is_empty() && untracked(statement_import::current).is_some() {
        for file in &files {
            drop(take(&file.path));
        }
        return Opened::StatementBusy;
    }
    let mut opened = Opened::Unsupported;
    for (index, file) in files.into_iter().enumerate() {
        let Some(bytes) = take(&file.path) else {
            continue;
        };
        if index == 0 {
            let name = if file.name.trim().is_empty() {
                file.path
                    .file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .unwrap_or_default()
            } else {
                file.name
            };
            match statement_import::open_file(name, bytes).await {
                Ok(()) => opened = Opened::Statement,
                Err(error) => log::warn!("incoming: statement not read: {error}"),
            }
        }
    }
    opened
}

/// Stages the images as a draft's unsent evidence, prepared exactly like
/// picked ones, with the text as its unsent first message.
async fn open_capture(text: String, images: Vec<SharedFile>) -> Opened {
    let mut draft = capture::new();
    draft.input = text;
    for (serial, file) in images.into_iter().enumerate() {
        let Some(bytes) = take(&file.path) else {
            continue;
        };
        let prepared = blocking(move || photos::prepare_capture(&bytes))
            .await
            .ok()
            .flatten();
        let Some((upload, _)) = prepared else {
            log::warn!("incoming: a shared image could not be prepared");
            continue;
        };
        let extension = if upload.starts_with(b"\x89PNG") {
            "png"
        } else {
            "jpg"
        };
        let name = format!("{}-shared-{serial}.{extension}", draft.id);
        if let Err(failure) = photos::keep(&name, &upload) {
            log::error!("incoming: image could not be kept: {failure}");
            continue;
        }
        if draft.photo.is_none() {
            draft.photo = Some(name.clone());
        }
        draft.attachments.push(name);
    }
    if draft.input.is_empty() && draft.attachments.is_empty() {
        return Opened::Unsupported;
    }
    let id = draft.id.clone();
    match capture::put(draft) {
        Ok(()) => Opened::Capture(id),
        Err(error) => {
            log::error!("incoming: draft not kept: {error}");
            Opened::Unsupported
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_plain_names_directly_inside_the_folder_are_read() {
        let ok = Path::new("/data/user/0/app/files/naviwealth-incoming/3f2a-1.png");
        assert!(inside_folder(ok));
        for refused in [
            "naviwealth-incoming/a.png",
            "/data/files/naviwealth-incoming/../secret.db",
            "/data/files/other/a.png",
            "/data/files/naviwealth-incoming/sub/a.png",
            "/data/files/naviwealth-incoming/.hidden",
            "/data/files/naviwealth-incoming/a b.png",
        ] {
            assert!(!inside_folder(Path::new(refused)), "{refused}");
        }
    }

    #[test]
    fn images_go_by_type_and_statements_by_extension() {
        let file = |name: &str, mime: &str| SharedFile {
            path: PathBuf::from(format!("/x/{FOLDER}/copy")),
            name: name.into(),
            mime: mime.into(),
        };
        assert_eq!(kind(&file("receipt", "image/jpeg")), Kind::Image);
        assert_eq!(kind(&file("alipay.CSV", "text/plain")), Kind::Statement);
        assert_eq!(
            kind(&file("wechat.xlsx", "application/octet-stream")),
            Kind::Statement
        );
        assert_eq!(kind(&file("cmb.txt", "text/plain")), Kind::Statement);
        assert_eq!(kind(&file("bill.pdf", "application/pdf")), Kind::Other);
    }
}
