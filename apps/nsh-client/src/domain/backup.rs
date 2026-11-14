//! The backup file: a [`Bundle`] (the database, and meal photos in backups
//! made by hand) encrypted with a key derived from the user's passphrase.
//! Plain Rust, no I/O.
//!
//! Layout: `NWBK`, a version byte, the header's length (u32 LE), the header
//! (JSON: KDF parameters, salt, nonce, when, schema version), then the
//! ciphertext. Version 2 encrypts a bundle; version 1 files, the database
//! alone, still open. The key is Argon2id(passphrase, salt); the cipher is
//! XChaCha20-Poly1305 with the magic, version and header as associated
//! data, so a changed header fails like a wrong passphrase.

use argon2::{Algorithm, Argon2, Params, Version};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use chacha20poly1305::{
    XChaCha20Poly1305, XNonce,
    aead::{Aead, KeyInit, Payload},
};
use serde::{Deserialize, Serialize};

use super::backup_bundle::{self, Bundle};

const MAGIC: &[u8; 4] = b"NWBK";
const VERSION: u8 = 2;
/// The oldest version still opened.
const OLDEST: u8 = 1;
/// The shortest passphrase accepted.
pub const MIN_PASSPHRASE: usize = 8;
/// The file name extension.
pub const EXTENSION: &str = "nwbk";

/// Argon2id cost: 32 MiB, 3 passes (well above OWASP's minimum).
const MEMORY_KIB: u32 = 32 * 1024;
const PASSES: u32 = 3;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Header {
    pub kdf: String,
    pub memory_kib: u32,
    pub passes: u32,
    pub lanes: u32,
    pub salt: String,
    pub nonce: String,
    pub created_at_ms: i64,
    /// The database's schema version (its migrations count).
    pub schema: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum BackupError {
    #[error("not a NaviWealth backup")]
    NotABackup,
    #[error("a backup from a newer version of the app")]
    Newer,
    #[error("wrong passphrase, or the file was changed")]
    WrongPassphrase,
    #[error("the passphrase is too short")]
    ShortPassphrase,
    #[error("no randomness available")]
    Random,
}

fn cipher(
    passphrase: &str,
    salt: &[u8],
    memory_kib: u32,
    passes: u32,
    lanes: u32,
) -> Result<XChaCha20Poly1305, BackupError> {
    let params =
        Params::new(memory_kib, passes, lanes, Some(32)).map_err(|_| BackupError::NotABackup)?;
    let mut key = [0_u8; 32];
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params)
        .hash_password_into(passphrase.as_bytes(), salt, &mut key)
        .map_err(|_| BackupError::NotABackup)?;
    Ok(XChaCha20Poly1305::new((&key).into()))
}

fn associated(version: u8, header: &[u8]) -> Vec<u8> {
    let mut data = MAGIC.to_vec();
    data.push(version);
    data.extend_from_slice(header);
    data
}

/// Encrypts `bundle` (its database at schema `schema`) with `passphrase`.
pub fn seal(
    bundle: &Bundle,
    passphrase: &str,
    schema: u32,
    now_ms: i64,
) -> Result<Vec<u8>, BackupError> {
    if passphrase.chars().count() < MIN_PASSPHRASE {
        return Err(BackupError::ShortPassphrase);
    }
    let mut salt = [0_u8; 16];
    let mut nonce = [0_u8; 24];
    getrandom::fill(&mut salt).map_err(|_| BackupError::Random)?;
    getrandom::fill(&mut nonce).map_err(|_| BackupError::Random)?;
    let header = Header {
        kdf: "argon2id".into(),
        memory_kib: MEMORY_KIB,
        passes: PASSES,
        lanes: 1,
        salt: B64.encode(salt),
        nonce: B64.encode(nonce),
        created_at_ms: now_ms,
        schema,
    };
    let header_bytes = serde_json::to_vec(&header).map_err(|_| BackupError::NotABackup)?;
    let ciphertext = cipher(passphrase, &salt, MEMORY_KIB, PASSES, 1)?
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: &backup_bundle::pack(bundle),
                aad: &associated(VERSION, &header_bytes),
            },
        )
        .map_err(|_| BackupError::NotABackup)?;
    let mut file = MAGIC.to_vec();
    file.push(VERSION);
    file.extend_from_slice(&(header_bytes.len() as u32).to_le_bytes());
    file.extend_from_slice(&header_bytes);
    file.extend_from_slice(&ciphertext);
    Ok(file)
}

/// The header of a backup file, readable without the passphrase.
pub fn header(file: &[u8]) -> Result<Header, BackupError> {
    split(file).map(|(header, _, _)| header)
}

fn split(file: &[u8]) -> Result<(Header, &[u8], &[u8]), BackupError> {
    if file.len() < 9 || &file[..4] != MAGIC {
        return Err(BackupError::NotABackup);
    }
    if file[4] > VERSION {
        return Err(BackupError::Newer);
    }
    if file[4] < OLDEST {
        return Err(BackupError::NotABackup);
    }
    let len = u32::from_le_bytes(file[5..9].try_into().unwrap_or_default()) as usize;
    let header_bytes = file.get(9..9 + len).ok_or(BackupError::NotABackup)?;
    let header: Header =
        serde_json::from_slice(header_bytes).map_err(|_| BackupError::NotABackup)?;
    if header.kdf != "argon2id" {
        return Err(BackupError::NotABackup);
    }
    Ok((header, header_bytes, &file[9 + len..]))
}

/// The bundle in `file`, decrypted with `passphrase` (a version 1 file
/// holds the database alone).
pub fn open(file: &[u8], passphrase: &str) -> Result<(Header, Bundle), BackupError> {
    let (header, header_bytes, ciphertext) = split(file)?;
    // A forged header must not make the device spend unbounded memory.
    if header.memory_kib > 256 * 1024 || header.passes > 10 || header.lanes > 4 {
        return Err(BackupError::NotABackup);
    }
    let salt = B64
        .decode(&header.salt)
        .map_err(|_| BackupError::NotABackup)?;
    let nonce = B64
        .decode(&header.nonce)
        .map_err(|_| BackupError::NotABackup)?;
    if nonce.len() != 24 {
        return Err(BackupError::NotABackup);
    }
    let plain = cipher(
        passphrase,
        &salt,
        header.memory_kib,
        header.passes,
        header.lanes,
    )?
    .decrypt(
        XNonce::from_slice(&nonce),
        Payload {
            msg: ciphertext,
            aad: &associated(file[4], header_bytes),
        },
    )
    .map_err(|_| BackupError::WrongPassphrase)?;
    let bundle = if file[4] == 1 {
        Bundle {
            database: plain,
            photos: Vec::new(),
        }
    } else {
        backup_bundle::unpack(&plain)?
    };
    Ok((header, bundle))
}

/// A new name per snapshot; another install must never overwrite a backup.
/// A backup with photos says so in its name, for the restore list.
pub fn file_name(day: &str, now_ms: i64, with_photos: bool) -> String {
    let photos = if with_photos { "-photos" } else { "" };
    format!("naviwealth-{day}-{now_ms:013}{photos}.{EXTENSION}")
}

/// When the backup named `name` was made (milliseconds), from its name.
pub fn created_ms(name: &str) -> Option<i64> {
    let stem = name.strip_suffix(&format!(".{EXTENSION}"))?;
    let stem = stem.strip_suffix("-photos").unwrap_or(stem);
    let stamp = stem.rsplit('-').next()?;
    // `file_name` writes 13 digits; anything else is not a timestamp.
    (stamp.len() == 13).then(|| stamp.parse().ok()).flatten()
}

/// Whether the backup named `name` holds photos.
pub fn has_photos(name: &str) -> bool {
    name.ends_with(&format!("-photos.{EXTENSION}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db(bytes: &[u8]) -> Bundle {
        Bundle {
            database: bytes.to_vec(),
            photos: Vec::new(),
        }
    }

    #[test]
    fn a_backup_opens_only_with_its_passphrase() {
        let bundle = Bundle {
            database: b"SQLite format 3\0rows".to_vec(),
            photos: vec![("m1.jpg".into(), vec![0xff, 0xd8])],
        };
        let sealed = seal(&bundle, "correct horse", 3, 42).unwrap();
        let (header, opened) = open(&sealed, "correct horse").unwrap();
        assert_eq!(opened, bundle);
        assert_eq!((header.schema, header.created_at_ms), (3, 42));
        assert_eq!(
            open(&sealed, "wrong horse!"),
            Err(BackupError::WrongPassphrase)
        );
        // Each seal has its own salt and nonce.
        assert_ne!(
            seal(&db(b"x"), "correct horse", 3, 42).unwrap(),
            seal(&db(b"x"), "correct horse", 3, 42).unwrap()
        );
    }

    #[test]
    fn changed_or_foreign_files_are_refused() {
        let sealed = seal(&db(b"db"), "correct horse", 3, 1).unwrap();
        let mut tampered = sealed.clone();
        // The header is authenticated: change its timestamp digit.
        let at = tampered.windows(4).position(|w| w == b"\":1,").unwrap() + 2;
        tampered[at] = b'2';
        assert_eq!(
            open(&tampered, "correct horse"),
            Err(BackupError::WrongPassphrase)
        );
        let last = tampered.len() - 1;
        let mut flipped = sealed.clone();
        flipped[last] ^= 1;
        assert_eq!(
            open(&flipped, "correct horse"),
            Err(BackupError::WrongPassphrase)
        );
        assert_eq!(open(b"PK\x03\x04zip", "x"), Err(BackupError::NotABackup));
        let mut newer = sealed;
        newer[4] = 9;
        assert_eq!(header(&newer), Err(BackupError::Newer));
        assert_eq!(
            seal(&db(b"db"), "short", 3, 1),
            Err(BackupError::ShortPassphrase)
        );
        assert_eq!(
            file_name("2026-11-13", 1794564000000, false),
            "naviwealth-2026-11-13-1794564000000.nwbk"
        );
        let named = file_name("2026-11-13", 1794564000000, true);
        assert_eq!(named, "naviwealth-2026-11-13-1794564000000-photos.nwbk");
        assert!(has_photos(&named) && !has_photos("naviwealth-2026-11-13-1.nwbk"));
        assert_eq!(created_ms(&named), Some(1794564000000));
        assert_eq!(
            created_ms("naviwealth-2026-11-13-0000000000042.nwbk"),
            Some(42)
        );
        assert_eq!(created_ms("notes.txt"), None);
        assert_eq!(created_ms("naviwealth-2026-11-13.nwbk"), None);
    }

    #[test]
    fn a_version_one_backup_still_opens_as_its_database() {
        // Seal the old way: the database alone, version byte 1.
        let mut sealed = seal(&db(b"x"), "correct horse", 3, 7).unwrap();
        let (header, _, _) = split(&sealed).unwrap();
        let header_bytes = serde_json::to_vec(&header).unwrap();
        let salt = B64.decode(&header.salt).unwrap();
        let nonce = B64.decode(&header.nonce).unwrap();
        let ciphertext = cipher("correct horse", &salt, header.memory_kib, header.passes, 1)
            .unwrap()
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: b"old database",
                    aad: &associated(1, &header_bytes),
                },
            )
            .unwrap();
        sealed.truncate(9 + header_bytes.len());
        sealed[4] = 1;
        sealed.extend_from_slice(&ciphertext);
        let (_, opened) = open(&sealed, "correct horse").unwrap();
        assert_eq!(opened, db(b"old database"));
    }
}
