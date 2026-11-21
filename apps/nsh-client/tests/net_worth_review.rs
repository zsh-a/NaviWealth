//! Review's net-worth change: parts, drill-down, missing rates and the
//! ledger-only headline.
mod common;

use common::*;
use navi_finance::{
    account::{Account, AccountKind, defaults},
    currency::Currency,
    holdings::{self, Kind, Quote, Security, Trade, store},
    journal::{self, Entry, Source},
    repository,
};

fn entry(id: &str, day: jiff::civil::Date, source: Source) -> Entry {
    Entry {
        id: id.into(),
        at: day.at(12, 0, 0, 0),
        payee: id.into(),
        note: String::new(),
        source,
    }
}

/// Starts once to create the database, lets `seed` write it, starts again.
fn seeded(seed: impl FnOnce(&rusqlite::Connection)) -> (Headless, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), vec![], None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    seed(&db);
    drop(db);
    let (app, _) = start_in(Some(dir.path()), vec![], None);
    (app, dir)
}

fn long_ago() -> jiff::civil::Date {
    today().plus_days(-40).0
}

#[test]
fn recorded_parts_explain_the_change_and_corrections_open_their_entry() -> Result<(), String> {
    let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
    let (mut app, _dir) = seeded(|db| {
        let day = today().0;
        for t in [
            journal::opening(entry("Opening", long_ago(), Source::Manual), &cash, 100_000),
            journal::receive(
                entry("Salary", day, Source::Manual),
                &cash,
                &defaults::income("工资"),
                500_000,
            ),
            journal::spend(
                entry("Lunch", day, Source::Manual),
                &cash,
                &defaults::expense("餐饮"),
                3_150,
            ),
            journal::adjustment(entry("Check", day, Source::BalanceCheck), &cash, -2_000),
        ] {
            repository::save(db, &t.unwrap()).unwrap();
        }
    });
    app.press("label:Review")?;
    app.wait_for("Net worth change")?;
    app.wait_for("text:+¥4,948.50")?;
    app.wait_for("text:/ close ¥1,000.00 → ¥5,948.50$/")?;
    // The only change of a ledger-only period leads the page.
    app.wait_for("text:Net worth rose ¥4,948.50 this period.")?;
    for part in ["Income", "+¥5,000.00", "Spending", "−¥31.50"] {
        app.wait_for(&format!("text:{part}"))?;
    }
    // Nothing moved for investments, openings or rates: no zero rows.
    assert!(!app.shows("text:Investments"));
    assert!(!app.shows("text:Exchange rates"));
    assert!(!app.shows("text:Opening balances"));
    app.press("label:/^Balance corrections, −¥20.00, Show details/")?;
    app.wait_for("label:/^Balance corrections, −¥20.00, Hide details/")?;
    app.press("text:/^Check · /")?;
    app.wait_for("text:/Balance adjustment/")?;
    Ok(())
}

#[test]
fn investments_open_per_holding() -> Result<(), String> {
    let (mut app, _dir) = seeded(|db| {
        let etf = Security::new("etf", "Test ETF").unwrap();
        let opening = Trade {
            id: "open".into(),
            security: "etf".into(),
            at: long_ago().at(10, 0, 0, 0),
            kind: Kind::Opening,
            quantity: 100 * holdings::SCALE,
            price: 10 * holdings::SCALE,
            amount: 0,
            fee: 0,
            cash: None,
        };
        store::add_trade(db, Some(&etf), &opening, today().0).unwrap();
        for (day, price) in [(long_ago(), 10), (today().0, 12)] {
            let quote = Quote {
                security: "etf".into(),
                day,
                price: price * holdings::SCALE,
            };
            store::set_quote(db, &quote, today().0).unwrap();
        }
    });
    app.press("label:Review")?;
    app.wait_for("text:+¥200.00")?;
    app.press("label:/^Investments, \\+¥200.00, Show details/")?;
    app.wait_for("text:Test ETF")?;
    Ok(())
}

#[test]
fn a_missing_rate_is_said_instead_of_a_partial_split() -> Result<(), String> {
    let usd = Account::new_in(AccountKind::Assets, "Broker cash", Currency::USD).unwrap();
    let (mut app, _dir) = seeded(|db| {
        let t = journal::opening(entry("USD", long_ago(), Source::Manual), &usd, 10_000);
        repository::save(db, &t.unwrap()).unwrap();
    });
    app.press("label:Review")?;
    app.wait_for("text:Missing USD rates — the change can't be fully explained yet.")?;
    assert!(!app.shows("text:/^Net worth (rose|fell)/"));
    assert!(!app.shows("text:/close ¥/"));
    Ok(())
}

#[test]
fn health_only_review_has_no_net_worth() -> Result<(), String> {
    let (mut app, _) = start(pasta_today(), None);
    app.press("label:Review")?;
    app.wait_for("text:300")?;
    assert!(!app.shows("Net worth change"));
    Ok(())
}
