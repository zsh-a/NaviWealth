use jiff::civil::date;
use navi_finance::{
    account::Account,
    assets,
    holdings::{self, Book, Error, Kind, Quote, Security, Trade, store},
    journal::{self, Entry, Source},
    repository,
};
fn db() -> navi_storage::sqlite::Connection {
    let c = navi_storage::memory(&[
        repository::SCHEMA,
        repository::BALANCE_SCHEMA,
        store::SCHEMA,
    ])
    .unwrap();
    repository::ensure_defaults(&c).unwrap();
    repository::create_account(&c, &cash()).unwrap();
    c
}
fn cash() -> Account {
    Account::parse("资产:券商现金").unwrap()
}
fn trade(id: &str, kind: Kind, q: &str, p: &str, fee: i64, day: i8) -> Trade {
    Trade {
        id: id.into(),
        security: "etf".into(),
        at: date(2026, 11, day).at(12, 0, 0, 0),
        kind,
        quantity: holdings::parse_units(q).unwrap(),
        price: holdings::parse_units(p).unwrap(),
        amount: 0,
        fee,
        cash: if kind == Kind::Opening {
            None
        } else {
            Some(cash())
        },
    }
}
#[test]
fn fractional_average_cost_partial_sale_dividend_and_full_close_are_exact() {
    let s = Security::new("etf", "指数ETF").unwrap();
    let mut trades = vec![
        trade("a", Kind::Buy, "10.5", "1.2345", 5, 1),
        trade("b", Kind::Buy, "4.5", "2", 0, 2),
        trade("c", Kind::Sell, "6", "2.1", 3, 3),
    ];
    let (p, _) = holdings::replay(&s, &trades, date(2026, 11, 3)).unwrap();
    assert_eq!(p.closed_at, None);
    assert_eq!((p.quantity, p.cost, p.realized), (9_000_000, 1321, 377));
    trades.push(Trade {
        amount: 250,
        quantity: 0,
        price: 0,
        ..trade("d", Kind::Dividend, "0", "0", 10, 4)
    });
    trades.push(trade("e", Kind::Sell, "9", "2.1", 2, 5));
    let (p, entries) = holdings::replay(&s, &trades, date(2026, 11, 5)).unwrap();
    assert_eq!(p.closed_at, Some(trades[4].at));
    trades.push(trade("f", Kind::Buy, "1", "2", 0, 6));
    trades.push(trade("g", Kind::Sell, "1", "2", 0, 8));
    assert_eq!(
        holdings::replay(&s, &trades, date(2026, 11, 7))
            .unwrap()
            .0
            .closed_at,
        None
    );
    assert_eq!(
        holdings::replay(&s, &trades, date(2026, 11, 8))
            .unwrap()
            .0
            .closed_at,
        Some(trades[6].at)
    );
    assert_eq!(
        (p.quantity, p.cost, p.realized, p.dividends),
        (0, 0, 944, 240)
    );
    assert!(entries.iter().all(|t| t.validate().is_ok()));
    assert!(holdings::parse_units("1.0000001").is_none());
    assert!(holdings::parse_units("1e2").is_none());
    assert_eq!(holdings::format_units(1_234_500), "1.2345");
}
#[test]
fn trades_and_cash_commit_together_and_unsafe_history_edits_roll_back() {
    let c = db();
    let s = Security::new("etf", "指数ETF").unwrap();
    let today = date(2026, 11, 15);
    c.execute_batch("CREATE TRIGGER fail_cost BEFORE INSERT ON finance_postings WHEN NEW.account LIKE '资产:持仓%' BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    assert!(
        store::add_trade(
            &c,
            Some(&s),
            &trade("buy", Kind::Buy, "100", "4", 5, 1),
            today
        )
        .is_err()
    );
    assert!(store::load(&c).unwrap().securities.is_empty());
    assert!(repository::transactions(&c).unwrap().is_empty());
    c.execute_batch("DROP TRIGGER fail_cost").unwrap();
    store::add_trade(
        &c,
        Some(&s),
        &trade("buy", Kind::Buy, "100", "4", 5, 1),
        today,
    )
    .unwrap();
    store::add_trade(&c, None, &trade("sell", Kind::Sell, "40", "5", 2, 3), today).unwrap();
    let before = repository::transactions(&c).unwrap();
    assert!(matches!(
        store::remove_trade(&c, "buy"),
        Err(Error::Oversell)
    ));
    assert!(matches!(
        store::add_trade(
            &c,
            None,
            &trade("early", Kind::Sell, "1", "5", 0, 1).with_early_time(),
            today
        ),
        Err(Error::Oversell)
    ));
    assert_eq!(repository::transactions(&c).unwrap(), before);
    assert!(repository::remove(&c, "trade:buy").is_err());
    let fake = journal::opening(
        Entry {
            id: "fake".into(),
            at: today.at(12, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        },
        &s.account,
        50,
    )
    .unwrap();
    assert!(repository::save(&c, &fake).is_err());
    repository::validate(&c).unwrap();
    let renamed = Account::parse("资产:证券现金").unwrap();
    let tx = c.unchecked_transaction().unwrap();
    repository::rename_account(&tx, &cash(), &renamed).unwrap();
    tx.commit().unwrap();
    repository::validate(&c).unwrap();
    assert!(
        store::load(&c)
            .unwrap()
            .trades
            .iter()
            .all(|t| t.cash.as_ref() == Some(&renamed))
    );
    store::remove_trade(&c, "sell").unwrap();
    assert_eq!(
        store::load(&c)
            .unwrap()
            .position(&s, today)
            .unwrap()
            .quantity,
        100_000_000
    );
}
trait Early {
    fn with_early_time(self) -> Self;
}
impl Early for Trade {
    fn with_early_time(mut self) -> Self {
        self.at = self.at.date().at(8, 0, 0, 0);
        self
    }
}
#[test]
fn dated_prices_replace_cost_in_net_worth_and_never_backfill_the_past() {
    let c = db();
    let s = Security::new("etf", "指数ETF").unwrap();
    let today = date(2026, 11, 15);
    store::add_trade(
        &c,
        Some(&s),
        &trade("opening", Kind::Opening, "100", "4", 0, 1),
        today,
    )
    .unwrap();
    let marked = store::set_quote(
        &c,
        &Quote {
            security: s.id.clone(),
            day: date(2026, 11, 10),
            price: 5_000_000,
        },
        today,
    )
    .unwrap();
    assert_eq!(
        marked
            .book
            .overview(&marked.entries, date(2026, 11, 9))
            .unwrap()
            .net,
        40000
    );
    assert_eq!(
        marked.book.overview(&marked.entries, today).unwrap().net,
        50000
    );
    assert_eq!(assets::snapshot(&marked.entries, today).net, 40000);
    assert_eq!(
        marked.book.position(&s, today).unwrap().unrealized(),
        Some(10000)
    );
    let unpriced = Book {
        quotes: vec![],
        ..marked.book
    };
    assert_eq!(
        unpriced.overview(&marked.entries, today).unwrap().net,
        40000
    );
    let zero = store::set_quote(
        &c,
        &Quote {
            security: s.id.clone(),
            day: today,
            price: 0,
        },
        today,
    )
    .unwrap();
    assert_eq!(zero.book.overview(&zero.entries, today).unwrap().net, 0);
    assert!(journal::spending(&zero.entries, date(2026, 11, 1), today).is_empty());
    repository::validate(&c).unwrap();
}

#[test]
fn foreign_trades_preserve_native_cost_and_reject_wrong_currency_atomically() {
    use navi_finance::currency::Currency;
    let c = db();
    let today = date(2026, 11, 15);
    for currency in [Currency::HKD, Currency::USD] {
        let native_cash = cash().in_currency(currency);
        repository::create_account(&c, &native_cash).unwrap();
        let s = Security::new_in(
            &format!("etf-{currency}"),
            &format!("ETF {currency}"),
            currency,
        )
        .unwrap();
        let make = |id: &str, kind, q, p, fee, day| Trade {
            id: format!("{currency}-{id}"),
            security: s.id.clone(),
            cash: Some(native_cash.clone()),
            ..trade(id, kind, q, p, fee, day)
        };
        let wrong = Trade {
            cash: Some(cash()),
            ..make("bad", Kind::Buy, "10", "20", 5, 1)
        };
        assert!(matches!(
            store::add_trade(&c, Some(&s), &wrong, today),
            Err(Error::Cash)
        ));
        assert!(!store::load(&c).unwrap().securities.contains(&s));
        store::add_trade(
            &c,
            Some(&s),
            &make("buy", Kind::Buy, "10", "20", 5, 1),
            today,
        )
        .unwrap();
        store::add_trade(&c, None, &make("sell", Kind::Sell, "5", "30", 2, 2), today).unwrap();
        let dividend = Trade {
            amount: 100,
            ..make("div", Kind::Dividend, "0", "0", 1, 3)
        };
        let saved = store::add_trade(&c, None, &dividend, today).unwrap();
        let p = saved.book.position(&s, today).unwrap();
        assert_eq!(
            (p.quantity, p.cost, p.realized, p.dividends),
            (5_000_000, 10002, 4995, 99)
        );
        for entry in saved.entries.iter().filter(|t| match &t.source {
            Source::Investment { trade_id } => trade_id.starts_with(currency.code()),
            _ => false,
        }) {
            assert!(
                entry
                    .postings
                    .iter()
                    .all(|p| p.account.currency() == currency)
            );
        }
        store::validate(&c).unwrap();
    }
}
#[test]
fn multi_currency_overview_converts_marks_and_exposes_dated_missing_rates() {
    use navi_finance::currency::{Currency, FxRate};
    let c = db();
    let day = date(2026, 11, 15);
    let s = Security::new_in("etf", "US ETF", Currency::USD).unwrap();
    let saved = store::add_trade(
        &c,
        Some(&s),
        &trade("opening", Kind::Opening, "10", "20", 0, 1),
        day,
    )
    .unwrap();
    let missing = saved
        .book
        .overview_with_rates(&saved.entries, day, &[])
        .unwrap();
    assert_eq!(missing.snapshot.net, 0);
    assert_eq!(missing.missing, vec![Currency::USD]);
    let rate = FxRate {
        currency: Currency::USD,
        day,
        rate: 7_000_000,
        source: "manual".into(),
    };
    let past = saved
        .book
        .overview_with_rates(
            &saved.entries,
            date(2026, 11, 14),
            std::slice::from_ref(&rate),
        )
        .unwrap();
    assert_eq!(past.missing, vec![Currency::USD]);
    let valued = store::set_quote(
        &c,
        &Quote {
            security: s.id.clone(),
            day,
            price: 30_000_000,
        },
        day,
    )
    .unwrap();
    let result = valued
        .book
        .overview_with_rates(&valued.entries, day, &[rate])
        .unwrap();
    assert_eq!(result.snapshot.net, 210000);
    assert!(result.missing.is_empty());
}

#[test]
fn daily_range_matches_individual_valuations_across_changes_gaps_and_overflow() {
    use navi_finance::currency::{Currency, FxRate};
    let day = |d| date(2026, 11, d);
    let security = Security::new_in("etf", "US ETF", Currency::USD).unwrap();
    let book = Book {
        securities: vec![security.clone()],
        trades: vec![trade("opening", Kind::Opening, "10", "20", 0, 3)],
        // Input order is authoritative for equal-date quotes (manual mark last).
        quotes: [(9, 8), (4, 22), (9, 10_000)]
            .map(|(d, price)| Quote {
                security: security.id.clone(),
                day: day(d),
                price: price * holdings::SCALE,
            })
            .to_vec(),
    };
    let (_, mut entries) = holdings::replay(&security, &book.trades, day(20)).unwrap();
    let cash_entry = journal::opening(
        Entry {
            id: "cash".into(),
            at: day(12).at(12, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        },
        &cash(),
        1000,
    )
    .unwrap();
    entries.insert(0, cash_entry);
    let rates = [
        (11, 6_000_000, "ecb"),
        (8, i64::MAX, "manual"),
        (5, 7_000_000, "manual"),
        (11, 7_000_001, "manual"),
        (5, -1, "invalid"),
    ]
    .map(|(d, rate, source)| FxRate {
        currency: Currency::USD,
        day: day(d),
        rate,
        source: source.into(),
    });
    // Cover both first-entry clipping and the running balance at a mid-history start.
    for start in [1, 6, 10, 12] {
        let series = book.valuation_range(&entries, &rates, day(start), day(15));
        assert_eq!(series.first().unwrap().0, day(start.max(3)));
        assert_eq!(series.last().unwrap().0, day(15));
        for (at, actual) in series {
            let expected = book.overview_with_rates(&entries, at, &rates);
            assert_eq!(expected.is_err(), (9..=10).contains(&at.day()));
            assert_eq!(
                actual.map_err(|e| e.to_string()),
                expected.map_err(|e| e.to_string()),
                "{at}"
            );
        }
    }
}
