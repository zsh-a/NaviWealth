//! Meal photos. A picked photo becomes one upright JPEG of at most 1280 px
//! to send (re-encoding drops EXIF and GPS metadata) and a smaller one to
//! keep. Kept photos live only in the app's data directory: they are never
//! synced or uploaded again.

use std::{
    collections::HashMap,
    path::PathBuf,
    rc::Rc,
    sync::atomic::{AtomicU64, Ordering},
};

use base64::Engine;
use nsh_core::prelude::*;

/// Image decoding, orientation and metadata stripping are shared with Flutter.
pub fn prepare(bytes: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    health_core::photo::prepare(bytes).ok()
}

/// `jpeg` as a `data:` URI an image shows without a request.
pub fn data_uri(jpeg: &[u8]) -> SharedString {
    format!(
        "data:image/jpeg;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(jpeg)
    )
    .into()
}

fn folder() -> Option<PathBuf> {
    data_dir().map(|dir| dir.join("meal-photos"))
}

fn path_of(name: &str) -> Option<PathBuf> {
    // Names are the app's own (`<meal id>.jpg`); refuse anything else.
    let safe = !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        && !name.starts_with('.');
    if safe {
        folder().map(|dir| dir.join(name))
    } else {
        None
    }
}

/// Keeps `jpeg` as `name` and shows it at once. A small write, done in
/// place so it is never cut short by the page that asked for it closing.
pub fn keep(name: &str, jpeg: &[u8]) {
    cache().update(|cache| {
        cache.0.insert(name.to_owned(), data_uri(jpeg));
    });
    let Some(path) = path_of(name) else {
        return;
    };
    let written = path
        .parent()
        .map(std::fs::create_dir_all)
        .transpose()
        .and_then(|_| {
            let partial = path.with_extension("part");
            std::fs::write(&partial, jpeg)?;
            std::fs::rename(&partial, &path)
        });
    if let Err(error) = written {
        log::error!("photos: could not keep {name}: {error}");
    }
}

/// Deletes the kept photo `name`.
pub fn delete(name: &str) {
    cache().update(|cache| {
        cache.0.remove(name);
    });
    if let Some(path) = path_of(name)
        && let Err(error) = std::fs::remove_file(&path)
        && error.kind() != std::io::ErrorKind::NotFound
    {
        log::warn!("photos: could not delete {name}: {error}");
    }
}

/// Deletes kept photos no meal refers to (meals deleted earlier, after
/// their Undo window). Runs off the engine thread.
pub async fn sweep_orphans() {
    let Some(dir) = folder() else {
        return;
    };
    let referenced = super::meals::photo_names();
    let _ = blocking(move || {
        let Ok(entries) = std::fs::read_dir(&dir) else {
            return;
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !referenced.contains(&name) {
                let _ = std::fs::remove_file(entry.path());
            }
        }
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
    fn data_uris_carry_jpeg() {
        assert_eq!(
            data_uri(&[0xff, 0xd8]).as_ref(),
            "data:image/jpeg;base64,/9g="
        );
    }
}
