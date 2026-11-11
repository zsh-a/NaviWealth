//! Deterministic Finance planning. User intent syncs as typed complete aggregates;
//! cash movements always use the authoritative journal in the same transaction.
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

use crate::{
    FinanceError, Result, builders, daily,
    models::{Account, AccountCategory, AccountSide, EntryFlag},
    repos::{account_repository as accounts, journal_repository as journal},
};
use chrono::{TimeZone, Utc};
use lifeos::{
    db::migrations::Migration,
    sync::{MutationStamper, SqlTableAdapter, SyncRegistry, outbox},
};
use rusqlite::{Connection, OptionalExtension, params};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{collections::BTreeMap, sync::Arc};

pub mod portfolio;
pub use portfolio::*;

pub const TABLE: &str = "fin:planning";
const COLUMNS: &[&str] = &[
    "id",
    "kind",
    "payload",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];
pub fn migration() -> Migration {
    Migration {
        version: 8,
        name: "finance-planning",
        sql: r#"
CREATE TABLE "fin:planning" (
 id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL,
 owner_user_id TEXT NOT NULL, updated_at INTEGER NOT NULL,
 updated_by_device TEXT NOT NULL, hlc TEXT NOT NULL, deleted_at INTEGER
);
CREATE INDEX idx_planning_owner_kind ON "fin:planning"(owner_user_id,kind);
"#,
    }
}
pub fn register(registry: &mut SyncRegistry) {
    registry.add(Arc::new(SqlTableAdapter::new(
        TABLE,
        lifeos::error::Domain::Finance,
        COLUMNS,
    )));
}

#[derive(Debug, Clone, PartialEq)]
pub struct Stored<T> {
    pub id: String,
    pub data: T,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlanKind {
    Budget,
    Recurring,
    Goal,
    Dca,
    Fire,
    CashScenario,
    Portfolio,
}
pub fn remove_plan(
    conn: &mut Connection,
    st: &MutationStamper,
    kind: PlanKind,
    id: &str,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let family = match kind {
        PlanKind::Budget => "budget",
        PlanKind::Recurring => "recurring",
        PlanKind::Goal => "goal",
        PlanKind::Dca => "dca",
        PlanKind::Fire => "fire",
        PlanKind::CashScenario => "cash_scenario",
        PlanKind::Portfolio => "portfolio",
    };
    let _: serde_json::Value = get(&tx, &st.owner_user_id, family, id)?;
    let protected = match kind {
        PlanKind::Recurring => has_resolutions(&tx, &st.owner_user_id, "recurring-occurrence", id)?,
        PlanKind::Dca => has_resolutions(&tx, &st.owner_user_id, "dca-occurrence", id)?,
        PlanKind::Goal => {
            list::<Contribution>(&tx, &st.owner_user_id, "contribution")?
                .iter()
                .any(|c| c.data.goal_id == id)
                || list::<DcaPlan>(&tx, &st.owner_user_id, "dca")?
                    .iter()
                    .any(|p| p.data.goal_id.as_deref() == Some(id))
        }
        PlanKind::Portfolio => {
            list::<RebalanceReceipt>(&tx, &st.owner_user_id, "rebalance_receipt")?
                .iter()
                .any(|r| r.data.plan_id == id)
        }
        _ => false,
    };
    if protected {
        return Err(invalid(
            "此计划已有处理记录或关联，请先撤销关联；周期计划也可暂停以保留历史",
        ));
    }
    tombstone(&tx, st, family, id)?;
    tx.commit()?;
    Ok(())
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum PlanningSource {
    Recurring { template_id: String, due: i64 },
    Liability { liability_id: String, index: u32 },
    LiabilityOpening { liability_id: String },
    Dca { plan_id: String, due: i64 },
}
/// A structured journal must be corrected through its owning lifecycle, never
/// rewritten by the two-leg daily form. This also resolves deleted evidence.
pub fn source_for_entry(
    conn: &Connection,
    owner: &str,
    journal_id: &str,
) -> Result<Option<PlanningSource>> {
    for d in liabilities(conn, owner)? {
        if journal_id == format!("liability-opening:{}", d.id) {
            return Ok(Some(PlanningSource::LiabilityOpening {
                liability_id: d.id,
            }));
        }
    }
    for r in list::<Resolution>(conn, owner, "resolution")? {
        if r.data.journal_id.as_deref() != Some(journal_id) {
            continue;
        }
        let parts: Vec<String> =
            serde_json::from_str(&r.id).map_err(|_| invalid("到期行动身份损坏"))?;
        if parts.len() != 4 || parts[0] != owner {
            return Err(invalid("到期行动所属数据空间无效"));
        }
        let source = match parts[1].as_str() {
            "recurring-occurrence" => PlanningSource::Recurring {
                template_id: parts[2].clone(),
                due: parts[3].parse().map_err(|_| invalid("到期日期无效"))?,
            },
            "installment" => PlanningSource::Liability {
                liability_id: parts[2].clone(),
                index: parts[3].parse().map_err(|_| invalid("还款期数无效"))?,
            },
            "dca-occurrence" => PlanningSource::Dca {
                plan_id: parts[2].clone(),
                due: parts[3].parse().map_err(|_| invalid("定投日期无效"))?,
            },
            _ => continue,
        };
        return Ok(Some(source));
    }
    Ok(None)
}
#[derive(Debug, Clone, PartialEq)]
pub struct PlanningAction {
    pub source: PlanningSource,
    pub name: String,
    pub due: i64,
    pub amount: Decimal,
    pub currency: String,
    pub state: OccurrenceState,
    pub journal_id: Option<String>,
}
pub fn planning_actions(
    conn: &Connection,
    owner: &str,
    from: i64,
    until: i64,
) -> Result<Vec<PlanningAction>> {
    let mut actions = occurrences(conn, owner, from, until)?
        .into_iter()
        .map(|o| PlanningAction {
            source: PlanningSource::Recurring {
                template_id: o.template_id,
                due: o.due,
            },
            name: o.name,
            due: o.due,
            amount: o.amount,
            currency: o.currency,
            state: o.state,
            journal_id: o.journal_id,
        })
        .collect::<Vec<_>>();
    for d in liabilities(conn, owner)? {
        for i in liability_schedule(conn, owner, &d.id)? {
            if i.due >= from && i.due < until {
                actions.push(PlanningAction {
                    source: PlanningSource::Liability {
                        liability_id: d.id.clone(),
                        index: i.index,
                    },
                    name: d.data.terms.name.clone(),
                    due: i.due,
                    amount: i.total,
                    currency: d.data.terms.currency.clone(),
                    state: i.state,
                    journal_id: i.journal_id,
                });
            }
        }
    }
    for o in dca_occurrences(conn, owner, from, until)? {
        actions.push(PlanningAction {
            source: PlanningSource::Dca {
                plan_id: o.template_id,
                due: o.due,
            },
            name: o.name,
            due: o.due,
            amount: o.amount,
            currency: o.currency,
            state: o.state,
            journal_id: o.journal_id,
        });
    }
    actions.sort_by_key(|a| a.due);
    Ok(actions)
}
fn invalid(s: &str) -> FinanceError {
    FinanceError::InvalidData(s.to_owned())
}
fn add(a: Decimal, b: Decimal) -> Result<Decimal> {
    a.checked_add(b).ok_or_else(|| invalid("金额超出支持范围"))
}
fn sub(a: Decimal, b: Decimal) -> Result<Decimal> {
    a.checked_sub(b).ok_or_else(|| invalid("金额超出支持范围"))
}
fn mul(a: Decimal, b: Decimal) -> Result<Decimal> {
    a.checked_mul(b).ok_or_else(|| invalid("金额超出支持范围"))
}
fn div(a: Decimal, b: Decimal) -> Result<Decimal> {
    a.checked_div(b)
        .ok_or_else(|| invalid("计算分母无效或金额超出范围"))
}
fn positive(a: Decimal) -> Result<()> {
    if a <= Decimal::ZERO {
        Err(invalid("金额必须大于零"))
    } else {
        Ok(())
    }
}
fn currency(code: &str) -> Result<()> {
    let parsed = lifeos::money::Currency::new(code).map_err(|_| invalid("币种无效"))?;
    if parsed.as_str() != code {
        return Err(invalid("请使用大写且无空格的币种代码"));
    }
    Ok(())
}
fn loan_decimals(conn: &Connection, code: &str) -> Result<u32> {
    let stored: Option<i64> = conn
        .query_row(
            "SELECT decimals FROM currencies WHERE code=?1",
            [code],
            |r| r.get(0),
        )
        .optional()?;
    let decimals = stored.unwrap_or(match code {
        "JPY" | "KRW" | "VND" => 0,
        "KWD" | "BHD" | "OMR" | "JOD" | "TND" => 3,
        _ => 2,
    });
    if !(0..=18).contains(&decimals) {
        return Err(invalid("币种的小数位配置无效"));
    }
    Ok(decimals as u32)
}
fn name(s: &str) -> Result<()> {
    if s.trim().is_empty() || s.chars().count() > 100 {
        Err(invalid("名称须为 1–100 字"))
    } else {
        Ok(())
    }
}
fn key(parts: &[&str]) -> String {
    serde_json::to_string(parts).expect("string list serialization")
}
fn get<T: DeserializeOwned>(conn: &Connection, owner: &str, kind: &str, id: &str) -> Result<T> {
    let raw:Option<String>=conn.query_row(r#"SELECT payload FROM "fin:planning" WHERE id=?1 AND owner_user_id=?2 AND kind=?3 AND deleted_at IS NULL"#,params![id,owner,kind],|r|r.get(0)).optional()?;
    serde_json::from_str(&raw.ok_or_else(|| invalid("计划不存在或无法访问"))?)
        .map_err(|_| invalid("计划数据无法读取"))
}
fn list<T: DeserializeOwned>(conn: &Connection, owner: &str, kind: &str) -> Result<Vec<Stored<T>>> {
    let mut stmt=conn.prepare_cached(r#"SELECT id,payload FROM "fin:planning" WHERE owner_user_id=?1 AND kind=?2 AND deleted_at IS NULL ORDER BY id"#)?;
    let rows = stmt.query_map(params![owner, kind], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
    })?;
    rows.map(|r| {
        let (id, raw) = r?;
        Ok(Stored {
            id,
            data: serde_json::from_str(&raw).map_err(|_| invalid("计划数据无法读取"))?,
        })
    })
    .collect()
}
fn put<T: Serialize>(
    conn: &Connection,
    st: &MutationStamper,
    kind: &str,
    id: &str,
    value: &T,
) -> Result<()> {
    let foreign:bool=conn.query_row(r#"SELECT EXISTS(SELECT 1 FROM "fin:planning" WHERE id=?1 AND (owner_user_id<>?2 OR kind<>?3))"#,params![id,st.owner_user_id,kind],|r|r.get(0))?;
    if foreign {
        return Err(invalid("计划所属数据空间不一致"));
    }
    let payload = serde_json::to_string(value).map_err(|_| invalid("计划无法保存"))?;
    let stamp = st.stamp(conn)?;
    conn.execute(r#"INSERT INTO "fin:planning"(id,kind,payload,owner_user_id,updated_at,updated_by_device,hlc,deleted_at) VALUES(?1,?2,?3,?4,?5,?6,?7,NULL) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at,updated_by_device=excluded.updated_by_device,hlc=excluded.hlc,deleted_at=NULL"#,params![id,kind,payload,st.owner_user_id,stamp.now.div_euclid(1000),stamp.device_id,stamp.hlc])?;
    outbox::enqueue(conn, TABLE, id)?;
    Ok(())
}
fn tombstone(conn: &Connection, st: &MutationStamper, kind: &str, id: &str) -> Result<()> {
    let _: serde_json::Value = get(conn, &st.owner_user_id, kind, id)?;
    let stamp = st.stamp(conn)?;
    conn.execute(r#"UPDATE "fin:planning" SET deleted_at=?1,updated_at=?1,updated_by_device=?2,hlc=?3 WHERE id=?4 AND owner_user_id=?5 AND kind=?6"#,params![stamp.now.div_euclid(1000),stamp.device_id,stamp.hlc,id,st.owner_user_id,kind])?;
    outbox::enqueue(conn, TABLE, id)?;
    Ok(())
}
/// Plan-linked trades must be unlinked explicitly before their economic facts
/// can change; otherwise stored capital inclusions could silently become false.
pub fn assert_operation_unlinked(conn: &Connection, owner: &str, operation_id: &str) -> Result<()> {
    if list::<Resolution>(conn, owner, "resolution")?
        .iter()
        .any(|r| r.data.journal_id.as_deref() == Some(operation_id))
    {
        return Err(invalid("此成交已用于计划，请先在计划中撤销关联"));
    }
    if list::<RebalanceReceipt>(conn, owner, "rebalance_receipt")?
        .iter()
        .any(|r| r.data.operation_id == operation_id)
    {
        return Err(invalid("此成交已用于再平衡，请先撤销再平衡关联"));
    }
    Ok(())
}
fn owned_account(conn: &Connection, owner: &str, id: &str, side: AccountSide) -> Result<Account> {
    accounts::get(conn, id)?
        .filter(|a| {
            a.sync.owner_user_id == owner
                && a.sync.deleted_at.is_none()
                && !a.archived
                && a.side == side
        })
        .ok_or_else(|| invalid("账户不可用，请重新选择"))
}
fn cash_account(conn: &Connection, owner: &str, id: &str, code: &str) -> Result<Account> {
    let a = owned_account(conn, owner, id, AccountSide::Asset)?;
    if !matches!(
        a.kind,
        AccountCategory::Cash | AccountCategory::Bank | AccountCategory::Broker
    ) || a.currency != code
    {
        return Err(invalid("请选择同币种现金账户"));
    }
    Ok(a)
}
fn posting_sum(
    conn: &Connection,
    owner: &str,
    account: &str,
    unit: &str,
    as_of: i64,
) -> Result<Decimal> {
    let mut total = Decimal::ZERO;
    for row in journal::list_owned(conn, owner, None, Some(as_of.saturating_add(1)))? {
        for p in row.postings {
            if p.account_id == account && p.unit == unit {
                total = add(total, p.units)?;
            }
        }
    }
    Ok(total)
}
fn write_journal(
    conn: &Connection,
    st: &MutationStamper,
    id: &str,
    code: &str,
    build: builders::EntryBuild,
) -> Result<()> {
    let fx = |c: &Connection, f: &str, t: &str, d: i64| crate::fx::rate_at(c, f, t, d);
    journal::create_in_transaction(conn, st, &fx, code, build, Some(id))?;
    Ok(())
}
fn delete_journal(conn: &Connection, st: &MutationStamper, id: &str) -> Result<()> {
    let entry = journal::get(conn, id)?
        .filter(|e| e.entry.sync.owner_user_id == st.owner_user_id)
        .ok_or_else(|| invalid("关联流水不存在"))?;
    let stamp = st.stamp(conn)?;
    conn.execute(r#"UPDATE "fin:journal_entries" SET deleted_at=?2,hlc=?3,updated_at=?2,updated_by_device=?4 WHERE id=?1"#,params![id,stamp.now.div_euclid(1000),stamp.hlc,stamp.device_id])?;
    outbox::enqueue(conn, crate::tables::JOURNAL_ENTRIES_TABLE, id)?;
    for p in entry.postings {
        conn.execute(r#"UPDATE "fin:postings" SET deleted_at=?2,hlc=?3,updated_at=?2,updated_by_device=?4 WHERE id=?1"#,params![p.id,stamp.now.div_euclid(1000),stamp.hlc,stamp.device_id])?;
        outbox::enqueue(conn, crate::tables::POSTINGS_TABLE, &p.id)?;
    }
    Ok(())
}
pub fn month_bounds(month: &str) -> Result<(i64, i64)> {
    let d = chrono::NaiveDate::parse_from_str(&format!("{month}-01"), "%Y-%m-%d")
        .map_err(|_| invalid("月份格式应为 YYYY-MM"))?;
    if d.format("%Y-%m").to_string() != month {
        return Err(invalid("月份格式应为 YYYY-MM"));
    }
    let start = d
        .and_hms_opt(0, 0, 0)
        .ok_or_else(|| invalid("月份无效"))?
        .and_utc()
        .timestamp();
    Ok((start, add_months(start, 1)?))
}
fn add_months(epoch: i64, months: u32) -> Result<i64> {
    let d = Utc
        .timestamp_opt(epoch, 0)
        .single()
        .ok_or_else(|| invalid("日期超出范围"))?;
    d.checked_add_months(chrono::Months::new(months))
        .map(|v| v.timestamp())
        .ok_or_else(|| invalid("日期超出范围"))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Budget {
    pub month: String,
    pub category_id: String,
    pub currency: String,
    #[serde(with = "decimal")]
    pub limit: Decimal,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BudgetProgress {
    pub id: String,
    pub budget: Budget,
    pub spent: Decimal,
    pub remaining: Decimal,
    pub entry_ids: Vec<String>,
}
pub fn save_budget(conn: &mut Connection, st: &MutationStamper, budget: Budget) -> Result<String> {
    month_bounds(&budget.month)?;
    currency(&budget.currency)?;
    positive(budget.limit)?;
    owned_account(
        conn,
        &st.owner_user_id,
        &budget.category_id,
        AccountSide::Expense,
    )?;
    let id = key(&[
        &st.owner_user_id,
        "budget",
        &budget.month,
        &budget.category_id,
        &budget.currency,
    ]);
    let tx = conn.savepoint()?;
    put(&tx, st, "budget", &id, &budget)?;
    tx.commit()?;
    Ok(id)
}
pub fn budgets(conn: &Connection, owner: &str, month: &str) -> Result<Vec<BudgetProgress>> {
    let (from, until) = month_bounds(month)?;
    let rows = journal::list_owned(conn, owner, Some(from), Some(until))?;
    list::<Budget>(conn, owner, "budget")?
        .into_iter()
        .filter(|b| b.data.month == month)
        .map(|s| {
            let mut spent = Decimal::ZERO;
            let mut ids = Vec::new();
            for row in &rows {
                let mut hit = false;
                for p in &row.postings {
                    if p.account_id == s.data.category_id && p.unit == s.data.currency {
                        spent = add(spent, p.units)?;
                        hit = true;
                    }
                }
                if hit {
                    ids.push(row.entry.id.clone());
                }
            }
            Ok(BudgetProgress {
                id: s.id,
                remaining: sub(s.data.limit, spent)?,
                budget: s.data,
                spent,
                entry_ids: ids,
            })
        })
        .collect()
}
pub fn budget(conn: &Connection, owner: &str, id: &str) -> Result<BudgetProgress> {
    let b: Budget = get(conn, owner, "budget", id)?;
    budgets(conn, owner, &b.month)?
        .into_iter()
        .find(|b| b.id == id)
        .ok_or_else(|| invalid("预算不存在"))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FlowKind {
    Income,
    Bill,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Recurring {
    pub name: String,
    pub kind: FlowKind,
    pub account_id: String,
    pub category_id: String,
    pub currency: String,
    #[serde(with = "decimal")]
    pub amount: Decimal,
    pub first_due: i64,
    pub interval_months: u32,
    pub end_due: Option<i64>,
    pub paused: bool,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OccurrenceState {
    Due,
    Posted,
    Skipped,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
struct Resolution {
    state: OccurrenceState,
    journal_id: Option<String>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Occurrence {
    pub template_id: String,
    pub due: i64,
    pub amount: Decimal,
    pub currency: String,
    pub name: String,
    pub state: OccurrenceState,
    pub journal_id: Option<String>,
}
pub fn save_recurring(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    draft: Recurring,
) -> Result<String> {
    name(&draft.name)?;
    currency(&draft.currency)?;
    positive(draft.amount)?;
    if draft.interval_months == 0
        || draft.interval_months > 120
        || draft.end_due.is_some_and(|d| d < draft.first_due)
    {
        return Err(invalid("重复周期或结束日期无效"));
    }
    add_months(draft.first_due, 0)?;
    cash_account(conn, &st.owner_user_id, &draft.account_id, &draft.currency)?;
    owned_account(
        conn,
        &st.owner_user_id,
        &draft.category_id,
        if draft.kind == FlowKind::Income {
            AccountSide::Income
        } else {
            AccountSide::Expense
        },
    )?;
    if let Some(id) = id {
        let mut previous: Recurring = get(conn, &st.owner_user_id, "recurring", id)?;
        previous.name = draft.name.clone();
        previous.paused = draft.paused;
        if previous != draft
            && has_resolutions(conn, &st.owner_user_id, "recurring-occurrence", id)?
        {
            return Err(invalid(
                "该计划已有处理记录；请暂停旧计划并新建调整后的计划，或先撤销原期次",
            ));
        }
    }
    let id = id.map(str::to_owned).unwrap_or_else(lifeos::ids::new_id);
    let tx = conn.savepoint()?;
    put(&tx, st, "recurring", &id, &draft)?;
    tx.commit()?;
    Ok(id)
}
pub fn list_recurring(conn: &Connection, owner: &str) -> Result<Vec<Stored<Recurring>>> {
    list(conn, owner, "recurring")
}
fn recurring_dates(draft: &Recurring, from: i64, until: i64) -> Result<Vec<i64>> {
    if from >= until {
        return Err(invalid("开始日期必须早于结束日期"));
    }
    let mut out = Vec::new();
    for n in 0_u32..12000 {
        let m = n
            .checked_mul(draft.interval_months)
            .ok_or_else(|| invalid("周期超出范围"))?;
        let due = add_months(draft.first_due, m)?;
        if due >= until || draft.end_due.is_some_and(|d| due > d) {
            return Ok(out);
        }
        if due >= from {
            out.push(due);
        }
    }
    Err(invalid("重复计划超过 1000 年范围"))
}
fn resolution(conn: &Connection, owner: &str, id: &str) -> Result<Resolution> {
    let exists:bool=conn.query_row(r#"SELECT EXISTS(SELECT 1 FROM "fin:planning" WHERE id=?1 AND owner_user_id=?2 AND kind='resolution' AND deleted_at IS NULL)"#,params![id,owner],|r|r.get(0))?;
    if exists {
        get(conn, owner, "resolution", id)
    } else {
        Ok(Resolution {
            state: OccurrenceState::Due,
            journal_id: None,
        })
    }
}
fn has_resolutions(conn: &Connection, owner: &str, kind: &str, template_id: &str) -> Result<bool> {
    for r in list::<Resolution>(conn, owner, "resolution")? {
        let parts: Vec<String> =
            serde_json::from_str(&r.id).map_err(|_| invalid("到期行动身份损坏"))?;
        if parts.len() == 4
            && parts[0] == owner
            && parts[1] == kind
            && parts[2] == template_id
            && r.data.state != OccurrenceState::Due
        {
            return Ok(true);
        }
    }
    Ok(false)
}
pub fn occurrences(
    conn: &Connection,
    owner: &str,
    from: i64,
    until: i64,
) -> Result<Vec<Occurrence>> {
    let mut out = Vec::new();
    for s in list_recurring(conn, owner)? {
        for due in recurring_dates(&s.data, from, until)? {
            let id = key(&[owner, "recurring-occurrence", &s.id, &due.to_string()]);
            let r = resolution(conn, owner, &id)?;
            if s.data.paused && r.state == OccurrenceState::Due {
                continue;
            }
            out.push(Occurrence {
                template_id: s.id.clone(),
                due,
                amount: s.data.amount,
                currency: s.data.currency.clone(),
                name: s.data.name.clone(),
                state: r.state,
                journal_id: r.journal_id,
            });
        }
    }
    out.sort_by_key(|o| (o.due, o.template_id.clone()));
    Ok(out)
}
pub fn resolve_occurrence(
    conn: &mut Connection,
    st: &MutationStamper,
    template_id: &str,
    due: i64,
    post: bool,
) -> Result<Option<String>> {
    let tx = conn.savepoint()?;
    let d: Recurring = get(&tx, &st.owner_user_id, "recurring", template_id)?;
    if d.paused
        || !recurring_dates(
            &d,
            due,
            due.checked_add(1).ok_or_else(|| invalid("日期无效"))?,
        )?
        .contains(&due)
    {
        return Err(invalid("该日期不是活动计划的到期日"));
    }
    let id = key(&[
        &st.owner_user_id,
        "recurring-occurrence",
        template_id,
        &due.to_string(),
    ]);
    let previous = resolution(&tx, &st.owner_user_id, &id)?;
    if previous.state != OccurrenceState::Due {
        if (post && previous.state == OccurrenceState::Posted)
            || (!post && previous.state == OccurrenceState::Skipped)
        {
            return Ok(previous.journal_id);
        }
        return Err(invalid("该期已处理，请先撤销"));
    }
    let journal_id = if post {
        cash_account(&tx, &st.owner_user_id, &d.account_id, &d.currency)?;
        owned_account(
            &tx,
            &st.owner_user_id,
            &d.category_id,
            if d.kind == FlowKind::Income {
                AccountSide::Income
            } else {
                AccountSide::Expense
            },
        )?;
        let build = if d.kind == FlowKind::Income {
            builders::income(
                due,
                &d.account_id,
                &d.category_id,
                d.amount,
                &d.currency,
                None,
                Some(&d.name),
                None,
                vec![format!("recurring:{template_id}")],
            )?
        } else {
            builders::expense(
                due,
                &d.category_id,
                &d.account_id,
                d.amount,
                &d.currency,
                None,
                Some(&d.name),
                None,
                vec![format!("recurring:{template_id}")],
            )?
        };
        let jid = format!("planning:{id}");
        write_journal(&tx, st, &jid, &d.currency, build)?;
        Some(jid)
    } else {
        None
    };
    put(
        &tx,
        st,
        "resolution",
        &id,
        &Resolution {
            state: if post {
                OccurrenceState::Posted
            } else {
                OccurrenceState::Skipped
            },
            journal_id: journal_id.clone(),
        },
    )?;
    tx.commit()?;
    Ok(journal_id)
}
pub fn undo_occurrence(
    conn: &mut Connection,
    st: &MutationStamper,
    template_id: &str,
    due: i64,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let _: Recurring = get(&tx, &st.owner_user_id, "recurring", template_id)?;
    let id = key(&[
        &st.owner_user_id,
        "recurring-occurrence",
        template_id,
        &due.to_string(),
    ]);
    let r = resolution(&tx, &st.owner_user_id, &id)?;
    if let Some(jid) = r.journal_id {
        delete_journal(&tx, st, &jid)?;
    }
    put(
        &tx,
        st,
        "resolution",
        &id,
        &Resolution {
            state: OccurrenceState::Due,
            journal_id: None,
        },
    )?;
    tx.commit()?;
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LiabilityDraft {
    pub name: String,
    pub currency: String,
    #[serde(with = "decimal")]
    pub principal: Decimal,
    #[serde(with = "decimal")]
    pub annual_rate: Decimal,
    pub months: u32,
    pub opened_on: i64,
    pub first_due: i64,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Liability {
    pub terms: LiabilityDraft,
    pub account_id: String,
    #[serde(default)]
    pub archived: bool,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Installment {
    pub index: u32,
    pub due: i64,
    pub principal: Decimal,
    pub interest: Decimal,
    pub total: Decimal,
    pub state: OccurrenceState,
    pub journal_id: Option<String>,
}
pub fn create_liability(
    conn: &mut Connection,
    st: &MutationStamper,
    draft: LiabilityDraft,
) -> Result<String> {
    name(&draft.name)?;
    currency(&draft.currency)?;
    positive(draft.principal)?;
    if draft.annual_rate < Decimal::ZERO
        || draft.annual_rate > Decimal::ONE
        || draft.months == 0
        || draft.months > 600
        || draft.first_due < draft.opened_on
    {
        return Err(invalid("贷款利率、期数或日期无效"));
    }
    let decimals = loan_decimals(conn, &draft.currency)?;
    let smallest = Decimal::new(1, decimals);
    if draft.principal.round_dp(decimals) != draft.principal
        || div(draft.principal, Decimal::from(draft.months))? < smallest
    {
        return Err(invalid(
            "本金小数位无效，或不足以让每期至少偿还一个最小货币单位",
        ));
    }
    let tx = conn.savepoint()?;
    let id = lifeos::ids::new_id();
    let a = accounts::create(
        &tx,
        st,
        crate::models::NewAccount::custody(AccountCategory::Loan, &draft.name, &draft.currency),
    )?;
    let build = builders::opening_balance(
        draft.opened_on,
        &a.id,
        accounts::system_account_id(&st.owner_user_id, "equity:openingBalance"),
        -draft.principal,
        &draft.currency,
        Some(&draft.name),
        None,
        vec![format!("liability:{id}")],
    )?;
    write_journal(
        &tx,
        st,
        &format!("liability-opening:{id}"),
        &draft.currency,
        build,
    )?;
    put(
        &tx,
        st,
        "liability",
        &id,
        &Liability {
            terms: draft,
            account_id: a.id,
            archived: false,
        },
    )?;
    tx.commit()?;
    Ok(id)
}
pub fn liabilities(conn: &Connection, owner: &str) -> Result<Vec<Stored<Liability>>> {
    list(conn, owner, "liability")
}
fn untouched_liability(conn: &Connection, owner: &str, id: &str, loan: &Liability) -> Result<()> {
    if liability_schedule(conn, owner, id)?
        .iter()
        .any(|i| i.state != OccurrenceState::Due)
    {
        return Err(invalid("已有还款记录；请先按倒序撤销还款后再修正合同"));
    }
    for row in journal::list_owned(conn, owner, None, None)? {
        if row.entry.id != format!("liability-opening:{id}")
            && row.postings.iter().any(|p| p.account_id == loan.account_id)
        {
            return Err(invalid("该债务有其他真实流水，请先核对相关记录"));
        }
    }
    Ok(())
}
pub fn update_liability(
    conn: &mut Connection,
    st: &MutationStamper,
    id: &str,
    draft: LiabilityDraft,
) -> Result<()> {
    name(&draft.name)?;
    currency(&draft.currency)?;
    positive(draft.principal)?;
    if draft.annual_rate < Decimal::ZERO
        || draft.annual_rate > Decimal::ONE
        || draft.months == 0
        || draft.months > 600
        || draft.first_due < draft.opened_on
    {
        return Err(invalid("贷款利率、期数或日期无效"));
    }
    add_months(draft.first_due, draft.months)?;
    let decimals = loan_decimals(conn, &draft.currency)?;
    if draft.principal.round_dp(decimals) != draft.principal
        || div(draft.principal, Decimal::from(draft.months))? < Decimal::new(1, decimals)
    {
        return Err(invalid("本金小数位或每期最小本金无效"));
    }
    let tx = conn.savepoint()?;
    let mut loan: Liability = get(&tx, &st.owner_user_id, "liability", id)?;
    untouched_liability(&tx, &st.owner_user_id, id, &loan)?;
    if draft.currency != loan.terms.currency {
        return Err(invalid("贷款币种不能修改，请新建正确币种的合同"));
    }
    let mut account = accounts::get_required(&tx, &loan.account_id)?;
    account.name = draft.name.clone();
    accounts::update(&tx, st, &account)?;
    let build = builders::opening_balance(
        draft.opened_on,
        &loan.account_id,
        accounts::system_account_id(&st.owner_user_id, "equity:openingBalance"),
        -draft.principal,
        &draft.currency,
        Some(&draft.name),
        None,
        vec![format!("liability:{id}")],
    )?;
    write_journal(
        &tx,
        st,
        &format!("liability-opening:{id}"),
        &draft.currency,
        build,
    )?;
    loan.terms = draft;
    put(&tx, st, "liability", id, &loan)?;
    tx.commit()?;
    Ok(())
}
pub fn delete_liability(conn: &mut Connection, st: &MutationStamper, id: &str) -> Result<()> {
    let tx = conn.savepoint()?;
    let loan: Liability = get(&tx, &st.owner_user_id, "liability", id)?;
    untouched_liability(&tx, &st.owner_user_id, id, &loan)?;
    delete_journal(&tx, st, &format!("liability-opening:{id}"))?;
    accounts::soft_delete(&tx, st, &loan.account_id)?;
    tombstone(&tx, st, "liability", id)?;
    tx.commit()?;
    Ok(())
}
pub fn archive_liability(
    conn: &mut Connection,
    st: &MutationStamper,
    id: &str,
    archived: bool,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let mut loan: Liability = get(&tx, &st.owner_user_id, "liability", id)?;
    if archived
        && (posting_sum(
            &tx,
            &st.owner_user_id,
            &loan.account_id,
            &loan.terms.currency,
            i64::MAX - 1,
        )? != Decimal::ZERO
            || liability_schedule(&tx, &st.owner_user_id, id)?
                .iter()
                .any(|i| i.state != OccurrenceState::Posted))
    {
        return Err(invalid("仅已清偿且计划全部处理的贷款可归档"));
    }
    accounts::set_archived(&tx, st, &loan.account_id, archived)?;
    loan.archived = archived;
    put(&tx, st, "liability", id, &loan)?;
    tx.commit()?;
    Ok(())
}
pub fn liability_schedule(conn: &Connection, owner: &str, id: &str) -> Result<Vec<Installment>> {
    let d: Liability = get(conn, owner, "liability", id)?;
    let mut balance = d.terms.principal;
    let decimals = loan_decimals(conn, &d.terms.currency)?;
    let rate = div(d.terms.annual_rate, Decimal::from(12))?;
    let mut out = Vec::new();
    for index in 0..d.terms.months {
        // Round cumulative principal, then take the difference. This fairly
        // distributes minor-unit remainders without zero/negative final rows.
        let cumulative = div(
            mul(d.terms.principal, Decimal::from(index + 1))?,
            Decimal::from(d.terms.months),
        )?
        .round_dp(decimals);
        let principal = sub(cumulative, sub(d.terms.principal, balance)?)?;
        let interest = mul(balance, rate)?.round_dp(decimals);
        let total = add(principal, interest)?;
        let rid = key(&[owner, "installment", id, &index.to_string()]);
        let r = resolution(conn, owner, &rid)?;
        out.push(Installment {
            index,
            due: add_months(d.terms.first_due, index)?,
            principal,
            interest,
            total,
            state: r.state,
            journal_id: r.journal_id,
        });
        balance = sub(balance, principal)?;
    }
    Ok(out)
}
pub fn pay_installment(
    conn: &mut Connection,
    st: &MutationStamper,
    id: &str,
    index: u32,
    cash_id: &str,
    paid_on: i64,
) -> Result<String> {
    let tx = conn.savepoint()?;
    let d: Liability = get(&tx, &st.owner_user_id, "liability", id)?;
    let schedule = liability_schedule(&tx, &st.owner_user_id, id)?;
    let item = schedule
        .get(index as usize)
        .ok_or_else(|| invalid("还款期数无效"))?;
    if let Some(jid) = &item.journal_id {
        return Ok(jid.clone());
    }
    if schedule
        .iter()
        .take(index as usize)
        .any(|i| i.state != OccurrenceState::Posted)
    {
        return Err(invalid("请先处理前期还款"));
    }
    cash_account(&tx, &st.owner_user_id, cash_id, &d.terms.currency)?;
    owned_account(
        &tx,
        &st.owner_user_id,
        &d.account_id,
        AccountSide::Liability,
    )?;
    if sub(
        Decimal::ZERO,
        posting_sum(
            &tx,
            &st.owner_user_id,
            &d.account_id,
            &d.terms.currency,
            i64::MAX.saturating_sub(1),
        )?,
    )? < item.principal
    {
        return Err(invalid("本金超过剩余债务"));
    }
    let interest_account =
        accounts::system_account_id(&st.owner_user_id, "expense:trading:interest");
    owned_account(
        &tx,
        &st.owner_user_id,
        &interest_account,
        AccountSide::Expense,
    )?;
    let mut postings = vec![
        builders::PostingDraft {
            position: 0,
            account_id: cash_id.to_owned(),
            units: -item.total,
            unit: d.terms.currency.clone(),
            cost: None,
            price: None,
        },
        builders::PostingDraft {
            position: 1,
            account_id: d.account_id,
            units: item.principal,
            unit: d.terms.currency.clone(),
            cost: None,
            price: None,
        },
    ];
    if item.interest > Decimal::ZERO {
        postings.push(builders::PostingDraft {
            position: 2,
            account_id: interest_account,
            units: item.interest,
            unit: d.terms.currency.clone(),
            cost: None,
            price: None,
        });
    }
    let rid = key(&[&st.owner_user_id, "installment", id, &index.to_string()]);
    let jid = format!("planning:{rid}");
    write_journal(
        &tx,
        st,
        &jid,
        &d.terms.currency,
        builders::EntryBuild {
            entry: builders::EntryDraft {
                date: paid_on,
                settled_on: None,
                narration: format!("{} · 第 {} 期还款", d.terms.name, index + 1),
                payee: None,
                flag: EntryFlag::Confirmed,
                tag_ids: vec![format!("liability:{id}")],
            },
            postings,
        },
    )?;
    put(
        &tx,
        st,
        "resolution",
        &rid,
        &Resolution {
            state: OccurrenceState::Posted,
            journal_id: Some(jid.clone()),
        },
    )?;
    tx.commit()?;
    Ok(jid)
}
pub fn undo_installment(
    conn: &mut Connection,
    st: &MutationStamper,
    id: &str,
    index: u32,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let schedule = liability_schedule(&tx, &st.owner_user_id, id)?;
    let item = schedule
        .get(index as usize)
        .ok_or_else(|| invalid("还款期数无效"))?;
    if schedule
        .iter()
        .skip(index as usize + 1)
        .any(|i| i.state == OccurrenceState::Posted)
    {
        return Err(invalid("请先撤销后续还款"));
    }
    if let Some(jid) = &item.journal_id {
        delete_journal(&tx, st, jid)?;
    }
    let mut loan: Liability = get(&tx, &st.owner_user_id, "liability", id)?;
    if loan.archived {
        accounts::set_archived(&tx, st, &loan.account_id, false)?;
        loan.archived = false;
        put(&tx, st, "liability", id, &loan)?;
    }
    let rid = key(&[&st.owner_user_id, "installment", id, &index.to_string()]);
    put(
        &tx,
        st,
        "resolution",
        &rid,
        &Resolution {
            state: OccurrenceState::Due,
            journal_id: None,
        },
    )?;
    tx.commit()?;
    Ok(())
}

#[derive(Debug, Clone, PartialEq)]
pub struct ScheduledFlow {
    pub source_id: String,
    pub name: String,
    pub due: i64,
    pub amount: Decimal,
    pub currency: String,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Runway {
    pub as_of: i64,
    pub currency: String,
    pub horizon_days: u32,
    pub starting_balance: Decimal,
    pub predicted_balance: Decimal,
    pub min_balance: Decimal,
    pub flows: Vec<ScheduledFlow>,
    pub assumptions: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CashScenario {
    pub name: String,
    pub currency: String,
    pub starts_on: i64,
    #[serde(with = "decimal")]
    pub one_off_change: Decimal,
    #[serde(with = "decimal")]
    pub monthly_change: Decimal,
    pub months: u32,
}
pub fn save_cash_scenario(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    draft: CashScenario,
) -> Result<String> {
    name(&draft.name)?;
    currency(&draft.currency)?;
    if draft.months == 0 || draft.months > 1200 {
        return Err(invalid("情景期限须为 1–1200 个月"));
    }
    add_months(draft.starts_on, draft.months)?;
    if let Some(id) = id {
        let _: CashScenario = get(conn, &st.owner_user_id, "cash_scenario", id)?;
    }
    let id = id.map(str::to_owned).unwrap_or_else(lifeos::ids::new_id);
    let tx = conn.savepoint()?;
    put(&tx, st, "cash_scenario", &id, &draft)?;
    tx.commit()?;
    Ok(id)
}
pub fn cash_scenarios(conn: &Connection, owner: &str) -> Result<Vec<Stored<CashScenario>>> {
    list(conn, owner, "cash_scenario")
}
/// Overlay explicit assumptions without changing any account or real schedule.
pub fn simulate_runway(base: &Runway, scenario: &CashScenario) -> Result<Runway> {
    currency(&scenario.currency)?;
    if scenario.currency != base.currency {
        return Err(invalid("情景与现金跑道币种不一致"));
    }
    if scenario.months == 0 || scenario.months > 1200 {
        return Err(invalid("情景期限无效"));
    }
    let until = base
        .as_of
        .checked_add(i64::from(base.horizon_days) * 86400)
        .ok_or_else(|| invalid("日期超出范围"))?;
    let mut result = base.clone();
    if scenario.starts_on >= base.as_of
        && scenario.starts_on < until
        && scenario.one_off_change != Decimal::ZERO
    {
        result.flows.push(ScheduledFlow {
            source_id: "scenario:one-off".into(),
            name: format!("假设 · {} · 一次性变动", scenario.name),
            due: scenario.starts_on,
            amount: scenario.one_off_change,
            currency: scenario.currency.clone(),
        });
    }
    for n in 0..scenario.months {
        let due = add_months(scenario.starts_on, n)?;
        if due >= until {
            break;
        }
        if due >= base.as_of && scenario.monthly_change != Decimal::ZERO {
            result.flows.push(ScheduledFlow {
                source_id: format!("scenario:month:{n}"),
                name: format!("假设 · {} · 每月变动", scenario.name),
                due,
                amount: scenario.monthly_change,
                currency: scenario.currency.clone(),
            });
        }
    }
    result.flows.sort_by_key(|f| (f.due, f.source_id.clone()));
    let mut balance = result.starting_balance;
    let mut minimum = balance;
    for f in &result.flows {
        balance = add(balance, f.amount)?;
        minimum = minimum.min(balance);
    }
    result.predicted_balance = balance;
    result.min_balance = minimum;
    result.assumptions.push(format!(
        "情景「{}」：一次性 {} {}，每月 {} {}，共 {} 个月；不写入真实流水",
        scenario.name,
        scenario.one_off_change,
        scenario.currency,
        scenario.monthly_change,
        scenario.currency,
        scenario.months
    ));
    Ok(result)
}
pub fn runway(
    conn: &Connection,
    owner: &str,
    as_of: i64,
    code: &str,
    horizon_days: u32,
) -> Result<Runway> {
    currency(code)?;
    if !matches!(horizon_days, 30 | 90) {
        return Err(invalid("现金跑道支持 30 或 90 天"));
    }
    let until = as_of
        .checked_add(i64::from(horizon_days) * 86400)
        .ok_or_else(|| invalid("日期超出范围"))?;
    let mut starting_balance = Decimal::ZERO;
    let mut excluded = Vec::new();
    for (a, _) in daily::list_accounts(conn, owner, false)? {
        if a.side == AccountSide::Asset
            && matches!(
                a.kind,
                AccountCategory::Cash | AccountCategory::Bank | AccountCategory::Broker
            )
        {
            if a.currency == code {
                starting_balance = add(
                    starting_balance,
                    posting_sum(conn, owner, &a.id, code, as_of)?,
                )?;
            } else {
                excluded.push(a.currency);
            }
        }
    }
    let mut flows = Vec::new();
    let templates = list_recurring(conn, owner)?;
    let recurring_start = templates
        .iter()
        .map(|t| t.data.first_due)
        .min()
        .unwrap_or(as_of)
        .min(as_of);
    let mut overdue_income = Vec::new();
    let mut carried_outflows = 0_usize;
    for o in occurrences(conn, owner, recurring_start, until)? {
        if o.state == OccurrenceState::Due && o.currency == code {
            let template = templates
                .iter()
                .find(|s| s.id == o.template_id)
                .ok_or_else(|| invalid("计划不存在"))?;
            if o.due < as_of && template.data.kind == FlowKind::Income {
                overdue_income.push(format!(
                    "{}（{}，{} {}）",
                    o.name,
                    chrono::DateTime::from_timestamp(o.due, 0)
                        .map(|d| d.format("%Y-%m-%d").to_string())
                        .unwrap_or_else(|| "到期日不可用".into()),
                    o.amount,
                    o.currency
                ));
                continue;
            }
            let overdue = o.due < as_of;
            if overdue {
                carried_outflows += 1;
            }
            flows.push(ScheduledFlow {
                source_id: o.template_id,
                name: forecast_name(&o.name, o.due, as_of),
                due: o.due.max(as_of),
                amount: if template.data.kind == FlowKind::Income {
                    o.amount
                } else {
                    -o.amount
                },
                currency: o.currency,
            });
        }
    }
    for d in liabilities(conn, owner)? {
        if d.data.terms.currency == code {
            for i in liability_schedule(conn, owner, &d.id)? {
                if i.state == OccurrenceState::Due && i.due < until {
                    if i.due < as_of {
                        carried_outflows += 1;
                    }
                    flows.push(ScheduledFlow {
                        source_id: d.id.clone(),
                        name: forecast_name(&d.data.terms.name, i.due, as_of),
                        due: i.due.max(as_of),
                        amount: -i.total,
                        currency: code.to_owned(),
                    });
                }
            }
        }
    }
    let dca_start = dca_plans(conn, owner)?
        .iter()
        .map(|p| p.data.first_due)
        .min()
        .unwrap_or(as_of)
        .min(as_of);
    for o in dca_occurrences(conn, owner, dca_start, until)? {
        if o.state == OccurrenceState::Due && o.currency == code {
            if o.due < as_of {
                carried_outflows += 1;
            }
            flows.push(ScheduledFlow {
                source_id: o.template_id,
                name: forecast_name(&o.name, o.due, as_of),
                due: o.due.max(as_of),
                amount: -o.amount,
                currency: o.currency,
            });
        }
    }
    flows.sort_by_key(|f| (f.due, f.source_id.clone()));
    let mut balance = starting_balance;
    let mut min_balance = balance;
    for f in &flows {
        balance = add(balance, f.amount)?;
        min_balance = min_balance.min(balance);
    }
    let mut assumptions=vec!["仅按已记录现金余额与未处理的周期收支、等额本金贷款、定投计划推演；不包含未录入消费、市场回报或自动交易".to_owned(),"到期流程需手动确认入账；本预测不会写入流水".to_owned()];
    if carried_outflows > 0 {
        assumptions.push(format!("{carried_outflows} 项今天已到期或逾期的未处理支出按基线时刻立即支付；它们是计划假设，可在所属流程确认或跳过"));
    }
    if !overdue_income.is_empty() {
        assumptions.push(format!(
            "以下已到期收入尚未确认，未计入可用余额：{}。确认实际收款后基线才会增加",
            overdue_income.join("；")
        ));
    }
    excluded.sort();
    excluded.dedup();
    if !excluded.is_empty() {
        assumptions.push(format!("未换算其他币种现金：{}", excluded.join("、")));
    }
    Ok(Runway {
        as_of,
        currency: code.to_owned(),
        horizon_days,
        starting_balance,
        predicted_balance: balance,
        min_balance,
        flows,
        assumptions,
    })
}
fn forecast_name(name: &str, due: i64, as_of: i64) -> String {
    if due < as_of {
        format!(
            "{name} · 未处理，原到期 {}",
            chrono::DateTime::from_timestamp(due, 0)
                .map(|d| d.format("%Y-%m-%d").to_string())
                .unwrap_or_else(|| "日期不可用".into())
        )
    } else {
        name.to_owned()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Goal {
    pub name: String,
    pub currency: String,
    #[serde(with = "decimal")]
    pub target: Decimal,
    pub target_date: i64,
    #[serde(with = "decimal")]
    pub monthly_contribution: Decimal,
    pub asset_id: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Contribution {
    pub goal_id: String,
    pub journal_id: String,
    #[serde(with = "decimal")]
    pub amount: Decimal,
    pub date: i64,
    #[serde(default)]
    pub dca_plan_id: Option<String>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct GoalProgress {
    pub id: String,
    pub goal: Goal,
    pub contributed: Decimal,
    pub remaining: Decimal,
    pub contribution_ids: Vec<String>,
}
pub fn save_goal(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    draft: Goal,
) -> Result<String> {
    name(&draft.name)?;
    currency(&draft.currency)?;
    positive(draft.target)?;
    if draft.monthly_contribution < Decimal::ZERO {
        return Err(invalid("每月投入不能为负数"));
    }
    add_months(draft.target_date, 0)?;
    if let Some(id) = id {
        let _: Goal = get(conn, &st.owner_user_id, "goal", id)?;
    }
    let id = id.map(str::to_owned).unwrap_or_else(lifeos::ids::new_id);
    let tx = conn.savepoint()?;
    put(&tx, st, "goal", &id, &draft)?;
    tx.commit()?;
    Ok(id)
}
pub fn goals(conn: &Connection, owner: &str) -> Result<Vec<GoalProgress>> {
    let contributions = list::<Contribution>(conn, owner, "contribution")?;
    list::<Goal>(conn, owner, "goal")?
        .into_iter()
        .map(|s| {
            let mut total = Decimal::ZERO;
            let mut ids = Vec::new();
            for c in &contributions {
                if c.data.goal_id == s.id {
                    let amount = eligible_goal_amount(conn, owner, &s.data, &c.data.journal_id)?
                        .min(c.data.amount);
                    if amount > Decimal::ZERO {
                        total = add(total, amount)?;
                        ids.push(c.data.journal_id.clone());
                    }
                }
            }
            Ok(GoalProgress {
                id: s.id,
                remaining: sub(s.data.target, total)?.max(Decimal::ZERO),
                goal: s.data,
                contributed: total,
                contribution_ids: ids,
            })
        })
        .collect()
}
/// Link a real positive asset leg to a goal. One ledger entry may fund one goal;
/// no cash is created and deleted journal entries cease contributing immediately.
pub fn contribute_goal(
    conn: &mut Connection,
    st: &MutationStamper,
    goal_id: &str,
    journal_id: &str,
    amount: Decimal,
) -> Result<()> {
    positive(amount)?;
    let tx = conn.savepoint()?;
    let goal: Goal = get(&tx, &st.owner_user_id, "goal", goal_id)?;
    let row = journal::get(&tx, journal_id)?
        .filter(|r| {
            r.entry.sync.owner_user_id == st.owner_user_id && r.entry.sync.deleted_at.is_none()
        })
        .ok_or_else(|| invalid("请选择真实的已入账记录"))?;
    let eligible = eligible_goal_amount(&tx, &st.owner_user_id, &goal, journal_id)?;
    if eligible < amount {
        return Err(invalid("贡献金额超过记录中符合目标的实际投入"));
    }
    let id = key(&[&st.owner_user_id, "contribution", journal_id]);
    let existing = list::<Contribution>(&tx, &st.owner_user_id, "contribution")?
        .into_iter()
        .find(|s| s.id == id);
    if existing.as_ref().is_some_and(|c| c.data.goal_id != goal_id) {
        return Err(invalid("此记录已用于其他目标"));
    }
    put(
        &tx,
        st,
        "contribution",
        &id,
        &Contribution {
            goal_id: goal_id.to_owned(),
            journal_id: journal_id.to_owned(),
            amount,
            date: row.entry.date,
            dca_plan_id: existing.and_then(|c| c.data.dca_plan_id),
        },
    )?;
    tx.commit()?;
    Ok(())
}
#[derive(Debug, Clone, PartialEq)]
pub struct ContributionCandidate {
    pub journal_id: String,
    pub date: i64,
    pub narration: String,
    pub eligible_amount: Decimal,
    pub currency: String,
}
pub fn contribution_candidates(
    conn: &Connection,
    owner: &str,
    goal_id: &str,
) -> Result<Vec<ContributionCandidate>> {
    let goal: Goal = get(conn, owner, "goal", goal_id)?;
    let mut out = Vec::new();
    for row in journal::list_owned(conn, owner, None, None)? {
        let eligible_amount = eligible_goal_amount(conn, owner, &goal, &row.entry.id)?;
        if eligible_amount > Decimal::ZERO {
            out.push(ContributionCandidate {
                journal_id: row.entry.id,
                date: row.entry.date,
                narration: row.entry.narration,
                eligible_amount,
                currency: goal.currency.clone(),
            });
        }
    }
    Ok(out)
}
pub fn unlink_goal_contribution(
    conn: &mut Connection,
    st: &MutationStamper,
    goal_id: &str,
    journal_id: &str,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let id = key(&[&st.owner_user_id, "contribution", journal_id]);
    let contribution: Contribution = get(&tx, &st.owner_user_id, "contribution", &id)?;
    if contribution.goal_id != goal_id {
        return Err(invalid("此贡献不属于该目标"));
    }
    if contribution.dca_plan_id.is_some() {
        return Err(invalid("此贡献来自定投计划，请在定投计划中撤销本期关联"));
    }
    tombstone(&tx, st, "contribution", &id)?;
    tx.commit()?;
    Ok(())
}
fn eligible_goal_amount(
    conn: &Connection,
    owner: &str,
    goal: &Goal,
    journal_id: &str,
) -> Result<Decimal> {
    let Some(row) = journal::get(conn, journal_id)?.filter(|r| {
        r.entry.sync.owner_user_id == owner
            && r.entry.sync.deleted_at.is_none()
            && r.entry.flag == EntryFlag::Confirmed
    }) else {
        return Ok(Decimal::ZERO);
    };
    let mut eligible = Decimal::ZERO;
    let mut has_outflow = false;
    for p in &row.postings {
        let a = accounts::get_required(conn, &p.account_id)?;
        if p.sync.owner_user_id != owner || a.sync.owner_user_id != owner {
            return Err(invalid("贡献记录所属数据空间不一致"));
        }
        if goal.asset_id.is_none() && a.side != AccountSide::Asset {
            return Ok(Decimal::ZERO);
        }
        if a.side == AccountSide::Asset && p.units < Decimal::ZERO && p.unit == goal.currency {
            has_outflow = true
        }
        if a.side == AccountSide::Asset && p.units > Decimal::ZERO {
            if goal.asset_id.as_deref() == Some(p.unit.as_str()) {
                if let Some(cost) = &p.cost
                    && cost.currency == goal.currency
                {
                    eligible = add(eligible, mul(p.units, cost.per_unit)?)?;
                }
            } else if goal.asset_id.is_none() && p.unit == goal.currency {
                eligible = add(eligible, p.units)?;
            }
        }
    }
    if has_outflow {
        Ok(eligible)
    } else {
        Ok(Decimal::ZERO)
    }
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FirePlan {
    pub name: String,
    pub currency: String,
    #[serde(with = "decimal")]
    pub current_capital: Decimal,
    #[serde(with = "decimal")]
    pub monthly_expense: Decimal,
    #[serde(with = "decimal")]
    pub monthly_income: Decimal,
    #[serde(with = "decimal")]
    pub monthly_contribution: Decimal,
    #[serde(with = "decimal")]
    pub annual_real_return: Decimal,
    #[serde(with = "decimal")]
    pub withdrawal_rate: Decimal,
    pub years: u32,
}
#[derive(Debug, Clone, PartialEq)]
pub struct FireProjection {
    pub target_capital: Decimal,
    pub projected_capital: Decimal,
    pub savings_rate: Option<Decimal>,
    pub months_to_target: Option<u32>,
    pub series: Vec<(u32, Decimal)>,
    pub assumptions: Vec<String>,
}
pub fn calculate_fire(d: &FirePlan) -> Result<FireProjection> {
    currency(&d.currency)?;
    positive(d.monthly_expense)?;
    positive(d.withdrawal_rate)?;
    if d.withdrawal_rate > Decimal::ONE
        || d.annual_real_return <= -Decimal::ONE
        || d.annual_real_return > Decimal::ONE
        || d.current_capital < Decimal::ZERO
        || d.monthly_contribution < Decimal::ZERO
        || d.monthly_income < Decimal::ZERO
        || d.years == 0
        || d.years > 100
    {
        return Err(invalid("规划假设超出支持范围"));
    }
    let target = div(
        mul(d.monthly_expense, Decimal::from(12))?,
        d.withdrawal_rate,
    )?;
    let monthly_rate = div(d.annual_real_return, Decimal::from(12))?;
    let mut capital = d.current_capital;
    let mut months_to_target = (capital >= target).then_some(0);
    let mut series = vec![(0, capital)];
    for month in 1..=d.years * 12 {
        capital = add(
            mul(capital, add(Decimal::ONE, monthly_rate)?)?,
            d.monthly_contribution,
        )?;
        if capital >= target && months_to_target.is_none() {
            months_to_target = Some(month)
        }
        if month % 12 == 0 {
            series.push((month, capital));
        }
    }
    Ok(FireProjection {
        target_capital: target,
        projected_capital: capital,
        savings_rate: if d.monthly_income > Decimal::ZERO {
            Some(div(
                sub(d.monthly_income, d.monthly_expense)?,
                d.monthly_income,
            )?)
        } else {
            None
        },
        months_to_target,
        series,
        assumptions: vec![
            "用户指定的实际年回报率 ÷ 12，月末固定投入；并非收益预测或历史回测".to_owned(),
            "目标资本 = 年支出 ÷ 提取率；未模拟税费、未来收入变化及收益顺序风险".to_owned(),
        ],
    })
}
pub fn save_fire(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    draft: FirePlan,
) -> Result<String> {
    name(&draft.name)?;
    calculate_fire(&draft)?;
    if let Some(id) = id {
        let _: FirePlan = get(conn, &st.owner_user_id, "fire", id)?;
    }
    let id = id.map(str::to_owned).unwrap_or_else(lifeos::ids::new_id);
    let tx = conn.savepoint()?;
    put(&tx, st, "fire", &id, &draft)?;
    tx.commit()?;
    Ok(id)
}
pub fn fire_plans(conn: &Connection, owner: &str) -> Result<Vec<Stored<FirePlan>>> {
    list(conn, owner, "fire")
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DcaPlan {
    pub name: String,
    pub currency: String,
    pub asset_id: String,
    pub account_id: String,
    #[serde(with = "decimal")]
    pub amount: Decimal,
    pub first_due: i64,
    pub interval_months: u32,
    pub months: u32,
    pub goal_id: Option<String>,
    pub paused: bool,
}
pub fn save_dca(
    conn: &mut Connection,
    st: &MutationStamper,
    id: Option<&str>,
    draft: DcaPlan,
) -> Result<String> {
    name(&draft.name)?;
    currency(&draft.currency)?;
    positive(draft.amount)?;
    if draft.interval_months == 0
        || draft.months == 0
        || draft.months > 1200
        || draft.interval_months > 120
    {
        return Err(invalid("定投周期或期限无效"));
    }
    cash_account(conn, &st.owner_user_id, &draft.account_id, &draft.currency)?;
    let a = crate::wealth::asset(conn, &st.owner_user_id, &draft.asset_id)?;
    if a.details.currency != draft.currency || a.archived {
        return Err(invalid("定投资产不可用或币种不匹配"));
    }
    if let Some(goal_id) = &draft.goal_id {
        let goal: Goal = get(conn, &st.owner_user_id, "goal", goal_id)?;
        if goal.currency != draft.currency
            || goal.asset_id.as_deref() != Some(draft.asset_id.as_str())
        {
            return Err(invalid("目标的币种和资产须与定投一致"));
        }
    }
    add_months(draft.first_due, draft.months)?;
    if let Some(id) = id {
        let mut previous: DcaPlan = get(conn, &st.owner_user_id, "dca", id)?;
        previous.name = draft.name.clone();
        previous.paused = draft.paused;
        if previous != draft && has_resolutions(conn, &st.owner_user_id, "dca-occurrence", id)? {
            return Err(invalid(
                "定投已有处理记录；请暂停旧计划并新建，或先撤销原期次关联",
            ));
        }
    }
    let id = id.map(str::to_owned).unwrap_or_else(lifeos::ids::new_id);
    let tx = conn.savepoint()?;
    put(&tx, st, "dca", &id, &draft)?;
    tx.commit()?;
    Ok(id)
}
pub fn dca_plans(conn: &Connection, owner: &str) -> Result<Vec<Stored<DcaPlan>>> {
    list(conn, owner, "dca")
}
pub fn dca_occurrences(
    conn: &Connection,
    owner: &str,
    from: i64,
    until: i64,
) -> Result<Vec<Occurrence>> {
    if from >= until {
        return Err(invalid("开始日期必须早于结束日期"));
    }
    let mut out = Vec::new();
    for s in dca_plans(conn, owner)? {
        let end = add_months(s.data.first_due, s.data.months)?;
        let mut offset = 0;
        while offset < s.data.months {
            let due = add_months(s.data.first_due, offset)?;
            if due >= end || due >= until {
                break;
            }
            if due >= from {
                let rid = key(&[owner, "dca-occurrence", &s.id, &due.to_string()]);
                let r = resolution(conn, owner, &rid)?;
                if s.data.paused && r.state == OccurrenceState::Due {
                    offset = offset
                        .checked_add(s.data.interval_months)
                        .ok_or_else(|| invalid("定投周期超出范围"))?;
                    continue;
                }
                out.push(Occurrence {
                    template_id: s.id.clone(),
                    due,
                    amount: s.data.amount,
                    currency: s.data.currency.clone(),
                    name: s.data.name.clone(),
                    state: r.state,
                    journal_id: r.journal_id,
                });
            }
            offset = offset
                .checked_add(s.data.interval_months)
                .ok_or_else(|| invalid("定投周期超出范围"))?;
        }
    }
    out.sort_by_key(|o| (o.due, o.template_id.clone()));
    Ok(out)
}
/// Only a real, matching manual buy can complete a contribution. Plans never
/// fetch history or require a quote to be saved, and never execute orders.
pub fn link_dca_trade(
    conn: &mut Connection,
    st: &MutationStamper,
    plan_id: &str,
    due: i64,
    operation_id: &str,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let d: DcaPlan = get(&tx, &st.owner_user_id, "dca", plan_id)?;
    let occurrence = dca_occurrences(
        &tx,
        &st.owner_user_id,
        due,
        due.checked_add(1).ok_or_else(|| invalid("日期无效"))?,
    )?
    .into_iter()
    .find(|o| o.template_id == plan_id)
    .ok_or_else(|| invalid("该日期不是活动定投的到期日"))?;
    if occurrence.state != OccurrenceState::Due {
        if occurrence.journal_id.as_deref() == Some(operation_id) {
            return Ok(());
        }
        return Err(invalid("该期已处理"));
    }
    let operation = crate::wealth::operations(&tx, &st.owner_user_id, Some(&d.asset_id))?
        .into_iter()
        .find(|o| o.id == operation_id)
        .ok_or_else(|| invalid("成交记录不存在"))?;
    if operation.details.kind != crate::wealth::OperationKind::Buy
        || operation.details.cash_account_id.as_deref() != Some(d.account_id.as_str())
        || operation.currency != d.currency
        || operation.details.date < due
        || operation.details.date >= add_months(due, d.interval_months)?
    {
        return Err(invalid("请选择该期、同资产、同资金账户的真实买入记录"));
    }
    let used = list::<Resolution>(&tx, &st.owner_user_id, "resolution")?
        .iter()
        .any(|r| r.data.journal_id.as_deref() == Some(operation_id));
    if used {
        return Err(invalid("该成交记录已用于其他计划"));
    }
    if let Some(goal_id) = d.goal_id {
        let goal: Goal = get(&tx, &st.owner_user_id, "goal", &goal_id)?;
        if goal.currency != d.currency || goal.asset_id.as_deref() != Some(d.asset_id.as_str()) {
            return Err(invalid("目标配置已改变，请先修正目标或新建定投计划"));
        }
        let contribution_id = key(&[&st.owner_user_id, "contribution", operation_id]);
        let existing = list::<Contribution>(&tx, &st.owner_user_id, "contribution")?
            .into_iter()
            .find(|c| c.id == contribution_id);
        if existing.as_ref().is_some_and(|c| c.data.goal_id != goal_id) {
            return Err(invalid("此成交已用于其他目标"));
        }
        let amount = mul(operation.details.quantity, operation.details.unit_price)?;
        put(
            &tx,
            st,
            "contribution",
            &contribution_id,
            &Contribution {
                goal_id,
                journal_id: operation_id.to_owned(),
                amount,
                date: operation.details.date,
                dca_plan_id: existing.map_or(Some(plan_id.to_owned()), |c| c.data.dca_plan_id),
            },
        )?;
    }
    let rid = key(&[
        &st.owner_user_id,
        "dca-occurrence",
        plan_id,
        &due.to_string(),
    ]);
    put(
        &tx,
        st,
        "resolution",
        &rid,
        &Resolution {
            state: OccurrenceState::Posted,
            journal_id: Some(operation_id.to_owned()),
        },
    )?;
    tx.commit()?;
    Ok(())
}
pub fn skip_dca_occurrence(
    conn: &mut Connection,
    st: &MutationStamper,
    plan_id: &str,
    due: i64,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let occurrence = dca_occurrences(
        &tx,
        &st.owner_user_id,
        due,
        due.checked_add(1).ok_or_else(|| invalid("日期无效"))?,
    )?
    .into_iter()
    .find(|o| o.template_id == plan_id)
    .ok_or_else(|| invalid("定投到期日无效"))?;
    if occurrence.state == OccurrenceState::Posted {
        return Err(invalid("该期已经关联成交记录"));
    }
    let rid = key(&[
        &st.owner_user_id,
        "dca-occurrence",
        plan_id,
        &due.to_string(),
    ]);
    put(
        &tx,
        st,
        "resolution",
        &rid,
        &Resolution {
            state: OccurrenceState::Skipped,
            journal_id: None,
        },
    )?;
    tx.commit()?;
    Ok(())
}
/// Remove only the planning association. The user's executed trade stays real.
pub fn undo_dca_occurrence(
    conn: &mut Connection,
    st: &MutationStamper,
    plan_id: &str,
    due: i64,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let _: DcaPlan = get(&tx, &st.owner_user_id, "dca", plan_id)?;
    let rid = key(&[
        &st.owner_user_id,
        "dca-occurrence",
        plan_id,
        &due.to_string(),
    ]);
    let r = resolution(&tx, &st.owner_user_id, &rid)?;
    if let Some(jid) = r.journal_id {
        let cid = key(&[&st.owner_user_id, "contribution", &jid]);
        if let Some(c) = list::<Contribution>(&tx, &st.owner_user_id, "contribution")?
            .into_iter()
            .find(|c| c.id == cid)
            && c.data.dca_plan_id.as_deref() == Some(plan_id)
        {
            tombstone(&tx, st, "contribution", &cid)?;
        }
    }
    put(
        &tx,
        st,
        "resolution",
        &rid,
        &Resolution {
            state: OccurrenceState::Due,
            journal_id: None,
        },
    )?;
    tx.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests;
