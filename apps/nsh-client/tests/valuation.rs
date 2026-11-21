//! Recalculated history and immutable observed revisions remain separate.
mod common;
use common::*;
#[test]
fn first_balance_creates_one_daily_snapshot_and_history_pages_older_revisions() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("text:Add account")?;
    app.type_text("label:Account name", "Cash")?;
    app.press("Create account")?;
    app.press("Check balance")?;
    app.type_text("label:Actual balance", "100.00")?;
    app.press("Review difference")?;
    app.press("Confirm balance")?;
    app.press("label:Back")?;
    app.press("label:Asset changes")?;
    app.wait_for("History recalculated from current records and dated prices. Edits can change these values.")?;
    app.press("Net worth snapshots")?;
    app.wait_for("text:/^Recorded at /")?;
    assert!(!app.shows("Record current valuation"));
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    app.press("Historical estimates")?;
    app.press("Net worth snapshots")?;
    assert_eq!(navi_finance::valuation::load(&c).unwrap().len(), 1);
    // Reopen with more than one page, including identical capture instants.
    app.press("Historical estimates")?;
    for _ in 0..30 {
        navi_finance::valuation::record_current(&c, today().0, jiff::Timestamp::now()).unwrap();
    }
    app.press("Net worth snapshots")?;
    app.press("Show more")?;
    app.wait_for_gone("Show more", GONE)?;
    app.press("text:/^Recorded at / >> nth=30")?;
    app.wait_for("Assets ¥100.00 · Debt ¥0.00")?;
    Ok(())
}

#[test]
fn price_history_exposes_daily_revisions_and_fx_audit() -> Result<(), String> {
    use navi_finance::{
        catalog::{self, SecurityBinding},
        currency::{self, Currency, FxRate},
        history::{self, DailyBar},
        holdings::{self, Kind, Security, Trade, store},
    };
    let dir = tempfile::tempdir().unwrap();
    let (app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let day = jiff::civil::date(2026, 11, 12);
    let now = jiff::Timestamp::now();
    let security = Security::new("index", "Index").unwrap();
    let trade = Trade {
        id: "open".into(),
        security: security.id.clone(),
        at: day.at(8, 0, 0, 0),
        kind: Kind::Opening,
        quantity: holdings::SCALE,
        price: 4 * holdings::SCALE,
        amount: 0,
        fee: 0,
        cash: None,
    };
    store::add_trade(&c, Some(&security), &trade, today().0).unwrap();
    let binding = SecurityBinding {
        security: security.id.clone(),
        market: "cn_a".into(),
        symbol: "510300".into(),
        currency: "CNY".into(),
    };
    catalog::bind(&c, &binding).unwrap();
    for (index, close) in [5_000_000, 6_000_000].into_iter().enumerate() {
        let fetched_at = now
            .checked_sub(jiff::Span::new().seconds(2 - index as i64))
            .unwrap();
        history::save_bars(
            &c,
            &binding,
            &[DailyBar {
                market: "cn_a".into(),
                symbol: "510300.SH".into(),
                currency: "CNY".into(),
                provider: "tencent:raw".into(),
                day,
                open: 4_000_000,
                high: close,
                low: 4_000_000,
                close,
                volume: Some(1000),
                fetched_at,
            }],
            now,
        )
        .unwrap();
    }
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
    let older = day.checked_sub(jiff::Span::new().days(12)).unwrap();
    currency::save_rates(
        &c,
        &[
            FxRate {
                currency: Currency::USD,
                day: older,
                rate: 7_200_015,
                source: "frankfurter:ecb".into(),
            },
            FxRate {
                currency: Currency::HKD,
                day,
                rate: 912_345,
                source: "frankfurter:ecb".into(),
            },
        ],
    )
    .unwrap();
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.press("label:Assets")?;
    app.wait_for("label:/^Index, ¥6.00, Daily close/")?;
    app.press("label:/^Index, ¥6.00, Daily close/")?;
    app.wait_for("id:trend-value")?;
    app.wait_for("text:¥6")?;
    app.press("label:Back")?;
    app.press("label:Manage")?;
    app.press("Prices & rates")?;
    app.wait_for("text:7.1")?;
    app.drag_and_hold(
        "id:trend-inspector",
        nsh_core::geometry::point(nsh_core::geometry::px(-140.0), nsh_core::geometry::px(0.0)),
    )?;
    app.wait_for("text:7.200015")?;
    app.drop_held()?;
    app.press("7D")?;
    app.wait_for("text:7.1")?;
    assert!(!app.shows("text:/7.200015/"));
    app.press("HKD → CNY")?;
    app.wait_for("text:0.912345")?;
    app.press("Daily closes")?;
    app.wait_for("510300.SH · 2026-11-12")?;
    app.press("510300.SH · 2026-11-12")?;
    app.wait_for("Open 4 · High 6 · Low 4 · Close 6")?;
    app.wait_for("Open 4 · High 5 · Low 4 · Close 5")?;
    app.press("Changes")?;
    app.wait_for("USD → CNY")?;
    app.press("text:USD → CNY >> nth=1")?;
    app.wait_for("7.1")?;
    Ok(())
}

#[test]
fn missing_historical_fx_keeps_known_values_and_cost_details_accessible() -> Result<(), String> {
    use navi_finance::{
        currency::{self, Currency, FxRate},
        holdings::{self, Kind, Security, Trade, store},
    };
    let dir = tempfile::tempdir().unwrap();
    let (app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let security = Security::new_in("fund", "USD fund", Currency::USD).unwrap();
    let trade = Trade {
        id: "opening".into(),
        security: security.id.clone(),
        at: today().plus_days(-3).0.at(8, 0, 0, 0),
        kind: Kind::Opening,
        quantity: holdings::SCALE,
        price: holdings::SCALE,
        amount: 0,
        fee: 0,
        cash: None,
    };
    store::add_trade(&c, Some(&security), &trade, today().0).unwrap();
    currency::save_rate(
        &c,
        &FxRate {
            currency: Currency::USD,
            day: today().plus_days(-1).0,
            rate: 7 * holdings::SCALE,
            source: "manual".into(),
        },
    )
    .unwrap();
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.press("label:Assets")?;
    app.press("Holdings valued at cost: 1")?;
    app.press("id:cost-holdings >> text:USD fund")?;
    app.wait_for("Record trade")?;
    app.press("label:Back")?;
    app.press("label:Asset changes")?;
    app.wait_for("Days missing USD rates: 2")?;
    app.wait_for("text:¥7.00")?;
    Ok(())
}

#[test]
fn trend_compares_exactly_thirty_days_and_drills_into_the_same_start() -> Result<(), String> {
    use navi_finance::{
        account::Account,
        journal::{self, Entry, Source},
        repository,
    };
    let dir = tempfile::tempdir().unwrap();
    let (app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let cash = Account::parse("资产:Cash").unwrap();
    repository::create_account(&db, &cash).unwrap();
    let opening = |id: &str, days: i32, amount: i64| {
        let entry = Entry {
            id: id.into(),
            at: today().plus_days(days).0.at(12, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        };
        repository::save(&db, &journal::opening(entry, &cash, amount).unwrap()).unwrap();
    };
    opening("recent", -29, 9500);
    let restart = || {
        start_in(
            Some(dir.path()),
            storage.entries().into_iter().collect(),
            None,
        )
        .0
    };
    let mut app = restart();
    app.press("label:Assets")?;
    assert!(!app.shows("text:/^Since 30 days ago/"));
    drop(app);
    opening("baseline", -30, 10000);
    let mut app = restart();
    app.press("label:Assets")?;
    app.wait_for("Since 30 days ago +¥95.00")?;
    app.press("label:/^Asset changes, Since 30 days ago/")?;
    app.wait_for("text:/¥100.00 – ¥195.00/")?;
    Ok(())
}
