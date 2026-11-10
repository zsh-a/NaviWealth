//! The SQLite database: a dedicated worker thread owns the single
//! `rusqlite` connection; callers submit jobs through a channel and get
//! results back (async callers via a tokio oneshot). Business writes and
//! their outbox pointers commit in the same transaction on this thread.

pub mod migrations;
pub mod settings;

use std::path::PathBuf;

use rusqlite::Connection;

use crate::error::{LifeosError, Result};

pub use migrations::{Migration, Migrations};

type DbJob = Box<dyn FnOnce(&mut Connection) + Send + 'static>;

/// Options for opening the database.
pub struct DbOpenOptions {
    /// File path, or `:memory:` for an ephemeral database (tests).
    pub path: PathBuf,
    /// Raw 32-byte SQLCipher master key. `None` opens an unencrypted
    /// database (development only).
    pub encryption_key: Option<Vec<u8>>,
    pub migrations: Migrations,
}

/// A cloneable handle to the database worker thread.
#[derive(Clone)]
pub struct Db {
    tx: std::sync::mpsc::Sender<DbJob>,
}

impl Db {
    /// Open (or create) the database and spawn its worker thread. Blocks
    /// until the connection is ready and migrations have been applied.
    pub fn open(options: DbOpenOptions) -> Result<Self> {
        let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<()>>();
        let (tx, rx) = std::sync::mpsc::channel::<DbJob>();

        std::thread::Builder::new()
            .name("lifeos-db".into())
            .spawn(move || {
                let mut conn = match open_connection(&options) {
                    Ok(conn) => conn,
                    Err(e) => {
                        ready_tx.send(Err(e)).ok();
                        return;
                    }
                };
                if let Err(e) = apply_migrations(&mut conn, &options.migrations) {
                    ready_tx.send(Err(e)).ok();
                    return;
                }
                ready_tx.send(Ok(())).ok();
                for job in rx {
                    job(&mut conn);
                }
            })?;

        ready_rx.recv().map_err(|_| LifeosError::DbClosed)??;

        Ok(Self { tx })
    }

    /// An ephemeral in-memory database (tests, headless UI tests).
    pub fn open_in_memory() -> Result<Self> {
        Self::open(DbOpenOptions {
            path: PathBuf::from(":memory:"),
            encryption_key: None,
            migrations: migrations::core_migrations(),
        })
    }

    /// Submit a job and await its result asynchronously (safe to call from
    /// the nsh engine thread or a tokio worker: the reply is a oneshot).
    pub async fn call<R, F>(&self, job: F) -> Result<R>
    where
        F: FnOnce(&mut Connection) -> Result<R> + Send + 'static,
        R: Send + 'static,
    {
        let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
        self.tx
            .send(Box::new(move |conn: &mut Connection| {
                let _ = reply_tx.send(job(conn));
            }))
            .map_err(|_| LifeosError::DbClosed)?;
        reply_rx.await.map_err(|_| LifeosError::DbClosed)?
    }

    /// Submit a job and block on the reply (tests and synchronous setup).
    pub fn call_sync<R, F>(&self, job: F) -> Result<R>
    where
        F: FnOnce(&mut Connection) -> Result<R> + Send + 'static,
        R: Send + 'static,
    {
        let (reply_tx, reply_rx) = std::sync::mpsc::channel();
        self.tx
            .send(Box::new(move |conn: &mut Connection| {
                let _ = reply_tx.send(job(conn));
            }))
            .map_err(|_| LifeosError::DbClosed)?;
        reply_rx.recv().map_err(|_| LifeosError::DbClosed)?
    }
}

impl std::fmt::Debug for Db {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Db").finish_non_exhaustive()
    }
}

fn open_connection(options: &DbOpenOptions) -> Result<Connection> {
    let conn = Connection::open(&options.path)?;

    // SQLCipher: the key must be the first statement on the connection.
    if let Some(key) = &options.encryption_key {
        if key.len() != 32 {
            return Err(LifeosError::InvalidData(format!(
                "database key must be 32 bytes, got {}",
                key.len()
            )));
        }
        let hex: String = key.iter().map(|b| format!("{b:02x}")).collect();
        conn.pragma_update(None, "key", format!("x'{hex}'"))?;
    }

    conn.query_row("PRAGMA journal_mode=WAL", [], |row| row.get::<_, String>(0))?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.pragma_update(None, "synchronous", "NORMAL")?;
    conn.busy_timeout(std::time::Duration::from_millis(5_000))?;
    Ok(conn)
}

fn apply_migrations(conn: &mut Connection, migrations: &Migrations) -> Result<()> {
    let current: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    for step in migrations.steps().iter().filter(|s| s.version > current) {
        let tx = conn.transaction()?;
        tx.execute_batch(step.sql)?;
        tx.pragma_update(None, "user_version", step.version)?;
        tx.commit()?;
        tracing::debug!(
            version = step.version,
            name = step.name,
            "applied migration"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::settings;

    fn temp_db_path() -> PathBuf {
        std::env::temp_dir().join(format!(
            "lifeos-db-test-{}-{}-{}.db",
            std::process::id(),
            crate::ids::now_millis(),
            uuid::Uuid::new_v4().simple()
        ))
    }

    #[test]
    fn open_applies_migrations_once() {
        let path = temp_db_path();
        let migrations = migrations::core_migrations().push(Migration {
            version: 2,
            name: "extra",
            sql: "CREATE TABLE extra (id TEXT PRIMARY KEY);",
        });
        let db = Db::open(DbOpenOptions {
            path: path.clone(),
            encryption_key: None,
            migrations: migrations.clone(),
        })
        .unwrap();

        db.call_sync(|conn| {
            let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            assert_eq!(version, 2);
            conn.execute("INSERT INTO extra (id) VALUES ('x')", [])?;
            Ok(())
        })
        .unwrap();

        // Re-open: no re-application, data survives.
        let db2 = Db::open(DbOpenOptions {
            path,
            encryption_key: None,
            migrations,
        })
        .unwrap();
        db2.call_sync(|conn| {
            settings::set_setting(conn, "k", "v").unwrap();
            Ok(())
        })
        .unwrap();
        let value = db2
            .call_sync(|conn| settings::get_setting(conn, "k"))
            .unwrap();
        assert_eq!(value, Some("v".to_owned()));
    }

    #[tokio::test]
    async fn async_call_roundtrip() {
        let db = Db::open_in_memory().unwrap();
        let sum: i64 = db
            .call(|conn| Ok(conn.query_row("SELECT 40 + 2", [], |r| r.get(0))?))
            .await
            .unwrap();
        assert_eq!(sum, 42);
    }

    #[test]
    fn sync_call_roundtrip() {
        let db = Db::open_in_memory().unwrap();
        let value: String = db
            .call_sync(|conn| Ok(conn.query_row("SELECT 'ok'", [], |r| r.get(0))?))
            .unwrap();
        assert_eq!(value, "ok");
    }
}
