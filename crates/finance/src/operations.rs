//! Reviewed statement ingestion, reconciliation and evidence-based month close.
//! All persisted operations are owner scoped and participate in row-state sync.
mod review;
mod statement;
use crate::{
    FinanceError, Result,
    models::{Account, AccountSide},
    repos::account_repository as accounts,
};
use lifeos::{
    db::migrations::Migration,
    error::Domain,
    sync::{MutationStamper, SqlTableAdapter, SyncRegistry, outbox},
};
pub use review::*;
use rusqlite::{Connection, OptionalExtension, params};
use rust_decimal::Decimal;
use serde_json::{Value, json};
pub use statement::*;
use std::sync::Arc;
pub const OPERATIONS_TABLE: &str = "fin:operations";
pub fn migration() -> Migration {
    Migration {
        version: 9,
        name: "finance_operations",
        sql: r#"CREATE TABLE "fin:operations" (id TEXT PRIMARY KEY NOT NULL,kind TEXT NOT NULL,payload_json TEXT NOT NULL,owner_user_id TEXT NOT NULL,updated_at INTEGER NOT NULL,updated_by_device TEXT NOT NULL,hlc TEXT NOT NULL,deleted_at INTEGER); CREATE INDEX idx_fin_operations_owner_kind ON "fin:operations"(owner_user_id,kind);"#,
    }
}
pub fn register(registry: &mut SyncRegistry) {
    registry.add(Arc::new(SqlTableAdapter::new(
        OPERATIONS_TABLE,
        Domain::Finance,
        &[
            "id",
            "kind",
            "payload_json",
            "owner_user_id",
            "updated_at",
            "updated_by_device",
            "hlc",
            "deleted_at",
        ],
    )));
}
fn invalid(message: &str) -> FinanceError {
    FinanceError::InvalidData(message.to_owned())
}
fn put(
    conn: &Connection,
    st: &MutationStamper,
    id: &str,
    kind: &str,
    payload: Value,
) -> Result<()> {
    check_identity(&payload, id)?;
    let existing: Option<(String, String)> = conn
        .query_row(
            "SELECT owner_user_id,kind FROM \"fin:operations\" WHERE id=?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    if existing
        .as_ref()
        .is_some_and(|(o, k)| o != &st.owner_user_id || k != kind)
    {
        return Err(invalid("无法修改其他数据空间的操作"));
    }
    let s = st.stamp(conn)?;
    conn.execute("INSERT INTO \"fin:operations\"(id,kind,payload_json,owner_user_id,updated_at,updated_by_device,hlc) VALUES(?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,payload_json=excluded.payload_json,updated_at=excluded.updated_at,updated_by_device=excluded.updated_by_device,hlc=excluded.hlc",params![id,kind,payload.to_string(),st.owner_user_id,s.now.div_euclid(1000),s.device_id,s.hlc])?;
    outbox::enqueue(conn, OPERATIONS_TABLE, id)?;
    Ok(())
}
fn get(conn: &Connection, owner: &str, id: &str, kind: &str) -> Result<Value> {
    let raw:Option<String>=conn.query_row("SELECT payload_json FROM \"fin:operations\" WHERE id=?1 AND owner_user_id=?2 AND kind=?3 AND deleted_at IS NULL",params![id,owner,kind],|r|r.get(0)).optional()?;
    let value: Value = serde_json::from_str(&raw.ok_or_else(|| invalid("操作不存在或无法访问"))?)
        .map_err(|_| invalid("操作数据无法读取"))?;
    check_identity(&value, id)?;
    Ok(value)
}
fn list(conn: &Connection, owner: &str, kind: &str) -> Result<Vec<(String, Value)>> {
    let mut q=conn.prepare("SELECT id,payload_json FROM \"fin:operations\" WHERE owner_user_id=?1 AND kind=?2 AND deleted_at IS NULL ORDER BY updated_at DESC,id")?;
    let rows = q.query_map(params![owner, kind], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
    })?;
    rows.map(|r| {
        let (id, s) = r?;
        let value: Value = serde_json::from_str(&s).map_err(|_| invalid("操作数据无法读取"))?;
        check_identity(&value, &id)?;
        Ok((id, value))
    })
    .collect()
}
fn owned_account(conn: &Connection, owner: &str, id: &str) -> Result<Account> {
    accounts::get(conn, id)?
        .filter(|a| {
            a.sync.owner_user_id == owner
                && a.sync.deleted_at.is_none()
                && !a.archived
                && !a.id.starts_with("system-account:")
                && matches!(a.side, AccountSide::Asset | AccountSide::Liability)
        })
        .ok_or_else(|| invalid("请选择当前数据空间的有效资金账户"))
}
/// Stable deterministic evidence hash, with length framing to avoid ambiguous inputs.
/// This is not a security or anonymization primitive. No statement content is logged.
fn digest(parts: &[&str]) -> String {
    let mut a = 0xcbf29ce484222325u64;
    let mut b = 0x84222325cbf29ce4u64;
    for part in parts {
        for byte in (part.len() as u64)
            .to_le_bytes()
            .iter()
            .chain(part.as_bytes())
        {
            a = (a ^ u64::from(*byte)).wrapping_mul(0x100000001b3);
            b = (b ^ u64::from(*byte)).wrapping_mul(0x100000001d3);
        }
    }
    format!("{a:016x}{b:016x}")
}
fn balance_at(conn: &Connection, owner: &str, account: &str, until: i64) -> Result<Decimal> {
    let a = accounts::get(conn, account)?
        .filter(|a| {
            a.sync.owner_user_id == owner
                && a.sync.deleted_at.is_none()
                && !a.id.starts_with("system-account:")
                && matches!(a.side, AccountSide::Asset | AccountSide::Liability)
        })
        .ok_or_else(|| invalid("账户不存在或无法访问"))?;
    let mut total = Decimal::ZERO;
    for e in crate::repos::journal_repository::list_owned(conn, owner, None, Some(until))? {
        for p in e.postings {
            if p.account_id == account && p.sync.owner_user_id == owner && p.unit == a.currency {
                total = total
                    .checked_add(p.units)
                    .ok_or_else(|| invalid("余额超出支持范围"))?;
            }
        }
    }
    Ok(total)
}

fn encode<T: serde::Serialize>(v: &T) -> Result<Value> {
    serde_json::to_value(v).map_err(|_| invalid("操作数据无法保存"))
}
fn decode<T: serde::de::DeserializeOwned>(v: Value) -> Result<T> {
    serde_json::from_value(v).map_err(|_| invalid("操作数据无法读取"))
}

fn delete_owned_journal(conn: &Connection, st: &MutationStamper, id: &str) -> Result<()> {
    let entry = crate::repos::journal_repository::get(conn, id)?
        .filter(|e| {
            e.entry.sync.owner_user_id == st.owner_user_id
                && e.postings
                    .iter()
                    .all(|p| p.sync.owner_user_id == st.owner_user_id)
        })
        .ok_or_else(|| invalid("记录不存在或无法访问"))?;
    if entry.entry.sync.deleted_at.is_some() {
        return Ok(());
    }
    let stamp = st.stamp(conn)?;
    let now = stamp.now.div_euclid(1000);
    conn.execute(r#"UPDATE "fin:journal_entries" SET deleted_at=?2,updated_at=?2,updated_by_device=?3,hlc=?4 WHERE id=?1 AND owner_user_id=?5"#,params![id,now,stamp.device_id,stamp.hlc,st.owner_user_id])?;
    outbox::enqueue(conn, crate::tables::JOURNAL_ENTRIES_TABLE, id)?;
    for p in entry.postings {
        conn.execute(r#"UPDATE "fin:postings" SET deleted_at=?2,updated_at=?2,updated_by_device=?3,hlc=?4 WHERE id=?1 AND owner_user_id=?5"#,params![p.id,now,stamp.device_id,stamp.hlc,st.owner_user_id])?;
        outbox::enqueue(conn, crate::tables::POSTINGS_TABLE, &p.id)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests;

// Money in operation sync payloads is always a decimal string. Numeric JSON
// values are rejected, including ostensibly harmless integer-looking values.
mod decimal {
    use rust_decimal::Decimal;
    use serde::{Deserialize, Deserializer, Serializer, de::Error};
    pub fn serialize<S: Serializer>(v: &Decimal, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(&v.to_string())
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> std::result::Result<Decimal, D::Error> {
        Decimal::from_str_exact(&String::deserialize(d)?).map_err(D::Error::custom)
    }
}
mod optional_decimal {
    use rust_decimal::Decimal;
    use serde::{Deserialize, Deserializer, Serializer, de::Error};
    pub fn serialize<S: Serializer>(
        v: &Option<Decimal>,
        s: S,
    ) -> std::result::Result<S::Ok, S::Error> {
        match v {
            Some(v) => s.serialize_some(&v.to_string()),
            None => s.serialize_none(),
        }
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(
        d: D,
    ) -> std::result::Result<Option<Decimal>, D::Error> {
        Option::<String>::deserialize(d)?
            .map(|s| Decimal::from_str_exact(&s).map_err(D::Error::custom))
            .transpose()
    }
}

fn check_identity(value: &Value, id: &str) -> Result<()> {
    if let Some(stored) = value.get("id")
        && stored.as_str() != Some(id)
    {
        return Err(invalid("操作身份与存储记录不一致"));
    }
    Ok(())
}

/// Repair opaque owner-derived primary keys after the application's recursive
/// owner/id remap. The caller must also remap outbox row_id to the resulting id.
/// Historical receipt hashes remain provenance only; import dedupe is rebuilt
/// from current-owner journal facts at confirmation, never from those hashes.
/// journal_hlc is intentionally untouched: adoption must repair it only when
/// its old (journal_id,HLC) pair matched the actual pre-adoption journal row.
pub fn remap_owner_row(row: &mut Value, old: &str, new: &str) -> Result<()> {
    if old == new {
        return Ok(());
    }
    let kind = row["kind"].as_str().unwrap_or_default();
    if !matches!(kind, "month_close" | "issue_note") {
        return Ok(());
    }
    let raw = row["payload_json"]
        .as_str()
        .ok_or_else(|| invalid("操作迁移缺少有效来源数据"))?;
    let mut payload: Value =
        serde_json::from_str(raw).map_err(|_| invalid("操作迁移无法读取来源数据"))?;
    let id = if kind == "month_close" {
        let month = payload["month"]
            .as_str()
            .ok_or_else(|| invalid("月结迁移缺少月份"))?;
        format!("month-close:{}", digest(&[new, month]))
    } else {
        let key = payload["issue_key"]
            .as_str()
            .ok_or_else(|| invalid("处理说明迁移缺少问题身份"))?;
        format!("issue-note:{}", digest(&[new, key]))
    };
    if kind == "month_close" {
        payload["id"] = json!(id);
    }
    row["id"] = json!(id);
    row["payload_json"] = json!(payload.to_string());
    if row["owner_user_id"].as_str() == Some(old) {
        row["owner_user_id"] = json!(new);
    }
    Ok(())
}
