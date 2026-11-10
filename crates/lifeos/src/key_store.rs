//! Secure key storage seam. On iOS/Android the platform crate provides a
//! Keychain / Android Keystore implementation; desktops and tests use the
//! file/memory fallbacks here.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

use crate::error::{LifeosError, Result};

/// Stores small binary secrets (e.g. the SQLCipher master key) by id.
pub trait KeyStore: Send + Sync {
    fn get_key(&self, id: &str) -> Result<Option<Vec<u8>>>;
    fn set_key(&self, id: &str, key: &[u8]) -> Result<()>;
    fn delete_key(&self, id: &str) -> Result<()>;
}

/// In-memory store for tests.
#[derive(Default)]
pub struct MemoryKeyStore {
    entries: Mutex<HashMap<String, Vec<u8>>>,
}

impl MemoryKeyStore {
    pub fn new() -> Self {
        Self::default()
    }
}

impl KeyStore for MemoryKeyStore {
    fn get_key(&self, id: &str) -> Result<Option<Vec<u8>>> {
        Ok(self.entries.lock().unwrap().get(id).cloned())
    }

    fn set_key(&self, id: &str, key: &[u8]) -> Result<()> {
        self.entries
            .lock()
            .unwrap()
            .insert(id.to_owned(), key.to_vec());
        Ok(())
    }

    fn delete_key(&self, id: &str) -> Result<()> {
        self.entries.lock().unwrap().remove(id);
        Ok(())
    }
}

/// Desktop fallback: one hex file per key under a private directory.
pub struct FileKeyStore {
    dir: PathBuf,
}

impl FileKeyStore {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    fn path(&self, id: &str) -> PathBuf {
        // Ids are dotted literals (`naviwealth.database.master_key.v2`);
        // keep them filesystem-safe.
        self.dir
            .join(format!("{}.key", id.replace(['/', ':'], "_")))
    }
}

impl KeyStore for FileKeyStore {
    fn get_key(&self, id: &str) -> Result<Option<Vec<u8>>> {
        let path = self.path(id);
        if !path.exists() {
            return Ok(None);
        }
        let text = std::fs::read_to_string(&path)?;
        let hex = text.trim();
        let bytes = hex::decode(hex)
            .map_err(|e| LifeosError::KeyStore(format!("corrupt key file {id}: {e}")))?;
        Ok(Some(bytes))
    }

    fn set_key(&self, id: &str, key: &[u8]) -> Result<()> {
        std::fs::create_dir_all(&self.dir)?;
        let path = self.path(id);
        let hex: String = key.iter().map(|b| format!("{b:02x}")).collect();
        std::fs::write(&path, hex)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(&path)?.permissions();
            perms.set_mode(0o600);
            std::fs::set_permissions(&path, perms)?;
        }
        Ok(())
    }

    fn delete_key(&self, id: &str) -> Result<()> {
        let path = self.path(id);
        if path.exists() {
            std::fs::remove_file(&path)?;
        }
        Ok(())
    }
}

// Minimal hex helpers (avoid an extra dependency for two call sites).
mod hex {
    pub fn decode(s: &str) -> std::result::Result<Vec<u8>, String> {
        if !s.len().is_multiple_of(2) {
            return Err("odd length".to_owned());
        }
        (0..s.len() / 2)
            .map(|i| u8::from_str_radix(&s[2 * i..2 * i + 2], 16).map_err(|e| e.to_string()))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_key_store_roundtrip() {
        let dir = std::env::temp_dir().join(format!(
            "lifeos-keys-{}-{}",
            std::process::id(),
            crate::ids::now_millis()
        ));
        let store = FileKeyStore::new(&dir);
        let key = [7u8; 32];
        assert!(store.get_key("test.key").unwrap().is_none());
        store.set_key("test.key", &key).unwrap();
        assert_eq!(store.get_key("test.key").unwrap().unwrap(), key);
        store.delete_key("test.key").unwrap();
        assert!(store.get_key("test.key").unwrap().is_none());
    }
}
