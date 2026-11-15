use finance_core::{
    catalog,
    currency::{self, Currency, FxRate},
    holdings::{self, Kind, Quote, Security, Trade, store},
    market, repository, valuation,
};
use jiff::{Timestamp, civil::date};
fn fixture() -> lifeos_core::sqlite::Connection {
    let c = lifeos_core::memory(&[
        repository::SCHEMA,
        repository::BALANCE_SCHEMA,
        store::SCHEMA,
        catalog::SCHEMA,
        market::SCHEMA,
        currency::SCHEMA,
        valuation::SCHEMA,
    ])
    .unwrap();
    repository::ensure_defaults(&c).unwrap();
    c
}
fn instant() -> Timestamp {
    "2026-11-15T08:30:00Z".parse().unwrap()
}
#[test]
fn revisions_are_immutable_after_trade_quote_and_fx_changes() {
    let c = fixture();
    let day = date(2026, 11, 15);
    let security = Security::new_in("a", "Apple", Currency::USD).unwrap();
    let trade = Trade {
        id: "opening".into(),
        security: "a".into(),
        at: day.at(8, 0, 0, 0),
        kind: Kind::Opening,
        quantity: 10 * holdings::SCALE,
        price: 20 * holdings::SCALE,
        amount: 0,
        fee: 0,
        cash: None,
    };
    store::add_trade(&c, Some(&security), &trade, day).unwrap();
    let first = valuation::record_current(&c, day, instant()).unwrap();
    assert_eq!(first.body.missing, vec![Currency::USD]);
    assert_eq!(first.body.holdings[0].quantity, 10 * holdings::SCALE);
    currency::save_rate(
        &c,
        &FxRate {
            currency: Currency::USD,
            day,
            rate: 7_000_000,
            source: "manual".into(),
        },
    )
    .unwrap();
    store::set_quote(
        &c,
        &Quote {
            security: "a".into(),
            day,
            price: 30 * holdings::SCALE,
        },
        day,
    )
    .unwrap();
    let second = valuation::record_current(&c, day, instant()).unwrap();
    assert_eq!(second.body.net, 210000);
    assert!(second.body.missing.is_empty());
    assert_eq!(second.body.holdings[0].source, "manual");
    store::remove_trade(&c, "opening").unwrap();
    currency::save_rate(
        &c,
        &FxRate {
            currency: Currency::USD,
            day,
            rate: 8_000_000,
            source: "manual".into(),
        },
    )
    .unwrap();
    let saved = valuation::load(&c).unwrap();
    assert_eq!(saved, vec![first, second.clone()]);
    assert_eq!(valuation::daily_latest(&saved), vec![second]);
}
#[test]
fn failed_insert_rolls_back_and_corrupt_totals_or_inputs_are_rejected() {
    let c = fixture();
    let day = date(2026, 11, 15);
    c.execute_batch("CREATE TRIGGER fail_snapshot BEFORE INSERT ON finance_valuation_snapshots BEGIN SELECT RAISE(ABORT,'disk full'); END;").unwrap();
    assert!(valuation::record_current(&c, day, instant()).is_err());
    assert!(valuation::load(&c).unwrap().is_empty());
    c.execute_batch("DROP TRIGGER fail_snapshot").unwrap();
    let saved = valuation::record_current(&c, day, instant()).unwrap();
    let mut bad = saved.body.clone();
    bad.net = 123;
    c.execute(
        "UPDATE finance_valuation_snapshots SET body=?1",
        [serde_json::to_string(&bad).unwrap()],
    )
    .unwrap();
    assert!(valuation::validate(&c).is_err());
    let mut bad = saved.body.clone();
    bad.ledger_fingerprint = "wrong".into();
    c.execute(
        "UPDATE finance_valuation_snapshots SET body=?1",
        [serde_json::to_string(&bad).unwrap()],
    )
    .unwrap();
    assert!(valuation::validate(&c).is_err());
}

#[test]
fn capture_rejects_fabricated_historical_day_and_allows_zero_manual_mark() {
    let c = fixture();
    let day = date(2026, 11, 15);
    assert!(valuation::record_current(&c, date(2026, 11, 1), instant()).is_err());
    let security = Security::new("zero", "Delisted").unwrap();
    let trade = Trade {
        id: "opening".into(),
        security: "zero".into(),
        at: day.at(8, 0, 0, 0),
        kind: Kind::Opening,
        quantity: holdings::SCALE,
        price: holdings::SCALE,
        amount: 0,
        fee: 0,
        cash: None,
    };
    store::add_trade(&c, Some(&security), &trade, day).unwrap();
    store::set_quote(
        &c,
        &Quote {
            security: "zero".into(),
            day,
            price: 0,
        },
        day,
    )
    .unwrap();
    let saved = valuation::record_current(&c, day, instant()).unwrap();
    assert_eq!(saved.body.net, 0);
    assert_eq!(saved.body.holdings[0].price, Some(0));
    valuation::validate(&c).unwrap();
}
