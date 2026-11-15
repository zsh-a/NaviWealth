//! Owner-visible account lifecycle, balance confirmation and storage recovery.
mod common;
use common::*;
use finance_core::{account::Account, assets, journal, repository};
use nsh_core::geometry::{Points, Size};

fn create(app: &mut Headless, name: &str, debt: bool) -> Result<(), String> {
    app.press("label:Assets")?;
    app.press("text:Add account")?;
    if debt {
        app.press("Credit / debt")?;
    }
    app.type_text("label:Account name", name)?;
    app.press("Create account")?;
    app.wait_for("Check balance")?;
    Ok(())
}
fn verify(app: &mut Headless, value: &str, debt: bool) -> Result<(), String> {
    app.press("Check balance")?;
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
    app.press("Create draft")?;
    app.wait_for("Confirm and save")?;
    app.press("Done")?;
    app.press("label:/^Cash, 1000.00 CNY/")?;
    app.press("label:Rename account")?;
    app.clear("label:Account name")?;
    app.type_text("label:Account name", "Wallet")?;
    app.press("Save name")?;
    app.wait_for("Account renamed")?;
    app.press("label:Back")?;
    app.wait_for("label:/^Wallet, 1000.00 CNY/")?;
    // Creation stays available from the overview management menu.
    app.press("text:Manage")?;
    app.press("text:Add account")?;
    app.press("Credit / debt")?;
    app.type_text("label:Account name", "Card")?;
    app.press("Create account")?;
    verify(&mut app, "250.00", true)?;
    app.press("label:Back")?;
    app.wait_for("label:¥750.00")?;
    app.press("label:Asset changes")?;
    app.wait_for("Changes include added records, balance adjustments and recorded prices. They are not investment returns.")?;
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
    let draft: nsh_app_naviwealth_health::domain::capture::Draft =
        serde_json::from_str(&body).unwrap();
    let nsh_app_naviwealth_health::domain::capture::Record::Money { draft: money, .. } =
        &draft.records[0]
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
    app.press("label:/^Card, 250.00 CNY/")?;
    // Reconfirming the same actual debt adds an observation, not fake spending.
    verify(&mut app, "250.00", true)?;
    assert_eq!(repository::transactions(&c).unwrap(), entries);
    assert_eq!(repository::balance_checks(&c).unwrap().len(), 3);
    Ok(())
}

#[test]
fn failed_balance_confirmation_preserves_preview_and_can_retry_once() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    create(&mut app, "Cash", false)?;
    app.press("Check balance")?;
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
    assert_eq!(repository::transactions(&c).unwrap().len(), 1);
    assert_eq!(repository::balance_checks(&c).unwrap().len(), 1);
    app.press("label:/^Opening balance, 500.01 CNY/")?;
    app.wait_for(
        "This is a confirmed balance entry. Check the account balance again to correct it.",
    )?;
    Ok(())
}
