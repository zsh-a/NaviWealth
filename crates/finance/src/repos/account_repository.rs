//! Account repository: CRUD over `fin:accounts`, custody-account balances,
//! and lookups for the seeded system tree.

use rusqlite::{Connection, OptionalExtension, params};
use rust_decimal::Decimal;

use lifeos::Result as LifeosResult;
use lifeos::ids::new_id;
use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::error::{FinanceError, Result};
pub use crate::models::NewAccount;
use crate::models::{Account, AccountCategory, AccountSide, side_for_category};
use crate::system_accounts;
use crate::tables::{ACCOUNTS_TABLE, POSTINGS_TABLE};

pub fn system_account_id(owner: &str, path: &str) -> String {
    system_accounts::system_account_id(owner, path)
}

/// Insert one account row (shared by create and seeding helpers).
fn insert(conn: &Connection, account: &Account, outbox_table: &str) -> LifeosResult<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{ACCOUNTS_TABLE}" (id, type, name, currency, institution, account_number, note, archived, category, parent_id, icon, color, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)"#
        ),
        params![
            account.id,
            account.kind.as_str(),
            account.name,
            account.currency,
            account.institution,
            account.account_number,
            account.note,
            i64::from(account.archived),
            account.side.as_str(),
            account.parent_id,
            account.icon,
            account.color,
            account.sync.owner_user_id,
            account.sync.updated_at,
            account.sync.updated_by_device,
            account.sync.hlc,
            account.sync.deleted_at,
        ],
    )?;
    outbox::enqueue(conn, outbox_table, &account.id)
}

fn row_to_account(row: &rusqlite::Row<'_>) -> rusqlite::Result<Account> {
    let kind = row
        .get::<_, String>(1)
        .ok()
        .and_then(|s| AccountCategory::parse(&s));
    Ok(Account {
        id: row.get(0)?,
        kind: kind.unwrap_or(AccountCategory::Asset),
        name: row.get(2)?,
        currency: row.get(3)?,
        institution: row.get(4)?,
        account_number: row.get(5)?,
        note: row.get(6)?,
        archived: row.get::<_, i64>(7)? != 0,
        side: row
            .get::<_, String>(8)
            .ok()
            .and_then(|s| AccountSide::parse(&s))
            .unwrap_or(AccountSide::Asset),
        parent_id: row.get(9)?,
        icon: row.get(10)?,
        color: row.get(11)?,
        sync: SyncMeta {
            owner_user_id: row.get(12)?,
            updated_at: row.get(13)?,
            updated_by_device: row.get(14)?,
            hlc: row.get(15)?,
            deleted_at: row.get(16)?,
        },
    })
}

const ACCOUNT_SELECT: &str = r#"SELECT id, type, name, currency, institution, account_number, note, archived, category, parent_id, icon, color, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "fin:accounts""#;

pub fn get(conn: &Connection, id: &str) -> Result<Option<Account>> {
    let mut stmt = conn.prepare_cached(&format!("{ACCOUNT_SELECT} WHERE id = ?1"))?;
    Ok(stmt.query_row(params![id], row_to_account).optional()?)
}

pub fn get_required(conn: &Connection, id: &str) -> Result<Account> {
    get(conn, id)?.ok_or_else(|| FinanceError::AccountNotFound(id.to_owned()))
}

pub fn list(conn: &Connection, include_archived: bool) -> Result<Vec<Account>> {
    let sql = if include_archived {
        format!("{ACCOUNT_SELECT} WHERE deleted_at IS NULL ORDER BY name")
    } else {
        format!("{ACCOUNT_SELECT} WHERE deleted_at IS NULL AND archived = 0 ORDER BY name")
    };
    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map([], row_to_account)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// Custody accounts the record form books from (cash/bank/broker/crypto).
pub fn list_cash_accounts(conn: &Connection) -> Result<Vec<Account>> {
    let sql = format!(
        "{ACCOUNT_SELECT} WHERE deleted_at IS NULL AND archived = 0 AND type IN ('cash', 'bank', 'broker', 'crypto') ORDER BY name"
    );
    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map([], row_to_account)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// Expense-side ledger accounts (category leaves), for pickers.
pub fn list_by_side(conn: &Connection, side: AccountSide) -> Result<Vec<Account>> {
    let sql = format!(
        "{ACCOUNT_SELECT} WHERE deleted_at IS NULL AND archived = 0 AND category = ?1 ORDER BY name"
    );
    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(params![side.as_str()], row_to_account)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn find_system_account(conn: &Connection, owner: &str, path: &str) -> Result<Option<Account>> {
    get(conn, &system_account_id(owner, path))
}

pub fn create(conn: &Connection, stamper: &MutationStamper, new: NewAccount) -> Result<Account> {
    let stamp = stamper.stamp(conn)?;
    let account = Account {
        id: new_id(),
        kind: new.kind,
        name: new.name,
        currency: new.currency,
        institution: new.institution,
        account_number: new.account_number,
        note: new.note,
        archived: false,
        side: side_for_category(new.kind),
        parent_id: new.parent_id,
        icon: new.icon,
        color: new.color,
        sync: SyncMeta::from_stamp(&stamp),
    };
    insert(conn, &account, ACCOUNTS_TABLE)?;
    Ok(account)
}

pub fn update(conn: &Connection, stamper: &MutationStamper, account: &Account) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let mut updated = account.clone();
    updated.sync = SyncMeta::from_stamp(&stamp);
    insert(conn, &updated, ACCOUNTS_TABLE)?;
    Ok(())
}

/// Tombstone delete (sync carries the deletion).
pub fn soft_delete(conn: &Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let deleted_at = stamp.now.div_euclid(1000);
    conn.execute(
        &format!(
            r#"UPDATE "{ACCOUNTS_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, deleted_at, stamp.hlc, stamp.device_id, stamp.now.div_euclid(1000)],
    )?;
    outbox::enqueue(conn, ACCOUNTS_TABLE, id)?;
    Ok(())
}

pub fn set_archived(
    conn: &Connection,
    stamper: &MutationStamper,
    id: &str,
    archived: bool,
) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    conn.execute(
        &format!(
            r#"UPDATE "{ACCOUNTS_TABLE}" SET archived = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, i64::from(archived), stamp.hlc, stamp.device_id, stamp.now.div_euclid(1000)],
    )?;
    outbox::enqueue(conn, ACCOUNTS_TABLE, id)?;
    Ok(())
}

/// Algebraic sum of non-deleted postings per unit, per account.
#[derive(Debug, Clone, PartialEq)]
pub struct AccountBalance {
    pub account_id: String,
    /// Fiat legs first, asset legs after (matching the Flutter read side).
    pub legs: Vec<(String, Decimal)>,
}

impl AccountBalance {
    pub fn is_multi_unit(&self) -> bool {
        self.legs.len() > 1
    }

    pub fn primary(&self) -> Option<&(String, Decimal)> {
        self.legs.first()
    }
}

pub fn balances(conn: &Connection) -> LifeosResult<Vec<AccountBalance>> {
    // Sum over TEXT units must stay exact decimal — do it in Rust, never
    // SQLite NUMERIC (money is forbidden in REAL/NUMERIC columns).
    let mut stmt = conn.prepare_cached(&format!(
        r#"SELECT account_id, unit, units FROM "{POSTINGS_TABLE}" WHERE deleted_at IS NULL"#
    ))?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    })?;

    // (account_id, unit) -> sum
    let mut sums: Vec<(String, String, Decimal)> = Vec::new();
    for row in rows {
        let (account_id, unit, units) = row?;
        let units = Decimal::from_str_exact(&units).map_err(|e| {
            lifeos::LifeosError::InvalidData(format!("bad decimal in postings {units:?}: {e}"))
        })?;
        match sums
            .iter_mut()
            .find(|(a, u, _)| a == &account_id && u == &unit)
        {
            Some((_, _, sum)) => {
                *sum = sum.checked_add(units).ok_or_else(|| {
                    lifeos::LifeosError::InvalidData(
                        "account balance exceeds supported decimal range".to_owned(),
                    )
                })?;
            }
            None => sums.push((account_id, unit, units)),
        }
    }

    let mut by_account: Vec<AccountBalance> = Vec::new();
    for (account_id, unit, sum) in sums {
        if !by_account.iter().any(|b| b.account_id == account_id) {
            by_account.push(AccountBalance {
                account_id: account_id.clone(),
                legs: Vec::new(),
            });
        }
        let entry = by_account
            .iter_mut()
            .find(|b| b.account_id == account_id)
            .expect("just pushed");
        entry.legs.push((unit, sum));
    }
    for balance in &mut by_account {
        // Fiat legs (3-8 uppercase letters) first, asset legs after.
        balance.legs.sort_by_key(|(unit, _)| {
            let fiat =
                (3..=8).contains(&unit.len()) && unit.bytes().all(|b| b.is_ascii_uppercase());
            !fiat
        });
    }
    by_account.sort_by(|a, b| a.account_id.cmp(&b.account_id));
    Ok(by_account)
}

/// Compile-time reminder that this repository belongs to the finance
/// domain.
pub const DOMAIN: lifeos::error::Domain = lifeos::error::Domain::Finance;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tables::migration;
    use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations};
    use std::path::PathBuf;

    pub(crate) fn test_db() -> Db {
        Db::open(DbOpenOptions {
            path: PathBuf::from(":memory:"),
            encryption_key: None,
            migrations: core_migrations().push(migration()),
        })
        .unwrap()
    }

    pub(crate) fn stamper() -> MutationStamper {
        MutationStamper::new("user-1", "device-1")
    }

    #[tokio::test]
    async fn create_list_balance_roundtrip() {
        let db = test_db();
        let st = stamper();
        db.call_sync(
            move |conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
                let cash = create(
                    conn,
                    &st,
                    NewAccount::custody(AccountCategory::Cash, "现金", "CNY"),
                )?;
                assert_eq!(cash.side, AccountSide::Asset);
                assert!(!cash.id.starts_with("system-account:"));

                let listed = list(conn, false)?;
                assert!(listed.iter().any(|a| a.id == cash.id));
                Ok(())
            },
        )
        .unwrap();
    }

    #[tokio::test]
    async fn balances_sum_exact_decimals() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
            let cash = create(conn, &st, NewAccount::custody(AccountCategory::Cash, "现金", "CNY"))?;
            // Two postings on the same account: exact decimal sum, not float.
            for units in ["100.10", "-0.01", "0.000001"] {
                conn.execute(
                    &format!(r#"INSERT INTO "{POSTINGS_TABLE}" (id, journal_entry_id, position, account_id, units, unit, owner_user_id, updated_at, updated_by_device, hlc) VALUES ('p'||random(), 'j', 0, ?1, ?2, 'CNY', 'u', 0, 'd', '1.0000-d')"#),
                    params![cash.id, units],
                )?;
            }
            let result = balances(conn)?;
            let balance = result.iter().find(|b| b.account_id == cash.id).unwrap();
            assert_eq!(balance.legs[0].1.to_string(), "100.090001");
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn tombstone_and_archive() {
        let db = test_db();
        let st = stamper();
        db.call_sync(
            move |conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
                let a = create(
                    conn,
                    &st,
                    NewAccount::custody(AccountCategory::Bank, "招行", "CNY"),
                )?;
                set_archived(conn, &st, &a.id, true)?;
                assert!(list(conn, false)?.is_empty());
                assert_eq!(list(conn, true)?.len(), 1);

                let b = create(
                    conn,
                    &st,
                    NewAccount::custody(AccountCategory::Cash, "零钱", "CNY"),
                )?;
                soft_delete(conn, &st, &b.id)?;
                assert!(get(conn, &b.id)?.unwrap().sync.deleted_at.is_some());
                assert!(list(conn, true)?.len() == 1);
                Ok(())
            },
        )
        .unwrap();
    }
}
