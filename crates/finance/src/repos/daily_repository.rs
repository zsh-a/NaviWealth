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

mod types;
pub use types::*;

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
        RecordKind::Expense => Ok(expense_categories(conn, owner)?
            .into_iter()
            .map(|c| (c.id, c.name))
            .collect()),
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

mod projection;
use projection::*;

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
) -> Result<String> {
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
    let saved = journal::create_in_transaction(&tx, stamper, &fx, &base, entry, id)?;
    tx.commit()?;
    Ok(saved.entry.id)
}

pub fn delete_record(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let record = record(conn, &stamper.owner_user_id, id)?;
    if !matches!(record.source, RecordSource::Daily | RecordSource::Other) {
        return Err(invalid("请从原始交易、计划或对账详情撤销此记录"));
    }
    journal::soft_delete(conn, stamper, id)
}

/// Undo a deletion inside the undo window. Mirrors [`delete_record`]'s guard:
/// structured records must still be corrected through their own workflow, and
/// every referenced account must have survived the window.
pub fn restore_record(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let entry = journal::get(conn, id)?.ok_or_else(|| invalid("记录不存在或无法访问"))?;
    if entry.entry.sync.owner_user_id != stamper.owner_user_id {
        return Err(invalid("记录不存在或无法访问"));
    }
    if entry.entry.sync.deleted_at.is_none() {
        return Ok(());
    }
    let structured = entry.entry.tag_ids.iter().any(|tag| {
        tag.starts_with("wealth:")
            || tag.starts_with("recurring:")
            || tag.starts_with("liability:")
            || tag.starts_with("reconciliation:")
    });
    if structured {
        return Err(invalid("请从原始交易、计划或对账详情撤销此记录"));
    }
    // get() intentionally excludes tombstoned postings. Only this deletion's
    // version may be restored; older versions belong to superseded edits.
    let account_ids = {
        let mut stmt = conn.prepare_cached(
            r#"SELECT account_id FROM "fin:postings" WHERE journal_entry_id = ?1
               AND owner_user_id = ?2 AND hlc = ?3 AND deleted_at IS NOT NULL"#,
        )?;
        stmt.query_map(
            params![id, stamper.owner_user_id, entry.entry.sync.hlc],
            |row| row.get::<_, String>(0),
        )?
        .collect::<std::result::Result<Vec<_>, _>>()?
    };
    if account_ids.len() != 2 {
        return Err(invalid("记录分录尚未同步完整，请刷新后重试"));
    }
    for account_id in &account_ids {
        if !accounts::get(conn, account_id)?.is_some_and(|account| {
            account.sync.owner_user_id == stamper.owner_user_id && account.sync.deleted_at.is_none()
        }) {
            return Err(invalid("记录引用的账户已被删除，无法恢复"));
        }
    }
    journal::restore(conn, stamper, id)
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
mod queries;
use queries::posting_weight;
pub use queries::*;

#[cfg(test)]
mod tests;

#[cfg(test)]
#[path = "daily_repository/query_tests.rs"]
mod query_tests;
