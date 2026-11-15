//! High-value capture contracts: text corrections, confirmation atomicity,
//! storage failure/retry and untrusted model output. No layout snapshots.
mod common;
use common::*;
use nsh_testing::StubRoute;
use std::sync::atomic::{AtomicUsize, Ordering};

#[test]
fn transfer_completion_excludes_its_source_and_view_reveals_a_multi_day_batch() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let mut transfer = money_record("20.00");
    transfer["money"]["kind"] = json!("transfer");
    transfer["money"]["account"] = Value::Null;
    transfer["money"]["category"] = Value::Null;
    transfer["money"]["payee"] = json!("");
    let weight = json!({"kind":"weight","day":today().0.yesterday().unwrap().to_string(),
        "weight_kg":74.2,"money":null,"meal":null,"slot":null});
    let stub = network(200, record_reply(vec![transfer, weight]));
    let (mut app, _) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    app.press("label:Assets")?;
    for name in ["Cash", "Bank"] {
        if name == "Bank" {
            app.press("Manage")?;
        }
        app.press("Add account")?;
        app.type_text("label:Account name", name)?;
        app.press("Create account")?;
        app.press("label:Back")?;
    }
    app.press("label:Records")?;
    app.press("Meals")?;
    app.press("label:New entry")?;
    app.set_viewport(nsh_core::geometry::Size::new(
        nsh_core::geometry::Points(360.0),
        nsh_core::geometry::Points(640.0),
    ))?;
    app.set_environment("small phone with IME", |e| {
        e.font_scale = 1.3;
        e.keyboard_height = nsh_core::geometry::Points(280.0);
    })?;
    app.type_text(
        "label:What would you like to record?",
        "Transfer 20 yuan and yesterday's weight 74.2 kg",
    )?;
    app.press("Create draft")?;
    app.set_environment("IME dismissed", |e| {
        e.keyboard_height = nsh_core::geometry::Points(0.0)
    })?;
    app.wait_for("Which account was used?")?;
    app.press("label:From account, Choose account")?;
    app.press("label:Cash")?;
    app.press("label:To account, Choose account")?;
    assert!(
        !app.shows("label:Cash"),
        "transfer destination excludes its source"
    );
    app.press("label:Bank")?;
    app.press("Confirm and save (2)")?;
    app.wait_for("Saved 2 records")?;
    app.press("View")?;
    app.wait_for("text:74.2 kg")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let entries = finance_core::repository::transactions(&db).unwrap();
    assert_eq!(entries.len(), 1);
    assert!(entries[0].validate().is_ok());
    let balances = finance_core::journal::balances(&entries);
    assert_eq!(
        balances[&finance_core::account::Account::parse("资产:Cash").unwrap()],
        -2000
    );
    assert_eq!(
        balances[&finance_core::account::Account::parse("资产:Bank").unwrap()],
        2000
    );
    assert_eq!(stub.requests().len(), 1);
    Ok(())
}

#[test]
fn account_completion_is_local_durable_and_never_posts_before_confirmation() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let mut money = money_record("32.00");
    money["money"]["account"] = Value::Null;
    let stub = network(200, record_reply(vec![money]));
    let (mut app, storage) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    app.press("label:Assets")?;
    app.press("Add account")?;
    app.type_text("label:Account name", "Cash")?;
    app.press("Create account")?;
    app.press("label:Back")?;
    app.press("label:New entry")?;
    app.type_text("label:What would you like to record?", "Lunch 32 yuan")?;
    app.press("Create draft")?;
    app.wait_for("Which account was used?")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_draft BEFORE UPDATE ON capture_drafts BEGIN SELECT RAISE(ABORT,'disk failure'); END;").unwrap();
    app.press("label:Account, Choose account")?;
    app.press("label:Cash")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(
        finance_core::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    let body: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let kept: nsh_app_naviwealth_health::domain::capture::Draft =
        serde_json::from_str(&body).unwrap();
    let nsh_app_naviwealth_health::domain::capture::Record::Money { draft, .. } = &kept.records[0]
    else {
        panic!("money draft");
    };
    assert!(
        draft.account.is_none(),
        "failed selection did not change the stored draft"
    );
    db.execute_batch("DROP TRIGGER reject_draft").unwrap();
    app.press("label:Cash")?;
    app.wait_for("label:Account, Cash")?;
    assert!(app.screen().enabled("Confirm and save")?);
    app.press("label:Close")?;
    app.wait_for("Draft kept; no records saved")?;
    assert_eq!(stub.requests().len(), 1, "account selection never calls AI");
    assert!(
        finance_core::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    drop(app);

    let quiet = Arc::new(StubNetwork::new([] as [(String, StubResponse); 0]));
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(quiet.clone()),
    );
    // View must reveal the saved transaction even after a meal-only filter.
    app.press("label:Records")?;
    app.press("Meals")?;
    app.press("label:Review records")?;
    app.wait_for("label:Account, Cash")?;
    app.press("Confirm and save")?;
    app.wait_for("Saved Spending · ¥32.00")?;
    app.press("View")?;
    app.wait_for("label:/^Lunch shop, −32.00 CNY/")?;
    assert_eq!(
        finance_core::repository::transactions(&db).unwrap().len(),
        1
    );
    assert!(quiet.requests().is_empty());
    Ok(())
}

#[test]
fn natural_correction_then_batch_confirmation_is_atomic_and_survives_restart() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let calls = Arc::new(AtomicUsize::new(0));
    let calls_in = calls.clone();
    let stub = Arc::new(StubNetwork::new([(
        MESSAGES.into(),
        StubRoute::Handler(Arc::new(move |_, reply| {
            let index = calls_in.fetch_add(1, Ordering::SeqCst);
            let mut money = money_record(if index == 0 { "31.50" } else { "32.00" });
            if index == 0 {
                money["money"]["account"] = Value::Null;
            }
            reply.send(response(200,record_reply(vec![money,meal_record(),
            json!({"kind":"weight","day":today().to_string(),"weight_kg":74.2,"money":null,"meal":null,"slot":null})])));
        })),
    )]));
    let (mut app, storage) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    app.press("label:New entry")?;
    app.type_text(
        "label:What would you like to record?",
        "Record lunch spending, the meal and today's weight 74.2 kg",
    )?;
    app.press("Create draft")?;
    app.wait_for("Which account was used?")?;
    assert!(!app.screen().enabled("text:/^Confirm and save/")?);
    app.type_text(
        "label:What would you like to record?",
        "Use Cash; the amount is 32 yuan",
    )?;
    app.press("Update draft")?;
    app.wait_for("text:¥32.00")?;
    assert!(app.screen().enabled("text:/^Confirm and save/")?);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(
        finance_core::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    assert!(stored_meals(dir.path()).is_empty());
    db.execute_batch("CREATE TRIGGER reject_meal BEFORE INSERT ON meals BEGIN SELECT RAISE(ABORT,'disk failure'); END;").unwrap();
    app.press("text:/^Confirm and save/")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(
        finance_core::repository::transactions(&db)
            .unwrap()
            .is_empty(),
        "earlier writes rolled back"
    );
    assert!(stored_meals(dir.path()).is_empty());
    assert_eq!(
        db.query_row("SELECT COUNT(*) FROM capture_drafts", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        1
    );
    assert!(
        !finance_core::repository::accounts(&db)
            .unwrap()
            .iter()
            .any(|a| a.name() == "Cash")
    );
    db.execute_batch("DROP TRIGGER reject_meal").unwrap();
    app.press("text:/^Confirm and save/")?;
    app.wait_for("Saved 3 records")?;
    app.press("label:New entry")?;
    assert!(
        !app.shows("text:View"),
        "an old receipt cannot navigate behind a new draft"
    );
    app.press("label:Close")?;
    let entries = finance_core::repository::transactions(&db).unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].postings[0].amount, 3200);
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert_eq!(
        db.query_row("SELECT kg FROM weights", [], |r| r.get::<_, f64>(0))
            .unwrap(),
        74.2
    );
    assert_eq!(
        db.query_row("SELECT COUNT(*) FROM capture_drafts", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
    assert_eq!(
        calls.load(Ordering::SeqCst),
        2,
        "save and retry must not call the model"
    );
    let request = &stub.requests()[1];
    let nsh_core::platform::HttpBody::Bytes(bytes) = &request.body else {
        panic!("JSON request")
    };
    let body = String::from_utf8_lossy(bytes);
    assert!(body.contains("previous_draft") && body.contains("Use Cash"));
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.wait_for("label:/^Lunch shop, −32.00 CNY/")?;
    assert_eq!(
        finance_core::repository::transactions(&db).unwrap(),
        entries
    );
    Ok(())
}

#[test]
fn interrupted_text_is_kept_and_malformed_model_money_cannot_be_saved() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let mut bad = money_record("1.005");
    bad["money"]["currency"] = json!("USD");
    let (mut app, storage) = start_in(
        Some(dir.path()),
        account(true),
        Some(network(200, record_reply(vec![bad.clone()]))),
    );
    app.press("label:New entry")?;
    app.type_text("label:What would you like to record?", "Lunch 32 yuan")?;
    app.press("label:Close")?;
    app.wait_for("label:What would you like to record?")?;
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(network(200, record_reply(vec![bad]))),
    );
    app.press("label:What would you like to record?")?;
    app.press("Create draft")?;
    app.wait_for("Open settings…")?;
    assert!(!app.shows("text:/^Confirm and save/"));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(
        finance_core::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    Ok(())
}
