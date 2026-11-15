use jiff::{Timestamp, civil::date};
use navi_finance::{
    catalog::{self, SecurityBinding},
    holdings::{self, Kind, Quote, Security, Trade, store},
    market::{self, MarketQuote},
    repository,
};
fn ts(s: &str) -> Timestamp {
    s.parse().unwrap()
}
fn fixture() -> (navi_storage::sqlite::Connection, Security) {
    let c = navi_storage::memory(&[
        repository::SCHEMA,
        repository::BALANCE_SCHEMA,
        store::SCHEMA,
        catalog::SCHEMA,
        market::SCHEMA,
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
fn quote(day: i8, price: i64) -> MarketQuote {
    MarketQuote {
        security: "etf".into(),
        symbol: "510300.SH".into(),
        currency: "CNY".into(),
        provider: "tencent".into(),
        price,
        observed_at: ts(&format!("2026-11-{day:02}T07:00:00Z")),
        fetched_at: ts(&format!("2026-11-{day:02}T07:01:00Z")),
        previous_close_only: false,
    }
}
#[test]
fn quote_identity_and_async_freshness_are_enforced_without_ledger_changes() {
    let (c, _) = fixture();
    let before = repository::transactions(&c).unwrap();
    let now = ts("2026-11-15T10:00:00Z");
    assert!(market::save(&c, &quote(12, 5_000_000), now).unwrap());
    assert!(!market::save(&c, &quote(11, 8_000_000), now).unwrap());
    for bad in [
        MarketQuote {
            symbol: "510300.SZ".into(),
            ..quote(13, 5_000_000)
        },
        MarketQuote {
            currency: "USD".into(),
            ..quote(13, 5_000_000)
        },
        quote(13, 0),
        MarketQuote {
            security: "missing".into(),
            ..quote(13, 5_000_000)
        },
    ] {
        assert!(market::save(&c, &bad, now).is_err());
    }
    assert_eq!(repository::transactions(&c).unwrap(), before);
    assert_eq!(market::load(&c).unwrap().len(), 1);
}
#[test]
fn dated_network_marks_and_manual_ties_preserve_historical_values() {
    let (c, s) = fixture();
    let now = ts("2026-11-15T10:00:00Z");
    market::save(&c, &quote(10, 5_000_000), now).unwrap();
    store::set_quote(
        &c,
        &Quote {
            security: s.id.clone(),
            day: date(2026, 11, 10),
            price: 6_000_000,
        },
        date(2026, 11, 15),
    )
    .unwrap();
    let book = market::valued_book(&c, store::load(&c).unwrap()).unwrap();
    let journal = repository::transactions(&c).unwrap();
    assert_eq!(
        book.overview(&journal, date(2026, 11, 9)).unwrap().net,
        40000
    );
    assert_eq!(
        book.position(&s, date(2026, 11, 10)).unwrap().value,
        Some(60000)
    );
    market::save(&c, &quote(12, 7_000_000), now).unwrap();
    let book = market::valued_book(&c, store::load(&c).unwrap()).unwrap();
    assert_eq!(
        book.position(&s, date(2026, 11, 11)).unwrap().value,
        Some(60000)
    );
    assert_eq!(
        book.position(&s, date(2026, 11, 12)).unwrap().value,
        Some(70000)
    );
    assert_eq!(holdings::store::load(&c).unwrap().quotes.len(), 1);
}

#[test]
fn increasing_quantity_cannot_commit_an_overflowing_network_valuation() {
    let (c, _) = fixture();
    let now = ts("2026-11-15T10:00:00Z");
    market::save(&c, &quote(12, 9_000_000_000_000_000), now).unwrap();
    let cash = navi_finance::account::Account::parse("资产:Cash").unwrap();
    repository::create_account(&c, &cash).unwrap();
    let before_journal = repository::transactions(&c).unwrap();
    let before_book = store::load(&c).unwrap();
    let buy = Trade {
        id: "huge-quantity".into(),
        security: "etf".into(),
        at: date(2026, 11, 13).at(12, 0, 0, 0),
        kind: Kind::Buy,
        quantity: 1_000_000_000_000_000_000,
        price: 1,
        amount: 0,
        fee: 0,
        cash: Some(cash),
    };
    assert!(matches!(
        store::add_trade(&c, None, &buy, date(2026, 11, 15)),
        Err(holdings::Error::Overflow)
    ));
    assert_eq!(store::load(&c).unwrap(), before_book);
    assert_eq!(repository::transactions(&c).unwrap(), before_journal);
    market::validate(&c).unwrap();
}

fn foreign_binding(hk: bool) -> SecurityBinding {
    SecurityBinding {
        security: "foreign".into(),
        market: if hk { "hk_stock" } else { "us_stock" }.into(),
        symbol: if hk { "00700" } else { "AAPL" }.into(),
        currency: if hk { "HKD" } else { "USD" }.into(),
    }
}
fn tencent_fixture(hk: bool) -> String {
    let mut fields = vec![""; 77];
    fields[0] = if hk { "100" } else { "200" };
    fields[2] = if hk { "00700" } else { "AAPL.OQ" };
    fields[3] = "386.600";
    fields[30] = if hk {
        "2026/11/13 16:08:22"
    } else {
        "2026-11-13 16:00:01"
    };
    fields[if hk { 75 } else { 35 }] = if hk { "HKD" } else { "USD" };
    format!(
        "v_{}=\"{}\";",
        if hk { "hk00700" } else { "usAAPL" },
        fields.join("~")
    )
}
#[test]
fn foreign_provider_checks_identity_currency_time_and_exchange_day() {
    let fetched = ts("2026-11-14T02:00:00Z");
    for hk in [true, false] {
        let b = foreign_binding(hk);
        let raw = tencent_fixture(hk);
        let q = market::parse_tencent(&b, &raw, fetched).unwrap();
        assert_eq!(q.price, 386600000);
        assert_eq!(q.day(), date(2026, 11, 13));
        assert_eq!(
            q.observed_at,
            ts(if hk {
                "2026-11-13T08:08:22Z"
            } else {
                "2026-11-13T21:00:01Z"
            })
        );
        for bad in [
            raw.replace(if hk { "hk00700" } else { "usAAPL" }, "usMSFT"),
            raw.replace(if hk { "HKD" } else { "USD" }, "CNY"),
            raw.replace("2026", "2027"),
            raw.replace("386.600", "NaN"),
        ] {
            assert!(market::parse_tencent(&b, &bad, fetched).is_err());
        }
    }
}
#[test]
fn fx_reference_rate_is_exact_dated_and_never_assumes_parity() {
    use navi_finance::currency::Currency;
    let today = date(2026, 11, 15);
    let raw = r#"[{"date":"2026-11-13","base":"HKD","quote":"CNY","rate":0.8503605}]"#;
    let r = market::parse_fx(raw, Currency::HKD, today).unwrap();
    assert_eq!(r.rate, 850361);
    assert_eq!(r.day, date(2026, 11, 13));
    assert_eq!(r.source, "frankfurter:ecb");
    for bad in [
        raw.replace("HKD", "USD"),
        raw.replace("CNY", "HKD"),
        raw.replace("2026-11-13", "2027-01-01"),
        raw.replace("0.8503605", "null"),
        raw.replace("0.8503605", "0"),
        "[]".into(),
    ] {
        assert!(market::parse_fx(&bad, Currency::HKD, today).is_err());
    }
}
