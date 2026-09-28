//! Optional cache backends. Hosts can implement Cache using their existing database.
use crate::{Error, ErrorKind, Result};
use async_trait::async_trait;
use std::{collections::HashMap, sync::Mutex};

#[async_trait]
pub trait Cache: Send + Sync {
    async fn get(&self, key: &str) -> Result<Option<Vec<u8>>>;
    async fn put(&self, key: &str, value: Vec<u8>) -> Result<()>;
}

pub struct MemoryCache {
    capacity: usize,
    entries: Mutex<MemoryEntries>,
}
type MemoryEntries = (u64, HashMap<String, (u64, Vec<u8>)>);
impl MemoryCache {
    pub fn new(capacity: usize) -> Self {
        Self {
            capacity,
            entries: Mutex::new((0, HashMap::new())),
        }
    }
}
impl Default for MemoryCache {
    fn default() -> Self {
        Self::new(1024)
    }
}
#[async_trait]
impl Cache for MemoryCache {
    async fn get(&self, key: &str) -> Result<Option<Vec<u8>>> {
        Ok(self
            .entries
            .lock()
            .unwrap()
            .1
            .get(key)
            .map(|(_, v)| v.clone()))
    }
    async fn put(&self, key: &str, value: Vec<u8>) -> Result<()> {
        if self.capacity == 0 {
            return Ok(());
        }
        if value.len() > 8 * 1024 * 1024 {
            return Err(Error::new(ErrorKind::Cache, "cache entry too large"));
        }
        let mut entries = self.entries.lock().unwrap();
        entries.0 += 1;
        let serial = entries.0;
        entries.1.insert(key.into(), (serial, value));
        if entries.1.len() > self.capacity {
            let oldest = entries
                .1
                .iter()
                .min_by_key(|(_, (serial, _))| serial)
                .map(|(key, _)| key.clone())
                .unwrap();
            entries.1.remove(&oldest);
        }
        Ok(())
    }
}

pub struct NoCache;
#[async_trait]
impl Cache for NoCache {
    async fn get(&self, _: &str) -> Result<Option<Vec<u8>>> {
        Ok(None)
    }
    async fn put(&self, _: &str, _: Vec<u8>) -> Result<()> {
        Ok(())
    }
}

#[cfg(feature = "sqlite")]
pub struct SqliteCache {
    connection: std::sync::Arc<Mutex<rusqlite::Connection>>,
    capacity: usize,
}
#[cfg(feature = "sqlite")]
impl SqliteCache {
    pub fn open(path: impl AsRef<std::path::Path>, capacity: usize) -> Result<Self> {
        let connection = rusqlite::Connection::open(path).map_err(cache_error)?;
        connection
            .busy_timeout(std::time::Duration::from_secs(2))
            .map_err(cache_error)?;
        connection.execute_batch("PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS cache_v1 (key TEXT PRIMARY KEY, value BLOB NOT NULL, updated INTEGER NOT NULL);").map_err(cache_error)?;
        Ok(Self {
            connection: std::sync::Arc::new(Mutex::new(connection)),
            capacity,
        })
    }
}
#[cfg(feature = "sqlite")]
#[async_trait]
impl Cache for SqliteCache {
    async fn get(&self, key: &str) -> Result<Option<Vec<u8>>> {
        use rusqlite::OptionalExtension;
        let connection = self.connection.clone();
        let key = key.to_owned();
        tokio::task::spawn_blocking(move || {
            connection
                .lock()
                .unwrap()
                .query_row("SELECT value FROM cache_v1 WHERE key=?1", [key], |r| {
                    r.get(0)
                })
                .optional()
                .map_err(cache_error)
        })
        .await
        .map_err(cache_error)?
    }
    async fn put(&self, key: &str, value: Vec<u8>) -> Result<()> {
        if value.len() > 8 * 1024 * 1024 {
            return Err(Error::new(ErrorKind::Cache, "cache entry too large"));
        }
        let connection = self.connection.clone();
        let key = key.to_owned();
        let capacity = self.capacity;
        tokio::task::spawn_blocking(move || {
            let mut guard = connection.lock().unwrap();
            let tx = guard.transaction().map_err(cache_error)?;
            tx.execute("INSERT INTO cache_v1(key,value,updated) VALUES(?1,?2,?3) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated=excluded.updated", rusqlite::params![key, value, chrono::Utc::now().timestamp_millis()]).map_err(cache_error)?;
            tx.execute("DELETE FROM cache_v1 WHERE key IN (SELECT key FROM cache_v1 ORDER BY updated DESC,key DESC LIMIT -1 OFFSET ?1)", [capacity as i64]).map_err(cache_error)?;
            tx.commit().map_err(cache_error)
        }).await.map_err(cache_error)?
    }
}
#[cfg(feature = "sqlite")]
fn cache_error(_: impl std::fmt::Display) -> Error {
    Error::new(ErrorKind::Cache, "cache storage operation failed")
}
