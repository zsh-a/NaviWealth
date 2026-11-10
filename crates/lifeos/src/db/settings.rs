//! Small KV helpers over the `settings` table (device-scoped configuration:
//! owner, device id, sync cursor, the local HLC clock, AI profile, ...).

use rusqlite::{Connection, OptionalExtension, params};

use crate::error::Result;

pub fn get_setting(conn: &Connection, key: &str) -> Result<Option<String>> {
    let mut stmt = conn.prepare_cached("SELECT value FROM settings WHERE key = ?1")?;
    Ok(stmt
        .query_row(params![key], |row| row.get::<_, String>(0))
        .optional()?)
}

pub fn set_setting(conn: &Connection, key: &str, value: &str) -> Result<()> {
    conn.execute(
        "INSERT INTO settings (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        params![key, value],
    )?;
    Ok(())
}

pub fn delete_setting(conn: &Connection, key: &str) -> Result<()> {
    conn.execute("DELETE FROM settings WHERE key = ?1", params![key])?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Db;

    #[tokio::test]
    async fn settings_roundtrip() {
        let db = Db::open_in_memory().unwrap();
        db.call_sync(|conn| {
            assert_eq!(get_setting(conn, "k")?, None);
            set_setting(conn, "k", "v1")?;
            set_setting(conn, "k", "v2")?;
            assert_eq!(get_setting(conn, "k")?, Some("v2".to_owned()));
            delete_setting(conn, "k")?;
            assert_eq!(get_setting(conn, "k")?, None);
            Ok(())
        })
        .unwrap();
    }
}
