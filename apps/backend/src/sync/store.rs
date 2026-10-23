//! Generic row-state store for sync v3 (docs/sync/sync-v3.md).
//!
//! The server is schema-agnostic: every business row lives in `sync_rows` as
//! an opaque JSON `payload` keyed by `(user_id, table_name, row_id)`. Conflict
//! resolution is per-row last-writer-wins on `(version, device_id)`; the pull
//! cursor is the monotonic `seq` SQLite mints on every write.

use std::collections::{BTreeMap, HashMap};

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use worker::{D1Database, D1PreparedStatement, D1Type};

use crate::error::AppError;
use crate::sync::domain::{domain_for_wire_table, prefix_for_domain};

/// Stop accumulating a pull page once it would exceed this serialized size.
const PULL_BODY_BUDGET: usize = 900 * 1024;

// Both guards execute against the row state at the instant of the write. A
// prior SELECT cannot enforce LWW: another request (or an earlier statement
// in this batch) may replace the row before this statement executes.
const APPLY_CHANGE_SQL: &str = "
INSERT OR REPLACE INTO sync_rows
    (user_id, table_name, row_id, payload, version, device_id,
     deleted, updated_at, generation)
SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9
WHERE ?9 = COALESCE(
  (SELECT generation FROM sync_domain_generations
   WHERE user_id = ?1 AND domain = ?10),
  0
)
AND NOT EXISTS (
  SELECT 1 FROM sync_rows
  WHERE user_id = ?1 AND table_name = ?2 AND row_id = ?3
    AND generation = ?9
    AND (version > ?5 OR (version = ?5 AND device_id >= ?6))
)";

const PULL_ROWS_SQL: &str = "
SELECT seq, table_name, row_id, payload, version, device_id,
       deleted, generation
FROM sync_rows
WHERE user_id = ?1 AND device_id <> ?2 AND seq > ?3 AND seq <= ?4
ORDER BY seq ASC
LIMIT ?5";

const MAX_SEQ_SQL: &str = "SELECT MAX(seq) AS m FROM sync_rows WHERE user_id = ?1";

const RESET_DOMAIN_SQL: &str = "
INSERT INTO sync_domain_generations
   (user_id, domain, generation, reset_at, reset_device_id)
VALUES (?1, ?2, 1, ?3, ?4)
ON CONFLICT(user_id, domain) DO UPDATE SET
  generation = sync_domain_generations.generation + 1,
  reset_at = excluded.reset_at,
  reset_device_id = excluded.reset_device_id";

const CLEAR_DOMAIN_SQL: &str = "DELETE FROM sync_rows WHERE user_id = ?1 AND table_name LIKE ?2";

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
    /// server never interprets it (docs/sync/sync-v3.md).
    pub version: String,
    #[serde(default)]
    pub deleted: bool,
    /// Author device. Server-set on outbound rows; ignored on inbound.
    #[serde(default)]
    pub device_id: String,
    /// Server-assigned cursor value. Meaningful on outbound rows only.
    #[serde(default)]
    pub seq: i64,
    /// Domain reset generation. A stale generation is never accepted.
    #[serde(default)]
    pub generation: i64,
}

/// One page of a pull.
pub struct PullPage {
    pub changes: Vec<RowChange>,
    pub more: bool,
    /// Cursor the client should adopt: the last change's `seq` when `more`,
    /// otherwise the horizon captured before reading this page. Writes after
    /// that horizon remain eligible for the next pull.
    pub high_seq: i64,
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
    generation: i64,
}

#[derive(Deserialize)]
struct MaxRow {
    m: Option<i64>,
}

#[derive(Deserialize)]
struct GenerationRow {
    domain: String,
    generation: i64,
}

#[derive(Deserialize)]
struct GenerationValueRow {
    generation: i64,
}

fn d1_err(e: impl std::fmt::Display) -> AppError {
    AppError::Internal(format!("d1: {e}"))
}

/// Apply one atomic batch. Each SQL statement enforces generation and LWW,
/// including when requests interleave or the batch repeats a row key. Winning
/// replacements mint a fresh `seq`; losing/idempotent writes leave it intact.
/// Returns the number of rows actually stored, not the number attempted.
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
    let mut writes: Vec<D1PreparedStatement> = Vec::with_capacity(changes.len());

    for change in changes {
        let domain = domain_for_wire_table(&change.table)
            .ok_or_else(|| AppError::BadRequest("unknown sync domain".into()))?;
        let generation = i32::try_from(change.generation)
            .map_err(|_| AppError::BadRequest("invalid domain generation".into()))?;
        let payload_json = match (&change.payload, change.deleted) {
            (Some(p @ Value::Object(_)), false) => {
                serde_json::to_string(p).map_err(|e| AppError::Internal(e.to_string()))?
            }
            // Deleted rows (and degenerate non-object payloads) store `{}`.
            _ => "{}".to_string(),
        };
        payloads.push(payload_json);
        let payload_ref = payloads.last().unwrap();
        let deleted_int: i32 = if change.deleted { 1 } else { 0 };

        writes.push(
            db.prepare(APPLY_CHANGE_SQL)
                .bind_refs([
                    &D1Type::Text(user_id),
                    &D1Type::Text(&change.table),
                    &D1Type::Text(&change.id),
                    &D1Type::Text(payload_ref),
                    &D1Type::Text(&change.version),
                    &D1Type::Text(device_id),
                    &D1Type::Integer(deleted_int),
                    &D1Type::Text(&now),
                    &D1Type::Integer(generation),
                    &D1Type::Text(domain),
                ])
                .map_err(d1_err)?,
        );
    }

    db.batch(writes)
        .await
        .map_err(d1_err)?
        .into_iter()
        .try_fold(0, |count, result| {
            let changes = result
                .meta()
                .map_err(d1_err)?
                .and_then(|meta| meta.changes)
                .ok_or_else(|| AppError::Internal("sync write metadata missing".into()))?;
            Ok(count + changes)
        })
}

/// Fetch rows newer than `since` for every device other than `device_id`.
pub async fn pull(
    db: &D1Database,
    user_id: &str,
    device_id: &str,
    since: i64,
    limit: i64,
) -> Result<PullPage, AppError> {
    // Capture a horizon before the page read, and never advance past it. A
    // row inserted/replaced between these reads has a larger seq and remains
    // eligible next time. If erasure leaves MAX below since, return the current
    // horizon rather than retaining an invalid cursor ahead of server state.
    let horizon = max_seq(db, user_id).await?;
    // Cursors are bound as TEXT; SQLite applies the seq column's numeric
    // affinity so these comparisons remain correct past i32 range.
    let since_str = since.to_string();
    let horizon_str = horizon.to_string();
    let fetch_limit = (limit + 1) as i32; // one extra row to detect `more`

    let rows: Vec<DbRow> = db
        .prepare(PULL_ROWS_SQL)
        .bind_refs([
            &D1Type::Text(user_id),
            &D1Type::Text(device_id),
            &D1Type::Text(&since_str),
            &D1Type::Text(&horizon_str),
            &D1Type::Integer(fetch_limit),
        ])
        .map_err(d1_err)?
        .all()
        .await
        .map_err(d1_err)?
        .results()
        .map_err(d1_err)?;

    Ok(build_pull_page(rows, since, horizon, limit))
}

fn build_pull_page(rows: Vec<DbRow>, since: i64, horizon: i64, limit: i64) -> PullPage {
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
            generation: r.generation,
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
        horizon
    };

    PullPage {
        changes,
        more,
        high_seq,
    }
}

/// Current reset generation for every domain visible to the caller.
pub async fn load_domain_generations(
    db: &D1Database,
    user_id: &str,
    domains: &[String],
) -> Result<BTreeMap<String, i64>, AppError> {
    let rows: Vec<GenerationRow> = db
        .prepare(
            "SELECT domain, generation FROM sync_domain_generations
             WHERE user_id = ?1",
        )
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(d1_err)?
        .all()
        .await
        .map_err(d1_err)?
        .results()
        .map_err(d1_err)?;
    let stored = rows
        .into_iter()
        .map(|row| (row.domain, row.generation))
        .collect::<HashMap<_, _>>();
    Ok(domains
        .iter()
        .filter(|domain| prefix_for_domain(domain).is_some())
        .map(|domain| (domain.clone(), *stored.get(domain).unwrap_or(&0)))
        .collect())
}

/// Permanently clears one domain and advances its generation atomically.
pub async fn reset_domain(
    db: &D1Database,
    user_id: &str,
    device_id: &str,
    domain: &str,
) -> Result<i64, AppError> {
    let prefix = prefix_for_domain(domain)
        .ok_or_else(|| AppError::BadRequest("unknown sync domain".into()))?;
    let prefix_like = format!("{prefix}%");
    let now = Utc::now().to_rfc3339();
    let bump = db
        .prepare(RESET_DOMAIN_SQL)
        .bind_refs([
            &D1Type::Text(user_id),
            &D1Type::Text(domain),
            &D1Type::Text(&now),
            &D1Type::Text(device_id),
        ])
        .map_err(d1_err)?;
    let clear = db
        .prepare(CLEAR_DOMAIN_SQL)
        .bind_refs([&D1Type::Text(user_id), &D1Type::Text(&prefix_like)])
        .map_err(d1_err)?;
    db.batch(vec![bump, clear]).await.map_err(d1_err)?;

    let row: GenerationValueRow = db
        .prepare(
            "SELECT generation FROM sync_domain_generations
             WHERE user_id = ?1 AND domain = ?2",
        )
        .bind_refs([&D1Type::Text(user_id), &D1Type::Text(domain)])
        .map_err(d1_err)?
        .first(None)
        .await
        .map_err(d1_err)?
        .ok_or_else(|| AppError::Internal("domain generation missing after reset".into()))?;
    Ok(row.generation)
}

/// The user's highest `seq` (their sync horizon). `0` when nothing is stored.
pub async fn max_seq(db: &D1Database, user_id: &str) -> Result<i64, AppError> {
    let row: Option<MaxRow> = db
        .prepare(MAX_SEQ_SQL)
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

    const CLIENT_PUSH_FIXTURE: &str =
        include_str!("../../../../docs/fixtures/sync_v3_client_push_row_change.json");
    const SERVER_TOMBSTONE_FIXTURE: &str =
        include_str!("../../../../docs/fixtures/sync_v3_server_tombstone_row_change.json");

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
    fn row_change_deserializes_shared_client_push_fixture() {
        let row: RowChange = serde_json::from_str(CLIENT_PUSH_FIXTURE).unwrap();

        assert_eq!(row.table, "fin:accounts");
        assert_eq!(row.id, "acc-1");
        assert_eq!(
            row.payload,
            Some(json!({
                "id": "acc-1",
                "name": "Cash",
                "hlc": "1716381000123.0000-device-a",
                "deleted_at": null
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
            generation: 3,
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
                "seq": 42,
                "generation": 3
            })
        );
    }

    #[test]
    fn row_change_serializes_shared_server_tombstone_fixture() {
        let row: RowChange = serde_json::from_str(SERVER_TOMBSTONE_FIXTURE).unwrap();
        let actual = serde_json::to_value(&row).unwrap();
        let expected: serde_json::Value = serde_json::from_str(SERVER_TOMBSTONE_FIXTURE).unwrap();

        assert_eq!(actual, expected);
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
#[path = "store_sql_tests.rs"]
mod sql_tests;
