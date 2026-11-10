//! The seam between the domain-neutral sync engine and domain tables.
//! Domain crates register one [`TableAdapter`] per syncable row family; a
//! spec-driven [`SqlTableAdapter`] covers the common case (every column
//! round-trips as JSON, money as decimal strings, no REAL columns ever).

use rusqlite::{Connection, ToSql};

use crate::error::{Domain, LifeosError, Result};

/// A syncable row family.
pub trait TableAdapter: Send + Sync {
    /// Full table name at the sync boundary, e.g. `fin:accounts`.
    fn table(&self) -> &'static str;
    fn domain(&self) -> Domain;
    /// All columns, in DDL order; the first must be the primary key `id`.
    fn columns(&self) -> &'static [&'static str];

    /// Read the full row (including sync columns) as a JSON object, or
    /// `None` when the row does not exist.
    fn read_row(&self, conn: &Connection, id: &str) -> Result<Option<serde_json::Value>>;

    /// Upsert the full row from a payload. The payload must carry every
    /// column, including `hlc`, `owner_user_id`, `deleted_at`.
    fn apply_upsert(&self, conn: &Connection, payload: &serde_json::Value) -> Result<()>;

    /// Mark a known row deleted (LWW winner is a tombstone). Unknown rows
    /// are skipped: a delete never needs conflict protection against a
    /// later create, and skip keeps adapters free of per-table defaults.
    fn apply_tombstone(
        &self,
        conn: &Connection,
        id: &str,
        version: &str,
        device_id: &str,
    ) -> Result<()>;

    /// Every row as a JSON object (backup export).
    fn read_all(&self, conn: &Connection) -> Result<Vec<serde_json::Value>>;

    /// Delete every row (backup restore / domain reset).
    fn delete_all(&self, conn: &Connection) -> Result<usize>;
}

/// Spec-driven adapter over a plain table: all columns are JSON round-trip
/// (TEXT ↔ string, INTEGER ↔ number, no REAL).
#[derive(Debug, Clone)]
pub struct SqlTableAdapter {
    table: &'static str,
    domain: Domain,
    columns: &'static [&'static str],
}

impl SqlTableAdapter {
    pub fn new(table: &'static str, domain: Domain, columns: &'static [&'static str]) -> Self {
        Self {
            table,
            domain,
            columns,
        }
    }

    fn column_values(&self, payload: &serde_json::Value) -> Result<Vec<rusqlite::types::Value>> {
        let map = payload
            .as_object()
            .ok_or_else(|| LifeosError::InvalidData("row payload must be an object".into()))?;
        self.columns
            .iter()
            .map(|col| {
                let value = map.get(*col).ok_or_else(|| {
                    LifeosError::InvalidData(format!("row payload missing column {col:?}"))
                })?;
                json_to_sql(value).map_err(|e| LifeosError::InvalidData(format!("{col:?}: {e}")))
            })
            .collect()
    }
}

impl TableAdapter for SqlTableAdapter {
    fn table(&self) -> &'static str {
        self.table
    }

    fn domain(&self) -> Domain {
        self.domain
    }

    fn columns(&self) -> &'static [&'static str] {
        self.columns
    }

    fn read_row(&self, conn: &Connection, id: &str) -> Result<Option<serde_json::Value>> {
        let sql = format!(
            "SELECT {} FROM \"{}\" WHERE id = ?1",
            self.columns.join(", "),
            self.table
        );
        let mut stmt = conn.prepare_cached(&sql)?;
        let mut rows = stmt.query(rusqlite::params![id])?;
        let Some(row) = rows.next()? else {
            return Ok(None);
        };
        let mut map = serde_json::Map::new();
        for (index, col) in self.columns.iter().enumerate() {
            map.insert((*col).to_owned(), sql_to_json(row.get_ref(index)?)?);
        }
        Ok(Some(serde_json::Value::Object(map)))
    }

    fn apply_upsert(&self, conn: &Connection, payload: &serde_json::Value) -> Result<()> {
        let values = self.column_values(payload)?;
        let sql = format!(
            "INSERT OR REPLACE INTO \"{}\" ({}) VALUES ({})",
            self.table,
            self.columns.join(", "),
            vec!["?"; self.columns.len()].join(", ")
        );
        let params: Vec<&dyn ToSql> = values.iter().map(|v| v as &dyn ToSql).collect();
        conn.execute(&sql, params.as_slice())?;
        Ok(())
    }

    fn apply_tombstone(
        &self,
        conn: &Connection,
        id: &str,
        version: &str,
        device_id: &str,
    ) -> Result<()> {
        let sql = format!(
            "UPDATE \"{}\" SET deleted_at = COALESCE(deleted_at, ?1), hlc = ?2, updated_by_device = ?3 WHERE id = ?4",
            self.table
        );
        let updated = conn.execute(
            &sql,
            rusqlite::params![crate::ids::now_secs(), version, device_id, id],
        )?;
        if updated == 0 {
            tracing::debug!(table = self.table, id, "tombstone for unknown row skipped");
        }
        Ok(())
    }

    fn read_all(&self, conn: &Connection) -> Result<Vec<serde_json::Value>> {
        let sql = format!("SELECT {} FROM \"{}\"", self.columns.join(", "), self.table);
        let mut stmt = conn.prepare_cached(&sql)?;
        let mut rows = stmt.query([])?;
        let mut out = Vec::new();
        while let Some(row) = rows.next()? {
            let mut map = serde_json::Map::new();
            for (index, col) in self.columns.iter().enumerate() {
                map.insert((*col).to_owned(), sql_to_json(row.get_ref(index)?)?);
            }
            out.push(serde_json::Value::Object(map));
        }
        Ok(out)
    }

    fn delete_all(&self, conn: &Connection) -> Result<usize> {
        let sql = format!(r#"DELETE FROM "{}""#, self.table);
        Ok(conn.execute(&sql, [])?)
    }
}

/// REAL columns are forbidden (money is TEXT); blobs are not used.
fn sql_to_json(value: rusqlite::types::ValueRef<'_>) -> Result<serde_json::Value> {
    use rusqlite::types::ValueRef;
    Ok(match value {
        ValueRef::Null => serde_json::Value::Null,
        ValueRef::Integer(i) => serde_json::Value::from(i),
        ValueRef::Text(text) => serde_json::Value::from(
            std::str::from_utf8(text)
                .map_err(|e| LifeosError::InvalidData(format!("non-utf8 text column: {e}")))?,
        ),
        ValueRef::Real(_) => {
            return Err(LifeosError::InvalidData(
                "REAL column in a sync table is forbidden".into(),
            ));
        }
        ValueRef::Blob(_) => {
            return Err(LifeosError::InvalidData(
                "BLOB column in a sync table is not supported".into(),
            ));
        }
    })
}

fn json_to_sql(value: &serde_json::Value) -> std::result::Result<rusqlite::types::Value, String> {
    use rusqlite::types::Value;
    Ok(match value {
        serde_json::Value::Null => Value::Null,
        serde_json::Value::Bool(b) => Value::Integer(i64::from(*b)),
        serde_json::Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                Value::Integer(i)
            } else {
                return Err("non-integer numbers are forbidden in sync rows".to_owned());
            }
        }
        serde_json::Value::String(s) => Value::Text(s.clone()),
        serde_json::Value::Array(_) | serde_json::Value::Object(_) => {
            return Err("nested values are forbidden in sync rows".to_owned());
        }
    })
}
