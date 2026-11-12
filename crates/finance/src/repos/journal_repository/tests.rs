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
    |conn: &Connection, from: &str, to: &str, as_of: i64| crate::fx::rate_at(conn, from, to, as_of)
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
                accounts::NewAccount::custody(crate::models::AccountCategory::Cash, "现金", "CNY"),
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
                accounts::NewAccount::custody(crate::models::AccountCategory::Cash, "USD", "USD"),
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
                accounts::NewAccount::custody(crate::models::AccountCategory::Cash, "现金", "CNY"),
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
