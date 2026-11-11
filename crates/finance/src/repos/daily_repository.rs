//! Daily finance use cases. Forms consume economic records rather than raw
//! journal legs; all writes remain balanced, owner-scoped and sync-aware.

use crate::{
    FinanceError, Result, builders,
    models::{Account, AccountSide},
    repos::{account_repository as accounts, journal_repository as journal, settings_repository},
    system_accounts,
};
use lifeos::sync::MutationStamper;
use rusqlite::{Connection, params};
use rust_decimal::Decimal;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordKind {
    Expense,
    Income,
    Transfer,
    OpeningBalance,
    Investment,
    Other,
}
impl RecordKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Expense => "支出",
            Self::Income => "收入",
            Self::Transfer => "转账",
            Self::OpeningBalance => "期初余额",
            Self::Investment => "投资交易",
            Self::Other => "其他记录",
        }
    }
}

/// Owning workflow for corrections. Structured records must be changed through
/// their original use case so linked receipts and the ledger remain consistent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordSource {
    Daily,
    Wealth,
    Planning,
    Reconciliation,
    Other,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecordDraft {
    pub kind: RecordKind,
    pub date: i64,
    /// Positive magnitude, except opening balances which retain account signs.
    pub amount: Decimal,
    pub account_id: String,
    pub category_id: Option<String>,
    pub destination_account_id: Option<String>,
    pub destination_amount: Option<Decimal>,
    pub payee: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FinanceRecord {
    pub source: RecordSource,
    /// Typed investment intent for display; account arrows and signs cannot infer it.
    pub investment_kind: Option<crate::wealth::OperationKind>,
    /// Only standard two-leg daily records can be rewritten by the simple form.
    pub editable: bool,
    pub id: String,
    pub kind: RecordKind,
    pub date: i64,
    pub amount: Decimal,
    pub currency: String,
    pub account_id: String,
    pub account_name: String,
    pub category_id: Option<String>,
    pub category_name: Option<String>,
    pub destination_account_id: Option<String>,
    pub destination_account_name: Option<String>,
    pub destination_amount: Option<Decimal>,
    pub destination_currency: Option<String>,
    pub payee: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct RecordFilter {
    pub query: String,
    pub kind: Option<RecordKind>,
    pub account_id: Option<String>,
    pub from: Option<i64>,
    /// Exclusive upper date bound.
    pub until: Option<i64>,
}

fn invalid(message: &str) -> FinanceError {
    FinanceError::InvalidData(message.to_owned())
}
fn custody(account: &Account) -> bool {
    matches!(account.side, AccountSide::Asset | AccountSide::Liability)
        && !account.id.starts_with("system-account:")
}
fn owned_account(conn: &Connection, owner: &str, id: &str, active: bool) -> Result<Account> {
    let account = accounts::get(conn, id)?
        .filter(|a| a.sync.owner_user_id == owner && a.sync.deleted_at.is_none())
        .ok_or_else(|| invalid("账户不存在或无法访问"))?;
    if !custody(&account) {
        return Err(invalid("请选择资金账户"));
    }
    if active && account.archived {
        return Err(invalid("账户已归档，请先恢复账户"));
    }
    Ok(account)
}
fn owned_entry(conn: &Connection, owner: &str, id: &str) -> Result<journal::EntryWithPostings> {
    journal::get(conn, id)?
        .filter(|r| {
            r.entry.sync.owner_user_id == owner
                && r.entry.sync.deleted_at.is_none()
                && r.postings.iter().all(|p| p.sync.owner_user_id == owner)
        })
        .ok_or_else(|| invalid("记录不存在或无法访问"))
}
fn clean(text: Option<String>) -> Option<String> {
    text.and_then(|v| {
        let s = v.trim();
        (!s.is_empty()).then(|| s.to_owned())
    })
}
fn category_label(conn: &Connection, owner: &str, account: &Account) -> Result<String> {
    if account.side == AccountSide::Expense {
        let label: Option<String> = conn.query_row(
            r#"SELECT COALESCE(name_override,name) FROM "fin:categories" WHERE ledger_account_id=?1 AND owner_user_id=?2 AND deleted_at IS NULL LIMIT 1"#,
            params![account.id,owner], |row| row.get(0),
        ).optional()?;
        return Ok(label.unwrap_or_else(|| account.name.clone()));
    }
    Ok(match account.name.as_str() {
        "Salary" => "工资薪酬",
        "Dividend" => "股息红利",
        "Interest" => "利息收入",
        "Capital Gains" => "资本利得",
        "Options Income" => "期权收入",
        "Other Income" => "其他收入",
        other => other,
    }
    .to_owned())
}
use rusqlite::OptionalExtension;

pub fn categories(
    conn: &Connection,
    owner: &str,
    kind: RecordKind,
) -> Result<Vec<(String, String)>> {
    match kind {
        RecordKind::Expense => {
            let mut stmt = conn.prepare_cached(r#"
                SELECT c.ledger_account_id, COALESCE(c.name_override,c.name)
                FROM "fin:categories" c JOIN "fin:accounts" a ON a.id=c.ledger_account_id
                WHERE c.owner_user_id=?1 AND a.owner_user_id=?1
                  AND c.deleted_at IS NULL AND c.archived=0
                  AND a.deleted_at IS NULL AND a.archived=0 AND a.category='expense'
                  AND NOT EXISTS (SELECT 1 FROM "fin:categories" child
                    WHERE child.parent_id=c.id AND child.owner_user_id=?1 AND child.deleted_at IS NULL)
                ORDER BY c.sort_order,c.name,c.id
            "#)?;
            Ok(stmt
                .query_map(params![owner], |row| Ok((row.get(0)?, row.get(1)?)))?
                .collect::<std::result::Result<Vec<_>, _>>()?)
        }
        RecordKind::Income => {
            let mut leaves: Vec<Account> = accounts::list_by_side(conn, AccountSide::Income)?
                .into_iter()
                .filter(|a| a.sync.owner_user_id == owner && a.parent_id.is_some())
                .collect();
            let common = [
                "salary",
                "dividend",
                "interest",
                "capitalGains",
                "options",
                "other",
            ];
            leaves.sort_by_key(|a| {
                (
                    common
                        .iter()
                        .position(|path| {
                            a.id == system_accounts::system_account_id(
                                owner,
                                &format!("income:{path}"),
                            )
                        })
                        .unwrap_or(common.len()),
                    a.name.clone(),
                    a.id.clone(),
                )
            });
            leaves
                .into_iter()
                .map(|a| Ok((a.id.clone(), category_label(conn, owner, &a)?)))
                .collect()
        }
        _ => Ok(Vec::new()),
    }
}

pub fn list_accounts(
    conn: &Connection,
    owner: &str,
    include_archived: bool,
) -> Result<Vec<(Account, Option<accounts::AccountBalance>)>> {
    let list = accounts::list(conn, include_archived)?
        .into_iter()
        .filter(|a| a.sync.owner_user_id == owner && custody(a));
    let mut balances: BTreeMap<String, BTreeMap<String, Decimal>> = BTreeMap::new();
    let mut stmt=conn.prepare_cached(r#"SELECT p.account_id,p.unit,p.units FROM "fin:postings" p JOIN "fin:journal_entries" e ON e.id=p.journal_entry_id WHERE p.owner_user_id=?1 AND e.owner_user_id=?1 AND p.deleted_at IS NULL AND e.deleted_at IS NULL"#)?;
    for row in stmt.query_map(params![owner], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
        ))
    })? {
        let (account, unit, amount) = row?;
        let value = Decimal::from_str_exact(&amount).map_err(|_| invalid("记录金额格式错误"))?;
        let total = balances
            .entry(account)
            .or_default()
            .entry(unit)
            .or_default();
        *total = total
            .checked_add(value)
            .ok_or_else(|| invalid("账户余额超出支持范围"))?;
    }
    Ok(list
        .map(|account| {
            let balance = balances
                .remove(&account.id)
                .map(|legs| accounts::AccountBalance {
                    account_id: account.id.clone(),
                    legs: legs.into_iter().collect(),
                });
            (account, balance)
        })
        .collect())
}

pub fn record(conn: &Connection, owner: &str, id: &str) -> Result<FinanceRecord> {
    project(conn, owner, owned_entry(conn, owner, id)?)
}
fn posting_weight(posting: &crate::models::Posting) -> Result<(String, Decimal)> {
    if let Some(cost) = &posting.cost {
        return Ok((
            cost.currency.clone(),
            posting
                .units
                .checked_mul(cost.per_unit)
                .ok_or_else(|| invalid("分录金额超出支持范围"))?,
        ));
    }
    if let Some(price) = &posting.price {
        return Ok((
            price.currency.clone(),
            posting
                .units
                .checked_mul(price.per_unit)
                .ok_or_else(|| invalid("分录金额超出支持范围"))?,
        ));
    }
    Ok((posting.unit.clone(), posting.units))
}

fn project(
    conn: &Connection,
    owner: &str,
    row: journal::EntryWithPostings,
) -> Result<FinanceRecord> {
    if row
        .entry
        .tag_ids
        .iter()
        .any(|tag| tag.starts_with("wealth:"))
    {
        let op = crate::wealth::operation(conn, owner, &row.entry.id)?;
        let asset = crate::wealth::asset(conn, owner, &op.details.asset_id)?;
        let account = owned_account(conn, owner, &op.details.account_id, false)?;
        let cash = op
            .details
            .cash_account_id
            .as_deref()
            .map(|id| owned_account(conn, owner, id, false))
            .transpose()?;
        let amount = match op.details.kind {
            crate::wealth::OperationKind::Opening => op
                .details
                .quantity
                .checked_mul(op.details.unit_price)
                .ok_or_else(|| invalid("持仓成本超出支持范围"))?,
            _ => op.cash_amount,
        };
        return Ok(FinanceRecord {
            source: RecordSource::Wealth,
            investment_kind: Some(op.details.kind),
            editable: false,
            id: op.id,
            kind: RecordKind::Investment,
            date: op.details.date,
            amount,
            currency: op.currency,
            account_id: account.id,
            account_name: account.name,
            category_id: None,
            category_name: Some(op.details.kind.label().to_owned()),
            destination_account_id: cash.as_ref().map(|a| a.id.clone()),
            destination_account_name: cash.map(|a| a.name),
            destination_amount: None,
            destination_currency: None,
            payee: Some(asset.details.name),
            note: op.details.note,
        });
    }
    let source = if row
        .entry
        .tag_ids
        .iter()
        .any(|tag| tag.starts_with("recurring:") || tag.starts_with("liability:"))
    {
        RecordSource::Planning
    } else if row
        .entry
        .tag_ids
        .iter()
        .any(|tag| tag.starts_with("reconciliation:"))
    {
        RecordSource::Reconciliation
    } else {
        RecordSource::Daily
    };
    let mut record = project_ledger(conn, owner, row)?;
    if source != RecordSource::Daily {
        record.source = source;
        record.editable = false;
    }
    Ok(record)
}

fn project_ledger(
    conn: &Connection,
    owner: &str,
    row: journal::EntryWithPostings,
) -> Result<FinanceRecord> {
    let legs = row
        .postings
        .iter()
        .map(|posting| {
            let account = accounts::get_required(conn, &posting.account_id)?;
            if account.sync.owner_user_id != owner || posting.sync.owner_user_id != owner {
                return Err(invalid("记录账户所属数据空间不一致"));
            }
            Ok((posting, account))
        })
        .collect::<Result<Vec<_>>>()?;
    if legs.len() == 2 {
        let standard = row.entry.flag != crate::models::EntryFlag::Padding
            && legs
                .iter()
                .all(|(p, a)| p.unit == a.currency || !custody(a))
            && legs.iter().all(|(p, _)| p.cost.is_none())
            && match (
                legs.iter().find(|(_, a)| a.side == AccountSide::Expense),
                legs.iter().find(|(_, a)| a.side == AccountSide::Income),
            ) {
                (Some((expense, _)), None) => {
                    expense.units > Decimal::ZERO
                        && legs.iter().any(|(p, a)| {
                            custody(a) && p.units < Decimal::ZERO && p.price.is_none()
                        })
                        && expense.price.is_none()
                }
                (None, Some((income, _))) => {
                    income.units < Decimal::ZERO
                        && legs.iter().any(|(p, a)| {
                            custody(a) && p.units > Decimal::ZERO && p.price.is_none()
                        })
                        && income.price.is_none()
                }
                (None, None) => {
                    let opening = legs.iter().any(|(_, a)| {
                        a.id == system_accounts::system_account_id(owner, "equity:openingBalance")
                    });
                    (opening
                        && legs.iter().any(|(_, a)| custody(a))
                        && legs.iter().all(|(p, _)| p.price.is_none()))
                        || (legs.iter().all(|(_, a)| custody(a))
                            && legs
                                .iter()
                                .any(|(p, _)| p.units < Decimal::ZERO && p.price.is_none())
                            && legs.iter().any(|(p, _)| p.units > Decimal::ZERO))
                }
                _ => false,
            };
        if standard {
            return project_daily(conn, owner, row);
        }
    }
    let expense: Vec<_> = legs
        .iter()
        .filter(|(_, a)| a.side == AccountSide::Expense)
        .collect();
    let income: Vec<_> = legs
        .iter()
        .filter(|(_, a)| a.side == AccountSide::Income)
        .collect();
    let infer = |items: Vec<&(&crate::models::Posting, Account)>,
                 kind: RecordKind|
     -> Result<Option<(RecordKind, String, Decimal)>> {
        let mut sum = Decimal::ZERO;
        let mut currency = None;
        for (posting, _) in items {
            let (unit, weight) = posting_weight(posting)?;
            if (kind == RecordKind::Expense && weight < Decimal::ZERO)
                || (kind == RecordKind::Income && weight > Decimal::ZERO)
            {
                return Ok(None);
            }
            if currency.as_ref().is_some_and(|current| current != &unit) {
                return Ok(None);
            }
            currency = Some(unit);
            sum = sum
                .checked_add(weight)
                .ok_or_else(|| invalid("分录合计超出支持范围"))?;
        }
        Ok(currency.map(|currency| {
            (
                kind,
                currency,
                if kind == RecordKind::Income {
                    -sum
                } else {
                    sum
                },
            )
        }))
    };
    let inferred = if !expense.is_empty() && income.is_empty() {
        infer(expense, RecordKind::Expense)?
    } else if expense.is_empty() && !income.is_empty() {
        infer(income, RecordKind::Income)?
    } else {
        None
    };
    let representative = legs
        .iter()
        .find(|(_, a)| custody(a))
        .or_else(|| legs.first());
    let (account_id, account_name) = if let Some((_, account)) = representative {
        let mut names = Vec::new();
        for (_, account) in legs.iter().filter(|(_, a)| custody(a)) {
            if !names.contains(&account.name) {
                names.push(account.name.clone());
            }
        }
        if names.is_empty() {
            names.push(account.name.clone());
        }
        (account.id.clone(), names.join(" / "))
    } else {
        (String::new(), "未关联账户".to_owned())
    };
    let (kind, currency, amount) = match inferred {
        Some(inferred) => inferred,
        None => {
            let (currency, amount) = representative
                .map(|(p, _)| posting_weight(p))
                .transpose()?
                .unwrap_or(("—".to_owned(), Decimal::ZERO));
            (RecordKind::Other, currency, amount)
        }
    };
    Ok(FinanceRecord {
        source: RecordSource::Other,
        investment_kind: None,
        editable: false,
        id: row.entry.id,
        kind,
        date: row.entry.date,
        amount,
        currency,
        account_id,
        account_name,
        category_id: None,
        category_name: Some(
            match kind {
                RecordKind::Expense => "多分录支出",
                RecordKind::Income => "多分录收入",
                _ => "其他记录 · 首项金额",
            }
            .to_owned(),
        ),
        destination_account_id: None,
        destination_account_name: None,
        destination_amount: None,
        destination_currency: None,
        payee: row.entry.payee,
        note: clean(Some(row.entry.narration)),
    })
}

fn project_daily(
    conn: &Connection,
    owner: &str,
    row: journal::EntryWithPostings,
) -> Result<FinanceRecord> {
    if row.postings.len() != 2 {
        return Err(invalid("该记录不是可编辑的日常收支记录"));
    }
    let legs = row
        .postings
        .iter()
        .map(|p| {
            let a = accounts::get_required(conn, &p.account_id)?;
            if a.sync.owner_user_id != owner || p.sync.owner_user_id != owner {
                return Err(invalid("记录账户所属数据空间不一致"));
            }
            Ok((p, a))
        })
        .collect::<Result<Vec<_>>>()?;
    let category = legs
        .iter()
        .find(|(_, a)| matches!(a.side, AccountSide::Expense | AccountSide::Income));
    let opening = legs
        .iter()
        .any(|(_, a)| a.id == system_accounts::system_account_id(owner, "equity:openingBalance"));
    let kind = match category.map(|(_, a)| a.side) {
        Some(AccountSide::Expense) => RecordKind::Expense,
        Some(AccountSide::Income) => RecordKind::Income,
        _ if opening => RecordKind::OpeningBalance,
        _ => RecordKind::Transfer,
    };
    let (source, account) = if kind == RecordKind::Transfer {
        legs.iter()
            .find(|(p, a)| custody(a) && p.units < Decimal::ZERO)
    } else {
        legs.iter().find(|(_, a)| custody(a))
    }
    .ok_or_else(|| invalid("记录缺少资金账户"))?;
    let destination = if kind == RecordKind::Transfer {
        Some(
            legs.iter()
                .find(|(p, a)| custody(a) && p.units > Decimal::ZERO && a.id != account.id)
                .ok_or_else(|| invalid("转账记录缺少收款账户"))?,
        )
    } else {
        None
    };
    let note = clean(Some(row.entry.narration)).filter(|n| {
        !matches!(
            n.as_str(),
            "Expense" | "Income" | "Transfer" | "Opening Balance" | "Opening balance"
        )
    });
    Ok(FinanceRecord {
        source: RecordSource::Daily,
        investment_kind: None,
        editable: true,
        id: row.entry.id,
        kind,
        date: row.entry.date,
        amount: if kind == RecordKind::OpeningBalance {
            source.units
        } else {
            source.units.abs()
        },
        currency: source.unit.clone(),
        account_id: account.id.clone(),
        account_name: account.name.clone(),
        category_id: category.map(|(_, a)| a.id.clone()),
        category_name: category
            .map(|(_, a)| category_label(conn, owner, a))
            .transpose()?,
        destination_account_id: destination.map(|(_, a)| a.id.clone()),
        destination_account_name: destination.map(|(_, a)| a.name.clone()),
        destination_amount: destination.map(|(p, _)| p.units),
        destination_currency: destination.map(|(_, account)| account.currency.clone()),
        payee: row.entry.payee,
        note,
    })
}

pub fn records(
    conn: &Connection,
    owner: &str,
    filter: &RecordFilter,
    limit: i64,
    offset: i64,
) -> Result<Vec<FinanceRecord>> {
    if let (Some(from), Some(until)) = (filter.from, filter.until)
        && from >= until
    {
        return Err(invalid("开始日期必须早于结束日期"));
    }
    let query = filter.query.trim().to_lowercase();
    let mut rows = Vec::new();
    let mut skipped = 0_i64;
    for row in journal::list_owned(conn, owner, filter.from, filter.until)? {
        if filter
            .account_id
            .as_ref()
            .is_some_and(|id| !row.postings.iter().any(|posting| &posting.account_id == id))
        {
            continue;
        }
        let record = project(conn, owner, row)?;
        if filter.kind.is_some_and(|k| k != record.kind) {
            continue;
        }
        if !query.is_empty() {
            let haystack = format!(
                "{} {} {} {} {}",
                record.account_name,
                record
                    .destination_account_name
                    .as_deref()
                    .unwrap_or_default(),
                record.category_name.as_deref().unwrap_or_default(),
                record.payee.as_deref().unwrap_or_default(),
                record.note.as_deref().unwrap_or_default()
            )
            .to_lowercase();
            if !haystack.contains(&query) {
                continue;
            }
        }
        if skipped < offset.max(0) {
            skipped += 1;
            continue;
        }
        rows.push(record);
        if rows.len() >= limit.clamp(1, 200) as usize {
            break;
        }
    }
    Ok(rows)
}

fn build(
    conn: &Connection,
    owner: &str,
    draft: &RecordDraft,
    previous: Option<&FinanceRecord>,
) -> Result<builders::EntryBuild> {
    // Archiving closes an account to new activity, while an existing
    // record may still be corrected against its original account legs.
    // It never authorizes a redirect to another archived account.
    let original_account = |id: &str| {
        previous.is_some_and(|record| {
            record.account_id == id || record.destination_account_id.as_deref() == Some(id)
        })
    };
    let account = owned_account(
        conn,
        owner,
        &draft.account_id,
        !original_account(&draft.account_id),
    )?;
    let note = clean(draft.note.clone());
    let payee = clean(draft.payee.clone());
    if draft.kind == RecordKind::OpeningBalance {
        let equity = system_accounts::system_account_id(owner, "equity:openingBalance");
        return builders::opening_balance(
            draft.date,
            &account.id,
            equity,
            draft.amount,
            &account.currency,
            note.as_deref(),
            None,
            vec![],
        );
    }
    if draft.amount <= Decimal::ZERO {
        return Err(invalid("金额必须大于零"));
    }
    match draft.kind {
        RecordKind::Expense | RecordKind::Income => {
            let category_id = draft
                .category_id
                .as_ref()
                .ok_or_else(|| invalid("请选择分类"))?;
            let side = if draft.kind == RecordKind::Expense {
                AccountSide::Expense
            } else {
                AccountSide::Income
            };
            let original_category = previous.is_some_and(|record| {
                record.kind == draft.kind && record.category_id.as_ref() == Some(category_id)
            });
            let actual = if original_category {
                // Category leaves available for new capture can change. A
                // historical record keeps its exact classification unless
                // the user explicitly chooses a different available leaf.
                let account = accounts::get(conn, category_id)?
                    .filter(|account| {
                        account.sync.owner_user_id == owner
                            && account.sync.deleted_at.is_none()
                            && account.side == side
                    })
                    .ok_or_else(|| invalid("分类不可用，请重新选择"))?;
                if side == AccountSide::Expense {
                    let exists: bool = conn.query_row(
                        r#"SELECT EXISTS(
                        SELECT 1 FROM "fin:categories" WHERE ledger_account_id=?1
                        AND owner_user_id=?2 AND deleted_at IS NULL)"#,
                        params![category_id, owner],
                        |row| row.get(0),
                    )?;
                    if !exists {
                        return Err(invalid("分类已删除，请重新选择"));
                    }
                }
                account
            } else {
                let available = categories(conn, owner, draft.kind)?
                    .into_iter()
                    .find(|(id, _)| id == category_id)
                    .ok_or_else(|| invalid("分类不可用，请重新选择"))?;
                accounts::get_required(conn, &available.0)?
            };
            if actual.side != side {
                return Err(invalid("分类与收支类型不匹配"));
            }
            if draft.kind == RecordKind::Expense {
                builders::expense(
                    draft.date,
                    actual.id,
                    &account.id,
                    draft.amount,
                    &account.currency,
                    payee,
                    note.as_deref(),
                    None,
                    vec![],
                )
            } else {
                builders::income(
                    draft.date,
                    &account.id,
                    actual.id,
                    draft.amount,
                    &account.currency,
                    payee,
                    note.as_deref(),
                    None,
                    vec![],
                )
            }
        }
        RecordKind::Transfer => {
            let id = draft
                .destination_account_id
                .as_ref()
                .ok_or_else(|| invalid("请选择转入账户"))?;
            if id == &account.id {
                return Err(invalid("转出与转入账户不能相同"));
            }
            let destination = owned_account(conn, owner, id, !original_account(id))?;
            if destination.currency == account.currency
                && draft
                    .destination_amount
                    .is_some_and(|amount| amount != draft.amount)
            {
                return Err(invalid("同币种转账的转出与转入金额必须一致"));
            }
            let received = if destination.currency != account.currency {
                Some(
                    draft
                        .destination_amount
                        .filter(|a| *a > Decimal::ZERO)
                        .ok_or_else(|| invalid("跨币种转账请输入实际到账金额"))?,
                )
            } else {
                None
            };
            builders::transfer(
                draft.date,
                &account.id,
                &destination.id,
                draft.amount,
                &account.currency,
                received,
                received.map(|_| destination.currency.as_str()),
                payee,
                note.as_deref(),
                None,
                vec![],
            )
        }
        RecordKind::OpeningBalance => unreachable!(),
        RecordKind::Investment => Err(invalid("请从投资交易录入或更正此记录")),
        RecordKind::Other => Err(invalid("此记录包含复杂分录，仅支持查看和删除")),
    }
}

pub fn save(
    conn: &mut Connection,
    stamper: &MutationStamper,
    id: Option<&str>,
    draft: &RecordDraft,
) -> Result<()> {
    let tx = conn.savepoint()?;
    let previous = id
        .map(|id| record(&tx, &stamper.owner_user_id, id))
        .transpose()?;
    if let Some(previous) = &previous {
        if !previous.editable {
            return Err(invalid("此记录包含复杂分录，仅支持查看和删除"));
        }
        if previous.kind == RecordKind::OpeningBalance
            && (draft.kind != RecordKind::OpeningBalance || draft.account_id != previous.account_id)
        {
            return Err(invalid("期初余额只能修改金额与日期"));
        }
        if previous.kind != RecordKind::OpeningBalance && draft.kind == RecordKind::OpeningBalance {
            return Err(invalid("普通记录不能改为期初余额"));
        }
    } else if draft.kind == RecordKind::OpeningBalance {
        return Err(invalid("期初余额请在新建账户时设置"));
    }
    let mut entry = build(&tx, &stamper.owner_user_id, draft, previous.as_ref())?;
    if let Some(id) = id {
        let previous = owned_entry(&tx, &stamper.owner_user_id, id)?;
        entry.entry.settled_on = previous.entry.settled_on;
        entry.entry.tag_ids = previous.entry.tag_ids;
        entry.entry.flag = previous.entry.flag;
    }
    let base = if draft.kind == RecordKind::Transfer {
        // The received amount defines this transfer's rate. Its annotated
        // legs share the source currency; validate there so reciprocal
        // decimal rounding does not require an unrelated market FX quote.
        entry.postings[0].unit.clone()
    } else {
        settings_repository::base_currency(&tx)?
    };
    let fx = |conn: &Connection, from: &str, to: &str, as_of: i64| {
        crate::fx::rate_at(conn, from, to, as_of)
    };
    journal::create_in_transaction(&tx, stamper, &fx, &base, entry, id)?;
    tx.commit()?;
    Ok(())
}

pub fn delete_record(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let record = record(conn, &stamper.owner_user_id, id)?;
    if !matches!(record.source, RecordSource::Daily | RecordSource::Other) {
        return Err(invalid("请从原始交易、计划或对账详情撤销此记录"));
    }
    journal::soft_delete(conn, stamper, id)
}

pub fn update_account(
    conn: &mut Connection,
    stamper: &MutationStamper,
    id: &str,
    name: String,
    institution: Option<String>,
    note: Option<String>,
) -> Result<()> {
    if name.trim().is_empty() {
        return Err(invalid("请输入账户名称"));
    }
    if name.trim().chars().count() > 80 {
        return Err(invalid("账户名称请控制在 80 字以内"));
    }
    let tx = conn.savepoint()?;
    let mut account = owned_account(&tx, &stamper.owner_user_id, id, false)?;
    account.name = name.trim().to_owned();
    account.institution = clean(institution);
    account.note = clean(note);
    accounts::update(&tx, stamper, &account)?;
    tx.commit()?;
    Ok(())
}

pub fn archive_account(
    conn: &mut Connection,
    stamper: &MutationStamper,
    id: &str,
    archived: bool,
) -> Result<()> {
    let tx = conn.savepoint()?;
    owned_account(&tx, &stamper.owner_user_id, id, false)?;
    accounts::set_archived(&tx, stamper, id, archived)?;
    tx.commit()?;
    Ok(())
}

pub fn delete_account(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let tx = conn.savepoint()?;
    owned_account(&tx, &stamper.owner_user_id, id, false)?;
    let used: bool = tx.query_row(
        r#"SELECT EXISTS(SELECT 1 FROM "fin:postings" WHERE account_id=?1)"#,
        params![id],
        |r| r.get(0),
    )?;
    if used {
        return Err(invalid("账户已有历史记录，请归档以保留账本"));
    }
    accounts::soft_delete(&tx, stamper, id)?;
    tx.commit()?;
    Ok(())
}

/// Totals retain currencies; transfers and opening balances are not income.
pub fn monthly_totals(
    conn: &Connection,
    owner: &str,
    from: i64,
    until: i64,
) -> Result<Vec<(String, Decimal, Decimal)>> {
    if from >= until {
        return Err(invalid("开始日期必须早于结束日期"));
    }
    let mut totals: BTreeMap<String, (Decimal, Decimal)> = BTreeMap::new();
    for row in journal::list_owned(conn, owner, Some(from), Some(until))? {
        for posting in &row.postings {
            let account = accounts::get_required(conn, &posting.account_id)?;
            if posting.sync.owner_user_id != owner || account.sync.owner_user_id != owner {
                return Err(invalid("记录账户所属数据空间不一致"));
            }
            if !matches!(account.side, AccountSide::Expense | AccountSide::Income) {
                continue;
            }
            let (currency, weight) = posting_weight(posting)?;
            let pair = totals.entry(currency).or_default();
            if account.side == AccountSide::Expense {
                pair.1 = pair
                    .1
                    .checked_add(weight)
                    .ok_or_else(|| invalid("支出合计超出支持范围"))?;
            } else {
                pair.0 = pair
                    .0
                    .checked_sub(weight)
                    .ok_or_else(|| invalid("收入合计超出支持范围"))?;
            }
        }
    }

    Ok(totals
        .into_iter()
        .map(|(currency, (income, expense))| (currency, income, expense))
        .collect())
}

#[cfg(test)]
mod tests;
