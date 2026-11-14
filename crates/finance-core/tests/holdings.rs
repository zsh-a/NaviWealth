use finance_core::{
    account::Account,
    assets,
    holdings::{self, Book, Error, Kind, Quote, Security, Trade, store},
    journal::{self, Entry, Source},
    repository,
};
use jiff::civil::date;
fn db() -> lifeos_core::sqlite::Connection {
    let c = lifeos_core::memory(&[
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
    assert_eq!((p.quantity, p.cost, p.realized), (9_000_000, 1321, 377));
    trades.push(Trade {
        amount: 250,
        quantity: 0,
        price: 0,
        ..trade("d", Kind::Dividend, "0", "0", 10, 4)
    });
    trades.push(trade("e", Kind::Sell, "9", "2.1", 2, 5));
    let (p, entries) = holdings::replay(&s, &trades, date(2026, 11, 5)).unwrap();
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
