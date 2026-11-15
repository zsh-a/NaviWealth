use finance_core::{
    catalog::{self, SecurityBinding},
    holdings::{Kind, Quote, Security, Trade, store},
    market::{self, MarketQuote},
    repository,
};
use jiff::{Timestamp, civil::date};
fn ts(s: &str) -> Timestamp {
    s.parse().unwrap()
}
fn fixture() -> (lifeos_core::sqlite::Connection, Security) {
    let c = lifeos_core::memory(&[
        repository::SCHEMA,
        repository::BALANCE_SCHEMA,
        store::SCHEMA,
        catalog::SCHEMA,
        market::SCHEMA,
        finance_core::currency::SCHEMA,
        finance_core::history::SCHEMA,
    ])
    .unwrap();
    repository::ensure_defaults(&c).unwrap();
    let s = Security::new("etf", "Index").unwrap();
    let t = Trade {
        id: "open".into(),
        security: s.id.clone(),
        at: date(2026, 11, 1).at(12, 0, 0, 0),
        kind: Kind::Opening,
        quantity: 100_000_000,
        price: 4_000_000,
        amount: 0,
        fee: 0,
        cash: None,
    };
    store::add_trade(&c, Some(&s), &t, date(2026, 11, 15)).unwrap();
    catalog::bind(
        &c,
        &SecurityBinding {
            security: s.id.clone(),
            market: "cn_a".into(),
            symbol: "510300".into(),
            currency: "CNY".into(),
        },
    )
    .unwrap();
    (c, s)
}

use finance_core::history::{self, DailyBar};
fn bar(day: i8, close: i64) -> DailyBar {
    DailyBar {
        market: "cn_a".into(),
        symbol: "510300.SH".into(),
        currency: "CNY".into(),
        provider: "eastmoney".into(),
        day: date(2026, 11, day),
        open: 4_000_000,
        high: close.max(4_000_000),
        low: close.min(4_000_000),
        close,
        volume: Some(12_000),
        fetched_at: ts("2026-11-15T01:00:00Z"),
    }
}
#[test]
fn backfill_revision_retries_stale_results_and_binding_archive() {
    let (c, s) = fixture();
    let b = catalog::bindings(&c).unwrap().remove(0);
    let now = ts("2026-11-15T04:00:00Z");
    assert_eq!(
        history::save_bars(&c, &b, &[bar(12, 5_000_000), bar(2, 4_100_000)], now).unwrap(),
        2
    );
    assert_eq!(
        history::save_bars(&c, &b, &[bar(12, 5_000_000)], now).unwrap(),
        0
    );
    let mut revised = bar(12, 6_000_000);
    // Fractional precision must sort by the instant, not RFC3339 text.
    revised.fetched_at = ts("2026-11-15T01:00:00.001Z");
    assert_eq!(history::save_bars(&c, &b, &[revised], now).unwrap(), 1);
    assert_eq!(
        history::save_bars(&c, &b, &[bar(12, 5_000_000)], now).unwrap(),
        0
    );
    assert_eq!(
        history::revisions(&c, &b, date(2026, 11, 1), date(2026, 11, 14))
            .unwrap()
            .len(),
        3
    );
    let book = market::valued_book(&c, store::load(&c).unwrap()).unwrap();
    assert_eq!(
        book.position(&s, date(2026, 11, 12)).unwrap().value,
        Some(60000)
    );
    catalog::bind(
        &c,
        &SecurityBinding {
            symbol: "510500".into(),
            ..b.clone()
        },
    )
    .unwrap();
    assert!(history::save_bars(&c, &b, &[bar(3, 4_100_000)], now).is_err());
    assert_eq!(
        history::bars(&c, &b, date(2026, 11, 1), date(2026, 11, 14))
            .unwrap()
            .len(),
        2
    );
    assert!(
        market::valued_book(&c, store::load(&c).unwrap())
            .unwrap()
            .quotes
            .is_empty()
    );
}
#[test]
fn invalid_batch_is_atomic_and_current_day_is_not_final() {
    let (c, _) = fixture();
    let b = catalog::bindings(&c).unwrap().remove(0);
    let now = ts("2026-11-15T04:00:00Z");
    assert!(history::save_bars(&c, &b, &[bar(2, 4_000_000), bar(15, 4_000_000)], now).is_err());
    assert!(
        history::revisions(&c, &b, date(2026, 11, 1), date(2026, 11, 15))
            .unwrap()
            .is_empty()
    );
}
#[test]
fn audit_is_transactional_manual_fx_and_rebinding_preserve_revisions() {
    use finance_core::currency::{self, Currency, FxRate};
    let (c, _) = fixture();
    let day = date(2026, 11, 12);
    for price in [4_000_000, 5_000_000] {
        store::set_quote(
            &c,
            &Quote {
                security: "etf".into(),
                day,
                price,
            },
            day,
        )
        .unwrap();
    }
    for rate in [7_000_000, 7_100_000] {
        currency::save_rate(
            &c,
            &FxRate {
                currency: Currency::USD,
                day,
                rate,
                source: "manual".into(),
            },
        )
        .unwrap();
    }
    store::set_quote(
        &c,
        &Quote {
            security: "etf".into(),
            day,
            price: 5_000_000,
        },
        day,
    )
    .unwrap();
    currency::save_rate(
        &c,
        &FxRate {
            currency: Currency::USD,
            day,
            rate: 7_100_000,
            source: "manual".into(),
        },
    )
    .unwrap();
    assert_eq!(history::audit(&c).unwrap().len(), 4);
    c.execute_batch("CREATE TRIGGER reject_audit BEFORE INSERT ON finance_price_audit BEGIN SELECT RAISE(ABORT,'audit unavailable'); END;").unwrap();
    assert!(
        store::set_quote(
            &c,
            &Quote {
                security: "etf".into(),
                day,
                price: 6_000_000
            },
            day
        )
        .is_err()
    );
    assert_eq!(store::load(&c).unwrap().quotes[0].price, 5_000_000);
    c.execute_batch("DROP TRIGGER reject_audit").unwrap();
    assert_eq!(history::audit(&c).unwrap().len(), 4);
    let q = MarketQuote {
        security: "etf".into(),
        symbol: "510300.SH".into(),
        currency: "CNY".into(),
        provider: "tencent".into(),
        price: 4_000_000,
        observed_at: ts("2026-11-12T07:00:00Z"),
        fetched_at: ts("2026-11-12T07:01:00Z"),
        previous_close_only: false,
    };
    market::save(&c, &q, ts("2026-11-15T04:00:00Z")).unwrap();
    let b = catalog::bindings(&c).unwrap().remove(0);
    catalog::bind(
        &c,
        &SecurityBinding {
            symbol: "510500".into(),
            ..b
        },
    )
    .unwrap();
    assert!(market::load(&c).unwrap().is_empty());
    assert!(
        history::audit(&c)
            .unwrap()
            .iter()
            .any(|r| r.kind == "market_quote_unbound" && r.body.contains("510300"))
    );
}

#[test]
fn restored_history_rejects_corrupt_audit_identity_and_received_time() {
    let (c, _) = fixture();
    let b = catalog::bindings(&c).unwrap().remove(0);
    let mut saved_bar = bar(12, 4_000_000);
    saved_bar.fetched_at = ts("2026-11-14T04:00:00Z");
    history::save_bars(&c, &b, &[saved_bar], Timestamp::now()).unwrap();
    store::set_quote(
        &c,
        &Quote {
            security: "etf".into(),
            day: date(2026, 11, 12),
            price: 5_000_000,
        },
        date(2026, 11, 15),
    )
    .unwrap();
    history::validate(&c).unwrap();
    for sql in [
        "UPDATE finance_price_audit SET item_key='other'",
        "UPDATE finance_price_audit SET kind='unknown'",
        "UPDATE finance_daily_bars SET symbol='510300.SZ'",
        "UPDATE finance_daily_bars SET currency='USD'",
        "UPDATE finance_price_audit SET body='{}'",
        "UPDATE finance_price_audit SET received_at='invalid'",
        "UPDATE finance_daily_bars SET received_at='2020-01-01T00:00:00Z'",
        "UPDATE finance_daily_bars SET fetched_at='2026-11-01T00:00:00Z'",
    ] {
        let tx = c.unchecked_transaction().unwrap();
        tx.execute_batch(sql).unwrap();
        assert!(history::validate(&tx).is_err(), "{sql}");
    }
    history::validate(&c).unwrap();
    let q = market::valued_book(&c, store::load(&c).unwrap())
        .unwrap()
        .quotes
        .into_iter()
        .last()
        .unwrap();
    assert!(history::effective_bar(&c, &q).unwrap().is_none());
}
