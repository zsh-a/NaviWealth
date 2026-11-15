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
    app.press("Recorded")?;
    app.wait_for("No recorded valuations yet. Record the current value to start a history.")?;
    app.press("Record current valuation")?;
    app.wait_for("Valuation recorded")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert_eq!(navi_finance::valuation::load(&c).unwrap().len(), 1);
    app.press("Record current valuation")?;
    assert_eq!(navi_finance::valuation::load(&c).unwrap().len(), 2);
    app.press("Recalculated")?;
    app.wait_for("History recalculated from current records and dated prices. Edits can change these values.")?;
    app.press("Recorded")?;
    app.wait_for("Observations captured at the time shown. Later edits do not change them. These are not end-of-day closing values.")?;
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
