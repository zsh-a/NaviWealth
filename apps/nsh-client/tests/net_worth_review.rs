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
    app.wait_for("text:Missing exchange rates · USD")?;
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

#[test]
fn assets_explains_the_inspected_close_from_the_first_plotted_close() -> Result<(), String> {
    use nsh_core::geometry::{point, px};
    let cash = Account::parse("资产:Wallet").unwrap();
    let (mut app, _) = seeded(|db| {
        let day = today();
        for t in [
            journal::opening(
                entry("Baseline", day.plus_days(-2).0, Source::Manual),
                &cash,
                10000,
            ),
            journal::spend(
                entry("Bus", day.plus_days(-1).0, Source::Manual),
                &cash,
                &defaults::expense("交通"),
                250,
            ),
            journal::adjustment(
                entry("Correction", day.0, Source::BalanceCheck),
                &cash,
                -1000,
            ),
        ] {
            repository::save(db, &t.unwrap()).unwrap();
        }
    });
    app.press("label:Assets")?;
    app.press("label:/^Asset changes/")?;
    // A short, complete history uses its first recorded day, with the
    // explanation already open. The normal 30-day control covers these dates.
    assert!(!app.shows("text:Comparison"));
    let baseline = today().plus_days(-2).0.strftime("%b %-d, %Y");
    app.wait_for(&format!("text:/Since {baseline} −¥12.50$/"))?;
    app.wait_for("text:−¥12.50")?;
    app.wait_for("text:−¥2.50")?;
    assert!(
        !app.shows("text:Opening balances"),
        "the chart starts after the opening transaction"
    );
    app.press("label:/^Balance corrections, −¥10.00, Show details/")?;
    app.press("text:/^Correction · /")?;
    app.wait_for("text:Balance adjustment")?;
    app.press("text:Close")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.wait_for("text:/^Correction · /")?;
    app.drag_and_hold("id:trend-inspector", point(px(0.0), px(0.0)))?;
    app.drop_held()?;
    app.wait_for("text:¥97.50")?;
    assert!(!app.shows("text:−¥12.50"));
    assert!(!app.shows("text:Balance corrections"));
    app.press("Net worth snapshots")?;
    app.press("Historical estimates")?;
    app.wait_for("text:¥97.50")?;
    app.wait_for("text:Spending")?;
    app.press("7D")?;
    app.wait_for("text:−¥12.50")?;
    Ok(())
}

#[test]
fn assets_does_not_shift_the_baseline_past_a_missing_dated_rate() -> Result<(), String> {
    use navi_finance::currency::{self, FxRate};
    let usd = Account::parse("资产/USD:Broker").unwrap();
    let (mut app, _) = seeded(|db| {
        repository::save(
            db,
            &journal::opening(
                entry("Opening", today().plus_days(-4).0, Source::Manual),
                &usd,
                10_000,
            )
            .unwrap(),
        )
        .unwrap();
        currency::save_rates(
            db,
            &[FxRate {
                currency: Currency::USD,
                day: today().0,
                rate: 7_000_000,
                source: "manual".into(),
            }],
        )
        .unwrap();
    });
    app.press("label:Assets")?;
    app.press("label:/^Asset changes/")?;
    app.press("Change breakdown")?;
    app.wait_for("text:Missing exchange rates · USD")?;
    assert!(!app.shows("text:Exchange rates"));
    Ok(())
}

#[test]
fn disjoint_missing_currency_ranges_open_their_own_dates() -> Result<(), String> {
    let usd = Account::parse("资产/USD:Broker").unwrap();
    let (mut app, _dir) = seeded(|db| {
        for (id, days, amount) in [
            ("Early", -10, 2_000),
            ("Settled", -8, -2_000),
            ("First", -6, 10_000),
            ("Closed", -4, -10_000),
            ("Second", -2, 3_000),
        ] {
            let txn = journal::adjustment(
                entry(id, today().plus_days(days).0, Source::Manual),
                &usd,
                amount,
            )
            .unwrap();
            repository::save(db, &txn).unwrap();
        }
    });
    app.press("label:Assets")?;
    app.press("label:/^Asset changes/")?;
    app.press("Missing USD rate · 7 days")?;
    for (from, to) in [(-10, -9), (-6, -5), (-2, 0)] {
        let span = format!(
            "{} – {}",
            today().plus_days(from).0,
            today().plus_days(to).0
        );
        app.press(&format!("Missing USD rate · {span}"))?;
        app.wait_for("text:USD → CNY")?;
        app.wait_for(&format!("text:{span}"))?;
        app.press("label:Back")?;
    }
    Ok(())
}

#[test]
fn account_history_keeps_matched_checks_and_original_adjustments_after_backfills()
-> Result<(), String> {
    let own = Account::parse("负债:Card").unwrap();
    let (mut app, _) = seeded(|db| {
        let day = today().plus_days(-2).0;
        repository::create_account(db, &own).unwrap();
        repository::save(
            db,
            &journal::opening(
                entry("seed", day.yesterday().unwrap(), Source::Manual),
                &own,
                -10000,
            )
            .unwrap(),
        )
        .unwrap();
        for (id, hour, actual) in [("matched", 11, -10000), ("corrected", 12, -12500)] {
            repository::confirm_balance(
                db,
                &repository::BalanceCheck {
                    id: id.into(),
                    account: own.clone(),
                    day,
                    actual,
                    checked_at: today().0.at(hour, 0, 0, 0),
                },
                -10000,
            )
            .unwrap();
        }
        // A later entry about an older date must not advance the summary.
        repository::confirm_balance(
            db,
            &repository::BalanceCheck {
                id: "older-check".into(),
                account: own.clone(),
                day: today().plus_days(-4).0,
                actual: 0,
                checked_at: today().0.at(15, 0, 0, 0),
            },
            0,
        )
        .unwrap();
        repository::save(
            db,
            &journal::spend(
                entry("Backdated", day, Source::Manual),
                &own,
                &defaults::expense("餐饮"),
                2000,
            )
            .unwrap(),
        )
        .unwrap();
    });
    app.press("label:Assets")?;
    let effective = today().plus_days(-2).0;
    let checked = format!(
        "Balance checked through {}",
        effective.strftime(if effective.year() == today().0.year() {
            "%b %-d"
        } else {
            "%b %-d, %Y"
        })
    );
    app.press(&format!("label:Card, ¥145.00, {checked}"))?;
    app.press(&format!("text:{checked}"))?;
    app.wait_for("text:Matched at the time")?;
    app.wait_for("text:¥100.00")?;
    app.wait_for("text:¥125.00")?;
    app.press("label:/Balance adjustment \\+¥25.00/")?;
    app.wait_for("text:Balance adjustment")?;
    app.wait_for("label:Revoke balance entry")?;
    app.press("text:Close")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.wait_for("text:Matched at the time")?;
    Ok(())
}
