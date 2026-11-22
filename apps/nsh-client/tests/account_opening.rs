mod common;
use common::*;
use navi_finance::{
    account::{Account, defaults},
    assets, journal, repository,
};
use nsh_core::geometry::{Points, Size};

#[test]
fn dated_opening_debt_saves_with_account_and_retries_atomically() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.press("label:Assets")?;
    app.press("text:Add account")?;
    app.press("label:Account type, Bank account")?;
    for purpose in [
        "Cash",
        "Bank account",
        "Digital wallet",
        "Brokerage cash",
        "Consumer credit",
        "Loan",
    ] {
        app.wait_for(&format!("task-sheet >> label:{purpose}"))?;
    }
    app.press("Consumer credit")?;
    app.type_text("label:Account name", "Card")?;
    app.press("label:Opening debt, Optional")?;
    app.type_text("label:Opening debt", "38.45")?;
    app.press("label:/^As of date, /")?;
    app.press("Yesterday")?;
    app.press("Done")?;
    app.wait_for("label:Opening debt, ¥38.45")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER fail_open BEFORE INSERT ON finance_postings BEGIN SELECT RAISE(ABORT,'disk full'); END;").unwrap();
    app.press("Create account")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    let card = Account::parse("负债:Card").unwrap();
    assert!(!repository::accounts(&db).unwrap().contains(&card));
    assert!(repository::balance_checks(&db).unwrap().is_empty());
    db.execute_batch("DROP TRIGGER fail_open").unwrap();
    app.press("Create account")?;
    app.wait_for_gone("task-sheet", GONE)?;
    let entries = repository::transactions(&db).unwrap();
    let checks = repository::balance_checks(&db).unwrap();
    assert_eq!(checks.len(), 1);
    assert_eq!(checks[0].day, today().plus_days(-1).0);
    assert_eq!(checks[0].actual, -3845);
    assert_eq!(assets::displayed(&card, entries[0].amount_in(&card)), 3845);
    assert_eq!(entries[0].amount_in(&defaults::opening()), 3845);
    app.press("label:/^Card, /")?;
    app.press("Edit account")?;
    assert!(!app.screen().enabled("Save changes")?);
    assert!(app.screen().enabled("Deactivate account")?);
    app.press("label:Account type, Consumer credit")?;
    app.wait_for("task-sheet >> Loan")?;
    assert!(!app.shows("task-sheet >> Brokerage cash"));
    app.press("task-header >> Back")?;
    app.clear("label:Account name")?;
    assert!(!app.screen().enabled("Save changes")?);
    app.type_text("label:Account name", "Travel card")?;
    assert!(app.screen().enabled("Save changes")?);
    Ok(())
}

#[test]
fn first_spending_can_be_preceded_by_an_explicit_zero_opening() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let card = Account::parse("资产:Checking").unwrap();
    let first_day = today().plus_days(-6);
    let expense = journal::spend(
        journal::Entry {
            id: "groceries".into(),
            at: first_day.0.at(14, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: journal::Source::Manual,
        },
        &card,
        &defaults::other_expense(),
        3000,
    )
    .unwrap();
    repository::save(&db, &expense).unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("label:/^Checking, /")?;
    app.wait_for("Check balance")?;
    app.press("Set opening balance")?;
    app.press("label:/^Date, /")?;
    assert!(!app.screen().enabled("task-sheet >> Today")?);
    assert!(!app.screen().enabled("task-sheet >> Yesterday")?);
    app.press("Done")?;
    app.type_text("label:Actual balance", "0")?;
    app.press("Review difference")?;
    app.press("Confirm balance")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.wait_for("Check balance")?;
    assert!(!app.shows("Set opening balance"));
    let checks = repository::balance_checks(&db).unwrap();
    assert_eq!(checks.len(), 1);
    assert_eq!(checks[0].day, first_day.plus_days(-1).0);
    assert_eq!(checks[0].actual, 0);
    assert_eq!(repository::transactions(&db).unwrap(), vec![expense]);
    Ok(())
}

#[test]
fn existing_unclassified_account_can_set_its_purpose_without_renaming() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let account = Account::parse("资产:Metro").unwrap();
    repository::create_account(&db, &account).unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("text:Metro")?;
    app.wait_for("text:Asset account · CNY")?;
    app.press("Edit account")?;
    app.press("label:Account type, Asset account")?;
    app.wait_for("task-sheet >> Digital wallet")?;
    assert!(!app.shows("task-sheet >> Loan"));
    app.back()?;
    assert!(!app.screen().enabled("Save changes")?);
    app.press("label:Account type, Asset account")?;
    app.press("task-sheet >> Digital wallet")?;
    assert!(app.screen().enabled("Save changes")?);
    assert!(!app.shows("Deactivate account"));
    app.on_dialog(|_| nsh_testing::DialogAnswer::Press("Keep editing".into()));
    app.back()?;
    app.wait_for("label:Account type, Digital wallet")?;
    app.press("Save changes")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.wait_for("text:Digital wallet · CNY")?;
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Assets")?;
    app.press("text:Metro")?;
    app.wait_for("text:Digital wallet · CNY")?;
    assert!(repository::balance_checks(&db).unwrap().is_empty());
    assert!(repository::transactions(&db).unwrap().is_empty());
    Ok(())
}
