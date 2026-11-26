//! Recalculated history and immutable observed revisions remain separate.
mod common;
use common::*;
use jiff::civil::{Date, date};

fn noon(day: Date) -> jiff::Timestamp {
    day.at(12, 0, 0, 0)
        .to_zoned_datetime(jiff::tz::TimeZone::UTC)
        .unwrap()
        .timestamp()
}

fn start_on(dir: &Path, day: Date) -> Headless {
    let now = std::time::SystemTime::UNIX_EPOCH + Duration::from_secs(noon(day).as_second() as u64);
    start_in_with_clock(Some(dir), vec![], None, nsh_core::time::Clock::manual(now)).0
}

fn opening(
    db: &rusqlite::Connection,
    account: &navi_finance::account::Account,
    day: Date,
    amount: i64,
) {
    use navi_finance::{
        journal::{self, Entry, Source},
        repository,
    };
    let entry = Entry {
        id: day.to_string(),
        at: day.at(9, 0, 0, 0),
        payee: String::new(),
        note: String::new(),
        source: Source::Manual,
    };
    repository::save(db, &journal::opening(entry, account, amount).unwrap()).unwrap();
}

fn more_period(app: &mut Headless, option: &str) -> Result<(), String> {
    app.press("id:trend-period-more")?;
    app.press(&format!("role:option[{option}]"))
}

#[test]
fn ytd_includes_january_first_with_the_previous_close_and_filters_real_snapshots()
-> Result<(), String> {
    use navi_finance::{account::Account, valuation};
    let january = date(2026, 1, 1);
    let march = date(2026, 3, 16);
    let prior = date(2024, 12, 15);
    let dir = tempfile::tempdir().unwrap();
    drop(start_on(dir.path(), january));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let cash = Account::parse("资产:Cash").unwrap();
    for (day, amount) in [
        (prior, 10_000),
        (date(2025, 12, 30), 1_000),
        (date(2025, 12, 31), 2_000),
        (january, 300),
        (march, 700),
    ] {
        opening(&db, &cash, day, amount);
        if day != date(2025, 12, 31) {
            valuation::record_current(&db, day, noon(day)).unwrap();
        }
    }
    // The estimate includes January 1's ¥3, even on the first day of the year.
    let mut app = start_on(dir.path(), january);
    app.press("label:Assets")?;
    app.press("label:/^Asset changes/")?;
    more_period(&mut app, "YTD")?;
    app.wait_for("text:/Since Dec 31, 2025 \\+¥3.00$/")?;
    app.wait_for("text:Dec 31, 2025 – Jan 1, 2026")?;
    drop(app);

    let mut app = start_on(dir.path(), march);
    app.press("label:Assets")?;
    app.press("label:/^Asset changes/")?;
    more_period(&mut app, "YTD")?;
    app.wait_for("text:/Since Dec 31, 2025 \\+¥10.00$/")?;
    app.wait_for("text:Dec 31, 2025 – Mar 16, 2026")?;
    app.press("Net worth snapshots")?;
    more_period(&mut app, "YTD")?;
    // No snapshot was taken on December 31. Start the recorded change on
    // January 1; both the list and the chart exclude the actual Dec 30 capture.
    app.wait_for("text:/Since Jan 1, 2026 \\+¥7.00$/")?;
    app.wait_for("text:/^Recorded at 2026-01-01/")?;
    assert!(!app.shows("text:/^Recorded at 2025-12-3/"));
    more_period(&mut app, "1Y")?;
    app.wait_for("text:/^Recorded at 2025-12-30/")?;
    assert!(!app.shows("text:/^Recorded at 2024/"));
    more_period(&mut app, "All")?;
    app.wait_for("text:/^Recorded at 2024-12-15/")?;
    app.press("Historical estimates")?;
    app.wait_for("text:Dec 31, 2025 – Mar 16, 2026")?;
    Ok(())
}

#[test]
fn first_year_uses_the_first_ledger_day_even_when_the_value_is_unchanged() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let march = date(2026, 3, 16);
    drop(start_on(dir.path(), march));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let wallet = navi_finance::account::Account::parse("资产:Wallet").unwrap();
    opening(&db, &wallet, date(2026, 3, 12), 10_000);
    let mut app = start_on(dir.path(), march);
    app.press("label:Assets")?;
    app.press("label:/^Asset changes/")?;
    more_period(&mut app, "YTD")?;
    app.wait_for("text:/Since Mar 12, 2026 ¥0.00$/")?;
    app.press("Change breakdown")?;
    app.wait_for("text:Mar 12 – Mar 16")?;
    app.wait_for("Net worth did not change in this period.")?;
    Ok(())
}

#[test]
fn ytd_uses_the_first_complete_date_and_keeps_earlier_fx_gaps_inspectable() -> Result<(), String> {
    use navi_finance::{
        account::Account,
        currency::{self, Currency, FxRate},
    };
    let dir = tempfile::tempdir().unwrap();
    let march = date(2026, 3, 16);
    drop(start_on(dir.path(), march));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let usd = Account::parse("资产/USD:Broker cash").unwrap();
    let first_rate = date(2026, 3, 12);
    opening(&db, &usd, date(2025, 12, 20), 10_000);
    opening(&db, &usd, march, 200);
    currency::save_rate(
        &db,
        &FxRate {
            currency: Currency::USD,
            day: first_rate,
            rate: 7_000_000,
            source: "manual".into(),
        },
    )
    .unwrap();
    let mut app = start_on(dir.path(), march);
    app.press("label:Assets")?;
    app.press("label:/^Asset changes/")?;
    more_period(&mut app, "YTD")?;
    app.wait_for("text:/Since Mar 12, 2026 \\+¥14.00$/")?;
    app.wait_for("text:Mar 12 – Mar 16")?;
    app.wait_for("text:+¥14.00")?;
    let gap = "Missing USD rate · 2025-12-31 – 2026-03-11";
    app.press(gap)?;
    app.wait_for("2025-12-31 – 2026-03-11")?;
    app.press("label:Back")?;
    app.wait_for("text:Mar 12 – Mar 16")?;
    app.drag_and_hold(
        "id:trend-inspector",
        nsh_core::geometry::point(nsh_core::geometry::px(-160.0), nsh_core::geometry::px(0.0)),
        Default::default(),
    )?;
    app.drop_held()?;
    app.wait_for("text:—")?;
    app.wait_for("text:/Valuation unavailable$/")?;
    assert!(!app.shows("text:+¥14.00"));
    // The retained disclosure keeps the inspected date across closing and
    // reopening, then updates from the gap text back to a complete breakdown.
    app.press("Change breakdown")?;
    assert!(!app.shows("text:/Valuation unavailable$/"));
    app.press("Change breakdown")?;
    app.wait_for("text:/Valuation unavailable$/")?;
    app.drag_and_hold(
        "id:trend-inspector",
        nsh_core::geometry::point(nsh_core::geometry::px(160.0), nsh_core::geometry::px(0.0)),
        Default::default(),
    )?;
    app.drop_held()?;
    app.wait_for("text:Mar 12 – Mar 16")?;
    app.wait_for("text:+¥14.00")?;
    assert!(!app.shows("text:/Valuation unavailable$/"));
    Ok(())
}

#[test]
fn first_balance_creates_one_daily_snapshot_and_history_pages_older_revisions() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("text:Add account")?;
    app.type_text("label:Account name", "Cash")?;
    app.press("Create account")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.press("Set opening balance")?;
    app.type_text("label:Actual balance", "100.00")?;
    app.press("Review difference")?;
    app.press("Confirm balance")?;
    app.press("label:Back")?;
    app.press("label:/^Asset changes/")?;
    let basis = "Calculated from the ledger, dated prices and exchange rates.";
    assert!(!app.shows(basis));
    app.press("Valuation basis")?;
    app.wait_for(basis)?;
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
    let day = today().plus_days(-2).0;
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
    app.wait_for("label:/^Index, ¥6.00, Tencent unadjusted close/")?;
    app.press("label:/^Index, ¥6.00, Tencent unadjusted close/")?;
    app.wait_for("text:¥6")?;
    assert!(!app.shows("id:trend-inspector"));
    app.press("Price history")?;
    app.wait_for(&format!("510300.SH · {day}"))?;
    app.press("label:Back")?;
    app.press("label:Back")?;
    app.press("label:Manage")?;
    app.press("Prices & rates")?;
    app.wait_for("text:7.1")?;
    app.drag_and_hold(
        "id:trend-inspector",
        nsh_core::geometry::point(nsh_core::geometry::px(-140.0), nsh_core::geometry::px(0.0)),
        Default::default(),
    )?;
    app.wait_for("text:7.200015")?;
    app.drop_held()?;
    app.press("7D")?;
    app.wait_for("text:7.1")?;
    assert!(!app.shows("text:/7.200015/"));
    more_period(&mut app, "All")?;
    app.wait_for("id:trend-period-more >> text:All")?;
    app.wait_for("text:/7.200015/")?;
    app.press("HKD → CNY")?;
    app.wait_for("text:0.912345")?;
    app.wait_for("id:trend-period-more >> text:All")?;
    app.press("Daily closes")?;
    app.wait_for(&format!("510300.SH · {day}"))?;
    app.press(&format!("510300.SH · {day}"))?;
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
        at: today().plus_days(-9).0.at(8, 0, 0, 0),
        kind: Kind::Opening,
        quantity: holdings::SCALE,
        price: holdings::SCALE,
        amount: 0,
        fee: 0,
        cash: None,
    };
    store::add_trade(&c, Some(&security), &trade, today().0).unwrap();
    let missing_day = trade.at.date();
    let observed_at = trade
        .at
        .to_zoned_datetime(jiff::tz::TimeZone::UTC)
        .unwrap()
        .timestamp();
    navi_finance::valuation::record_current(&c, missing_day, observed_at).unwrap();
    currency::save_rate(
        &c,
        &FxRate {
            currency: Currency::USD,
            day: today().plus_days(-7).0,
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
    app.press("label:/^Asset changes/")?;
    let warning = format!(
        "Missing USD rate · {missing_day} – {}",
        today().plus_days(-8).0
    );
    app.wait_for(&warning)?;
    app.wait_for("text:¥7.00")?;
    app.press(&warning)?;
    app.wait_for("text:USD → CNY")?;
    app.wait_for(&format!("text:{missing_day} – {}", today().plus_days(-8).0))?;
    app.press("label:Back")?;
    app.wait_for(&warning)?;
    app.press("7D")?;
    app.wait_for_gone(&warning, GONE)?;
    app.wait_for("text:¥7.00")?;
    app.press("Net worth snapshots")?;
    let snapshot_warning = format!("Missing exchange rates · {missing_day}");
    app.wait_for(&snapshot_warning)?;
    app.wait_for("text:/^Known value .*Missing FX USD/")?;
    app.press("7D")?;
    app.wait_for_gone(&snapshot_warning, GONE)?;
    assert!(!app.shows("text:/^Known value .*Missing FX USD/"));
    Ok(())
}

#[test]
fn overview_opens_the_exact_comparison_and_calendar_windows_remain_available() -> Result<(), String>
{
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
    app.wait_for("text:¥195.00")?;
    app.wait_for("text:+¥95.00")?;
    app.wait_for("text:/¥100.00 – ¥195.00/")?;
    assert!(
        !app.shows("text:Comparison"),
        "All already covers the exact comparison"
    );
    app.press("30D")?;
    app.wait_for_gone("text:/¥100.00 – ¥195.00/", GONE)?;
    more_period(&mut app, "All")?;
    app.wait_for("text:+¥95.00")?;

    drop(app);
    opening("older", -50, 500);
    let mut app = restart();
    app.press("label:Assets")?;
    app.press("label:/^Asset changes, Since 30 days ago/")?;
    app.wait_for("text:+¥95.00")?;
    app.wait_for("text:/¥105.00 – ¥200.00/")?;
    app.press("7D")?;
    app.wait_for_gone("text:/¥105.00 – ¥200.00/", GONE)?;
    more_period(&mut app, "Comparison")?;
    app.wait_for("text:/¥105.00 – ¥200.00/")?;
    app.press("Net worth snapshots")?;
    app.press("Historical estimates")?;
    app.wait_for("text:+¥95.00")?;
    Ok(())
}
