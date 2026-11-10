//! Journal repository: the write path for the double-entry ledger. Every
//! create validates the balance invariant first, then commits the entry,
//! its postings and their outbox pointers in one transaction with one
//! shared HLC stamp.

use rusqlite::{Connection, params};
use rust_decimal::Decimal;

use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::builders::EntryBuild;
use crate::error::{FinanceError, Result};
use crate::invariants::{FxRateSource, evaluate_entry_balance};
use crate::models::{EntryFlag, JournalEntry, Posting};
use crate::tables::{JOURNAL_ENTRIES_TABLE, POSTINGS_TABLE};

#[derive(Debug, Clone, PartialEq)]
pub struct EntryWithPostings {
    pub entry: JournalEntry,
    pub postings: Vec<Posting>,
}

const ENTRY_SELECT: &str = r#"SELECT id, date, settled_on, narration, payee, flag, tag_ids_json, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "fin:journal_entries""#;

fn row_to_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<JournalEntry> {
    Ok(JournalEntry {
        id: row.get(0)?,
        date: row.get(1)?,
        settled_on: row.get(2)?,
        narration: row.get(3)?,
        payee: row.get(4)?,
        flag: row
            .get::<_, String>(5)
            .ok()
            .and_then(|s| EntryFlag::parse(&s))
            .unwrap_or(EntryFlag::Confirmed),
        tag_ids: serde_json::from_str(&row.get::<_, String>(6)?).unwrap_or_default(),
        sync: SyncMeta {
            owner_user_id: row.get(7)?,
            updated_at: row.get(8)?,
            updated_by_device: row.get(9)?,
            hlc: row.get(10)?,
            deleted_at: row.get(11)?,
        },
    })
}

const POSTING_SELECT: &str = r#"SELECT id, journal_entry_id, position, account_id, units, unit, cost_per_unit, cost_currency, cost_lot_id, cost_acquired_on, price_per_unit, price_currency, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "fin:postings""#;

fn row_to_posting(row: &rusqlite::Row<'_>) -> rusqlite::Result<Posting> {
    let cost = (|| Some((row.get::<_, String>(6).ok()?, row.get::<_, String>(7).ok()?)))()
        .and_then(|(per_unit, currency)| {
            Decimal::from_str_exact(&per_unit)
                .ok()
                .map(|per_unit| crate::models::Cost {
                    per_unit,
                    currency,
                    lot_id: row.get(8).ok().flatten(),
                    acquired_on: row.get(9).ok().flatten(),
                })
        });
    let price = (|| {
        Some((
            row.get::<_, String>(10).ok()?,
            row.get::<_, String>(11).ok()?,
        ))
    })()
    .and_then(|(per_unit, currency)| {
        Decimal::from_str_exact(&per_unit)
            .ok()
            .map(|per_unit| crate::models::Price { per_unit, currency })
    });

    Ok(Posting {
        id: row.get(0)?,
        journal_entry_id: row.get(1)?,
        position: row.get(2)?,
        account_id: row.get(3)?,
        units: Decimal::from_str_exact(&row.get::<_, String>(4)?).map_err(|e| {
            rusqlite::Error::FromSqlConversionFailure(4, rusqlite::types::Type::Text, Box::new(e))
        })?,
        unit: row.get(5)?,
        cost,
        price,
        sync: SyncMeta {
            owner_user_id: row.get(12)?,
            updated_at: row.get(13)?,
            updated_by_device: row.get(14)?,
            hlc: row.get(15)?,
            deleted_at: row.get(16)?,
        },
    })
}

fn insert_entry(conn: &Connection, entry: &JournalEntry) -> rusqlite::Result<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{JOURNAL_ENTRIES_TABLE}" (id, date, settled_on, narration, payee, flag, tag_ids_json, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)"#
        ),
        params![
            entry.id,
            entry.date,
            entry.settled_on,
            entry.narration,
            entry.payee,
            entry.flag.as_str(),
            serde_json::to_string(&entry.tag_ids).unwrap_or_else(|_| "[]".into()),
            entry.sync.owner_user_id,
            entry.sync.updated_at,
            entry.sync.updated_by_device,
            entry.sync.hlc,
            entry.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn insert_posting(conn: &Connection, posting: &Posting) -> rusqlite::Result<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{POSTINGS_TABLE}" (id, journal_entry_id, position, account_id, units, unit, cost_per_unit, cost_currency, cost_lot_id, cost_acquired_on, price_per_unit, price_currency, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)"#
        ),
        params![
            posting.id,
            posting.journal_entry_id,
            posting.position,
            posting.account_id,
            posting.units.to_string(),
            posting.unit,
            posting.cost.as_ref().map(|c| c.per_unit.to_string()),
            posting.cost.as_ref().map(|c| c.currency.clone()),
            posting.cost.as_ref().and_then(|c| c.lot_id.clone()),
            posting.cost.as_ref().and_then(|c| c.acquired_on),
            posting.price.as_ref().map(|p| p.per_unit.to_string()),
            posting.price.as_ref().map(|p| p.currency.clone()),
            posting.sync.owner_user_id,
            posting.sync.updated_at,
            posting.sync.updated_by_device,
            posting.sync.hlc,
            posting.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn postings_for_entry(conn: &Connection, entry_id: &str) -> rusqlite::Result<Vec<Posting>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{POSTING_SELECT} WHERE journal_entry_id = ?1 AND deleted_at IS NULL ORDER BY position"
    ))?;
    let rows = stmt.query_map(params![entry_id], row_to_posting)?;
    rows.collect::<std::result::Result<Vec<_>, _>>()
}

/// Validate, then commit the entry + postings + outbox pointers in one
/// transaction. All rows share one stamp (one HLC tick per mutation).
pub fn create(
    conn: &mut Connection,
    stamper: &MutationStamper,
    fx: &dyn FxRateSource,
    base_currency: &str,
    build: EntryBuild,
) -> Result<EntryWithPostings> {
    let stamp = stamper.stamp(conn)?;
    let sync = SyncMeta::from_stamp(&stamp);
    let entry = JournalEntry {
        id: lifeos::ids::new_id(),
        date: build.entry.date,
        settled_on: build.entry.settled_on,
        narration: build.entry.narration.clone(),
        payee: build.entry.payee.clone(),
        flag: build.entry.flag,
        tag_ids: build.entry.tag_ids.clone(),
        sync: sync.clone(),
    };
    let postings: Vec<Posting> = build
        .postings
        .iter()
        .map(|d| Posting {
            id: lifeos::ids::new_id(),
            journal_entry_id: entry.id.clone(),
            position: d.position as i64,
            account_id: d.account_id.clone(),
            units: d.units,
            unit: d.unit.clone(),
            cost: d.cost.clone(),
            price: d.price.clone(),
            sync: sync.clone(),
        })
        .collect();

    // Validate against the DB-backed FX source *before* writing.
    let report = evaluate_entry_balance(conn, &entry, &postings, fx, base_currency, None);
    if !report.is_balanced() {
        return Err(FinanceError::Unbalanced(report));
    }

    let tx = conn.transaction()?;
    insert_entry(&tx, &entry)?;
    for posting in &postings {
        insert_posting(&tx, posting)?;
        outbox::enqueue(&tx, POSTINGS_TABLE, &posting.id)?;
    }
    outbox::enqueue(&tx, JOURNAL_ENTRIES_TABLE, &entry.id)?;
    tx.commit()?;

    Ok(EntryWithPostings { entry, postings })
}

/// Recent entries newest-first with their (non-deleted) postings.
pub fn list_recent(conn: &Connection, limit: i64) -> Result<Vec<EntryWithPostings>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{ENTRY_SELECT} WHERE deleted_at IS NULL ORDER BY date DESC, hlc DESC LIMIT ?1"
    ))?;
    let entries = stmt
        .query_map(params![limit], row_to_entry)?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let mut result = Vec::with_capacity(entries.len());
    for entry in entries {
        let postings = postings_for_entry(conn, &entry.id)?;
        result.push(EntryWithPostings { entry, postings });
    }
    Ok(result)
}

pub fn get(conn: &Connection, entry_id: &str) -> Result<Option<EntryWithPostings>> {
    let mut stmt = conn.prepare_cached(&format!("{ENTRY_SELECT} WHERE id = ?1"))?;
    let entry = match stmt.query_row(params![entry_id], row_to_entry) {
        Ok(entry) => entry,
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok(None),
        Err(e) => return Err(e.into()),
    };
    let postings = postings_for_entry(conn, &entry.id)?;
    Ok(Some(EntryWithPostings { entry, postings }))
}

/// Tombstone the entry and its postings (sync carries the deletion).
pub fn soft_delete(conn: &mut Connection, stamper: &MutationStamper, entry_id: &str) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let deleted_at = stamp.now.div_euclid(1000);
    let tx = conn.transaction()?;
    tx.execute(
        &format!(
            r#"UPDATE "{JOURNAL_ENTRIES_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![entry_id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    tx.execute(
        &format!(
            r#"UPDATE "{POSTINGS_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE journal_entry_id = ?1 AND deleted_at IS NULL"#
        ),
        params![entry_id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    outbox::enqueue(&tx, JOURNAL_ENTRIES_TABLE, entry_id)?;
    // Re-enqueue every posting of the entry so the tombstones fan out.
    let ids: Vec<String> = {
        let mut stmt = tx.prepare_cached(&format!(
            r#"SELECT id FROM "{POSTINGS_TABLE}" WHERE journal_entry_id = ?1"#
        ))?;
        stmt.query_map(params![entry_id], |row| row.get::<_, String>(0))?
            .collect::<std::result::Result<Vec<_>, _>>()?
    };
    for id in ids {
        outbox::enqueue(&tx, POSTINGS_TABLE, &id)?;
    }
    tx.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::builders;
    use crate::repos::account_repository as accounts;
    use crate::system_accounts;
    use crate::tables::migration;
    use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations};
    use lifeos::hlc::Hlc;
    use rust_decimal::Decimal;
    use std::path::PathBuf;
    use std::str::FromStr;

    fn test_db() -> Db {
        Db::open(DbOpenOptions {
            path: PathBuf::from(":memory:"),
            encryption_key: None,
            migrations: core_migrations().push(migration()),
        })
        .unwrap()
    }

    fn stamper() -> MutationStamper {
        MutationStamper::new("user-1", "device-1")
    }

    /// The fx closure used by real writes: reads fx_rates off whatever
    /// connection the validator hands it (inside the write transaction).
    fn conn_fx() -> impl FxRateSource {
        |conn: &Connection, from: &str, to: &str, as_of: i64| {
            crate::fx::rate_at(conn, from, to, as_of)
        }
    }

    #[tokio::test]
    async fn expense_write_is_atomic_with_outbox() {
        let db = test_db();
        let st = stamper();
        db.call_sync(
            move |conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
                system_accounts::seed_system_accounts(conn, &st).unwrap();
                let cash = accounts::create(
                    conn,
                    &st,
                    accounts::NewAccount::custody(
                        crate::models::AccountCategory::Cash,
                        "现金",
                        "CNY",
                    ),
                )?;
                let expense_account =
                    accounts::find_system_account(conn, "user-1", "expense:dining")?.unwrap();
                let fx = conn_fx();
                let build = builders::expense(
                    1_767_258_000,
                    &expense_account.id,
                    &cash.id,
                    Decimal::from_str("42.50").unwrap(),
                    "CNY",
                    Some("星巴克".into()),
                    None,
                    None,
                    vec![],
                )?;
                let created = create(conn, &st, &fx, "CNY", build)?;
                assert_eq!(created.postings.len(), 2);

                // Entry + 2 postings + 2 accounts + categories: outbox has them all.
                let pending = outbox::count(conn)?;
                assert!(pending >= 3);

                let listed = list_recent(conn, 10)?;
                assert_eq!(listed.len(), 1);
                assert_eq!(listed[0].entry.narration, "Expense");
                assert_eq!(listed[0].postings.len(), 2);

                // Restart recovery: a fresh handle over the same storage sees it.
                let _ = Hlc::parse(&created.entry.sync.hlc).unwrap();
                Ok(())
            },
        )
        .unwrap();
    }

    #[tokio::test]
    async fn unbalanced_write_is_refused() {
        let db = test_db();
        let st = stamper();
        db.call_sync(
            move |conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
                system_accounts::seed_system_accounts(conn, &st).unwrap();
                // Hand-built unbalanced entry: legs don't cancel.
                let build = builders::EntryBuild {
                    entry: builders::EntryDraft {
                        date: 1,
                        settled_on: None,
                        narration: "bad".into(),
                        payee: None,
                        flag: EntryFlag::Confirmed,
                        tag_ids: vec![],
                    },
                    postings: vec![
                        builders::PostingDraft {
                            position: 0,
                            account_id: "a".into(),
                            units: Decimal::from(10),
                            unit: "CNY".into(),
                            cost: None,
                            price: None,
                        },
                        builders::PostingDraft {
                            position: 1,
                            account_id: "b".into(),
                            units: Decimal::from(-9),
                            unit: "CNY".into(),
                            cost: None,
                            price: None,
                        },
                    ],
                };
                let fx = conn_fx();
                let result = create(conn, &st, &fx, "CNY", build);
                match result {
                    Err(FinanceError::Unbalanced(report)) => {
                        assert!(!report.is_balanced());
                    }
                    other => panic!("expected Unbalanced, got {other:?}"),
                }
                // Nothing was written.
                assert!(list_recent(conn, 10)?.is_empty());
                Ok(())
            },
        )
        .unwrap();
    }

    #[tokio::test]
    async fn self_balanced_foreign_currency_write_needs_no_fx() {
        let db = test_db();
        let st = stamper();
        db.call_sync(
            move |conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
                system_accounts::seed_system_accounts(conn, &st).unwrap();
                let usd = accounts::create(
                    conn,
                    &st,
                    accounts::NewAccount::custody(
                        crate::models::AccountCategory::Cash,
                        "USD",
                        "USD",
                    ),
                )?;
                let expense_account =
                    accounts::find_system_account(conn, "user-1", "expense:dining")?.unwrap();
                // No fx_rates rows: a USD expense paid from a USD account still
                // cancels natively, so no CNY rate is required.
                let fx = conn_fx();
                let build = builders::expense(
                    1_767_258_000,
                    &expense_account.id,
                    &usd.id,
                    Decimal::from(5),
                    "USD",
                    None,
                    None,
                    None,
                    vec![],
                )?;
                assert!(create(conn, &st, &fx, "CNY", build).is_ok());
                Ok(())
            },
        )
        .unwrap();
    }

    #[tokio::test]
    async fn delete_tombstones_entry_and_postings() {
        let db = test_db();
        let st = stamper();
        db.call_sync(
            move |conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
                system_accounts::seed_system_accounts(conn, &st).unwrap();
                let cash = accounts::create(
                    conn,
                    &st,
                    accounts::NewAccount::custody(
                        crate::models::AccountCategory::Cash,
                        "现金",
                        "CNY",
                    ),
                )?;
                let expense_account =
                    accounts::find_system_account(conn, "user-1", "expense:dining")?.unwrap();
                let fx = conn_fx();
                let build = builders::expense(
                    1_767_258_000,
                    &expense_account.id,
                    &cash.id,
                    Decimal::from(10),
                    "CNY",
                    None,
                    None,
                    None,
                    vec![],
                )?;
                let created = create(conn, &st, &fx, "CNY", build)?;
                soft_delete(conn, &st, &created.entry.id)?;
                assert!(list_recent(conn, 10)?.is_empty());
                Ok(())
            },
        )
        .unwrap();
    }
}
