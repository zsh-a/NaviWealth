//! The app's SQLite database, `naviwealth.sqlite` in its data directory.
//! The file sits in the app's private storage, which Android encrypts at
//! rest; the database itself is not encrypted (ADR 0002). Hosts that keep
//! no files for the app (headless tests without a data directory) get an
//! in-memory database instead.
//!
//! Schema changes are appended to [`MIGRATIONS`]; `PRAGMA user_version`
//! records how many have run, and each runs in its own transaction.

use std::{path::Path, rc::Rc};

use nsh_core::prelude::*;
use rusqlite::Connection;

const FILE: &str = "naviwealth.sqlite";

/// Every schema change, in order. Never edit one that has shipped.
const MIGRATIONS: &[&str] = &[
    // 1: confirmed meals, one JSON body per meal (`domain::meal`).
    "CREATE TABLE meals (
        id TEXT PRIMARY KEY NOT NULL,
        day TEXT NOT NULL,
        logged_at_ms INTEGER NOT NULL,
        body TEXT NOT NULL
    );
    CREATE INDEX meals_by_day ON meals (day, logged_at_ms);",
    // 2: body weight, one entry per day (`domain::weight`).
    "CREATE TABLE weights (
        day TEXT PRIMARY KEY NOT NULL,
        kg REAL NOT NULL,
        logged_at_ms INTEGER NOT NULL
    );",
    // 3: Garmin daily summaries, one JSON body per day (`health_core::garmin`).
    "CREATE TABLE garmin_days (
        day TEXT PRIMARY KEY NOT NULL,
        body TEXT NOT NULL,
        fetched_at_ms INTEGER NOT NULL
    );",
];

#[derive(Clone, Default)]
struct Db(Option<Rc<Connection>>);

impl PartialEq for Db {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (Some(a), Some(b)) => Rc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        }
    }
}

fn db() -> Signal<Db> {
    global::<Db>()
}

/// Opens the database once per app; the root calls it before loading.
pub fn open() {
    if db().with_untracked(|db| db.0.is_some()) {
        return;
    }
    let connection = match data_dir() {
        Some(dir) => open_file(&dir).unwrap_or_else(|error| {
            log::error!("db: cannot open {FILE} ({error}); changes will not be kept");
            in_memory()
        }),
        None => in_memory(),
    };
    db().set(Db(Some(Rc::new(connection))));
}

fn open_file(dir: &Path) -> rusqlite::Result<Connection> {
    if let Err(error) = std::fs::create_dir_all(dir) {
        log::warn!("db: cannot create the data directory: {error}");
    }
    let mut connection = Connection::open(dir.join(FILE))?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    migrate(&mut connection)?;
    Ok(connection)
}

fn in_memory() -> Connection {
    let mut connection = Connection::open_in_memory().expect("SQLite opens in memory");
    migrate(&mut connection).expect("the schema applies to an empty database");
    connection
}

/// Runs the migrations `connection` has not run yet.
fn migrate(connection: &mut Connection) -> rusqlite::Result<()> {
    let done: usize = connection.pragma_query_value(None, "user_version", |row| row.get(0))?;
    for (index, sql) in MIGRATIONS.iter().enumerate().skip(done) {
        let tx = connection.transaction()?;
        tx.execute_batch(sql)?;
        tx.pragma_update(None, "user_version", index + 1)?;
        tx.commit()?;
    }
    Ok(())
}

/// Runs `f` on the open database; `None` before [`open`].
pub fn with<R>(f: impl FnOnce(&Connection) -> R) -> Option<R> {
    let connection = db().with_untracked(|db| db.0.clone())?;
    Some(f(&connection))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_run_once_and_record_the_version() {
        let mut connection = Connection::open_in_memory().unwrap();
        migrate(&mut connection).unwrap();
        migrate(&mut connection).unwrap();
        let version: usize = connection
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, MIGRATIONS.len());
        connection
            .execute(
                "INSERT INTO meals (id, day, logged_at_ms, body) VALUES ('a', '2026-11-13', 1, '{}')",
                [],
            )
            .unwrap();
    }

    #[test]
    fn a_file_database_keeps_rows_across_opens() {
        let dir = tempfile::tempdir().unwrap();
        open_file(dir.path())
            .unwrap()
            .execute(
                "INSERT INTO meals (id, day, logged_at_ms, body) VALUES ('a', '2026-11-13', 1, '{}')",
                [],
            )
            .unwrap();
        let count: i64 = open_file(dir.path())
            .unwrap()
            .query_row("SELECT COUNT(*) FROM meals", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }
}
