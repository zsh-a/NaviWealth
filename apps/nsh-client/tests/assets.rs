//! Owner-visible account lifecycle, balance confirmation and storage recovery.
mod common;
use common::*;
use navi_finance::{account::Account, assets, journal, repository};
use nsh_core::geometry::{Points, Size};

fn create(app: &mut Headless, name: &str, debt: bool) -> Result<(), String> {
    app.press("label:Assets")?;
    app.press("text:Add account")?;
    if debt {
        app.press("label:/^Account type, /")?;
        app.press("Consumer credit")?;
    }
    app.type_text("label:Account name", name)?;
    app.press("Create account")?;
    app.wait_for("Set opening balance")?;
    app.wait_for_gone("task-sheet", GONE)?;
    Ok(())
}
fn verify(app: &mut Headless, value: &str, debt: bool) -> Result<(), String> {
    app.wait_for_gone("task-sheet", GONE)?;
    app.press(if app.shows("Set opening balance") {
        "Set opening balance"
    } else {
        "Check balance"
    })?;
    app.wait_for(if debt {
        "label:Actual debt"
    } else {
        "label:Actual balance"
    })?;
    app.type_text(
        if debt {
            "label:Actual debt"
        } else {
            "label:Actual balance"
        },
        value,
    )?;
    app.press("Review difference")?;
    if debt {
        app.wait_for("Book debt")?;
    }
    app.press("Confirm balance")?;
    app.wait_for("Balance checked")?;
    // The receipt can appear while the balance sheet is still exiting.
    // Wait for it to release hit testing before interacting with the account.
    app.wait_for_gone("task-sheet", GONE)?;
    Ok(())
}

#[test]
fn accounts_balances_rename_and_net_worth_survive_restart() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(
        Some(dir.path()),
        account(true),
        Some(network(200, record_reply(vec![money_record("31.50")]))),
    );
    create(&mut app, "Cash", false)?;
    verify(&mut app, "1000.00", false)?;
    app.press("label:Back")?;
    app.press("label:New entry")?;
    app.type_text(
        "label:What would you like to record?",
        "Lunch 31.50 yuan from Cash",
    )?;
    app.press("label:Send")?;
    app.wait_for("Confirm and save")?;
    app.press("label:Close")?;
    assert!(!app.shows("text:/^Balance checked through/"));
    app.press("label:/^Cash, ¥1,000.00, Balance checked through/")?;
    app.press("label:Edit account")?;
    app.clear("label:Account name")?;
    app.type_text("label:Account name", "Wallet")?;
    app.press("Save changes")?;
    app.wait_for("Account updated")?;
    app.press("label:Back")?;
    app.wait_for("label:/^Wallet, ¥1,000.00/")?;
    // Creation stays available from the overview management menu.
    app.press("label:Manage")?;
    app.press("text:Add account")?;
    app.press("label:/^Account type, /")?;
    app.press("Consumer credit")?;
    app.type_text("label:Account name", "Card")?;
    app.press("Create account")?;
    verify(&mut app, "250.00", true)?;
    app.press("label:Back")?;
    app.wait_for("label:¥750.00")?;
    app.press("label:/^Asset changes/")?;
    app.press("Valuation basis")?;
    app.wait_for("Calculated from the ledger, dated prices and exchange rates.")?;
    app.press("label:Back")?;
    app.wait_for("label:¥750.00")?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let entries = repository::transactions(&c).unwrap();
    assert_eq!(assets::snapshot(&entries, today().0).net, 75000);
    assert!(journal::spending(&entries, today().0, today().0).is_empty());
    assert!(
        !repository::accounts(&c)
            .unwrap()
            .contains(&Account::parse("资产:Cash").unwrap())
    );
    assert_eq!(repository::balance_checks(&c).unwrap().len(), 2);
    let body: String = c
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let draft: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
    let naviwealth_app::domain::capture::Record::Money { draft: money, .. } = &draft.records[0]
    else {
        panic!("money draft")
    };
    assert_eq!(
        money.account.as_ref().unwrap().as_str(),
        "资产:Wallet",
        "rename also updates durable recognition references"
    );
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.press("label:Assets")?;
    app.wait_for("label:¥750.00")?;
    app.press("label:/^Card, ¥250.00/")?;
    // Reconfirming the same actual debt adds an observation, not fake spending.
    verify(&mut app, "250.00", true)?;
    assert_eq!(repository::transactions(&c).unwrap(), entries);
    assert_eq!(repository::balance_checks(&c).unwrap().len(), 3);
    Ok(())
}

#[test]
fn deactivated_account_keeps_its_balance_and_can_be_restored_from_manage() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    create(&mut app, "Reserve", false)?;
    verify(&mut app, "135.50", false)?;
    app.press("label:Edit account")?;
    app.press("Deactivate account")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.wait_for("Reactivate account")?;
    app.wait_for("Opening balance")?;
    app.press("label:Back")?;
    app.wait_for("label:Reserve, ¥135.50, Inactive")?;
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.press("label:Assets")?;
    app.press("label:Manage")?;
    app.press("task-sheet >> Inactive accounts")?;
    app.press("label:/^Reserve, ¥135.50/")?;
    app.press("Reactivate account")?;
    app.wait_for("Check balance")?;
    app.press("label:Back")?;
    app.wait_for("No inactive accounts")?;
    app.press("label:Back")?;
    app.wait_for("task-sheet >> Add account")?;
    assert!(!app.shows("text:Inactive accounts"));
    app.press("label:Close")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.wait_for("label:/^Reserve, ¥135.50, Balance checked through/")?;
    Ok(())
}

#[test]
fn new_account_keeps_its_opening_action_until_a_balance_is_recorded() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    create(&mut app, "Wallet", false)?;
    assert!(!app.shows("label:¥0.00"));
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.press("label:Assets")?;
    app.press("label:Wallet, Set opening balance")?;
    app.wait_for("label:Actual balance")?;
    app.press("Cancel")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.press("label:Back")?;
    app.wait_for("label:Wallet, Set opening balance")?;
    verify(&mut app, "0.00", false)?;
    app.press("label:Back")?;
    app.wait_for("label:/^Wallet, ¥0.00, Balance checked through/")?;
    assert!(!app.shows("Set opening balance"));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert_eq!(repository::balance_checks(&db).unwrap().len(), 1);
    assert!(repository::transactions(&db).unwrap().is_empty());
    app.press("label:/^Wallet, ¥0.00, Balance checked through/")?;
    app.press("label:Edit account")?;
    app.press("Deactivate account")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.press("label:Back")?;
    assert!(!app.shows("text:Wallet"));
    app.press("label:Manage")?;
    app.press("task-sheet >> Inactive accounts")?;
    app.wait_for("label:/^Wallet, ¥0.00,/")?;
    Ok(())
}

#[test]
fn failed_balance_confirmation_preserves_preview_and_can_retry_once() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    create(&mut app, "Cash", false)?;
    app.press("Set opening balance")?;
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.set_environment("large text with IME", |e| {
        e.font_scale = 1.3;
        e.keyboard_height = Points(280.0);
    })?;
    app.type_text("label:Actual balance", "500.01")?;
    app.press("Review difference")?;
    app.set_environment("IME dismissed", |e| e.keyboard_height = Points(0.0))?;
    let c = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(repository::transactions(&c).unwrap().is_empty());
    c.execute_batch("CREATE TRIGGER fail_post BEFORE INSERT ON finance_postings BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("Confirm balance")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(repository::transactions(&c).unwrap().is_empty());
    assert!(repository::balance_checks(&c).unwrap().is_empty());
    c.execute_batch("DROP TRIGGER fail_post").unwrap();
    app.press("Confirm balance")?;
    app.wait_for("Balance checked")?;
    // The receipt can appear while the balance sheet is still exiting.
    // Wait for it to release hit testing before interacting with the account.
    app.wait_for_gone("task-sheet", GONE)?;
    assert_eq!(repository::transactions(&c).unwrap().len(), 1);
    assert_eq!(repository::balance_checks(&c).unwrap().len(), 1);
    app.press("label:/^Opening balance, ¥500.01/")?;
    app.wait_for(
        "This entry comes from a balance check. Check the account again, or revoke this entry to recalculate its balance.",
    )?;
    Ok(())
}

#[test]
fn balance_entry_revocation_and_undo_keep_the_check_and_journal_together() -> Result<(), String> {
    use nsh_testing::DialogAnswer;
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    create(&mut app, "Cash", false)?;
    verify(&mut app, "500.00", false)?;
    app.wait_for_gone("task-sheet", GONE)?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let entries = repository::transactions(&db).unwrap();
    let checks = repository::balance_checks(&db).unwrap();
    app.press("label:/^Opening balance, ¥500.00/")?;
    app.on_dialog(|dialog| {
        assert_eq!(dialog.title.as_deref(), Some("Revoke this balance entry?"));
        let summary = dialog.message.as_deref().unwrap();
        assert!(summary.contains("Cash"));
        assert!(summary.contains("500.00"));
        DialogAnswer::Press("Cancel".into())
    });
    app.press("id:task-header >> label:Revoke balance entry")?;
    assert_eq!(repository::transactions(&db).unwrap(), entries);
    assert_eq!(repository::balance_checks(&db).unwrap(), checks);
    app.on_dialog(|_| DialogAnswer::Press("Revoke balance entry".into()));
    app.press("id:task-header >> label:Revoke balance entry")?;
    app.wait_for("Balance entry removed")?;
    assert!(repository::transactions(&db).unwrap().is_empty());
    assert!(repository::balance_checks(&db).unwrap().is_empty());
    assert!(
        repository::accounts(&db)
            .unwrap()
            .contains(&Account::parse("资产:Cash").unwrap())
    );
    app.press("Undo")?;
    app.wait_for("label:/^Opening balance, ¥500.00/")?;
    assert_eq!(repository::transactions(&db).unwrap(), entries);
    assert_eq!(repository::balance_checks(&db).unwrap(), checks);
    Ok(())
}

#[test]
fn direct_creation_returns_to_the_empty_overview() -> Result<(), String> {
    use nsh_testing::DialogAnswer;
    let (mut app, _) = start(Vec::new(), None);
    app.press("label:Assets")?;
    app.press("text:Add account")?;
    app.type_text("label:Account name", "Wallet")?;
    app.on_dialog(|_| DialogAnswer::Press("Keep editing".into()));
    app.press("task-header >> Back")?;
    assert_eq!(
        app.screen().input_text("label:Account name")?,
        Some("Wallet")
    );
    app.on_dialog(|_| DialogAnswer::Press("Discard".into()));
    app.press("task-header >> Back")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.press("text:Add holding")?;
    app.wait_for("security-search")?;
    app.back()?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.press("label:Manage")?;
    app.wait_for("task-sheet >> Add account")?;
    assert!(!app.shows("text:Closed holdings"));
    app.press("task-sheet >> Prices & rates")?;
    app.wait_for("CNY per US dollar")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.back()?;
    app.wait_for("task-sheet >> Add account")?;
    Ok(())
}

#[test]
fn manage_back_keeps_one_sheet_and_opening_balance_stays_on_the_account_row() -> Result<(), String>
{
    use nsh_testing::DialogAnswer;
    let (mut app, _) = start(Vec::new(), None);
    app.press("label:Assets")?;
    app.press("label:Manage")?;
    let sheet = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("task-sheet"))
        .unwrap()
        .id;
    app.press("task-sheet >> Add account")?;
    assert_eq!(app.screen().count("task-sheet")?, 1);
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.set_environment("IME and large text", |e| {
        e.font_scale = 1.3;
        e.keyboard_height = Points(280.0);
    })?;
    // Currency and kind alone are meaningful draft changes.
    app.press("label:Currency")?;
    app.press("USD")?;
    app.press("label:/^Account type, /")?;
    app.press("Consumer credit")?;
    app.on_dialog(|_| DialogAnswer::Press("Keep editing".into()));
    app.back()?;
    app.wait_for("Create account")?;
    assert!(app.shows("USD"));
    app.type_text("label:Account name", "Card")?;
    for id in ["task-header", "task-actions"] {
        let node = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some(id))
            .unwrap();
        assert!(node.bounds.origin.y.0 >= 0.0, "{id} stays on screen");
        assert!(
            node.bounds.origin.y.0 + node.bounds.size.height.0 <= 360.5,
            "{id} stays above the IME: {:?}",
            node.bounds
        );
    }
    app.on_dialog(|_| DialogAnswer::Press("Discard".into()));
    app.press("Back")?;
    app.wait_for("task-sheet >> Add holding")?;
    assert_eq!(
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("task-sheet"))
            .unwrap()
            .id,
        sheet,
        "Back replaces a frame in the existing sheet"
    );
    app.press("task-sheet >> Add holding")?;
    app.wait_for("security-search")?;
    app.back()?;
    app.wait_for("task-sheet >> Add account")?;
    app.back()?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.set_environment("IME dismissed", |e| {
        e.font_scale = 1.0;
        e.keyboard_height = Points(0.0);
        e.reduce_motion = true;
    })?;
    app.press("Manage")?;
    app.press("task-sheet >> Add account")?;
    assert_eq!(app.screen().input_text("label:Account name")?, Some(""));
    app.type_text("label:Account name", "Wallet")?;
    app.press("Create account")?;
    app.wait_for("Account added")?;
    app.wait_for_gone("task-sheet", GONE)?;
    app.wait_for("label:Manage")?;
    app.press("Set opening balance")?;
    app.wait_for("label:Actual balance")?;
    Ok(())
}

#[test]
fn saving_resets_the_task_and_a_swipe_leaves_the_whole_task() -> Result<(), String> {
    use nsh_core::{geometry::Point, time::Clock};
    use nsh_testing::DialogAnswer;
    use std::time::{Duration, SystemTime};
    let motion = Duration::from_millis(500);
    let mut config = EngineConfig::new(Root::of::<App>());
    config.clock = Clock::manual(SystemTime::now());
    config.storage = Some(MemoryStorage::new(Vec::new()));
    let mut app = Headless::start(config).expect("the app starts");
    app.wait_for("label:New entry")?;
    app.press("label:Assets")?;
    app.press("label:Manage")?;
    app.run_for(motion)?;
    app.press("task-sheet >> Add account")?;
    app.type_text("label:Account name", "Wallet")?;
    app.press("Create account")?;
    app.run_for(motion)?;
    assert_eq!(app.screen().count("task-sheet")?, 0);
    // The saved panel does not linger as task state: Manage opens its menu.
    app.press("label:Manage")?;
    app.run_for(motion)?;
    app.wait_for("task-sheet >> Add holding")?;
    app.back()?;
    app.run_for(motion)?;
    assert_eq!(app.screen().count("task-sheet")?, 0);

    // A swipe from a panel leaves the task instead of bouncing to the menu.
    app.press("label:Manage")?;
    app.run_for(motion)?;
    app.press("task-sheet >> Add account")?;
    app.drag("task-sheet", Point::new(Points(0.0), Points(500.0)))?;
    app.run_for(motion)?;
    assert_eq!(
        app.screen().count("task-sheet")?,
        0,
        "a clean panel leaves with the swipe"
    );

    // A dirty panel asks first; keeping the edit keeps the panel.
    app.press("label:Manage")?;
    app.run_for(motion)?;
    app.press("task-sheet >> Add account")?;
    app.type_text("label:Account name", "Card")?;
    app.on_dialog(|_| DialogAnswer::Press("Keep editing".into()));
    app.drag("task-sheet", Point::new(Points(0.0), Points(500.0)))?;
    app.run_for(motion)?;
    assert!(app.shows("Create account"), "the edit is kept");
    app.on_dialog(|_| DialogAnswer::Press("Discard".into()));
    app.drag("task-sheet", Point::new(Points(0.0), Points(500.0)))?;
    app.run_for(motion)?;
    assert_eq!(
        app.screen().count("task-sheet")?,
        0,
        "discarding leaves the whole task"
    );
    Ok(())
}

#[test]
fn a_showing_keyboard_lifts_a_task_sheet_without_resizing_it() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.set_viewport(Size::new(Points(390.0), Points(844.0)))?;
    app.set_environment("still", |e| e.reduce_motion = true)?;
    app.press("label:Assets")?;
    app.press("label:Manage")?;
    app.press("task-sheet >> Add holding")?;
    app.wait_for("security-search")?;
    let frame = |app: &Headless| {
        app.screen()
            .layout_nodes()
            .into_iter()
            .find(|n| n.test_id.as_deref() == Some("task-sheet"))
            .map(|n| n.bounds)
            .unwrap()
    };
    let before = frame(&app);
    // Within the planned height (38% of the window before any keyboard).
    app.set_environment("IME", |e| e.keyboard_height = Points(300.0))?;
    let after = frame(&app);
    assert_eq!(after.size, before.size, "the panel keeps its size");
    assert!(
        after.origin.y.0 + after.size.height.0 <= 844.0 - 300.0 + 0.5,
        "the sheet sits above the keyboard: {after:?}"
    );
    assert!(after.origin.y.0 >= 0.0, "and stays on screen: {after:?}");
    Ok(())
}

#[test]
fn narrow_large_text_keeps_account_suffixes_and_foreign_balances_readable() -> Result<(), String> {
    use navi_finance::{account::AccountKind, currency::Currency};
    use nsh_core::{ApproxTextEngine, TextEngine};
    let dir = tempfile::tempdir().unwrap();
    let (app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    drop(app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let names = [
        "Brokerage settlement account 1234",
        "Brokerage settlement account 5678",
    ];
    for (index, name) in names.iter().enumerate() {
        let account = Account::new_in(AccountKind::Assets, name, Currency::USD).unwrap();
        repository::create_account(&db, &account).unwrap();
        let entry = journal::Entry {
            id: name.to_string(),
            at: today().0.at(12, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: journal::Source::Manual,
        };
        repository::save(
            &db,
            &journal::opening(entry, &account, 123456789 + index as i64).unwrap(),
        )
        .unwrap();
    }
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.set_environment("large text", |env| env.font_scale = 1.5)?;
    app.press("label:Assets")?;
    let nodes = app.screen().layout_nodes();
    for name in names {
        let label = format!("{name} · USD");
        let node = nodes
            .iter()
            .find(|n| n.text.as_ref().is_some_and(|t| t.text.text == label))
            .unwrap();
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
    for value in ["USD 1,234,567.89", "USD 1,234,567.90"] {
        let node = nodes
            .iter()
            .find(|n| {
                n.test_id.as_deref() == Some("asset-row-value")
                    && n.text.as_ref().is_some_and(|t| t.text.text == value)
            })
            .unwrap();
        assert!(
            node.bounds.size.width.0 > 0.0
                && node.bounds.origin.x.0 + node.bounds.size.width.0 <= 360.0,
            "{value}: {:?}",
            node.bounds
        );
    }
    Ok(())
}
