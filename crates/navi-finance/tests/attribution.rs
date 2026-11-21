//! Net-worth change attribution against hand-computed fixtures. Every
//! complete attribution's parts sum to the change exactly.
use jiff::civil::{Date, date};
use navi_finance::{
    account::{Account, AccountKind, defaults},
    attribution::{Attribution, Correction, Outcome, Part, attribute},
    currency::{Currency, FxRate, RATE_SCALE},
    holdings::{self, Book, Kind, Quote, Security, Trade},
    journal::{self, Entry, Posting, Source, Transaction},
};

const START: Date = date(2026, 10, 31);
const END: Date = date(2026, 11, 30);

fn entry(id: &str, day: Date, source: Source) -> Entry {
    Entry {
        id: id.into(),
        at: day.at(12, 0, 0, 0),
        payee: String::new(),
        note: String::new(),
        source,
    }
}

fn manual(id: &str, day: Date) -> Entry {
    entry(id, day, Source::Manual)
}

fn cash(name: &str, currency: Currency) -> Account {
    Account::new_in(AccountKind::Assets, name, currency).unwrap()
}

fn refund(id: &str, day: Date, own: &Account, category: &Account, amount: i64) -> Transaction {
    let t = Transaction {
        id: id.into(),
        at: day.at(12, 0, 0, 0),
        payee: String::new(),
        note: String::new(),
        source: Source::Manual,
        postings: vec![
            Posting {
                account: own.clone(),
                amount,
            },
            Posting {
                account: category.clone(),
                amount: -amount,
            },
        ],
    };
    t.validate().unwrap();
    t
}

fn rate(currency: Currency, day: Date, rate: f64) -> FxRate {
    FxRate {
        currency,
        day,
        rate: (rate * RATE_SCALE as f64).round() as i64,
        source: "test".into(),
    }
}

fn complete(book: &Book, entries: &[Transaction], rates: &[FxRate]) -> Attribution {
    match attribute(book, entries, rates, START, END).unwrap() {
        Outcome::Complete(a) => {
            let sum: i64 = a.parts().iter().map(|p| p.1).sum();
            assert_eq!(sum, a.change(), "the parts sum to the change");
            a
        }
        Outcome::Missing(missing) => panic!("missing rates for {missing:?}"),
    }
}

#[test]
fn cny_flows_split_into_income_spending_openings_and_adjustments() {
    let wallet = cash("Wallet", Currency::CNY);
    let card = Account::new(AccountKind::Liabilities, "Card").unwrap();
    let day = date(2026, 11, 10);
    let entries = vec![
        journal::opening(manual("open-wallet", date(2026, 10, 1)), &wallet, 100_000).unwrap(),
        // On the start day itself: before the period.
        journal::spend(
            manual("before", START),
            &wallet,
            &defaults::expense("餐饮"),
            5_000,
        )
        .unwrap(),
        journal::receive(
            manual("salary", day),
            &wallet,
            &defaults::income("工资"),
            500_000,
        )
        .unwrap(),
        journal::spend(
            manual("lunch", day),
            &card,
            &defaults::expense("餐饮"),
            31_250,
        )
        .unwrap(),
        // A refund reverses part of a purchase and reduces spending.
        refund("refund", day, &card, &defaults::expense("餐饮"), 1_250),
        journal::transfer(manual("repay", day), &wallet, &card, 30_000).unwrap(),
        journal::adjustment(manual("check", date(2026, 11, 20)), &wallet, -2_000).unwrap(),
        journal::opening(
            manual("open-bank", date(2026, 11, 12)),
            &cash("Bank", Currency::CNY),
            30_000,
        )
        .unwrap(),
        // After the end: outside.
        journal::spend(
            manual("later", date(2026, 12, 1)),
            &wallet,
            &defaults::other_expense(),
            999,
        )
        .unwrap(),
    ];
    let a = complete(&Book::default(), &entries, &[]);
    assert_eq!(a.start, 95_000);
    assert_eq!(a.end, 95_000 + 500_000 - 30_000 - 2_000 + 30_000);
    assert_eq!((a.income, a.spending), (500_000, -30_000));
    assert_eq!((a.openings, a.adjustments), (30_000, -2_000));
    assert_eq!((a.investment, a.exchange), (0, 0));
    assert!(a.holdings.is_empty());
    assert_eq!(
        a.corrections,
        vec![
            Correction {
                transaction: "open-bank".into(),
                day: date(2026, 11, 12),
                part: Part::Openings,
                amount: 30_000,
            },
            Correction {
                transaction: "check".into(),
                day: date(2026, 11, 20),
                part: Part::Adjustments,
                amount: -2_000,
            },
        ]
    );
}

fn trade(id: &str, day: Date, kind: Kind, quantity: i64, price: i64, amount: i64) -> Trade {
    Trade {
        id: id.into(),
        security: "etf".into(),
        at: day.at(10, 0, 0, 0),
        kind,
        quantity: quantity * holdings::SCALE,
        price: price * holdings::SCALE,
        amount,
        fee: 0,
        cash: (kind != Kind::Opening).then(|| cash("Broker", Currency::CNY)),
    }
}

fn quote(day: Date, price: i64) -> Quote {
    Quote {
        security: "etf".into(),
        day,
        price: price * holdings::SCALE,
    }
}

#[test]
fn holdings_count_unrealized_change_realized_gains_and_dividends_as_investment() {
    let etf = Security::new("etf", "ETF").unwrap();
    let trades = vec![
        // 100 shares at 10 before the period, marked at 12 on the start day.
        trade("open", date(2026, 10, 1), Kind::Opening, 100, 10, 0),
        // Sell half at 15: proceeds 750.00, released cost 500.00, gain 250.00.
        trade("sell", date(2026, 11, 15), Kind::Sell, 50, 15, 0),
        trade("dividend", date(2026, 11, 20), Kind::Dividend, 0, 0, 3_000),
    ];
    let book = Book {
        securities: vec![etf.clone()],
        trades: trades.clone(),
        quotes: vec![quote(START, 12), quote(date(2026, 11, 15), 15)],
    };
    let (_, generated) = holdings::replay(&etf, &trades, END).unwrap();
    let mut entries = vec![
        journal::opening(
            manual("broker", date(2026, 10, 1)),
            &cash("Broker", Currency::CNY),
            10_000,
        )
        .unwrap(),
    ];
    entries.extend(generated);
    let a = complete(&book, &entries, &[]);
    // Start: cash 100 + cost 1,000 + unrealized 200. End: cash 100 + 750 + 30,
    // cost 500 + unrealized 250.
    assert_eq!(a.start, 130_000);
    assert_eq!(a.end, 163_000);
    // Unrealized +50, realized +250, dividend +30.
    assert_eq!(a.investment, 33_000);
    assert_eq!(a.holdings, vec![("etf".into(), 33_000)]);
    assert_eq!(
        (a.income, a.spending, a.openings, a.adjustments, a.exchange),
        (0, 0, 0, 0, 0)
    );
}

#[test]
fn foreign_balances_revalue_into_the_exchange_part() {
    let usd = cash("Broker cash", Currency::USD);
    let wallet = cash("Wallet", Currency::CNY);
    let entries = vec![
        journal::opening(manual("cny", date(2026, 10, 1)), &wallet, 100_000).unwrap(),
        journal::opening(manual("usd", date(2026, 10, 1)), &usd, 10_000).unwrap(),
        // 700.00 CNY buys 100.00 USD, at the 7.0 reference rate.
        journal::exchange(
            manual("fx", date(2026, 11, 5)),
            &wallet,
            &usd,
            70_000,
            10_000,
        )
        .unwrap(),
        journal::spend(
            manual("usd-spend", date(2026, 11, 6)),
            &usd,
            &defaults::expense("购物").in_currency(Currency::USD),
            1_000,
        )
        .unwrap(),
    ];
    let rates = [
        rate(Currency::USD, date(2026, 10, 1), 7.0),
        rate(Currency::USD, date(2026, 11, 29), 7.2),
    ];
    let a = complete(&Book::default(), &entries, &rates);
    assert_eq!(a.start, 100_000 + 70_000);
    // CNY 300.00; USD 190.00 at 7.2.
    assert_eq!(a.end, 30_000 + 136_800);
    // Spending converts at the start's rate.
    assert_eq!(a.spending, -7_000);
    // 190.00 USD revalued by +0.2; the exchange itself was at the reference rate.
    assert_eq!(a.exchange, 3_800);
    assert_eq!(
        (a.income, a.investment, a.openings, a.adjustments),
        (0, 0, 0, 0)
    );
}

#[test]
fn an_exchange_away_from_the_reference_rate_lands_in_the_exchange_part() {
    let usd = cash("Broker cash", Currency::USD);
    let wallet = cash("Wallet", Currency::CNY);
    let entries = vec![
        journal::opening(manual("cny", date(2026, 10, 1)), &wallet, 100_000).unwrap(),
        // 720.00 CNY for 100.00 USD while the reference rate stays 7.0.
        journal::exchange(
            manual("fx", date(2026, 11, 5)),
            &wallet,
            &usd,
            72_000,
            10_000,
        )
        .unwrap(),
    ];
    let rates = [rate(Currency::USD, date(2026, 10, 1), 7.0)];
    let a = complete(&Book::default(), &entries, &rates);
    assert_eq!(a.change(), -2_000);
    assert_eq!(a.exchange, -2_000);
}

#[test]
fn a_currency_first_held_during_the_period_converts_at_the_end_rate() {
    let usd = cash("Broker cash", Currency::USD);
    let entries = vec![journal::opening(manual("usd", date(2026, 11, 20)), &usd, 10_000).unwrap()];
    let rates = [rate(Currency::USD, date(2026, 11, 20), 7.2)];
    let a = complete(&Book::default(), &entries, &rates);
    assert_eq!((a.start, a.end), (0, 72_000));
    assert_eq!((a.openings, a.exchange), (72_000, 0));
}

#[test]
fn missing_rates_make_the_attribution_incomplete_instead_of_partial() {
    let usd = cash("Broker cash", Currency::USD);
    let hkd = cash("HK cash", Currency::HKD);
    let wallet = cash("Wallet", Currency::CNY);
    let held = vec![
        journal::opening(manual("cny", date(2026, 10, 1)), &wallet, 100_000).unwrap(),
        journal::opening(manual("usd", date(2026, 10, 1)), &usd, 10_000).unwrap(),
    ];
    assert_eq!(
        attribute(&Book::default(), &held, &[], START, END).unwrap(),
        Outcome::Missing(vec![Currency::USD])
    );
    // Flows in a currency held at neither end still need a rate.
    let passing = vec![
        journal::opening(manual("cny", date(2026, 10, 1)), &wallet, 100_000).unwrap(),
        journal::opening(manual("hkd", date(2026, 11, 3)), &hkd, 10_000).unwrap(),
        journal::spend(
            manual("hkd-spend", date(2026, 11, 4)),
            &hkd,
            &defaults::other_expense().in_currency(Currency::HKD),
            10_000,
        )
        .unwrap(),
    ];
    assert_eq!(
        attribute(&Book::default(), &passing, &[], START, END).unwrap(),
        Outcome::Missing(vec![Currency::HKD])
    );
}

#[test]
fn an_unpriced_holding_stays_at_cost_and_an_empty_period_is_all_zero() {
    let etf = Security::new("etf", "ETF").unwrap();
    let trades = vec![trade("open", date(2026, 10, 1), Kind::Opening, 100, 10, 0)];
    let book = Book {
        securities: vec![etf.clone()],
        trades: trades.clone(),
        quotes: vec![],
    };
    let (_, generated) = holdings::replay(&etf, &trades, END).unwrap();
    let a = complete(&book, &generated, &[]);
    assert_eq!((a.start, a.end), (100_000, 100_000));
    assert!(a.parts().iter().all(|p| p.1 == 0));
    assert!(a.holdings.is_empty() && a.corrections.is_empty());
    assert!(attribute(&book, &generated, &[], END, START).is_err());
}
