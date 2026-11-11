use super::*;
use crate::{
    FinanceError, Result,
    models::{AssetKind, AssetPrice, NewAssetPrice},
    repos::{account_repository as accounts, asset_repository as ar},
};
use lifeos::{
    db::migrations::Migration,
    error::Domain,
    sync::{MutationStamper, SqlTableAdapter, SyncRegistry, outbox},
};
use rusqlite::{Connection, OptionalExtension, params};
use rust_decimal::Decimal;
use serde::{Serialize, de::DeserializeOwned};
use std::sync::Arc;

const ASSETS: &str = "fin:wealth_assets";
const OPS: &str = "fin:wealth_operations";
const COLUMNS: &[&str] = &[
    "id",
    "payload",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];
pub fn migration() -> Migration {
    Migration {
        version: 7,
        name: "finance-wealth",
        sql: r#"
CREATE TABLE "fin:wealth_assets" (id TEXT PRIMARY KEY NOT NULL,payload TEXT NOT NULL,owner_user_id TEXT NOT NULL,updated_at INTEGER NOT NULL,updated_by_device TEXT NOT NULL,hlc TEXT NOT NULL,deleted_at INTEGER);
CREATE TABLE "fin:wealth_operations" (id TEXT PRIMARY KEY NOT NULL,payload TEXT NOT NULL,owner_user_id TEXT NOT NULL,updated_at INTEGER NOT NULL,updated_by_device TEXT NOT NULL,hlc TEXT NOT NULL,deleted_at INTEGER);
CREATE INDEX wealth_assets_owner ON "fin:wealth_assets"(owner_user_id,deleted_at);
CREATE INDEX wealth_operations_owner ON "fin:wealth_operations"(owner_user_id,deleted_at);
"#,
    }
}
pub fn register(registry: &mut SyncRegistry) {
    for table in [ASSETS, OPS] {
        registry.add(Arc::new(SqlTableAdapter::new(
            table,
            Domain::Finance,
            COLUMNS,
        )));
    }
}
pub(super) fn invalid(message: impl Into<String>) -> FinanceError {
    FinanceError::InvalidData(message.into())
}
pub(super) fn checked(v: Option<Decimal>) -> Result<Decimal> {
    v.ok_or_else(|| invalid("金额或数量超过支持范围"))
}

pub(super) fn local_civil_day() -> i64 {
    chrono::Local::now()
        .date_naive()
        .and_hms_opt(0, 0, 0)
        .expect("midnight")
        .and_utc()
        .timestamp()
}

pub(super) fn fact_date_allowed_at(date: i64, now: i64, local_day: i64) -> bool {
    date >= 0 && (date <= now || (date.rem_euclid(86_400) == 0 && date <= local_day))
}

/// Manual date pickers store civil dates as UTC-midnight labels. A label for
/// today's local calendar date is valid even before UTC reaches that date;
/// arbitrary future instants and later calendar dates remain invalid.
pub fn is_record_date_allowed(date: i64) -> bool {
    fact_date_allowed_at(date, lifeos::ids::now_secs(), local_civil_day())
}

pub(super) fn quote_date_allowed_at(
    date: i64,
    source: Option<&str>,
    now: i64,
    local_day: i64,
) -> bool {
    date >= 0
        && (date <= now || (source == Some("manual") && fact_date_allowed_at(date, now, local_day)))
}

pub(super) fn is_quote_date_allowed(date: i64, source: Option<&str>) -> bool {
    quote_date_allowed_at(date, source, lifeos::ids::now_secs(), local_civil_day())
}
pub(super) fn decode<T: DeserializeOwned>(raw: String) -> Result<T> {
    serde_json::from_str(&raw).map_err(|e| invalid(format!("财富记录无法读取: {e}")))
}
fn rows<T: DeserializeOwned>(conn: &Connection, table: &str, owner: &str) -> Result<Vec<T>> {
    let mut q=conn.prepare(&format!("SELECT payload FROM \"{table}\" WHERE owner_user_id=?1 AND deleted_at IS NULL ORDER BY hlc,id"))?;
    q.query_map([owner], |r| r.get::<_, String>(0))?
        .map(|r| decode(r?))
        .collect()
}
fn get<T: DeserializeOwned>(conn: &Connection, table: &str, owner: &str, id: &str) -> Result<T> {
    let raw=conn.query_row(&format!("SELECT payload FROM \"{table}\" WHERE id=?1 AND owner_user_id=?2 AND deleted_at IS NULL"),params![id,owner],|r|r.get::<_,String>(0)).optional()?;
    decode(raw.ok_or_else(|| invalid("记录不存在或不属于当前数据空间"))?)
}
fn put<T: Serialize>(
    conn: &Connection,
    table: &str,
    st: &MutationStamper,
    id: &str,
    value: &T,
    deleted: bool,
) -> Result<()> {
    let stamp = st.stamp(conn)?;
    let json = serde_json::to_string(value).map_err(|e| invalid(e.to_string()))?;
    let now = stamp.now.div_euclid(1000);
    conn.execute(&format!("INSERT INTO \"{table}\" (id,payload,owner_user_id,updated_at,updated_by_device,hlc,deleted_at) VALUES (?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at,updated_by_device=excluded.updated_by_device,hlc=excluded.hlc,deleted_at=excluded.deleted_at WHERE owner_user_id=excluded.owner_user_id"),params![id,json,st.owner_user_id,now,stamp.device_id,stamp.hlc,deleted.then_some(now)])?;
    outbox::enqueue(conn, table, id)?;
    Ok(())
}
pub fn assets(conn: &Connection, owner: &str, include_archived: bool) -> Result<Vec<WealthAsset>> {
    Ok(rows::<WealthAsset>(conn, ASSETS, owner)?
        .into_iter()
        .filter(|a| include_archived || !a.archived)
        .collect())
}
pub fn asset(conn: &Connection, owner: &str, id: &str) -> Result<WealthAsset> {
    get(conn, ASSETS, owner, id)
}
pub fn save_asset(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    mut draft: AssetDraft,
) -> Result<WealthAsset> {
    draft.name = draft.name.trim().to_owned();
    draft.currency = draft.currency.trim().to_uppercase();
    lifeos::money::Currency::new(&draft.currency).map_err(|e| invalid(e.to_string()))?;
    let kind = AssetKind::parse(&draft.kind).ok_or_else(|| invalid("不支持的资产类别"))?;
    if draft.name.is_empty() {
        return Err(invalid("请输入资产名称"));
    }
    draft.market = draft
        .market
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty());
    draft.symbol = draft
        .symbol
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty());
    if draft.market.is_some() != draft.symbol.is_some() {
        return Err(invalid("证券代码和市场必须同时填写"));
    }
    if draft.market.is_some()
        && assets(conn, &st.owner_user_id, true)?.iter().any(|a| {
            Some(a.id.as_str()) != id
                && a.details.market == draft.market
                && a.details.symbol == draft.symbol
        })
    {
        return Err(invalid("这个市场的证券已存在，请使用已有资产"));
    }
    let tx = conn.savepoint()?;
    let item = if let Some(id) = id {
        let mut item = asset(&tx, &st.owner_user_id, id)?;
        if item.archived {
            return Err(invalid("请先恢复已归档资产"));
        }
        if (item.details.currency != draft.currency
            || item.details.kind != draft.kind
            || item.details.market != draft.market
            || item.details.symbol != draft.symbol)
            && !operations(&tx, &st.owner_user_id, Some(id))?.is_empty()
        {
            return Err(invalid("已有交易的资产不能改变类别、证券身份或币种"));
        }
        let mut raw = ar::get_required(&tx, id)?;
        if raw.sync.owner_user_id != st.owner_user_id || raw.sync.deleted_at.is_some() {
            return Err(invalid("资产不属于当前数据空间"));
        }
        raw.kind = kind;
        raw.name = draft.name.clone();
        raw.note = draft.note.clone();
        // Existing asset repository uses transactions; write under this savepoint directly.
        raw.sync = lifeos::sync::SyncMeta::from_stamp(&st.stamp(&tx)?);
        ar::insert_asset(&tx, &raw)?;
        outbox::enqueue(&tx, crate::tables::ASSETS_TABLE, id)?;
        item.details = draft;
        item
    } else {
        let stamp = st.stamp(&tx)?;
        let raw = crate::models::Asset {
            id: lifeos::ids::new_id(),
            kind,
            name: draft.name.clone(),
            note: draft.note.clone(),
            sync: lifeos::sync::SyncMeta::from_stamp(&stamp),
        };
        ar::insert_asset(&tx, &raw)?;
        outbox::enqueue(&tx, crate::tables::ASSETS_TABLE, &raw.id)?;
        WealthAsset {
            id: raw.id,
            details: draft,
            archived: false,
        }
    };
    put(&tx, ASSETS, st, &item.id, &item, false)?;
    tx.commit()?;
    Ok(item)
}
pub fn archive_asset(
    conn: &mut Connection,
    st: &MutationStamper,
    id: &str,
    archived: bool,
) -> Result<()> {
    let mut item = asset(conn, &st.owner_user_id, id)?;
    item.archived = archived;
    let tx = conn.savepoint()?;
    put(&tx, ASSETS, st, id, &item, false)?;
    tx.commit()?;
    Ok(())
}
pub fn delete_asset(conn: &mut Connection, st: &MutationStamper, id: &str) -> Result<()> {
    let item = asset(conn, &st.owner_user_id, id)?;
    if !operations(conn, &st.owner_user_id, Some(id))?.is_empty() {
        return Err(invalid("资产已有交易，请归档以保留历史"));
    }
    let tx = conn.savepoint()?;
    put(&tx, ASSETS, st, id, &item, true)?;
    let stamp = st.stamp(&tx)?;
    let now = stamp.now.div_euclid(1000);
    tx.execute("UPDATE \"fin:assets\" SET deleted_at=?1,updated_at=?1,hlc=?2,updated_by_device=?3 WHERE id=?4 AND owner_user_id=?5",params![now,stamp.hlc,stamp.device_id,id,st.owner_user_id])?;
    outbox::enqueue(&tx, crate::tables::ASSETS_TABLE, id)?;
    tx.commit()?;
    Ok(())
}
pub fn operations(
    conn: &Connection,
    owner: &str,
    asset_id: Option<&str>,
) -> Result<Vec<WealthOperation>> {
    let mut values: Vec<WealthOperation> = rows(conn, OPS, owner)?;
    values.retain(|v| asset_id.is_none_or(|id| v.details.asset_id == id));
    values.sort_by(|a, b| {
        (a.details.date, a.sequence, &a.id).cmp(&(b.details.date, b.sequence, &b.id))
    });
    Ok(values)
}
pub fn operation(conn: &Connection, owner: &str, id: &str) -> Result<WealthOperation> {
    get(conn, OPS, owner, id)
}
pub(super) fn active_account(
    conn: &Connection,
    owner: &str,
    id: &str,
) -> Result<crate::models::Account> {
    let a = accounts::get_required(conn, id)?;
    if a.sync.owner_user_id != owner || a.sync.deleted_at.is_some() || a.archived {
        return Err(invalid("账户不可用，请选择当前数据空间内未归档的账户"));
    }
    Ok(a)
}
fn validate_operation(conn: &Connection, owner: &str, d: &OperationDraft) -> Result<WealthAsset> {
    let a = asset(conn, owner, &d.asset_id)?;
    if a.archived {
        return Err(invalid("请先恢复已归档资产"));
    }
    let custody = active_account(conn, owner, &d.account_id)?;
    if custody.side != crate::models::AccountSide::Asset {
        return Err(invalid("持仓必须属于资产账户"));
    }
    if !is_record_date_allowed(d.date) {
        return Err(invalid("交易日期不能在未来"));
    }
    if d.fees < Decimal::ZERO || d.unit_price < Decimal::ZERO || d.amount < Decimal::ZERO {
        return Err(invalid("价格、费用和金额不能为负数"));
    }
    match d.kind {
        OperationKind::Opening | OperationKind::Buy | OperationKind::Sell => {
            if d.quantity <= Decimal::ZERO || d.unit_price <= Decimal::ZERO {
                return Err(invalid("持仓数量和单价必须大于零"));
            }
            if d.kind == OperationKind::Opening && d.fees != Decimal::ZERO {
                return Err(invalid("期初成本请包含在单价内"));
            }
        }
        OperationKind::Dividend => {
            if d.amount <= Decimal::ZERO || d.fees > d.amount {
                return Err(invalid("分红必须大于零且不少于费用"));
            }
        }
        OperationKind::Split => {
            if d.quantity <= Decimal::ZERO || d.quantity == Decimal::ONE || d.fees != Decimal::ZERO
            {
                return Err(invalid("拆股比例必须为正且不等于 1，拆股不产生费用"));
            }
        }
    }
    if matches!(
        d.kind,
        OperationKind::Buy | OperationKind::Sell | OperationKind::Dividend
    ) {
        let cash = active_account(
            conn,
            owner,
            d.cash_account_id
                .as_deref()
                .ok_or_else(|| invalid("请选择结算账户"))?,
        )?;
        if cash.side != crate::models::AccountSide::Asset || cash.currency != a.details.currency {
            return Err(invalid("结算账户必须为同币种资产账户"));
        }
    }
    Ok(a)
}
pub fn save_operation(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    draft: OperationDraft,
) -> Result<WealthOperation> {
    let tx = conn.savepoint()?;
    let a = validate_operation(&tx, &st.owner_user_id, &draft)?;
    let mut all = operations(&tx, &st.owner_user_id, None)?;
    let (id, sequence) = if let Some(id) = id {
        let old = operation(&tx, &st.owner_user_id, id)?;
        crate::planning::assert_operation_unlinked(&tx, &st.owner_user_id, id)?;
        if old.details.asset_id != draft.asset_id || old.details.account_id != draft.account_id {
            return Err(invalid("修改交易不能改变资产或持仓账户，请删除后重新记录"));
        }
        (old.id, old.sequence)
    } else {
        (
            lifeos::ids::new_id(),
            all.iter()
                .map(|o| o.sequence)
                .max()
                .unwrap_or(0)
                .checked_add(1)
                .ok_or_else(|| invalid("交易序号超过范围"))?,
        )
    };
    let cash_amount = match draft.kind {
        OperationKind::Buy => checked(Decimal::ZERO.checked_sub(checked(
            checked(draft.quantity.checked_mul(draft.unit_price))?.checked_add(draft.fees),
        )?))?,
        OperationKind::Sell => {
            checked(checked(draft.quantity.checked_mul(draft.unit_price))?.checked_sub(draft.fees))?
        }
        OperationKind::Dividend => checked(draft.amount.checked_sub(draft.fees))?,
        _ => Decimal::ZERO,
    };
    if draft.kind == OperationKind::Sell && cash_amount < Decimal::ZERO {
        return Err(invalid("卖出费用不能超过成交金额"));
    }
    let value = WealthOperation {
        id: id.clone(),
        details: draft,
        sequence,
        currency: a.details.currency,
        cash_amount,
    };
    all.retain(|o| o.id != id);
    all.push(value.clone());
    super::replay::rewrite(
        &tx,
        st,
        &all,
        &value.details.asset_id,
        &value.details.account_id,
    )?;
    put(&tx, OPS, st, &id, &value, false)?;
    tx.commit()?;
    Ok(value)
}
pub fn delete_operation(conn: &mut Connection, st: &MutationStamper, id: &str) -> Result<()> {
    let tx = conn.savepoint()?;
    let old = operation(&tx, &st.owner_user_id, id)?;
    crate::planning::assert_operation_unlinked(&tx, &st.owner_user_id, id)?;
    validate_operation(&tx, &st.owner_user_id, &old.details)?;
    let all: Vec<_> = operations(&tx, &st.owner_user_id, None)?
        .into_iter()
        .filter(|o| o.id != id)
        .collect();
    super::replay::rewrite(
        &tx,
        st,
        &all,
        &old.details.asset_id,
        &old.details.account_id,
    )?;
    // Delete journal in the same transaction without nesting &mut Savepoint.
    let stamp = st.stamp(&tx)?;
    let now = stamp.now.div_euclid(1000);
    for table in [
        crate::tables::JOURNAL_ENTRIES_TABLE,
        crate::tables::POSTINGS_TABLE,
    ] {
        let condition = if table == crate::tables::POSTINGS_TABLE {
            "journal_entry_id"
        } else {
            "id"
        };
        let ids: Vec<String> = {
            let mut q = tx.prepare(&format!(
                "SELECT id FROM \"{table}\" WHERE {condition}=?1 AND owner_user_id=?2"
            ))?;
            q.query_map(params![id, st.owner_user_id], |r| r.get(0))?
                .collect::<std::result::Result<_, _>>()?
        };
        tx.execute(&format!("UPDATE \"{table}\" SET deleted_at=?1,updated_at=?1,updated_by_device=?2,hlc=?3 WHERE {condition}=?4 AND owner_user_id=?5"),params![now,stamp.device_id,stamp.hlc,id,st.owner_user_id])?;
        for row in ids {
            outbox::enqueue(&tx, table, &row)?;
        }
    }
    put(&tx, OPS, st, id, &old, true)?;
    tx.commit()?;
    Ok(())
}
pub fn record_price(
    conn: &mut Connection,
    st: &MutationStamper,
    asset_id: &str,
    price: Decimal,
    observed_on: i64,
    source: Option<String>,
) -> Result<AssetPrice> {
    let item = asset(conn, &st.owner_user_id, asset_id)?;
    if item.archived {
        return Err(invalid("请先恢复已归档资产"));
    }
    let source = source
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| "manual".to_owned());
    if !is_quote_date_allowed(observed_on, Some(&source)) {
        return Err(invalid("估值日期不能在未来"));
    }
    ar::record_price(
        conn,
        st,
        NewAssetPrice {
            unit: asset_id.to_owned(),
            quote_currency: item.details.currency,
            observed_on,
            per_unit: price,
            source: Some(source),
        },
    )
}
pub fn prices(conn: &Connection, owner: &str, asset_id: &str) -> Result<Vec<AssetPrice>> {
    asset(conn, owner, asset_id)?;
    Ok(ar::list_prices(conn, asset_id)?
        .into_iter()
        .filter(|p| p.sync.owner_user_id == owner)
        .collect())
}

/// User-authored FX observations use the existing synced price family. Provider
/// caches remain in fx_rates only and are never inferred to be authored facts.
pub fn record_manual_fx(
    conn: &mut Connection,
    st: &MutationStamper,
    from: &str,
    to: &str,
    rate: Decimal,
    observed_on: i64,
) -> Result<()> {
    let from = lifeos::money::Currency::new(from)
        .map_err(|e| invalid(e.to_string()))?
        .to_string();
    let to = lifeos::money::Currency::new(to)
        .map_err(|e| invalid(e.to_string()))?
        .to_string();
    if from == to || rate <= Decimal::ZERO || !is_record_date_allowed(observed_on) {
        return Err(invalid("请选择不同币种，填写大于零的汇率及非未来日期"));
    }
    let tx = conn.savepoint()?;
    let stamp = st.stamp(&tx)?;
    let id = lifeos::ids::new_id();
    tx.execute(r#"INSERT INTO "fin:prices" (id,unit,quote_currency,observed_on,per_unit,source,owner_user_id,updated_at,updated_by_device,hlc,deleted_at) VALUES (?1,?2,?3,?4,?5,'manual_fx',?6,?7,?8,?9,NULL)"#,
        params![id,from,to,observed_on,rate.to_string(),st.owner_user_id,stamp.now.div_euclid(1000),stamp.device_id,stamp.hlc])?;
    outbox::enqueue(&tx, crate::tables::PRICES_TABLE, &id)?;
    rebuild_manual_fx(&tx, &st.owner_user_id)?;
    tx.commit()?;
    Ok(())
}

/// Replace the authored portion of the device FX cache for exactly this owner.
/// Call inside the caller's transaction after restore, sync, reset, adoption or
/// owner change, and during init before queries. Removing rates in a restore
/// therefore removes their later cache values too. Unrelated provider rows stay;
/// an authored rate overrides the same provider pair/day until the next refresh.
pub fn rebuild_manual_fx(conn: &Connection, owner: &str) -> Result<usize> {
    let rates = {
        let mut q = conn.prepare(r#"SELECT unit,quote_currency,observed_on,per_unit FROM "fin:prices" WHERE source='manual_fx' AND owner_user_id=?1 AND deleted_at IS NULL ORDER BY observed_on,hlc,id"#)?;
        q.query_map([owner], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, i64>(2)?,
                r.get::<_, String>(3)?,
            ))
        })?
        .map(|row| {
            let (from, to, date, raw) = row?;
            let from = lifeos::money::Currency::new(from)
                .map_err(|e| invalid(e.to_string()))?
                .to_string();
            let to = lifeos::money::Currency::new(to)
                .map_err(|e| invalid(e.to_string()))?
                .to_string();
            let rate = Decimal::from_str_exact(&raw).map_err(|e| invalid(e.to_string()))?;
            if from == to || rate <= Decimal::ZERO {
                return Err(invalid("已保存的手动汇率无效，请修复来源记录"));
            }
            Ok((from, to, date, rate))
        })
        .collect::<Result<Vec<_>>>()?
    };
    conn.execute("DELETE FROM fx_rates WHERE source='manual_fx'", [])?;
    let mut count = 0;
    for (from, to, date, rate) in rates {
        if is_record_date_allowed(date) {
            crate::fx::upsert_rate(conn, &from, &to, date, rate, Some("manual_fx"))?;
            count += 1;
        }
    }
    Ok(count)
}
