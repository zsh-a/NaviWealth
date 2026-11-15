//! Portfolio ownership through the real UI, exact cash coupling and recovery.
mod common;
use common::*;
use finance_core::{
    account::Account,
    holdings::{self, store},
    journal, repository,
};
use nsh_core::geometry::{Points, Size};
use nsh_testing::DialogAnswer;

fn add_holding(app: &mut Headless, name: &str, qty: &str, cost: &str) -> Result<(), String> {
    app.press("label:Assets")?;
    app.press("text:Manage")?;
    app.press("Add holding")?;
    app.type_text("label:Name or code", name)?;
    app.type_text("label:Quantity", qty)?;
    app.type_text("label:Cost per unit", cost)?;
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
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
    app.press("label:Back")?;
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
    app.press("label:/^Index ETF, 300.00 CNY/")?;
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
    app.wait_for("text:Manage")?;
    assert!(!app.shows("text:Index ETF"));
    app.press("text:Manage")?;
    app.press("text:Closed holdings")?;
    app.press("label:/^Index ETF, 0.00 CNY/")?;
    app.press("Record trade")?;
    app.type_text("label:Quantity", "10")?;
    app.type_text("label:Price per unit", "4")?;
    app.press("Save trade")?;
    app.wait_for("Trade saved")?;
    app.press("label:Back")?;
    app.wait_for("No closed holdings")?;
    app.press("label:Back")?;
    app.wait_for("label:/^Index ETF, 50.00 CNY/")?;
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
