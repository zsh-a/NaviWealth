//! Local meal and capture images. Re-encoding strips source metadata.
//! Capture keeps a text-preserving PNG or JPEG for subsequent recognition turns.
//! Images stay in the app directory unless explicitly sent or exported.

use std::{
    collections::{HashMap, HashSet},
    io::{self, Write},
    path::PathBuf,
    rc::Rc,
    sync::{
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

use base64::Engine;
use nsh_core::prelude::*;

// A startup sweep must finish before any restore creates new files. If a
// restore wins that race, leave cleanup to the next cold start: its reference
// snapshot may no longer describe the database. Locked only on workers.
static RESTORE_STARTED: Mutex<bool> = Mutex::new(false);

/// Legacy meal preparation uses the shared health core.
pub fn prepare(bytes: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    navi_health::photo::prepare(bytes).ok()
}

/// Capture preparation preserves screenshot and label detail.
pub fn prepare_capture(bytes: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    navi_health::photo::prepare_capture(bytes).ok()
}

/// Image bytes as a `data:` URI an image shows without a request.
pub fn data_uri(jpeg: &[u8]) -> SharedString {
    let mime = if jpeg.starts_with(b"\x89PNG\r\n\x1a\n") {
        "image/png"
    } else {
        "image/jpeg"
    };
    format!(
        "data:{mime};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(jpeg)
    )
    .into()
}

fn folder() -> Option<PathBuf> {
    data_dir().map(|dir| dir.join("meal-photos"))
}

fn path_of(name: &str) -> Option<PathBuf> {
    // Names are the app's own (`<meal id>.jpg`); refuse anything else.
    if crate::domain::backup_bundle::is_photo_name(name) {
        folder().map(|dir| dir.join(name))
    } else {
        None
    }
}

/// Keeps `jpeg` as `name` and shows it at once. A small write, done in
/// place so it is never cut short by the page that asked for it closing.
pub fn keep(name: &str, jpeg: &[u8]) -> Result<(), String> {
    if !crate::domain::backup_bundle::is_photo_name(name) {
        return Err("invalid photo name".into());
    }
    if let Some(path) = path_of(name) {
        let partial = path.with_extension("part");
        let written = path
            .parent()
            .map(std::fs::create_dir_all)
            .transpose()
            .and_then(|_| {
                std::fs::write(&partial, jpeg)?;
                std::fs::rename(&partial, &path)
            });
        if let Err(error) = written {
            let _ = std::fs::remove_file(partial);
            log::error!("photos: could not keep {name}: {error}");
            return Err(error.to_string());
        }
    }
    cache().update(|cache| {
        cache.0.insert(name.to_owned(), data_uri(jpeg));
    });
    Ok(())
}

/// The kept photo `name`'s bytes (a small file, read in place), to send
/// again.
pub fn bytes(name: &str) -> Option<Vec<u8>> {
    path_of(name)
        .and_then(|path| std::fs::read(path).ok())
        .or_else(|| {
            cache().with_untracked(|c| {
                c.0.get(name)
                    .and_then(|uri| {
                        uri.strip_prefix("data:image/jpeg;base64,")
                            .or_else(|| uri.strip_prefix("data:image/png;base64,"))
                    })
                    .and_then(|data| base64::engine::general_purpose::STANDARD.decode(data).ok())
            })
        })
}

/// The kept photos meals and favorites refer to, as names and bytes, for a
/// backup; read off the engine thread. Missing files are left out.
pub async fn read_for_backup() -> Vec<(String, Vec<u8>)> {
    let mut names: Vec<String> = super::meals::photo_names()
        .into_iter()
        .chain(super::favorites::photo_names())
        .collect();
    if let Some(Ok(conversation_names)) = super::db::with(super::assistant_store::photo_names) {
        names.extend(conversation_names);
    }
    names.sort();
    names.dedup();
    let paths: Vec<(String, PathBuf)> = names
        .into_iter()
        .filter_map(|name| path_of(&name).map(|path| (name, path)))
        .collect();
    blocking(move || {
        paths
            .into_iter()
            .filter_map(|(name, path)| std::fs::read(path).ok().map(|bytes| (name, bytes)))
            .collect()
    })
    .await
    .unwrap_or_default()
}

/// New photo files prepared before the database commits. Existing files are
/// never overwritten: collisions receive fresh names in the restored rows.
/// Dropping an uncommitted preparation removes only files it created.
#[derive(Default)]
pub struct RestoredPhotos {
    restored: HashMap<String, String>,
    names: Vec<String>,
    created: Vec<PathBuf>,
    committed: bool,
}

impl RestoredPhotos {
    /// Includes unchanged names so restore can distinguish present and missing images.
    pub fn restored(&self) -> &HashMap<String, String> {
        &self.restored
    }

    /// Called synchronously immediately after the database transaction commits.
    pub fn commit(mut self) {
        self.committed = true;
        cache().update(|cache| {
            for name in &self.names {
                cache.0.remove(name);
            }
        });
    }

    fn write_in(dir: Option<PathBuf>, photos: Vec<(String, Vec<u8>)>) -> io::Result<Self> {
        let mut prepared = Self::default();
        *RESTORE_STARTED
            .lock()
            .map_err(|_| io::Error::other("photo cleanup lock failed"))? = true;
        if photos.is_empty() {
            return Ok(prepared);
        }
        let dir = dir.ok_or_else(|| io::Error::other("photo storage is unavailable"))?;
        let mut seen = HashSet::new();
        if photos.iter().any(|(name, _)| {
            !crate::domain::backup_bundle::is_photo_name(name) || !seen.insert(name)
        }) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "invalid photo names",
            ));
        }
        std::fs::create_dir_all(&dir)?;
        for (original, bytes) in photos {
            let mut name = original.clone();
            loop {
                let path = dir.join(&name);
                match std::fs::OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .open(&path)
                {
                    Ok(mut file) => {
                        // Track the file before writing, so even a partial write is removed.
                        prepared.created.push(path);
                        file.write_all(&bytes)?;
                        file.sync_all()?;
                        break;
                    }
                    Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                        if std::fs::read(&path)? == bytes {
                            break;
                        }
                        let mut random = [0u8; 16];
                        getrandom::fill(&mut random).map_err(io::Error::other)?;
                        name = format!(
                            "restored-{}.jpg",
                            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(random)
                        );
                    }
                    Err(error) => return Err(error),
                }
            }
            prepared.restored.insert(original, name.clone());
            prepared.names.push(name);
        }
        Ok(prepared)
    }
}

impl Drop for RestoredPhotos {
    fn drop(&mut self) {
        if !self.committed {
            for path in &self.created {
                if let Err(error) = std::fs::remove_file(path) {
                    log::error!("photos: could not remove an uncommitted restore file: {error}");
                }
            }
        }
    }
}

/// Prepare all photo bytes off the engine thread. A failed write leaves current
/// records and photos intact; a crash can leave only unreferenced new files.
pub async fn prepare_restore(photos: Vec<(String, Vec<u8>)>) -> io::Result<RestoredPhotos> {
    let dir = folder();
    blocking(move || RestoredPhotos::write_in(dir, photos))
        .await
        .map_err(|_| io::Error::other("photo preparation was interrupted"))?
}

/// Snapshot candidates with the UI's reference inventory, before yielding to
/// another owner action. A delayed worker must never enumerate newer photos.
fn orphan_candidates(
    dir: &std::path::Path,
    referenced: &HashSet<String>,
) -> io::Result<Vec<PathBuf>> {
    let entries = std::fs::read_dir(dir)?.collect::<io::Result<Vec<_>>>()?;
    Ok(entries
        .into_iter()
        .filter(|entry| !referenced.contains(entry.file_name().to_string_lossy().as_ref()))
        .map(|entry| entry.path())
        .collect())
}

fn remove_candidates(candidates: Vec<PathBuf>) {
    for path in candidates {
        let _ = std::fs::remove_file(path);
    }
}

/// Deletes kept photos no meal, favorite or draft refers to (meals deleted
/// earlier, after their Undo window). Only initial candidates are considered;
/// file deletion runs off the engine thread.
pub async fn sweep_orphans() {
    let Some(dir) = folder() else {
        return;
    };
    let mut referenced = super::meals::photo_names();
    referenced.extend(super::favorites::photo_names());
    referenced.extend(super::pending::photo_names());
    referenced.extend(super::capture::photo_names());
    match super::db::with(super::assistant_store::photo_names) {
        Some(Ok(names)) => referenced.extend(names),
        // If any durable reference cannot be read, retaining files is safer
        // than collecting a still-live conversation attachment.
        _ => return,
    }
    let Ok(candidates) = orphan_candidates(&dir, &referenced) else {
        return;
    };
    let _ = blocking(move || {
        let Ok(restoring) = RESTORE_STARTED.lock() else {
            return;
        };
        if *restoring {
            return;
        }
        remove_candidates(candidates);
    })
    .await;
}

#[derive(Clone, Default, PartialEq)]
struct Cache(HashMap<String, SharedString>);

fn cache() -> Signal<Cache> {
    global::<Cache>()
}

/// The kept photo `name` as a URI, once loaded (tracked).
pub fn uri(name: &str) -> Option<SharedString> {
    cache().with(|cache| cache.0.get(name).cloned())
}

/// Loads the kept photos among `names` that are not loaded yet. Await it
/// in a task; reading happens off the engine thread.
pub async fn load(names: Vec<String>) {
    for name in names {
        if cache().with_untracked(|cache| cache.0.contains_key(&name)) {
            continue;
        }
        let Some(path) = path_of(&name) else {
            continue;
        };
        let read = blocking(move || std::fs::read(path)).await;
        if let Ok(Ok(bytes)) = read {
            let uri = data_uri(&bytes);
            cache().update(|cache| {
                cache.0.insert(name, uri);
            });
        }
    }
}

/// Picked photos waiting for the page that prepares them, by capture id.
#[derive(Clone, Default)]
struct Captures(HashMap<u64, Rc<Vec<u8>>>);

impl PartialEq for Captures {
    fn eq(&self, _: &Self) -> bool {
        false
    }
}

fn captures() -> Signal<Captures> {
    global::<Captures>()
}

static NEXT_CAPTURE: AtomicU64 = AtomicU64::new(1);

/// Holds picked `bytes` for the review page and gives its capture id.
pub fn hold(bytes: Vec<u8>) -> u64 {
    let id = NEXT_CAPTURE.fetch_add(1, Ordering::Relaxed);
    captures().update(|held| {
        held.0.insert(id, Rc::new(bytes));
    });
    id
}

/// Takes the picked bytes of capture `id`.
pub fn take(id: u64) -> Option<Rc<Vec<u8>>> {
    let mut taken = None;
    captures().update(|held| taken = held.0.remove(&id));
    taken
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageEncoder, RgbImage, codecs::png::PngEncoder};

    fn png(width: u32, height: u32) -> Vec<u8> {
        let image = RgbImage::from_fn(width, height, |x, y| {
            image::Rgb([(x % 255) as u8, (y % 255) as u8, 90])
        });
        let mut out = Vec::new();
        PngEncoder::new(&mut out)
            .write_image(
                image.as_raw(),
                width,
                height,
                image::ExtendedColorType::Rgb8,
            )
            .unwrap();
        out
    }

    fn size_of(jpeg: &[u8]) -> (u32, u32) {
        let image = image::load_from_memory(jpeg).unwrap();
        (image.width(), image.height())
    }

    #[test]
    fn large_photos_are_scaled_and_become_jpeg() {
        let (upload, keep) = prepare(&png(2000, 1500)).unwrap();
        assert_eq!(&upload[..2], &[0xff, 0xd8]);
        assert_eq!(size_of(&upload), (1280, 960));
        assert_eq!(size_of(&keep), (960, 720));
    }

    #[test]
    fn small_photos_keep_their_size() {
        let (upload, keep) = prepare(&png(400, 300)).unwrap();
        assert_eq!(size_of(&upload), (400, 300));
        assert_eq!(size_of(&keep), (400, 300));
    }

    #[test]
    fn unreadable_bytes_are_refused() {
        assert!(prepare(b"not an image").is_none());
        assert!(prepare(&[]).is_none());
    }

    #[test]
    fn data_uris_carry_png() {
        let bytes = png(16, 16);
        let uri = data_uri(&bytes);
        assert!(uri.starts_with("data:image/png;base64,"));
        let encoded = uri.strip_prefix("data:image/png;base64,").unwrap();
        assert_eq!(
            base64::engine::general_purpose::STANDARD
                .decode(encoded)
                .unwrap(),
            bytes
        );
    }

    #[test]
    fn data_uris_carry_jpeg() {
        assert_eq!(
            data_uri(&[0xff, 0xd8]).as_ref(),
            "data:image/jpeg;base64,/9g="
        );
    }

    #[test]
    fn restore_collisions_keep_existing_bytes_and_reuse_identical_files() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("m1.jpg"), b"existing").unwrap();
        std::fs::write(dir.path().join("same.jpg"), b"same").unwrap();
        let prepared = RestoredPhotos::write_in(
            Some(dir.path().to_owned()),
            vec![
                ("m1.jpg".into(), b"restored".to_vec()),
                ("same.jpg".into(), b"same".to_vec()),
            ],
        )
        .unwrap();
        let renamed = prepared.restored["m1.jpg"].clone();
        assert_ne!(renamed, "m1.jpg");
        assert_eq!(
            std::fs::read(dir.path().join("m1.jpg")).unwrap(),
            b"existing"
        );
        assert_eq!(
            std::fs::read(dir.path().join(&renamed)).unwrap(),
            b"restored"
        );
        assert_eq!(prepared.created.len(), 1);
        assert_eq!(prepared.restored["same.jpg"], "same.jpg");
        drop(prepared); // Database rejected the backup: only new files go away.
        assert!(!dir.path().join(renamed).exists());
        assert_eq!(std::fs::read(dir.path().join("same.jpg")).unwrap(), b"same");
    }

    #[test]
    fn photo_preparation_failure_cleans_earlier_writes_without_touching_existing_files() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::create_dir(dir.path().join("blocked.jpg")).unwrap();
        std::fs::write(dir.path().join("kept.jpg"), b"kept").unwrap();
        assert!(
            RestoredPhotos::write_in(
                Some(dir.path().to_owned()),
                vec![
                    ("new.jpg".into(), b"new".to_vec()),
                    ("blocked.jpg".into(), b"cannot write".to_vec()),
                ],
            )
            .is_err()
        );
        assert!(!dir.path().join("new.jpg").exists());
        assert_eq!(std::fs::read(dir.path().join("kept.jpg")).unwrap(), b"kept");
        assert!(dir.path().join("blocked.jpg").is_dir());
    }

    #[test]
    fn a_delayed_orphan_sweep_never_deletes_photos_created_after_its_snapshot() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("old-orphan.jpg"), b"old").unwrap();
        std::fs::write(dir.path().join("referenced.jpg"), b"kept").unwrap();
        let referenced = HashSet::from(["referenced.jpg".to_owned()]);
        let candidates = orphan_candidates(dir.path(), &referenced).unwrap();
        // A normal capture can keep a new image while the worker is queued.
        std::fs::write(dir.path().join("new-capture.jpg"), b"new").unwrap();
        remove_candidates(candidates);
        assert!(!dir.path().join("old-orphan.jpg").exists());
        assert_eq!(
            std::fs::read(dir.path().join("referenced.jpg")).unwrap(),
            b"kept"
        );
        assert_eq!(
            std::fs::read(dir.path().join("new-capture.jpg")).unwrap(),
            b"new"
        );
    }
}
