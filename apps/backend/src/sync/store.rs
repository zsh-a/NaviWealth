//! Generic row-state store for sync v2 (docs/sync-v2.md).
//!
//! The server is schema-agnostic: every business row lives in `sync_rows` as
//! an opaque JSON `payload` keyed by `(user_id, table_name, row_id)`. Conflict
//! resolution is per-row last-writer-wins on `(version, device_id)`; the pull
//! cursor is the monotonic `seq` SQLite mints on every write.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use worker::{D1Database, D1PreparedStatement, D1Type};

use crate::error::AppError;

/// Stop accumulating a pull page once it would exceed this serialized size.
const PULL_BODY_BUDGET: usize = 900 * 1024;

/// A row as it travels on the wire, both directions.
///
/// Inbound (client → server) only sets `table`, `id`, `payload`, `version`,
/// `deleted`. Outbound (server → client) additionally carries `device_id`
/// (the author) and `seq` (the cursor value).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RowChange {
    pub table: String,
    pub id: String,
    /// Full row payload as a JSON object. Client pushes may send `null` for
    /// deletes; stored tombstones are returned as `{}` with `deleted = true`.
    #[serde(default)]
    pub payload: Option<Value>,
    /// Opaque, lexicographically-ordered LWW token the client assigns; the
    /// server never interprets it (docs/sync-v2.md §4).
    pub version: String,
    #[serde(default)]
    pub deleted: bool,
    /// Author device. Server-set on outbound rows; ignored on inbound.
    #[serde(default)]
    pub device_id: String,
    /// Server-assigned cursor value. Meaningful on outbound rows only.
    #[serde(default)]
    pub seq: i64,
}

/// One page of a pull.
pub struct PullPage {
    pub changes: Vec<RowChange>,
    pub more: bool,
    /// Cursor the client should adopt: the last change's `seq` when `more`,
    /// otherwise the user's global `MAX(seq)`.
    pub high_seq: i64,
}

#[derive(Deserialize)]
struct MetaRow {
    version: String,
    device_id: String,
}

#[derive(Deserialize)]
struct DbRow {
    seq: i64,
    table_name: String,
    row_id: String,
    payload: String,
    version: String,
    device_id: String,
    deleted: i64,
}

#[derive(Deserialize)]
struct MaxRow {
    m: Option<i64>,
}

fn d1_err(e: impl std::fmt::Display) -> AppError {
    AppError::Internal(format!("d1: {e}"))
}

/// `incoming` beats `stored` under last-writer-wins. `device_id` only breaks
/// the exact-version tie so the order is total (docs/sync-v2.md §4.2).
fn lww_wins(incoming_version: &str, incoming_device: &str, stored: Option<&MetaRow>) -> bool {
    match stored {
        None => true,
        Some(s) => {
            incoming_version > s.version.as_str()
                || (incoming_version == s.version.as_str()
                    && incoming_device > s.device_id.as_str())
        }
    }
}

/// Apply a batch of inbound changes with LWW. Reads the current row metadata
/// up front, then ships every winning `INSERT OR REPLACE` as one atomic
/// `db.batch(...)`. Returns the number of rows actually stored.
pub async fn apply_changes(
    db: &D1Database,
    user_id: &str,
    device_id: &str,
    changes: &[RowChange],
) -> Result<usize, AppError> {
    if changes.is_empty() {
        return Ok(0);
    }
    let now = Utc::now().to_rfc3339();

    // Owned strings must outlive the prepared statements they are bound into,
    // so they are collected here rather than in the per-row loop scope.
    let mut payloads: Vec<String> = Vec::with_capacity(changes.len());
    let mut versions: Vec<String> = Vec::with_capacity(changes.len());
    let mut writes: Vec<D1PreparedStatement> = Vec::with_capacity(changes.len());

    for change in changes {
        let stored: Option<MetaRow> = db
            .prepare(
                "SELECT version, device_id FROM sync_rows
                 WHERE user_id = ?1 AND table_name = ?2 AND row_id = ?3",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&change.table),
                &D1Type::Text(&change.id),
            ])
            .map_err(d1_err)?
            .first(None)
            .await
            .map_err(d1_err)?;

        if !lww_wins(&change.version, device_id, stored.as_ref()) {
            continue;
        }

        let payload_json = match (&change.payload, change.deleted) {
            (Some(p @ Value::Object(_)), false) => {
                serde_json::to_string(p).map_err(|e| AppError::Internal(e.to_string()))?
            }
            // Deleted rows (and degenerate non-object payloads) store `{}`.
            _ => "{}".to_string(),
        };
        payloads.push(payload_json);
        versions.push(change.version.clone());
        let payload_ref = payloads.last().unwrap();
        let version_ref = versions.last().unwrap();
        let deleted_int: i32 = if change.deleted { 1 } else { 0 };

        writes.push(
            db.prepare(
                "INSERT OR REPLACE INTO sync_rows
                    (user_id, table_name, row_id, payload, version, device_id, deleted, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            )
            .bind_refs([
                &D1Type::Text(user_id),
                &D1Type::Text(&change.table),
                &D1Type::Text(&change.id),
                &D1Type::Text(payload_ref),
                &D1Type::Text(version_ref),
                &D1Type::Text(device_id),
                &D1Type::Integer(deleted_int),
                &D1Type::Text(&now),
            ])
            .map_err(d1_err)?,
        );
    }

    let count = writes.len();
    if !writes.is_empty() {
        db.batch(writes).await.map_err(d1_err)?;
    }
    Ok(count)
}

/// Fetch rows newer than `since` for every device other than `device_id`.
pub async fn pull(
    db: &D1Database,
    user_id: &str,
    device_id: &str,
    since: i64,
    limit: i64,
) -> Result<PullPage, AppError> {
    // `since` is bound as TEXT; SQLite applies the `seq` column's numeric
    // affinity to the comparison, so this stays correct past i32 range.
    let since_str = since.to_string();
    let fetch_limit = (limit + 1) as i32; // one extra row to detect `more`

    let rows: Vec<DbRow> = db
        .prepare(
            "SELECT seq, table_name, row_id, payload, version, device_id, deleted
             FROM sync_rows
             WHERE user_id = ?1 AND device_id <> ?2 AND seq > ?3
             ORDER BY seq ASC
             LIMIT ?4",
        )
        .bind_refs([
            &D1Type::Text(user_id),
            &D1Type::Text(device_id),
            &D1Type::Text(&since_str),
            &D1Type::Integer(fetch_limit),
        ])
        .map_err(d1_err)?
        .all()
        .await
        .map_err(d1_err)?
        .results()
        .map_err(d1_err)?;

    let mut more = rows.len() as i64 > limit;
    let mut taken = rows;
    if more {
        taken.truncate(limit as usize);
    }

    let mut changes: Vec<RowChange> = Vec::with_capacity(taken.len());
    let mut body_bytes = 0usize;
    for r in taken {
        let payload: Value = serde_json::from_str(&r.payload)
            .unwrap_or_else(|_| Value::Object(serde_json::Map::new()));
        let change = RowChange {
            table: r.table_name,
            id: r.row_id,
            payload: Some(payload),
            version: r.version,
            deleted: r.deleted != 0,
            device_id: r.device_id,
            seq: r.seq,
        };
        let est = serde_json::to_string(&change).map(|s| s.len()).unwrap_or(0);
        if !changes.is_empty() && body_bytes + est > PULL_BODY_BUDGET {
            more = true;
            break;
        }
        body_bytes += est;
        changes.push(change);
    }

    let high_seq = if more {
        changes.last().map(|c| c.seq).unwrap_or(since)
    } else {
        max_seq(db, user_id).await?
    };

    Ok(PullPage {
        changes,
        more,
        high_seq,
    })
}

/// The user's highest `seq` (their sync horizon). `0` when nothing is stored.
pub async fn max_seq(db: &D1Database, user_id: &str) -> Result<i64, AppError> {
    let row: Option<MaxRow> = db
        .prepare("SELECT MAX(seq) AS m FROM sync_rows WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(d1_err)?
        .first(None)
        .await
        .map_err(d1_err)?;
    Ok(row.and_then(|r| r.m).unwrap_or(0))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    // Version tokens are compared lexically; the client mints them so they
    // sort the same as their intended order (canonical HLC strings do).
    #[test]
    fn lww_first_write_wins() {
        assert!(lww_wins("1700000000000.0000-a", "dev-a", None));
    }

    #[test]
    fn lww_higher_version_wins() {
        let stored = MetaRow {
            version: "1700000000000.0001-a".into(),
            device_id: "dev-a".into(),
        };
        assert!(lww_wins("1700000000000.0002-a", "dev-b", Some(&stored)));
        assert!(!lww_wins("1700000000000.0000-a", "dev-b", Some(&stored)));
    }

    #[test]
    fn lww_equal_version_breaks_on_device_id() {
        let v = "1700000000000.0001-a";
        let stored = MetaRow {
            version: v.into(),
            device_id: "dev-b".into(),
        };
        // Higher device_id wins the tie.
        assert!(lww_wins(v, "dev-c", Some(&stored)));
        // Lower device_id loses; equal device_id is an idempotent no-op.
        assert!(!lww_wins(v, "dev-a", Some(&stored)));
        assert!(!lww_wins(v, "dev-b", Some(&stored)));
    }

    #[test]
    fn row_change_deserializes_client_push_shape() {
        let row: RowChange = serde_json::from_value(json!({
            "table": "fin:accounts",
            "id": "acc-1",
            "payload": {
                "id": "acc-1",
                "name": "Cash",
                "hlc": "1716381000123.0000-device-a"
            },
            "version": "1716381000123.0000-device-a",
            "deleted": false
        }))
        .unwrap();

        assert_eq!(row.table, "fin:accounts");
        assert_eq!(row.id, "acc-1");
        assert_eq!(
            row.payload,
            Some(json!({
                "id": "acc-1",
                "name": "Cash",
                "hlc": "1716381000123.0000-device-a"
            }))
        );
        assert_eq!(row.version, "1716381000123.0000-device-a");
        assert!(!row.deleted);
        assert_eq!(row.device_id, "");
        assert_eq!(row.seq, 0);
    }

    #[test]
    fn row_change_round_trips_server_tombstone_shape() {
        let row = RowChange {
            table: "health:health_metrics".into(),
            id: "metric-1".into(),
            payload: Some(json!({})),
            version: "1716381000124.0000-device-b".into(),
            deleted: true,
            device_id: "device-b".into(),
            seq: 42,
        };

        let value = serde_json::to_value(&row).unwrap();
        assert_eq!(
            value,
            json!({
                "table": "health:health_metrics",
                "id": "metric-1",
                "payload": {},
                "version": "1716381000124.0000-device-b",
                "deleted": true,
                "device_id": "device-b",
                "seq": 42
            })
        );
    }
}
