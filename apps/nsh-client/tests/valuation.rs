//! Recalculated history and immutable observed revisions remain separate.
mod common;
use common::*;
#[test]
fn recorded_mode_starts_empty_and_manual_capture_appends_revisions() -> Result<(), String> {
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
    app.wait_for("No recorded valuations yet. Record the current value to start a history.")?;
    app.press("Record current valuation")?;
    app.wait_for("Valuation recorded")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert_eq!(navi_finance::valuation::load(&c).unwrap().len(), 1);
    app.press("Record current valuation")?;
    assert_eq!(navi_finance::valuation::load(&c).unwrap().len(), 2);
    app.press("Historical estimates")?;
    app.wait_for("History recalculated from current records and dated prices. Edits can change these values.")?;
    app.press("Net worth snapshots")?;
    app.wait_for("Observations captured at the time shown. Later edits do not change them. These are not end-of-day closing values.")?;
    // Reopen with more than one page, including identical capture instants.
    app.press("Historical estimates")?;
    for _ in 0..29 {
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
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
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
    app.press("label:Assets")?;
    app.press("text:Manage")?;
    app.press("Price history")?;
    app.wait_for("510300.SH · 2026-11-12")?;
    app.press("510300.SH · 2026-11-12")?;
    app.wait_for("Open 4 · High 6 · Low 4 · Close 6")?;
    app.wait_for("Open 4 · High 5 · Low 4 · Close 5")?;
    app.press("Changes")?;
    app.wait_for("USD → CNY")?;
    app.press("USD → CNY")?;
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
    app.wait_for("text:/¥7.00 – ¥7.00/")?;
    Ok(())
}
