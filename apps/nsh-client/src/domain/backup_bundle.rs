//! What a backup holds before it is encrypted: the database and, for
//! backups made by hand, the meal photos. Plain Rust, no I/O.
//!
//! Layout: `NWBD`, the database's length (u32 LE) and bytes, the photo
//! count (u32 LE), then per photo its name's length (u16 LE), the name
//! (UTF-8) and the photo's length (u32 LE) and bytes.

use super::backup::BackupError;

const MAGIC: &[u8; 4] = b"NWBD";
/// The longest photo name kept (the app's own names are far shorter).
const MAX_NAME: usize = 128;

/// A backup's content.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Bundle {
    pub database: Vec<u8>,
    /// Photo file names and their JPEG bytes.
    pub photos: Vec<(String, Vec<u8>)>,
}

/// Whether `name` is one of the app's photo names: letters, digits, `-`,
/// `_` and `.`, not leading with a dot (never a path).
pub fn is_photo_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= MAX_NAME
        && !name.starts_with('.')
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
}

/// `bundle` as bytes; photos with names that are not the app's are left out.
pub fn pack(bundle: &Bundle) -> Vec<u8> {
    let photos: Vec<_> = bundle
        .photos
        .iter()
        .filter(|(name, _)| is_photo_name(name))
        .collect();
    let size = 12
        + bundle.database.len()
        + photos
            .iter()
            .map(|(n, b)| 6 + n.len() + b.len())
            .sum::<usize>();
    let mut out = Vec::with_capacity(size);
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&(bundle.database.len() as u32).to_le_bytes());
    out.extend_from_slice(&bundle.database);
    out.extend_from_slice(&(photos.len() as u32).to_le_bytes());
    for (name, bytes) in photos {
        out.extend_from_slice(&(name.len() as u16).to_le_bytes());
        out.extend_from_slice(name.as_bytes());
        out.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
        out.extend_from_slice(bytes);
    }
    out
}

/// The bundle in `bytes`; anything truncated, oversized or named unlike the
/// app's photos is refused.
pub fn unpack(bytes: &[u8]) -> Result<Bundle, BackupError> {
    let mut at: usize = 0;
    let mut take = |len: usize| -> Result<&[u8], BackupError> {
        let end = at.checked_add(len).ok_or(BackupError::NotABackup)?;
        let slice = bytes.get(at..end).ok_or(BackupError::NotABackup)?;
        at = end;
        Ok(slice)
    };
    if take(4)? != MAGIC {
        return Err(BackupError::NotABackup);
    }
    let u32_of = |b: &[u8]| u32::from_le_bytes(b.try_into().unwrap_or_default()) as usize;
    let db_len = u32_of(take(4)?);
    let database = take(db_len)?.to_vec();
    let count = u32_of(take(4)?);
    let mut photos = Vec::new();
    for _ in 0..count {
        let name_len = u16::from_le_bytes(take(2)?.try_into().unwrap_or_default()) as usize;
        let name = std::str::from_utf8(take(name_len)?)
            .map_err(|_| BackupError::NotABackup)?
            .to_owned();
        if !is_photo_name(&name) {
            return Err(BackupError::NotABackup);
        }
        let len = u32_of(take(4)?);
        photos.push((name, take(len)?.to_vec()));
    }
    if take(1).is_ok() {
        return Err(BackupError::NotABackup);
    }
    Ok(Bundle { database, photos })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bundle() -> Bundle {
        Bundle {
            database: b"SQLite format 3\0rows".to_vec(),
            photos: vec![
                ("m1.jpg".into(), vec![0xff, 0xd8, 1, 2]),
                ("d42.jpg".into(), vec![0xff, 0xd8]),
            ],
        }
    }

    #[test]
    fn a_bundle_round_trips() {
        assert_eq!(unpack(&pack(&bundle())), Ok(bundle()));
        let empty = Bundle {
            database: b"db".to_vec(),
            photos: Vec::new(),
        };
        assert_eq!(unpack(&pack(&empty)), Ok(empty));
    }

    #[test]
    fn foreign_names_and_damaged_bytes_are_refused() {
        let mut odd = bundle();
        odd.photos.push(("../escape.jpg".into(), vec![1]));
        assert_eq!(unpack(&pack(&odd)), Ok(bundle()), "never packed");
        let packed = pack(&bundle());
        assert_eq!(
            unpack(&packed[..packed.len() - 1]),
            Err(BackupError::NotABackup)
        );
        let mut longer = packed.clone();
        longer.push(0);
        assert_eq!(unpack(&longer), Err(BackupError::NotABackup));
        assert_eq!(unpack(b"NWBK"), Err(BackupError::NotABackup));
        // A name smuggled past `pack` is refused on the way in.
        let mut forged = packed;
        let at = forged.windows(6).position(|w| w == b"m1.jpg").unwrap();
        forged[at..at + 2].copy_from_slice(b"..");
        assert_eq!(unpack(&forged), Err(BackupError::NotABackup));
        assert!(!is_photo_name(".hidden") && !is_photo_name("a/b.jpg"));
    }
}
