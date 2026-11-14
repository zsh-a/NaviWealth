//! High-value capture contracts: text corrections, confirmation atomicity,
//! storage failure/retry and untrusted model output. No layout snapshots.
mod common;
use common::*;
use nsh_testing::StubRoute;
use std::sync::atomic::{AtomicUsize, Ordering};

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
    app.wait_for("Records saved")?;
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
    app.press("Done")?;
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
