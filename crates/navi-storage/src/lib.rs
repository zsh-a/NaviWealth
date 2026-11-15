//! Domain-neutral local storage. The composition root supplies the ordered
//! migrations and backup table inventory; domains own row validation and writes.

use std::path::Path;

pub use rusqlite as sqlite;
use sqlite::Connection;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Sql(#[from] sqlite::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("database schema {found} is newer than supported schema {supported}")]
    Newer { found: usize, supported: usize },
}

/// Opens private storage without falling back to an ephemeral database.
pub fn open(path: &Path, migrations: &[&str]) -> Result<Connection, Error> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let mut connection = Connection::open(path)?;
    // Refuse a downgrade before changing journal mode or schema.
    check_version(&connection, migrations.len())?;
    connection.pragma_update(None, "foreign_keys", true)?;
    connection.pragma_update(None, "journal_mode", "WAL")?;
    migrate(&mut connection, migrations)?;
    Ok(connection)
}

pub fn memory(migrations: &[&str]) -> Result<Connection, Error> {
    let mut connection = Connection::open_in_memory()?;
    connection.pragma_update(None, "foreign_keys", true)?;
    migrate(&mut connection, migrations)?;
    Ok(connection)
}

fn check_version(connection: &Connection, supported: usize) -> Result<usize, Error> {
    let found =
        connection.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))? as usize;
    if found > supported {
        return Err(Error::Newer { found, supported });
    }
    Ok(found)
}

/// Runs each unapplied migration transactionally. Shipped migrations are immutable.
pub fn migrate(connection: &mut Connection, migrations: &[&str]) -> Result<(), Error> {
    let done = check_version(connection, migrations.len())?;
    for (index, sql) in migrations.iter().enumerate().skip(done) {
        let tx = connection.transaction()?;
        tx.execute_batch(sql)?;
        tx.pragma_update(None, "user_version", (index + 1) as i64)?;
        tx.commit()?;
    }
    Ok(())
}

/// Copies one consistent SQLite snapshot to a caller-owned fresh scratch path.
pub fn snapshot(connection: &Connection, path: &Path) -> Result<Vec<u8>, Error> {
    connection.execute("VACUUM INTO ?1", [path.to_string_lossy()])?;
    Ok(std::fs::read(path)?)
}

/// Atomically replaces an explicit, trusted table inventory from a validated
/// database. Tables must be ordered parents before children; deletes reverse
/// that order. Names and column lists must be static application constants.
pub fn replace_tables(
    connection: &Connection,
    source: &Path,
    tables: &[(&str, &str)],
) -> Result<(), Error> {
    connection.execute("ATTACH DATABASE ?1 AS restored", [source.to_string_lossy()])?;
    let copied = (|| -> Result<(), Error> {
        let tx = connection.unchecked_transaction()?;
        for (table, _) in tables.iter().rev() {
            tx.execute(&format!("DELETE FROM main.{table}"), [])?;
        }
        for (table, columns) in tables {
            tx.execute(
                &format!(
                    "INSERT INTO main.{table} ({columns}) SELECT {columns} FROM restored.{table}"
                ),
                [],
            )?;
        }
        // This also protects callers whose connections did not enable FKs.
        let violations: i64 =
            tx.query_row("SELECT count(*) FROM pragma_foreign_key_check", [], |r| {
                r.get(0)
            })?;
        if violations != 0 {
            return Err(sqlite::Error::InvalidQuery.into());
        }
        tx.commit()?;
        Ok(())
    })();
    let detached = connection.execute("DETACH DATABASE restored", []);
    copied?;
    detached?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failed_migration_rolls_back_and_newer_databases_are_not_opened() {
        let mut db = memory(&["CREATE TABLE kept (value TEXT);"]).unwrap();
        db.execute("INSERT INTO kept VALUES ('original')", [])
            .unwrap();
        assert!(
            migrate(
                &mut db,
                &[
                    "CREATE TABLE kept (value TEXT);",
                    "CREATE TABLE partial (v); INVALID SQL;"
                ]
            )
            .is_err()
        );
        assert_eq!(
            db.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            1
        );
        assert!(db.prepare("SELECT * FROM partial").is_err());
        assert!(matches!(migrate(&mut db, &[]), Err(Error::Newer { .. })));
        assert_eq!(
            db.query_row("SELECT value FROM kept", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "original"
        );
    }

    #[test]
    fn replacement_rolls_back_all_tables_when_a_child_is_invalid() {
        let migrations = [
            "CREATE TABLE parent (id TEXT PRIMARY KEY); CREATE TABLE child (id TEXT PRIMARY KEY, parent TEXT REFERENCES parent(id));",
        ];
        let db = memory(&migrations).unwrap();
        db.execute_batch(
            "INSERT INTO parent VALUES ('old'); INSERT INTO child VALUES ('old', 'old');",
        )
        .unwrap();
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.sqlite");
        let mut other = Connection::open(&source).unwrap();
        migrate(&mut other, &migrations).unwrap();
        other.execute_batch("PRAGMA foreign_keys=OFF; INSERT INTO parent VALUES ('new'); INSERT INTO child VALUES ('new', 'missing');").unwrap();
        drop(other);
        assert!(
            replace_tables(&db, &source, &[("parent", "id"), ("child", "id, parent")]).is_err()
        );
        assert_eq!(
            db.query_row("SELECT id FROM parent", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "old"
        );
        assert_eq!(
            db.query_row("SELECT id FROM child", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "old"
        );
    }

    #[test]
    fn an_unusable_disk_path_fails_instead_of_opening_memory() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("file");
        std::fs::write(&file, b"not a directory").unwrap();
        assert!(open(&file.join("db.sqlite"), &[]).is_err());
    }
}
