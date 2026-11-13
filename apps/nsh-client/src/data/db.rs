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
    // 4: favorites, one JSON body each (`domain::favorite`).
    "CREATE TABLE saved_meals (
        id TEXT PRIMARY KEY NOT NULL,
        saved_at_ms INTEGER NOT NULL,
        used_at_ms INTEGER NOT NULL,
        body TEXT NOT NULL
    );",
    // 5: recognition drafts (`domain::pending`); not in backups.
    "CREATE TABLE meal_drafts (
        id TEXT PRIMARY KEY NOT NULL,
        created_at_ms INTEGER NOT NULL,
        body TEXT NOT NULL
    );",
    // 6: the owner's review notes, one line per day (`data::notes`).
    "CREATE TABLE review_notes (
        day TEXT PRIMARY KEY NOT NULL,
        text TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
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

/// The schema version this app writes: how many migrations exist.
pub const SCHEMA: u32 = MIGRATIONS.len() as u32;

/// What a backup carries and a restore replaces: each table and its columns.
const TABLES: &[(&str, &str)] = &[
    ("meals", "id, day, logged_at_ms, body"),
    ("weights", "day, kg, logged_at_ms"),
    ("garmin_days", "day, body, fetched_at_ms"),
    ("saved_meals", "id, saved_at_ms, used_at_ms, body"),
    ("review_notes", "day, text, updated_at_ms"),
];

/// Why a restore was refused; nothing changed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RestoreError {
    /// The file is not a readable database of this app.
    Unreadable,
    /// It was written by a newer version of the app.
    Newer,
    /// The device could not write.
    Storage,
}

/// A scratch file in the app's data directory (the temp directory without one).
fn scratch(name: &str) -> std::path::PathBuf {
    let dir = data_dir().unwrap_or_else(std::env::temp_dir);
    let _ = std::fs::create_dir_all(&dir);
    dir.join(format!("{name}-{}.sqlite", std::process::id()))
}

fn remove_scratch(path: &Path) {
    for suffix in ["", "-wal", "-shm", "-journal"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", path.display()));
    }
}

/// A consistent copy of the whole database, as file bytes.
pub fn snapshot() -> Result<Vec<u8>, String> {
    let path = scratch("snapshot");
    remove_scratch(&path);
    let copied = with(|c| c.execute("VACUUM INTO ?1", [path.to_string_lossy()]))
        .ok_or("the database is not open")?
        .map_err(|e| e.to_string());
    let bytes = copied.and_then(|_| std::fs::read(&path).map_err(|e| e.to_string()));
    remove_scratch(&path);
    bytes
}

/// Replaces every table's rows with those of the database `file` in one
/// transaction, after checking it (integrity, a schema this app knows) and
/// bringing it to the current schema. On any error nothing changes.
pub fn replace_with(file: &[u8]) -> Result<(), RestoreError> {
    let path = scratch("restore");
    remove_scratch(&path);
    std::fs::write(&path, file).map_err(|_| RestoreError::Storage)?;
    let result = (|| {
        {
            let mut restored = Connection::open(&path).map_err(|_| RestoreError::Unreadable)?;
            restored
                .pragma_update(None, "trusted_schema", false)
                .map_err(|_| RestoreError::Unreadable)?;
            let ok: String = restored
                .query_row("PRAGMA integrity_check", [], |row| row.get(0))
                .map_err(|_| RestoreError::Unreadable)?;
            let version: u32 = restored
                .pragma_query_value(None, "user_version", |row| row.get(0))
                .map_err(|_| RestoreError::Unreadable)?;
            if ok != "ok" || version == 0 {
                return Err(RestoreError::Unreadable);
            }
            if version > SCHEMA {
                return Err(RestoreError::Newer);
            }
            migrate(&mut restored).map_err(|_| RestoreError::Unreadable)?;
            validate_restored(&restored).map_err(|_| RestoreError::Unreadable)?;
        }
        with(|c| -> rusqlite::Result<()> {
            c.execute("ATTACH DATABASE ?1 AS restored", [path.to_string_lossy()])?;
            let copied = (|| {
                let tx = c.unchecked_transaction()?;
                for (table, columns) in TABLES {
                    tx.execute(&format!("DELETE FROM main.{table}"), [])?;
                    tx.execute(
                        &format!(
                            "INSERT INTO main.{table} ({columns}) SELECT {columns} FROM restored.{table}"
                        ),
                        [],
                    )?;
                }
                tx.commit()
            })();
            c.execute("DETACH DATABASE restored", [])?;
            copied
        })
        .ok_or(RestoreError::Storage)?
        .map_err(|error| {
            log::error!("db: restore failed: {error}");
            RestoreError::Unreadable
        })
    })();
    remove_scratch(&path);
    result
}

/// Reject malformed records before replacing anything. Ordinary loading
/// skips bad rows; doing that during restore would silently lose data.
fn validate_restored(connection: &Connection) -> Result<(), String> {
    use crate::domain::{meal::Meal, weight::valid_kg};
    for (table, _) in TABLES {
        let kind: String = connection
            .query_row(
                "SELECT type FROM sqlite_schema WHERE name = ?1",
                [table],
                |row| row.get(0),
            )
            .map_err(|e| e.to_string())?;
        if kind != "table" {
            return Err("expected a table".into());
        }
    }
    let read = || -> rusqlite::Result<()> {
        let mut statement = connection.prepare("SELECT id, day, logged_at_ms, body FROM meals")?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, String>(3)?,
            ))
        })?;
        for row in rows {
            let (id, day, at, body) = row?;
            let meal: Meal =
                serde_json::from_str(&body).map_err(|_| rusqlite::Error::InvalidQuery)?;
            if !meal.is_valid()
                || meal.id != id
                || meal.day.to_string() != day
                || meal.logged_at_ms != at
            {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement = connection.prepare("SELECT day, kg, logged_at_ms FROM weights")?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, f64>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })?;
        for row in rows {
            let (day, kg, _) = row?;
            if day.parse::<crate::domain::meal::Day>().is_err() || !valid_kg(kg) {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement =
            connection.prepare("SELECT day, body, fetched_at_ms FROM garmin_days")?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })?;
        for row in rows {
            let (day, body, _) = row?;
            let value: health_core::garmin::GarminDay =
                serde_json::from_str(&body).map_err(|_| rusqlite::Error::InvalidQuery)?;
            if day.parse::<crate::domain::meal::Day>().is_err() || value.day != day {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement = connection.prepare("SELECT id, body FROM saved_meals")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (id, body) = row?;
            let value: crate::domain::favorite::Favorite =
                serde_json::from_str(&body).map_err(|_| rusqlite::Error::InvalidQuery)?;
            if !value.is_valid() || value.id != id {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement = connection.prepare("SELECT day, text FROM review_notes")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (day, text) = row?;
            if day.parse::<crate::domain::meal::Day>().is_err() || !crate::data::notes::valid(&text)
            {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        Ok(())
    };
    read().map_err(|e| e.to_string())
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

    #[test]
    fn a_restore_checks_favorites_too() {
        let mut connection = Connection::open_in_memory().unwrap();
        migrate(&mut connection).unwrap();
        let food = r#"{"id":1,"name":"Oats","grams":50.0,"per_100g":{"kcal":380.0,"protein":13.0,"carbs":67.0,"fat":7.0},"source":{"kind":"manual"}}"#;
        let body = format!(r#"{{"id":"f1","foods":[{food}],"saved_at_ms":1,"used_at_ms":1}}"#);
        connection
            .execute(
                "INSERT INTO saved_meals (id, saved_at_ms, used_at_ms, body) VALUES ('f1', 1, 1, ?1)",
                [&body],
            )
            .unwrap();
        assert_eq!(validate_restored(&connection), Ok(()));
        connection
            .execute(
                "UPDATE saved_meals SET body = '{\"id\":\"f1\",\"foods\":[],\"saved_at_ms\":1,\"used_at_ms\":1}'",
                [],
            )
            .unwrap();
        assert!(
            validate_restored(&connection).is_err(),
            "a favorite without foods"
        );
    }
}
