//! Financial entry flows across the editor, timeline, restart and disk failures.
mod common;
use common::*;
use navi_finance::{account::Account, journal, money, repository};
use nsh_testing::DialogAnswer;

fn stored(dir: &Path) -> Vec<journal::Transaction> {
    let db = rusqlite::Connection::open(database_in(dir)).unwrap();
    repository::transactions(&db).unwrap()
}

fn open_new(app: &mut Headless) -> Result<(), String> {
    open_manual(app, "Log transaction")?;
    app.wait_for("Save transaction")?;
    assert!(!app.shows("id:task-header >> label:Delete transaction"));
    Ok(())
}

fn first_expense(app: &mut Headless) -> Result<(), String> {
    open_new(app)?;
    app.type_text("label:Amount", "31.50")?;
    app.press("Details")?;
    app.type_text("label:Payee / payer (optional)", "Lunch shop")?;
    app.press("Done")?;
    app.press("Account")?;
    app.press("Add account")?;
    app.type_text("label:Account name", "Cash")?;
    app.press("Done")?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    app.wait_for("label:/^Lunch shop, −¥31.50/")?;
    Ok(())
}

#[test]
fn expense_income_and_transfer_share_one_balanced_persistent_journal() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    first_expense(&mut app)?;
    open_new(&mut app)?;
    app.press("Income")?;
    app.type_text("label:Amount", "100.00")?;
    app.press("Details")?;
    app.type_text("label:Payee / payer (optional)", "Employer")?;
    app.press("Done")?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;

    open_new(&mut app)?;
    app.press("Transfer")?;
    app.type_text("label:Amount", "20.00")?;
    app.press("To account")?;
    app.press("Add account")?;
    app.press("Credit / debt")?;
    app.type_text("label:Account name", "Card")?;
    app.press("Done")?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    let entries = stored(dir.path());
    assert_eq!(entries.len(), 3);
    assert!(entries.iter().all(|t| t.validate().is_ok()));
    assert_eq!(
        money::sum(journal::spending(&entries, today().0, today().0).into_values()),
        3150
    );
    let balances = journal::balances(&entries);
    assert_eq!(balances[&Account::parse("资产:Cash").unwrap()], 4850);
    assert_eq!(balances[&Account::parse("负债:Card").unwrap()], 2000);
    app.press("label:Records")?;
    app.wait_for("text:Spending ¥31.50")?;
    app.wait_for("label:Tomato pasta, 300 kcal")?;
    app.wait_for(r"label:/^Employer, \+¥100.00/")?;
    app.press("Money")?;
    app.wait_for_gone("label:Tomato pasta, 300 kcal", GONE)?;
    app.wait_for("label:/^Lunch shop, −¥31.50/")?;
    app.press("Meals")?;
    app.wait_for("label:Tomato pasta, 300 kcal")?;
    app.wait_for_gone("label:/^Lunch shop, /", GONE)?;
    drop(app);
    let (mut again, _) = start_in(Some(dir.path()), Vec::new(), None);
    again.wait_for("label:/^Lunch shop, −¥31.50/")?;
    assert_eq!(stored(dir.path()), entries);
    Ok(())
}

#[test]
fn invalid_money_does_not_write_and_cancel_discards_new_accounts() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    open_new(&mut app)?;
    app.type_text("label:Amount", "1.005")?;
    app.press("Account")?;
    app.press("Add account")?;
    app.type_text("label:Account name", "Unsaved account")?;
    app.press("Done")?;
    app.press("Save transaction")?;
    assert!(app.shows("Save transaction"));
    assert!(stored(dir.path()).is_empty());
    app.on_dialog(|_| DialogAnswer::Press("Discard".into()));
    app.press("Cancel")?;
    app.wait_for_gone("Save transaction", GONE)?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(
        !repository::accounts(&db)
            .unwrap()
            .iter()
            .any(|a| a.name() == "Unsaved account")
    );
    Ok(())
}

#[test]
fn edited_date_is_reachable_from_calendar_and_delete_can_be_undone() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    first_expense(&mut app)?;
    app.press("label:/^Lunch shop, −¥31.50/")?;
    let previous = today().plus_days(-1);
    app.press("Date")?;
    app.press("Yesterday")?;
    app.clear("label:Amount")?;
    app.type_text("label:Amount", "42.25")?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    assert!(!app.shows("label:/^Lunch shop, /"));
    assert_eq!(stored(dir.path())[0].at.date(), previous.0);
    app.press("label:Records")?;
    app.wait_for("label:/^Lunch shop, −¥42.25/")?;
    app.press("label:Go to a day")?;
    if previous.0.month() != today().0.month() {
        app.press("label:Previous month")?;
    }
    app.press(&format!("label:{}", previous.0.strftime("%A, %B %-d")))?;
    app.wait_for("All days")?;
    app.press("label:/^Lunch shop, −¥42.25/")?;
    app.press("Details")?;
    app.on_dialog(|_| DialogAnswer::Press("Delete transaction".into()));
    app.press("Delete transaction")?;
    app.wait_for("Undo")?;
    assert!(stored(dir.path()).is_empty());
    app.press("Undo")?;
    app.wait_for("label:/^Lunch shop, −¥42.25/")?;
    assert_eq!(stored(dir.path()).len(), 1);
    Ok(())
}

#[test]
fn delete_is_visible_above_the_keyboard_and_cancel_keeps_unsaved_changes() -> Result<(), String> {
    use nsh_core::geometry::{Points, Size};
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    first_expense(&mut app)?;
    app.press("label:/^Lunch shop, −¥31.50/")?;
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.set_environment("large text with keyboard", |env| {
        env.font_scale = 1.3;
        env.keyboard_height = Points(280.0);
    })?;
    let delete = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("task-header"))
        .unwrap();
    assert!(delete.bounds.origin.y.0 >= 0.0);
    assert!(delete.bounds.origin.y.0 + delete.bounds.size.height.0 <= 360.5);
    assert!(delete.bounds.size.height.0 >= 48.0);
    app.clear("label:Amount")?;
    app.type_text("label:Amount", "42.25")?;
    app.on_dialog(|dialog| {
        assert_eq!(dialog.title.as_deref(), Some("Delete this transaction?"));
        let summary = dialog.message.as_deref().unwrap();
        assert!(summary.contains("Lunch shop"));
        assert!(summary.contains("31.50"));
        assert!(summary.contains("Cash"));
        assert!(!summary.contains("42.25"));
        DialogAnswer::Press("Cancel".into())
    });
    app.press("id:task-header >> label:Delete transaction")?;
    assert_eq!(stored(dir.path())[0].postings[0].amount.abs(), 3150);
    app.set_environment("keyboard dismissed", |env| {
        env.keyboard_height = Points(0.0)
    })?;
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    assert_eq!(stored(dir.path())[0].postings[0].amount.abs(), 4225);
    Ok(())
}

#[test]
fn failed_delete_and_failed_undo_can_retry_without_partial_postings() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    first_expense(&mut app)?;
    let original = stored(dir.path());
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_delete BEFORE DELETE ON finance_postings WHEN OLD.position=1 BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("label:/^Lunch shop, −¥31.50/")?;
    app.on_dialog(|_| DialogAnswer::Press("Delete transaction".into()));
    app.press("id:task-header >> label:Delete transaction")?;
    app.wait_for("Could not delete this record. Please try again.")?;
    assert_eq!(stored(dir.path()), original);
    assert!(app.shows("Save transaction"));
    db.execute_batch("DROP TRIGGER reject_delete").unwrap();
    app.press("id:task-header >> label:Delete transaction")?;
    app.wait_for("Transaction deleted")?;
    assert!(stored(dir.path()).is_empty());
    db.execute_batch("CREATE TRIGGER reject_restore BEFORE INSERT ON finance_postings WHEN NEW.position=1 BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("Undo")?;
    app.wait_for("Could not restore this record. Tap Try again to retry.")?;
    assert!(stored(dir.path()).is_empty());
    db.execute_batch("DROP TRIGGER reject_restore").unwrap();
    app.press("Try again")?;
    app.wait_for("label:/^Lunch shop, −¥31.50/")?;
    assert_eq!(stored(dir.path()), original);
    Ok(())
}

#[test]
fn undo_refuses_to_overwrite_a_newer_transaction_with_the_same_identity() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    first_expense(&mut app)?;
    let mut newer = stored(dir.path())[0].clone();
    app.press("label:/^Lunch shop, −¥31.50/")?;
    app.on_dialog(|_| DialogAnswer::Press("Delete transaction".into()));
    app.press("id:task-header >> label:Delete transaction")?;
    app.wait_for("Transaction deleted")?;
    newer.note = "Newer evidence".into();
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    repository::save(&db, &newer).unwrap();
    app.press("Undo")?;
    app.wait_for("This record or its account changed. Undo cannot overwrite newer data.")?;
    assert_eq!(stored(dir.path()), [newer]);
    Ok(())
}

#[test]
fn unreadable_database_blocks_capture_instead_of_saving_to_memory() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    // First find the runtime's private data directory, then replace the DB with
    // known invalid bytes while it is closed. Startup must preserve those bytes.
    let (app, _) = start_in(Some(dir.path()), Vec::new(), None);
    let path = database_in(dir.path());
    drop(app);
    std::fs::write(&path, b"not a SQLite database").unwrap();
    let mut config = EngineConfig::new(Root::of::<App>());
    config.data_dir = Some(dir.path().to_path_buf());
    config.storage = Some(MemoryStorage::new(Vec::<(String, String)>::new()));
    let mut app = Headless::start(config).map_err(|e| e.to_string())?;
    app.wait_for("Local data unavailable")?;
    assert!(!app.shows("label:New entry"));
    assert_eq!(std::fs::read(&path).unwrap(), b"not a SQLite database");
    Ok(())
}

#[test]
fn failed_save_keeps_editor_open_and_retry_writes_exactly_once() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_second_posting BEFORE INSERT ON finance_postings WHEN NEW.position = 1 BEGIN SELECT RAISE(ABORT, 'simulated full disk'); END;").unwrap();
    open_new(&mut app)?;
    app.type_text("label:Amount", "12.34")?;
    app.press("Account")?;
    app.press("Add account")?;
    app.type_text("label:Account name", "Retry wallet")?;
    app.press("Done")?;
    app.press("Save transaction")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(app.shows("Save transaction"));
    assert!(stored(dir.path()).is_empty());
    assert!(
        !repository::accounts(&db)
            .unwrap()
            .iter()
            .any(|a| a.name() == "Retry wallet")
    );
    let count: i64 = db
        .query_row("SELECT COUNT(*) FROM finance_postings", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0);
    db.execute_batch("DROP TRIGGER reject_second_posting;")
        .unwrap();
    app.press("Save transaction")?;
    app.wait_for_gone("Save transaction", GONE)?;
    let entries = stored(dir.path());
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].postings.len(), 2);
    assert_eq!(entries[0].validate(), Ok(()));
    Ok(())
}
