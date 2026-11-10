//! The outbox: dirty-row pointers. The engine dedupes to one `RowChange`
//! per `(table, row_id)` and re-reads the current row state at push time,
//! so enqueue is fire-and-forget inside the business transaction.

use rusqlite::{Connection, params};

use crate::error::Result;
use crate::ids;

pub fn enqueue(conn: &Connection, table: &str, row_id: &str) -> Result<()> {
    conn.execute(
        "INSERT OR IGNORE INTO op_outbox (table_name, row_id, created_at) VALUES (?1, ?2, ?3)",
        params![table, row_id, ids::now_millis()],
    )?;
    Ok(())
}

pub fn enqueue_many(conn: &Connection, table: &str, row_ids: &[String]) -> Result<()> {
    for row_id in row_ids {
        enqueue(conn, table, row_id)?;
    }
    Ok(())
}

/// Up to `limit` dirty pointers in FIFO order.
pub fn pending(conn: &Connection, limit: usize) -> Result<Vec<(String, String)>> {
    let mut stmt = conn.prepare_cached(
        "SELECT table_name, row_id FROM op_outbox ORDER BY created_at, table_name, row_id LIMIT ?1",
    )?;
    let rows = stmt.query_map(params![limit as i64], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// Clear pointers the server accepted.
pub fn clear(conn: &Connection, acks: &[(String, String)]) -> Result<usize> {
    let mut cleared = 0;
    for (table, row_id) in acks {
        cleared += conn.execute(
            "DELETE FROM op_outbox WHERE table_name = ?1 AND row_id = ?2",
            params![table, row_id],
        )?;
    }
    Ok(cleared)
}

/// Clear every pointer of one table (domain reset, backup restore).
pub fn clear_table(conn: &Connection, table: &str) -> Result<usize> {
    Ok(conn.execute(
        "DELETE FROM op_outbox WHERE table_name = ?1",
        params![table],
    )?)
}

pub fn count(conn: &Connection) -> Result<i64> {
    Ok(conn.query_row("SELECT COUNT(*) FROM op_outbox", [], |r| r.get(0))?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Db;

    #[tokio::test]
    async fn outbox_dedupes_and_clears() {
        let db = Db::open_in_memory().unwrap();
        db.call_sync(|conn| {
            enqueue(conn, "fin:accounts", "a1")?;
            enqueue(conn, "fin:accounts", "a1")?; // dedupe
            enqueue(conn, "fin:accounts", "a2")?;
            enqueue(conn, "fin:journal_entries", "j1")?;
            assert_eq!(count(conn)?, 3);

            let pending = pending(conn, 2)?;
            assert_eq!(pending.len(), 2);

            clear(conn, &[("fin:accounts".into(), "a1".into())])?;
            assert_eq!(count(conn)?, 2);

            clear_table(conn, "fin:accounts")?;
            assert_eq!(count(conn)?, 1);
            Ok(())
        })
        .unwrap();
    }
}
