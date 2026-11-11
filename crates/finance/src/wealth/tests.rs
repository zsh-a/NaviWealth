use super::*;
use crate::{
    models::{AccountCategory, NewAccount},
    repos::{account_repository as accounts, journal_repository as journal},
};
use lifeos::sync::{MutationStamper, outbox};
use rusqlite::{Connection, params};
use rust_decimal::Decimal;
fn d(s: &str) -> Decimal {
    Decimal::from_str_exact(s).unwrap()
}
struct Fixture {
    c: Connection,
    st: MutationStamper,
    a: String,
    broker: String,
    cash: String,
}
fn fixture() -> Fixture {
    let mut c = Connection::open_in_memory().unwrap();
    for m in lifeos::db::migrations::core_migrations()
        .push(crate::tables::migration())
        .push(crate::tables::assets_migration())
        .push(migration())
        .push(crate::planning::migration())
        .steps()
    {
        c.execute_batch(m.sql).unwrap();
    }
    let st = MutationStamper::new("owner", "device");
    crate::system_accounts::seed_system_accounts(&c, &st).unwrap();
    let broker = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Broker, "Broker", "USD"),
    )
    .unwrap()
    .id;
    let cash = accounts::create(
        &c,
        &st,
        NewAccount::custody(AccountCategory::Bank, "Cash", "USD"),
    )
    .unwrap()
    .id;
    let a = save_asset(
        &mut c,
        &st,
        None,
        AssetDraft {
            kind: "stock".into(),
            name: "Apple".into(),
            market: Some("us".into()),
            symbol: Some("aapl".into()),
            currency: "USD".into(),
            note: None,
        },
    )
    .unwrap()
    .id;
    Fixture {
        c,
        st,
        a,
        broker,
        cash,
    }
}
fn draft(f: &Fixture, kind: OperationKind, q: &str, p: &str, date: i64) -> OperationDraft {
    OperationDraft {
        kind,
        asset_id: f.a.clone(),
        account_id: f.broker.clone(),
        cash_account_id: Some(f.cash.clone()),
        date,
        quantity: d(q),
        unit_price: d(p),
        fees: Decimal::ZERO,
        amount: Decimal::ZERO,
        note: None,
    }
}
fn holding(f: &Fixture) -> Holding {
    snapshot(&f.c, "owner", lifeos::ids::now_secs(), "USD")
        .unwrap()
        .holdings
        .remove(0)
}
#[test]
fn fifo_partial_sale_fees_dividend_split_and_reprice_do_not_change_quantity() {
    let mut f = fixture();
    let mut buy = draft(&f, OperationKind::Buy, "10", "10", 100);
    buy.fees = d("2");
    save_operation(&mut f.c, &f.st, None, buy).unwrap();
    let split = draft(&f, OperationKind::Split, "2", "0", 110);
    save_operation(&mut f.c, &f.st, None, split).unwrap();
    let mut sell = draft(&f, OperationKind::Sell, "5", "12", 120);
    sell.fees = d("1");
    let sold = save_operation(&mut f.c, &f.st, None, sell).unwrap();
    assert_eq!(sold.cash_amount, d("59"));
    let mut dividend = draft(&f, OperationKind::Dividend, "0", "0", 130);
    dividend.amount = d("8");
    dividend.fees = d("1");
    save_operation(&mut f.c, &f.st, None, dividend).unwrap();
    let h = holding(&f);
    assert_eq!(h.quantity, d("15"));
    assert_eq!(h.cost_basis, d("76.5"));
    assert_eq!(h.realized_pnl, d("33.5"));
    assert_eq!(h.dividends, d("7"));
    assert!(h.market_value.is_none());
    record_price(&mut f.c, &f.st, &f.a, d("13"), 140, None).unwrap();
    record_price(&mut f.c, &f.st, &f.a, d("14"), 150, None).unwrap();
    let h = holding(&f);
    assert_eq!(h.quantity, d("15"));
    assert_eq!(h.market_value, Some(d("210")));
    assert_eq!(h.unrealized_pnl, Some(d("133.5")));
    let balances = accounts::balances(&f.c).unwrap();
    let broker = balances.iter().find(|v| v.account_id == f.broker).unwrap();
    assert_eq!(broker.legs.iter().find(|v| v.0 == f.a).unwrap().1, d("15"));
    let cash = cash_balances(&f.c, "owner", 200).unwrap();
    assert_eq!(
        cash.iter().find(|c| c.account_id == f.cash).unwrap().amount,
        d("-36")
    );
}
#[test]
fn edits_replay_later_sales_and_delete_restores_cost_and_cash() {
    let mut f = fixture();
    let buy = draft(&f, OperationKind::Buy, "10", "10", 100);
    let a = save_operation(&mut f.c, &f.st, None, buy).unwrap();
    let buy = draft(&f, OperationKind::Buy, "10", "20", 100);
    save_operation(&mut f.c, &f.st, None, buy).unwrap();
    let sell = draft(&f, OperationKind::Sell, "12", "30", 100);
    let s = save_operation(&mut f.c, &f.st, None, sell).unwrap();
    assert_eq!(holding(&f).cost_basis, d("160"));
    assert_eq!(holding(&f).realized_pnl, d("220"));
    let edit = draft(&f, OperationKind::Buy, "10", "12", 100);
    let edited = save_operation(&mut f.c, &f.st, Some(&a.id), edit).unwrap();
    assert_eq!(edited.id, a.id);
    assert_eq!(edited.sequence, a.sequence);
    assert_eq!(holding(&f).realized_pnl, d("200"));
    // Removing the earlier buy would leave the later sell oversold. The whole replay rolls back.
    let count = outbox::count(&f.c).unwrap();
    assert!(delete_operation(&mut f.c, &f.st, &a.id).is_err());
    assert_eq!(outbox::count(&f.c).unwrap(), count);
    assert_eq!(holding(&f).quantity, d("8"));
    delete_operation(&mut f.c, &f.st, &s.id).unwrap();
    assert_eq!(holding(&f).quantity, d("20"));
    assert_eq!(holding(&f).cost_basis, d("320"));
    assert!(
        journal::get(&f.c, &s.id)
            .unwrap()
            .unwrap()
            .entry
            .sync
            .deleted_at
            .is_some()
    );
    delete_operation(&mut f.c, &f.st, &a.id).unwrap();
    assert_eq!(holding(&f).quantity, d("10"));
    assert_eq!(holding(&f).cost_basis, d("200"));
}
#[test]
fn owner_guards_archive_guards_and_invalid_writes_are_atomic() {
    let mut f = fixture();
    let other = MutationStamper::new("other", "device");
    assert!(asset(&f.c, "other", &f.a).is_err());
    assert!(archive_asset(&mut f.c, &other, &f.a, true).is_err());
    assert!(delete_asset(&mut f.c, &other, &f.a).is_err());
    assert!(record_price(&mut f.c, &other, &f.a, d("3"), 100, None).is_err());
    let mut op = draft(&f, OperationKind::Buy, "10", "10", 100);
    let count = outbox::count(&f.c).unwrap();
    assert!(save_operation(&mut f.c, &other, None, op.clone()).is_err());
    op.quantity = d("-1");
    assert!(save_operation(&mut f.c, &f.st, None, op.clone()).is_err());
    op.quantity = d("1");
    op.date = lifeos::ids::now_secs() + 10000;
    assert!(save_operation(&mut f.c, &f.st, None, op).is_err());
    assert!(record_price(&mut f.c, &f.st, &f.a, d("0"), 100, None).is_err());
    assert!(
        record_price(
            &mut f.c,
            &f.st,
            &f.a,
            d("3"),
            lifeos::ids::now_secs() + 10000,
            None
        )
        .is_err()
    );
    assert_eq!(outbox::count(&f.c).unwrap(), count);
    archive_asset(&mut f.c, &f.st, &f.a, true).unwrap();
    let op = draft(&f, OperationKind::Opening, "1", "10", 100);
    assert!(save_operation(&mut f.c, &f.st, None, op.clone()).is_err());
    archive_asset(&mut f.c, &f.st, &f.a, false).unwrap();
    accounts::set_archived(&f.c, &f.st, &f.broker, true).unwrap();
    assert!(save_operation(&mut f.c, &f.st, None, op).is_err());
}
#[test]
fn failed_oversell_leaves_journal_metadata_and_outbox_unchanged() {
    let mut f = fixture();
    let op = draft(&f, OperationKind::Opening, "2", "10", 100);
    save_operation(&mut f.c, &f.st, None, op).unwrap();
    let entries = journal::list_recent(&f.c, 100).unwrap();
    let count = outbox::count(&f.c).unwrap();
    let op = draft(&f, OperationKind::Sell, "3", "10", 200);
    assert!(save_operation(&mut f.c, &f.st, None, op).is_err());
    assert_eq!(entries, journal::list_recent(&f.c, 100).unwrap());
    assert_eq!(outbox::count(&f.c).unwrap(), count);
    assert_eq!(operations(&f.c, "owner", None).unwrap().len(), 1);
}
#[test]
fn valuation_coverage_historical_quotes_and_currency_totals_are_explicit() {
    let mut f = fixture();
    let op = draft(&f, OperationKind::Opening, "2", "10", 100);
    save_operation(&mut f.c, &f.st, None, op).unwrap();
    let v = snapshot(&f.c, "owner", 105, "CNY").unwrap();
    assert!(v.net_worth.is_none());
    assert_eq!(v.missing_prices.len(), 1);
    record_price(&mut f.c, &f.st, &f.a, d("12"), 110, Some("manual".into())).unwrap();
    record_price(&mut f.c, &f.st, &f.a, d("14"), 120, None).unwrap();
    let v = snapshot(&f.c, "owner", 115, "CNY").unwrap();
    assert_eq!(v.holdings[0].market_value, Some(d("24")));
    assert_eq!(v.holdings[0].price_as_of, Some(110));
    assert!(v.net_worth.is_none());
    assert_eq!(v.missing_fx, vec!["USD/CNY"]);
    crate::fx::upsert_rate(&f.c, "USD", "CNY", 0, d("7"), Some("manual")).unwrap();
    assert_eq!(
        snapshot(&f.c, "owner", 115, "CNY").unwrap().net_worth,
        Some(d("168"))
    );
    let history = wealth_history(&f.c, "owner", "USD").unwrap();
    assert_eq!(
        history.iter().map(|p| p.as_of).collect::<Vec<_>>(),
        vec![100, 110, 120]
    );
    assert!(history[0].net_worth.is_none());
    assert_eq!(history[1].net_worth, Some(d("24")));
}
#[test]
fn registered_payloads_preserve_decimal_strings_and_tombstones() {
    let mut f = fixture();
    let op = draft(
        &f,
        OperationKind::Opening,
        "0.1234567890123456789",
        "123.45",
        100,
    );
    let op = save_operation(&mut f.c, &f.st, None, op).unwrap();
    let mut registry = lifeos::sync::SyncRegistry::new();
    register(&mut registry);
    let adapter = registry.adapter("fin:wealth_operations").unwrap();
    let raw = adapter.read_row(&f.c, &op.id).unwrap().unwrap();
    let payload: serde_json::Value =
        serde_json::from_str(raw["payload"].as_str().unwrap()).unwrap();
    assert_eq!(payload["details"]["quantity"], "0.1234567890123456789");
    delete_operation(&mut f.c, &f.st, &op.id).unwrap();
    assert!(!adapter.read_row(&f.c, &op.id).unwrap().unwrap()["deleted_at"].is_null());
    assert_eq!(
        f.c.query_row(
            "SELECT COUNT(*) FROM \"fin:wealth_operations\" WHERE owner_user_id=?1",
            params!["owner"],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        1
    );
}

#[test]
fn dividend_after_sale_is_recordable_and_overflow_rolls_back() {
    let mut f = fixture();
    let op = draft(&f, OperationKind::Opening, "1", "10", 100);
    save_operation(&mut f.c, &f.st, None, op).unwrap();
    let op = draft(&f, OperationKind::Sell, "1", "15", 110);
    save_operation(&mut f.c, &f.st, None, op).unwrap();
    let mut op = draft(&f, OperationKind::Dividend, "0", "0", 120);
    op.amount = d("2");
    save_operation(&mut f.c, &f.st, None, op).unwrap();
    assert_eq!(holding(&f).quantity, Decimal::ZERO);
    assert_eq!(holding(&f).dividends, d("2"));
    let count = outbox::count(&f.c).unwrap();
    let mut op = draft(&f, OperationKind::Buy, "1", "2", 130);
    op.quantity = Decimal::MAX;
    assert!(save_operation(&mut f.c, &f.st, None, op).is_err());
    assert_eq!(outbox::count(&f.c).unwrap(), count);
    assert_eq!(holding(&f).quantity, Decimal::ZERO);
}

#[test]
fn backup_restore_roundtrips_source_operations_prices_and_replayed_wealth() {
    let mut f = fixture();
    let op = draft(&f, OperationKind::Opening, "10", "20", 100);
    save_operation(&mut f.c, &f.st, None, op).unwrap();
    let op = draft(&f, OperationKind::Sell, "2", "30", 110);
    save_operation(&mut f.c, &f.st, None, op).unwrap();
    record_price(&mut f.c, &f.st, &f.a, d("35"), 120, None).unwrap();
    let expected = snapshot(&f.c, "owner", 130, "USD").unwrap();
    let full = crate::tables::sync_registry();
    let mut registry = lifeos::sync::SyncRegistry::new();
    for table in [
        "fin:accounts",
        "fin:journal_entries",
        "fin:postings",
        "fin:categories",
        "fin:assets",
        "fin:prices",
    ] {
        registry.add(full.adapter(table).unwrap().clone());
    }
    register(&mut registry);
    let payload =
        lifeos::backup::export_payload(&registry, &f.c, None, "2026-11-11T00:00:00Z".into())
            .unwrap();
    let mut target = fixture();
    lifeos::backup::restore_payload(&registry, &mut target.c, &payload).unwrap();
    assert_eq!(snapshot(&target.c, "owner", 130, "USD").unwrap(), expected);
    assert_eq!(
        operations(&target.c, "owner", None).unwrap(),
        operations(&f.c, "owner", None).unwrap()
    );
    assert!(!cash_balances(&target.c, "owner", 130).unwrap().is_empty());
}

#[test]
fn incomplete_sync_metadata_or_posting_revisions_never_claim_complete_wealth() {
    let mut f = fixture();
    let op = draft(&f, OperationKind::Opening, "10", "20", 100);
    let op = save_operation(&mut f.c, &f.st, None, op).unwrap();
    record_price(&mut f.c, &f.st, &f.a, d("25"), 110, None).unwrap();
    assert_eq!(
        snapshot(&f.c, "owner", 120, "USD").unwrap().net_worth,
        Some(d("250"))
    );
    f.c.execute(
        "UPDATE \"fin:postings\" SET units='9' WHERE journal_entry_id=?1 AND unit=?2",
        params![op.id, f.a],
    )
    .unwrap();
    assert!(snapshot(&f.c, "owner", 120, "USD").is_err());
    assert!(cash_balances(&f.c, "owner", 120).is_err());
    f.c.execute(
        "UPDATE \"fin:postings\" SET units='10' WHERE journal_entry_id=?1 AND unit=?2",
        params![op.id, f.a],
    )
    .unwrap();
    assert!(snapshot(&f.c, "owner", 120, "USD").is_ok());
    f.c.execute(
        "UPDATE \"fin:wealth_operations\" SET deleted_at=1 WHERE id=?1",
        params![op.id],
    )
    .unwrap();
    assert!(snapshot(&f.c, "owner", 120, "USD").is_err());
}

#[test]
fn civil_today_ahead_of_utc_is_valid_without_admitting_future_quote_instants() {
    let utc_day = 86_400 * 20_000;
    let now = utc_day + 20 * 3_600; // UTC 20:00, already tomorrow in Shanghai.
    let local_day = utc_day + 86_400;
    assert!(super::store::fact_date_allowed_at(
        local_day, now, local_day
    ));
    assert!(super::store::quote_date_allowed_at(
        local_day,
        Some("manual"),
        now,
        local_day
    ));
    assert!(!super::store::quote_date_allowed_at(
        local_day,
        Some("provider"),
        now,
        local_day
    ));
    assert!(!super::store::fact_date_allowed_at(
        now + 60,
        now,
        local_day
    ));
    assert!(!super::store::fact_date_allowed_at(
        local_day + 86_400,
        now,
        local_day
    ));
    assert_eq!(
        super::read::valuation_as_of_at(now, now, local_day),
        local_day
    );
    assert_eq!(
        super::read::valuation_as_of_at(local_day, now, local_day),
        local_day
    );
    assert_eq!(
        super::read::valuation_as_of_at(utc_day - 1, now, local_day),
        utc_day - 1
    );
}

#[test]
fn manual_fx_roundtrips_backup_clears_later_rates_and_never_leaks_between_owners() {
    let mut f = fixture();
    let full = crate::tables::sync_registry();
    let mut registry = lifeos::sync::SyncRegistry::new();
    for table in [
        "fin:accounts",
        "fin:journal_entries",
        "fin:postings",
        "fin:categories",
        "fin:assets",
        "fin:prices",
    ] {
        registry.add(full.adapter(table).unwrap().clone());
    }
    register(&mut registry);
    let no_rates =
        lifeos::backup::export_payload(&registry, &f.c, None, "2026-11-11T00:00:00Z".into())
            .unwrap();
    crate::fx::upsert_rate(&f.c, "EUR", "CNY", 0, d("8"), Some("provider")).unwrap();
    record_manual_fx(&mut f.c, &f.st, "USD", "CNY", d("7"), 0).unwrap();
    let original =
        lifeos::backup::export_payload(&registry, &f.c, None, "2026-11-11T00:00:00Z".into())
            .unwrap();
    record_manual_fx(&mut f.c, &f.st, "USD", "CNY", d("9"), 0).unwrap();
    assert_eq!(crate::fx::rate_at(&f.c, "USD", "CNY", 100), Some(d("9")));
    lifeos::backup::restore_payload(&registry, &mut f.c, &original).unwrap();
    rebuild_manual_fx(&f.c, "owner").unwrap();
    assert_eq!(crate::fx::rate_at(&f.c, "USD", "CNY", 100), Some(d("7")));
    assert_eq!(crate::fx::rate_at(&f.c, "EUR", "CNY", 100), Some(d("8")));
    rebuild_manual_fx(&f.c, "other-owner").unwrap();
    assert_eq!(crate::fx::rate_at(&f.c, "USD", "CNY", 100), None);
    rebuild_manual_fx(&f.c, "owner").unwrap();
    assert_eq!(crate::fx::rate_at(&f.c, "USD", "CNY", 100), Some(d("7")));
    lifeos::backup::restore_payload(&registry, &mut f.c, &no_rates).unwrap();
    rebuild_manual_fx(&f.c, "owner").unwrap();
    assert_eq!(crate::fx::rate_at(&f.c, "USD", "CNY", 100), None);
    assert_eq!(crate::fx::rate_at(&f.c, "EUR", "CNY", 100), Some(d("8")));
}
