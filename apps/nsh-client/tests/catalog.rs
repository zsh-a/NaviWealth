//! Explicit catalog links never infer a symbol from a manual holding's name.
mod common;
use common::*;
use navi_finance::{catalog, holdings::store, repository};
use nsh_testing::DialogAnswer;
#[test]
fn search_create_and_existing_holding_binding_preserve_identity() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed_catalog(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("Add holding")?;
    app.press("Enter manually")?;
    app.type_text("label:Name or code", "My bank shares")?;
    app.type_text("label:Quantity", "10")?;
    app.type_text("label:Cost per unit", "12")?;
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let before = store::load(&c).unwrap();
    let journal = repository::transactions(&c).unwrap();
    assert!(catalog::bindings(&c).unwrap().is_empty());
    app.press("Link a listed security")?;
    app.type_text("label:Code, name or pinyin", "payh")?;
    app.on_dialog(|_| DialogAnswer::Press("Cancel".into()));
    app.wait_for("label:/^平安银行, Mainland China · 000001/")?;
    app.press("label:/^平安银行, Mainland China · 000001/")?;
    app.wait_for("Link a listed security")?;
    assert!(catalog::bindings(&c).unwrap().is_empty());
    app.press("Link a listed security")?;
    app.type_text("label:Code, name or pinyin", "000001")?;
    app.on_dialog(|_| DialogAnswer::Press("Confirm link".into()));
    app.wait_for("label:/^平安银行, Mainland China · 000001/")?;
    app.press("label:/^平安银行, Mainland China · 000001/")?;
    app.wait_for("Mainland China · 000001 · CNY")?;
    assert_eq!(store::load(&c).unwrap(), before);
    assert_eq!(repository::transactions(&c).unwrap(), journal);
    let b = catalog::bindings(&c).unwrap();
    assert_eq!(b.len(), 1);
    assert_eq!(b[0].security, before.securities[0].id);
    assert_eq!(b[0].symbol, "000001");
    app.press("label:Back")?;
    app.press("text:Manage")?;
    app.press("Add holding")?;
    app.type_text("label:Code, name or pinyin", "aapl")?;
    app.wait_for("label:/^Apple Inc., United States · AAPL/")?;
    app.press("Enter manually")?;
    app.type_text("label:Name or code", "Offline manual fund")?;
    app.type_text("label:Quantity", "1")?;
    app.type_text("label:Cost per unit", "2")?;
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    assert_eq!(catalog::bindings(&c).unwrap().len(), 1);
    Ok(())
}

#[test]
fn catalog_selection_saves_binding_and_trade_together() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed_catalog(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("Add holding")?;
    app.type_text("label:Code, name or pinyin", "600000")?;
    app.wait_for("label:/^浦发银行, Mainland China · 600000/")?;
    app.press("label:/^浦发银行, Mainland China · 600000/")?;
    app.type_text("label:Quantity", "10")?;
    app.type_text("label:Cost per unit", "12")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    c.execute_batch("CREATE TRIGGER fail_binding BEFORE INSERT ON finance_security_bindings BEGIN SELECT RAISE(ABORT,'storage full'); END;").unwrap();
    app.press("Save holding")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(store::load(&c).unwrap().securities.is_empty());
    assert!(repository::transactions(&c).unwrap().is_empty());
    assert!(catalog::bindings(&c).unwrap().is_empty());
    c.execute_batch("DROP TRIGGER fail_binding").unwrap();
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    let book = store::load(&c).unwrap();
    let binding = catalog::bindings(&c).unwrap();
    assert_eq!(binding.len(), 1);
    assert_eq!(binding[0].symbol, "600000");
    assert_eq!(binding[0].security, book.securities[0].id);
    assert_ne!(binding[0].security, "600000");
    assert_eq!(book.trades.len(), 1);
    Ok(())
}

#[test]
fn foreign_catalog_selection_sets_currency_and_preserves_native_price() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    seed_catalog(dir.path());
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("Add holding")?;
    app.type_text("label:Code, name or pinyin", "aapl")?;
    app.wait_for("label:/^Apple Inc., United States · AAPL/")?;
    app.press("label:/^Apple Inc., United States · AAPL/")?;
    app.type_text("label:Quantity", "2")?;
    app.type_text("label:Cost per unit", "100")?;
    app.press("Save holding")?;
    app.wait_for("Record trade")?;
    app.wait_for("text:USD 200.00")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let book = store::load(&c).unwrap();
    assert_eq!(
        book.securities[0].currency(),
        navi_finance::currency::Currency::USD
    );
    assert_eq!(
        book.position(&book.securities[0], today().0).unwrap().cost,
        20000
    );
    assert_eq!(catalog::bindings(&c).unwrap()[0].currency, "USD");
    Ok(())
}
