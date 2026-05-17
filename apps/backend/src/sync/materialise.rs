use chrono::Utc;
use serde::Deserialize;
use serde_json::{Map, Value};
use worker::{D1Database, D1PreparedStatement, D1Type};

use crate::error::AppError;
use crate::hlc::Hlc;

use super::op::{Op, OpType};

/// Outcome of applying a single op to its materialised row + the OpLog.
#[derive(Debug)]
pub struct ApplyOutcome {
    /// `true` once the OpLog row was successfully inserted. Idempotent
    /// re-pushes of the *same* `op_id` + `client_hlc` also count as accepted
    /// (SP-C-2).
    pub accepted: bool,
    /// Set when the op was deduplicated — the previous OpLog row had an
    /// identical `op_id` but a *different* `client_hlc` (SP-C-3).
    pub op_id_mutated: bool,
    /// Set when the op was accepted into the OpLog but its `server_hlc` was
    /// shadowed by a higher HLC already on the row (LWW). SP-C-10: shadowed
    /// ops are still "accepted", not rejected.
    pub shadowed: bool,
}

/// Map a wire `table` name to the SQL table it materialises into. Most map
/// 1:1; the protocol's `devices` and `users` collide with the auth
/// `devices` / `users` tables, so they live under `synced_devices` /
/// `synced_users` server-side. See `apps/backend/migrations/`.
pub fn sql_table_name(wire: &str) -> Result<&'static str, AppError> {
    match wire {
        "accounts" => Ok("accounts"),
        "assets" => Ok("assets"),
        "journal_entries" => Ok("journal_entries"),
        "postings" => Ok("postings"),
        "prices" => Ok("prices"),
        "recurring_transactions" => Ok("recurring_transactions"),
        "liabilities" => Ok("liabilities"),
        "amortization_entries" => Ok("amortization_entries"),
        "fx_rates" => Ok("fx_rates"),
        "tags" => Ok("tags"),
        "tag_links" => Ok("tag_links"),
        "categories" => Ok("categories"),
        "settings" => Ok("settings"),
        "goals" => Ok("goals"),
        "devices" => Ok("synced_devices"),
        "users" => Ok("synced_users"),
        other => Err(AppError::unknown_table(other)),
    }
}

#[derive(Deserialize)]
struct OpLogRow {
    client_hlc: String,
}

#[derive(Deserialize)]
struct CurrentRow {
    payload: String,
    hlc_text: String,
}

/// Apply a stamped op:
/// 1. INSERT into `op_log` (PK on `op_id`; conflict => idempotent or mutated).
/// 2. UPSERT the materialised row iff `server_hlc > current.hlc`.
///
/// The two writes ship as a single `db.batch(...)` so a transient D1 failure
/// cannot leave op_log written without the matching row mutation (or vice
/// versa). The reads (idempotency probe, current-row lookup) stay outside
/// the batch — they don't need transactional isolation, and keeping them
/// sequential preserves shallow-merge semantics across ops in the same push.
///
/// Spec: docs/sync-protocol.md §6 (LWW), §8.1 step 4.
pub async fn apply(
    db: &D1Database,
    user_id: &str,
    op: &Op,
    server_hlc: &Hlc,
) -> Result<ApplyOutcome, AppError> {
    let table = sql_table_name(&op.table)?;

    // 1. OpLog idempotency check.
    let existing: Option<OpLogRow> = db
        .prepare("SELECT client_hlc FROM op_log WHERE op_id = ?1 AND user_id = ?2")
        .bind_refs([&D1Type::Text(&op.op_id), &D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("d1 first: {e}")))?;
    if let Some(prev) = existing {
        if prev.client_hlc != op.hlc.to_canonical() {
            return Ok(ApplyOutcome {
                accepted: false,
                op_id_mutated: true,
                shadowed: false,
            });
        }
        // Idempotent re-push (SP-C-2): treat as accepted, no row writes.
        return Ok(ApplyOutcome {
            accepted: true,
            op_id_mutated: false,
            shadowed: false,
        });
    }

    // 2. Current materialised row — drives shadowing decision and the
    //    shallow-merge that produces the row's next payload.
    let select_sql =
        format!("SELECT payload, hlc_text FROM {table} WHERE user_id = ?1 AND id = ?2");
    let current: Option<CurrentRow> = db
        .prepare(&select_sql)
        .bind_refs([&D1Type::Text(user_id), &D1Type::Text(&op.row_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("d1 first: {e}")))?;

    let server_hlc_str = server_hlc.to_canonical();
    let client_hlc_str = op.hlc.to_canonical();
    let op_type_str = op.op_type.as_str();
    let now = Utc::now().to_rfc3339();
    let diff_json: Option<String> = match &op.fields_diff {
        None => None,
        Some(v) => Some(serde_json::to_string(v).map_err(|e| AppError::Internal(e.to_string()))?),
    };
    let diff_param: D1Type = match &diff_json {
        Some(s) => D1Type::Text(s),
        None => D1Type::Null,
    };

    let shadowed = match &current {
        Some(cur) => server_hlc_str.as_str() <= cur.hlc_text.as_str(),
        None => false,
    };

    // 3. Compose the writes into one atomic batch.
    let mut writes: Vec<D1PreparedStatement> = Vec::with_capacity(2);

    writes.push(
        db.prepare(
            "INSERT INTO op_log
                (op_id, user_id, table_name, row_id, op_type, fields_diff,
                 hlc_text, client_hlc, device_id, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
        )
        .bind_refs([
            &D1Type::Text(&op.op_id),
            &D1Type::Text(user_id),
            &D1Type::Text(&op.table),
            &D1Type::Text(&op.row_id),
            &D1Type::Text(op_type_str),
            &diff_param,
            &D1Type::Text(&server_hlc_str),
            &D1Type::Text(&client_hlc_str),
            &D1Type::Text(&op.device_id),
            &D1Type::Text(&now),
        ])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?,
    );

    if !shadowed {
        let stmt = match (op.op_type.clone(), current.as_ref()) {
            (OpType::Delete, Some(_)) => {
                let sql = format!(
                    "UPDATE {table} SET hlc_text = ?1, updated_by_device = ?2, deleted_at = ?3 \
                     WHERE user_id = ?4 AND id = ?5"
                );
                db.prepare(&sql)
                    .bind_refs([
                        &D1Type::Text(&server_hlc_str),
                        &D1Type::Text(&op.device_id),
                        &D1Type::Text(&now),
                        &D1Type::Text(user_id),
                        &D1Type::Text(&op.row_id),
                    ])
                    .map_err(|e| AppError::Internal(format!("bind: {e}")))?
            }
            (OpType::Delete, None) => {
                // Tombstone for a row we've never seen. Materialise as a
                // placeholder so a future higher-HLC update can resurrect by
                // clearing deleted_at.
                let sql = format!(
                    "INSERT INTO {table} (user_id, id, payload, hlc_text, updated_by_device, deleted_at) \
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
                );
                db.prepare(&sql)
                    .bind_refs([
                        &D1Type::Text(user_id),
                        &D1Type::Text(&op.row_id),
                        &D1Type::Text("{}"),
                        &D1Type::Text(&server_hlc_str),
                        &D1Type::Text(&op.device_id),
                        &D1Type::Text(&now),
                    ])
                    .map_err(|e| AppError::Internal(format!("bind: {e}")))?
            }
            (OpType::Insert | OpType::Update, current_opt) => {
                let merged = merge_payload(
                    current_opt.map(|r| r.payload.as_str()),
                    op.fields_diff.as_ref(),
                );
                let merged_json = serde_json::to_string(&merged)
                    .map_err(|e| AppError::Internal(e.to_string()))?;
                if current_opt.is_some() {
                    let sql = format!(
                        "UPDATE {table} SET payload = ?1, hlc_text = ?2, updated_by_device = ?3, \
                         deleted_at = NULL WHERE user_id = ?4 AND id = ?5"
                    );
                    db.prepare(&sql)
                        .bind_refs([
                            &D1Type::Text(&merged_json),
                            &D1Type::Text(&server_hlc_str),
                            &D1Type::Text(&op.device_id),
                            &D1Type::Text(user_id),
                            &D1Type::Text(&op.row_id),
                        ])
                        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
                } else {
                    let sql = format!(
                        "INSERT INTO {table} (user_id, id, payload, hlc_text, updated_by_device, deleted_at) \
                         VALUES (?1, ?2, ?3, ?4, ?5, NULL)"
                    );
                    db.prepare(&sql)
                        .bind_refs([
                            &D1Type::Text(user_id),
                            &D1Type::Text(&op.row_id),
                            &D1Type::Text(&merged_json),
                            &D1Type::Text(&server_hlc_str),
                            &D1Type::Text(&op.device_id),
                        ])
                        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
                }
            }
        };
        writes.push(stmt);
    }

    db.batch(writes)
        .await
        .map_err(|e| AppError::Internal(format!("d1 batch: {e}")))?;

    Ok(ApplyOutcome {
        accepted: true,
        op_id_mutated: false,
        shadowed,
    })
}

/// Shallow-merge a partial diff onto a row payload. `{"k": null}` clears the
/// key in the merged payload (per docs/sync-protocol.md §4.2).
fn merge_payload(current_json: Option<&str>, diff: Option<&Value>) -> Value {
    let diff_obj: Map<String, Value> = diff
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();
    let base: Map<String, Value> = match current_json {
        Some(s) if !s.is_empty() => match serde_json::from_str::<Value>(s) {
            Ok(Value::Object(m)) => m,
            _ => Map::new(),
        },
        _ => Map::new(),
    };
    let mut merged = base;
    for (k, v) in diff_obj {
        merged.insert(k, v);
    }
    Value::Object(merged)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn merge_payload_inserts_keys() {
        let result = merge_payload(None, Some(&json!({"a": 1, "b": "x"})));
        assert_eq!(result, json!({"a": 1, "b": "x"}));
    }

    #[test]
    fn merge_payload_updates_keys() {
        let cur = r#"{"a":1,"b":"x"}"#;
        let result = merge_payload(Some(cur), Some(&json!({"b": "y", "c": 3})));
        assert_eq!(result, json!({"a": 1, "b": "y", "c": 3}));
    }

    #[test]
    fn merge_payload_explicit_null_clears() {
        let cur = r#"{"a":1,"b":"x"}"#;
        let result = merge_payload(Some(cur), Some(&json!({"b": null})));
        assert_eq!(result, json!({"a": 1, "b": null}));
    }

    #[test]
    fn sql_table_name_known_tables() {
        assert_eq!(sql_table_name("accounts").unwrap(), "accounts");
        assert_eq!(
            sql_table_name("journal_entries").unwrap(),
            "journal_entries"
        );
        assert_eq!(sql_table_name("postings").unwrap(), "postings");
        assert_eq!(sql_table_name("prices").unwrap(), "prices");
        assert_eq!(
            sql_table_name("recurring_transactions").unwrap(),
            "recurring_transactions"
        );
        assert_eq!(
            sql_table_name("amortization_entries").unwrap(),
            "amortization_entries"
        );
        assert_eq!(sql_table_name("categories").unwrap(), "categories");
        assert_eq!(sql_table_name("settings").unwrap(), "settings");
        assert_eq!(sql_table_name("tag_links").unwrap(), "tag_links");
        // `devices` and `users` collide with auth tables; both get aliased.
        assert_eq!(sql_table_name("devices").unwrap(), "synced_devices");
        assert_eq!(sql_table_name("users").unwrap(), "synced_users");
    }

    #[test]
    fn sql_table_name_unknown_rejected() {
        let err = sql_table_name("market_quotes").unwrap_err();
        assert_eq!(err.code(), "unknown_table");
    }
}
