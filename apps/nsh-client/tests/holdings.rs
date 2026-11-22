//! Portfolio ownership through the real UI, exact cash coupling and recovery.
mod common;
use common::*;
use navi_finance::{
    account::Account,
    holdings::{self, store},
    journal, repository,
};
use nsh_core::geometry::{Points, Size};
use nsh_testing::DialogAnswer;

fn add_holding(app: &mut Headless, name: &str, qty: &str, cost: &str) -> Result<(), String> {
    app.press("label:Assets")?;
    app.press("label:Manage")?;
    app.press("Add holding")?;
    app.press("Enter manually")?;
    app.type_text("label:Name or code", name)?;
    app.type_text("label:Quantity", qty)?;
    app.type_text("label:Cost per unit", cost)?;
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    Ok(())
}

#[test]
fn detail_prioritizes_trade_and_keeps_price_and_listing_actions_readable() -> Result<(), String> {
    use nsh_core::{
        ApproxTextEngine, TextEngine,
        platform::{Locale, LocaleSettings},
    };
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("Add holding")?;
    app.press("Enter manually")?;
    app.type_text("label:Name or code", "Fund")?;
    app.type_text("label:Quantity", "1000")?;
    app.type_text("label:Cost per unit", "4.125")?;
    app.press("Save holding")?;
    app.wait_for("label:Record trade")?;
    app.wait_for("text:¥4.125")?;
    app.wait_for("text:1000 × ¥4.125")?;
    app.press("label:Update price")?;
    app.type_text("label:Price", "6.25")?;
    app.press("text:Update price")?;
    app.wait_for("Price updated")?;
    assert_eq!(app.screen().count("text:¥6.25")?, 1);
    app.press("Price history")?;
    app.wait_for("text:¥6.25")?;
    app.wait_for("text:/Manual/")?;
    app.press("Daily closes")?;
    app.wait_for("No daily closes yet")?;
    app.press("label:Back")?;
    for tag in ["en", "zh-CN"] {
        let locale = Locale::parse(tag).unwrap();
        app.set_environment("language", |e| {
            e.locale = locale;
            e.locale_settings = LocaleSettings::of(locale);
        })?;
        let labels = if tag == "en" {
            ["Trade", "Link code", "Price history"]
        } else {
            ["记录交易", "关联代码", "价格记录"]
        };
        for width in [360.0, 390.0] {
            app.set_viewport(Size::new(Points(width), Points(640.0)))?;
            for scale in [1.0, 1.8] {
                app.set_environment("font scale", |e| e.font_scale = scale)?;
                let nodes = app.screen().layout_nodes();
                let mut buttons = Vec::new();
                for label in labels {
                    let node = nodes
                        .iter()
                        .find(|n| n.text.as_ref().is_some_and(|t| t.text.text == label))
                        .unwrap_or_else(|| panic!("missing {label} at {tag}/{width}/{scale}"));
                    let button = nodes.iter().find(|n| n.id == node.parent).unwrap();
                    assert!(button.bounds.size.height.0 >= 48.0);
                    assert!(button.bounds.origin.x.0 >= 19.5);
                    assert!(button.bounds.origin.x.0 + button.bounds.size.width.0 <= width - 19.5);
                    let content = node.text.as_ref().unwrap();
                    let mut written = (*content.text).clone();
                    written.max_lines = 0;
                    let measured = ApproxTextEngine.measure(
                        &ApproxTextEngine.prepare(&written),
                        Some(content.content.size.width),
                    );
                    assert!(
                        measured.height.0 <= content.content.size.height.0 + 0.5,
                        "{label} fits at {width}/{scale}"
                    );
                    buttons.push(button.bounds);
                }
                let [trade, link, history] = buttons.as_slice() else {
                    unreachable!()
                };
                assert!(trade.origin.y.0 + trade.size.height.0 < 180.0);
                assert!(trade.origin.y.0 + trade.size.height.0 <= link.origin.y.0);
                assert!(link.origin.y.0 + link.size.height.0 <= history.origin.y.0);
                let plot = nodes
                    .iter()
                    .find(|n| n.test_id.as_deref() == Some("trend-inspector"))
                    .unwrap();
                assert!(history.origin.y.0 + history.size.height.0 <= plot.bounds.origin.y.0);
                if scale == 1.0 {
                    assert!(
                        plot.bounds.origin.y.0 + plot.bounds.size.height.0 <= 640.0,
                        "trade and price plot should fit the first screen at {tag}/{width}"
                    );
                }
            }
        }
    }
    Ok(())
}

fn check_large_cash_preview(app: &mut Headless, account_label: &str) -> Result<(), String> {
    use nsh_core::{ApproxTextEngine, TextEngine};
    app.set_viewport(Size::new(Points(320.0), Points(640.0)))?;
    app.set_environment("large trade text", |e| e.font_scale = 1.3)?;
    app.clear("label:Price per unit")?;
    app.type_text("label:Price per unit", "1234567890")?;
    let amount = "−¥1,851,851,835.00";
    app.wait_for(&format!("text:{amount}"))?;
    let nodes = app.screen().layout_nodes();
    let mut previous_bottom = 0.0;
    for label in [account_label, amount] {
        let node = nodes
            .iter()
            .find(|n| n.text.as_ref().is_some_and(|v| v.text.text == label))
            .unwrap();
        let frame = node.bounds;
        assert!(
            frame.origin.x.0 >= 19.5 && frame.origin.x.0 + frame.size.width.0 <= 300.5,
            "{frame:?}"
        );
        assert!(previous_bottom <= frame.origin.y.0 + 0.5);
        previous_bottom = frame.origin.y.0 + frame.size.height.0;
        let content = node.text.as_ref().unwrap();
        let mut written = (*content.text).clone();
        written.max_lines = 0;
        let measured = ApproxTextEngine.measure(
            &ApproxTextEngine.prepare(&written),
            Some(content.content.size.width),
        );
        assert!(
            measured.height.0 <= content.content.size.height.0 + 0.5,
            "{label} clipped"
        );
    }
    app.clear("label:Price per unit")?;
    app.type_text("label:Price per unit", "4.13")?;
    app.set_environment("default trade text", |e| e.font_scale = 1.0)?;
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    Ok(())
}

#[test]
fn trade_cash_preview_matches_each_saved_posting_including_fees() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    let settlement = "Brokerage settlement account 1234";
    for name in [settlement, "Wallet"] {
        app.press("label:Assets")?;
        if name == "Wallet" {
            app.press("label:Manage")?;
        }
        app.press("text:Add account")?;
        app.type_text("label:Account name", name)?;
        app.press("Create account")?;
        app.wait_for("Account added")?;
        app.wait_for_gone("task-sheet", GONE)?;
    }
    add_holding(&mut app, "Fund", "10", "4")?;
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let account = Account::parse(&format!("资产:{settlement}")).unwrap();
    let balance =
        || journal::balance_on(&repository::transactions(&db).unwrap(), &account, today().0);
    for (side, expected, minor) in [
        ("Buy", "−¥6.23", -623),
        ("Sell", "+¥6.17", 617),
        ("Dividend", "+¥2.21", 221),
    ] {
        let before = balance();
        app.press("Record trade")?;
        app.press(side)?;
        if side == "Buy" {
            let nodes = app.screen().layout_nodes();
            let account = nodes
                .iter()
                .find(|n| {
                    n.text
                        .as_ref()
                        .is_some_and(|t| t.text.text == "Cash account")
                })
                .unwrap()
                .bounds;
            let actions = nodes
                .iter()
                .find(|n| n.test_id.as_deref() == Some("task-actions"))
                .unwrap()
                .bounds;
            assert!(
                account.origin.y.0 + account.size.height.0 <= actions.origin.y.0,
                "quantity, price and account should fit before the keyboard opens"
            );
        }
        if side == "Dividend" {
            app.wait_for("Enter a dividend amount to see the cash received.")?;
            app.type_text("label:Dividend amount", "2.33")?;
            app.wait_for("text:+¥2.33")?;
        } else {
            app.wait_for("Enter quantity and price per unit to see the cash amount.")?;
            app.type_text("label:Quantity", "1.5")?;
            app.type_text("label:Price per unit", "4.13")?;
            app.wait_for(if side == "Buy" {
                "text:−¥6.20"
            } else {
                "text:+¥6.20"
            })?;
        }
        app.wait_for("text:Choose a cash account")?;
        let direction = if side == "Buy" { "Cash out" } else { "Cash in" };
        if side == "Buy" {
            app.press("label:Cash account")?;
            app.press("text:Wallet")?;
            app.wait_for("Wallet · Cash out")?;
        }
        app.press("label:Cash account")?;
        app.press(&format!("text:{settlement}"))?;
        let account_label = format!("{settlement} · {direction}");
        app.wait_for(&account_label)?;
        if side == "Buy" {
            check_large_cash_preview(&mut app, &account_label)?;
        }
        app.press("Date and fee")?;
        if side == "Dividend" {
            app.type_text("label:Fee (optional)", "2.33")?;
            app.wait_for("The dividend must exceed the fee.")?;
            assert!(!app.shows("text:+¥2.33"));
            app.clear("label:Fee (optional)")?;
        }
        let fee = if side == "Dividend" { "0.12" } else { "0.03" };
        app.type_text("label:Fee (optional)", fee)?;
        app.wait_for(&format!("text:{expected}"))?;
        app.wait_for(&format!("Includes fee of ¥{fee}"))?;
        app.set_environment("fee keyboard", |e| e.keyboard_height = Points(280.0))?;
        let nodes = app.screen().layout_nodes();
        let actions = nodes
            .iter()
            .find(|n| n.test_id.as_deref() == Some("task-actions"))
            .unwrap()
            .bounds;
        let amount = nodes
            .iter()
            .find(|n| n.text.as_ref().is_some_and(|t| t.text.text == expected))
            .unwrap()
            .bounds;
        assert!(amount.origin.y.0 >= actions.origin.y.0);
        assert!(
            amount.origin.y.0 + amount.size.height.0 <= actions.origin.y.0 + actions.size.height.0
        );
        assert!(actions.origin.y.0 + actions.size.height.0 <= 360.5);
        app.set_environment("keyboard dismissed", |e| e.keyboard_height = Points(0.0))?;
        assert_eq!(balance(), before);
        app.press("Save trade")?;
        app.wait_for("Trade saved")?;
        assert_eq!(balance() - before, minor);
    }
    Ok(())
}
#[test]
fn opening_price_partial_sale_and_cash_survive_restart_without_double_counting()
-> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("text:Add account")?;
    app.type_text("label:Account name", "Broker cash")?;
    app.press("Create account")?;
    app.wait_for("Account added")?;
    add_holding(&mut app, "Index ETF", "100", "4")?;
    app.press("label:Update price")?;
    app.type_text("label:Price", "5")?;
    app.press("text:Update price")?;
    app.wait_for("Price updated")?;
    app.wait_for("text:¥500.00")?;
    app.press("Record trade")?;
    app.press("Sell")?;
    app.type_text("label:Quantity", "40")?;
    app.type_text("label:Price per unit", "5")?;
    app.press("Save trade")?;
    app.wait_for("Trade saved")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let book = store::load(&c).unwrap();
    let s = &book.securities[0];
    let position = book.position(s, today().0).unwrap();
    assert_eq!(
        (position.quantity, position.cost, position.realized),
        (60_000_000, 24000, 4000)
    );
    let entries = repository::transactions(&c).unwrap();
    assert_eq!(
        journal::balance_on(
            &entries,
            &Account::parse("资产:Broker cash").unwrap(),
            today().0
        ),
        20000
    );
    assert_eq!(book.overview(&entries, today().0).unwrap().net, 50000);
    assert!(journal::spending(&entries, today().0, today().0).is_empty());
    app.press("label:Back")?;
    app.wait_for("label:¥500.00")?;
    assert!(
        !app.shows("text:/^持仓·/"),
        "internal cost accounts never become cash accounts"
    );
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.press("label:Assets")?;
    app.wait_for("label:¥500.00")?;
    app.press("label:/^Index ETF, ¥300.00, Manual ·/")?;
    app.wait_for("text:¥300.00")?;
    app.press("label:/^Sell, 40 /")?;
    app.on_dialog(|_| DialogAnswer::Press("Delete trade".into()));
    app.press("Delete trade")?;
    app.wait_for("Trade deleted")?;
    let book = store::load(&c).unwrap();
    assert_eq!(
        book.position(&book.securities[0], today().0)
            .unwrap()
            .quantity,
        100_000_000
    );
    assert_eq!(
        journal::balance_on(
            &repository::transactions(&c).unwrap(),
            &Account::parse("资产:Broker cash").unwrap(),
            today().0
        ),
        0
    );
    // Closing removes the holding from the overview, but keeps its history
    // reachable. Buying again returns it to the overview automatically.
    app.press("Record trade")?;
    app.press("Sell")?;
    app.type_text("label:Quantity", "100")?;
    app.type_text("label:Price per unit", "5")?;
    app.press("Save trade")?;
    app.wait_for("Trade saved")?;
    app.press("label:Back")?;
    app.wait_for("label:Manage")?;
    assert!(!app.shows("text:Index ETF"));
    app.wait_for("Book balances")?;
    app.press("label:Manage")?;
    app.press("text:Closed holdings")?;
    app.press("label:/^Index ETF, ¥0.00/")?;
    app.press("Record trade")?;
    app.type_text("label:Quantity", "10")?;
    app.type_text("label:Price per unit", "4")?;
    app.press("Save trade")?;
    app.wait_for("Trade saved")?;
    app.press("label:Back")?;
    app.wait_for("No closed holdings")?;
    app.press("label:Back")?;
    app.wait_for("label:/^Index ETF, ¥50.00/")?;
    app.press("label:New entry")?;
    app.wait_for("What would you like to record?")?;
    Ok(())
}

#[test]
fn failed_new_position_keeps_input_and_overselling_never_changes_the_ledger() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("Add holding")?;
    app.press("Enter manually")?;
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.type_text("label:Name or code", "Fund")?;
    app.type_text("label:Quantity", "10.5")?;
    app.type_text("label:Cost per unit", "1.2345")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    c.execute_batch("CREATE TRIGGER fail_trade BEFORE INSERT ON finance_trades BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("Save holding")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(store::load(&c).unwrap().securities.is_empty());
    assert!(repository::transactions(&c).unwrap().is_empty());
    c.execute_batch("DROP TRIGGER fail_trade").unwrap();
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    let before = repository::transactions(&c).unwrap();
    app.press("Record trade")?;
    app.press("Sell")?;
    app.type_text("label:Quantity", "11")?;
    app.type_text("label:Price per unit", "2")?;
    app.press("Save trade")?;
    app.wait_for("This would sell more than was held. Correct later trades first.")?;
    assert_eq!(repository::transactions(&c).unwrap(), before);
    assert_eq!(
        holdings::format_units(
            store::load(&c)
                .unwrap()
                .position(&store::load(&c).unwrap().securities[0], today().0)
                .unwrap()
                .quantity
        ),
        "10.5"
    );
    Ok(())
}

#[test]
fn manual_hkd_holding_keeps_currency_when_recording_later_trades() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("Add holding")?;
    app.press("Enter manually")?;
    app.press("text:HKD")?;
    app.type_text("label:Name or code", "Hong Kong fund")?;
    app.type_text("label:Quantity", "10")?;
    app.type_text("label:Cost per unit", "12")?;
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    app.wait_for("text:HKD 120.00")?;
    app.press("Record trade")?;
    app.wait_for("Hong Kong fund · HKD")?;
    app.type_text("label:Quantity", "1")?;
    app.type_text("label:Price per unit", "13")?;
    app.press("Save trade")?;
    app.wait_for("Choose a cash account. Add one in Assets if needed.")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let book = store::load(&c).unwrap();
    assert_eq!(
        book.securities[0].currency(),
        navi_finance::currency::Currency::HKD
    );
    assert_eq!(book.trades.len(), 1);
    Ok(())
}

#[test]
fn security_search_back_preserves_values_query_and_one_fixed_task_viewport() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed_catalog(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("Add holding")?;
    app.press("Enter manually")?;
    app.type_text("label:Quantity", "2")?;
    app.type_text("label:Cost per unit", "100")?;
    let sheet = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("task-sheet"))
        .unwrap()
        .id;
    app.press("label:Search securities")?;
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.set_environment("search with IME", |e| {
        e.font_scale = 1.3;
        e.keyboard_height = Points(280.0);
    })?;
    app.type_text("security-search", "aapl")?;
    app.wait_for("label:/^Apple Inc., United States · AAPL/")?;
    assert_eq!(app.screen().count("task-sheet")?, 1);
    let search = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("security-search"))
        .unwrap();
    let search_frame = search.bounds;
    for id in ["task-header", "task-actions"] {
        let node = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some(id))
            .unwrap();
        assert!(node.bounds.origin.y.0 >= 0.0);
        assert!(
            node.bounds.origin.y.0 + node.bounds.size.height.0 <= 360.5,
            "{id} stays above the IME: {:?}",
            node.bounds
        );
    }
    app.clear("security-search")?;
    app.wait_for_gone("label:/^Apple Inc., United States · AAPL/", GONE)?;
    app.type_text("security-search", "600000")?;
    app.wait_for("label:/^浦发银行, Mainland China · 600000/")?;
    let after = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("security-search"))
        .unwrap();
    assert_eq!(
        (after.id, after.bounds),
        (search.id, search_frame),
        "search field stays fixed while only results change"
    );
    app.back()?;
    app.wait_for("Save holding")?;
    assert_eq!(app.screen().input_text("label:Quantity")?, Some("2"));
    assert_eq!(app.screen().input_text("label:Cost per unit")?, Some("100"));
    app.press("label:Search securities")?;
    assert_eq!(app.screen().input_text("security-search")?, Some("600000"));
    app.clear("security-search")?;
    app.type_text("security-search", "aapl")?;
    app.wait_for("label:/^Apple Inc., United States · AAPL/")?;
    app.press("label:/^Apple Inc., United States · AAPL/")?;
    app.set_environment("IME dismissed", |e| {
        e.keyboard_height = Points(0.0);
        e.font_scale = 1.0;
    })?;
    app.wait_for("United States · AAPL · USD")?;
    assert_eq!(
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("task-sheet"))
            .unwrap()
            .id,
        sheet
    );
    assert_eq!(app.screen().input_text("label:Quantity")?, Some("2"));
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let book = store::load(&db).unwrap();
    assert_eq!(
        book.securities[0].currency(),
        navi_finance::currency::Currency::USD
    );
    assert_eq!(
        book.position(&book.securities[0], today().0).unwrap().cost,
        20000
    );
    assert_eq!(
        navi_finance::catalog::bindings(&db).unwrap()[0].symbol,
        "AAPL"
    );
    Ok(())
}
