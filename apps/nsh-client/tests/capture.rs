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
        app.wait_for("Account added")?;
    }
    app.press("label:Records")?;
    app.press("Meals")?;
    app.press("label:New entry")?;
    // Keep this account/batch contract on the normal viewport. The compact
    // composer test below owns small-screen/IME coverage; simulating an IME
    // here leaves native sheet hit-test geometry stale during account picking.
    app.type_text(
        "label:What would you like to record?",
        "Transfer 20 yuan and yesterday's weight 74.2 kg",
    )?;
    app.press("label:Send")?;
    app.wait_for("Which account was used?")?;
    app.press("label:From account, Choose account")?;
    app.press("label:Cash")?;
    app.wait_for("label:From account, Cash")?;
    app.press("label:To account, Choose account")?;
    assert!(
        !app.shows("label:Cash"),
        "transfer destination excludes its source"
    );
    app.press("label:Bank")?;
    app.wait_for("label:To account, Bank")?;
    app.press("Confirm and save (2)")?;
    app.wait_for("Saved 2 records")?;
    app.press("View")?;
    app.wait_for("text:74.2 kg")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let entries = navi_finance::repository::transactions(&db).unwrap();
    assert_eq!(entries.len(), 1);
    assert!(entries[0].validate().is_ok());
    let balances = navi_finance::journal::balances(&entries);
    assert_eq!(
        balances[&navi_finance::account::Account::parse("资产:Cash").unwrap()],
        -2000
    );
    assert_eq!(
        balances[&navi_finance::account::Account::parse("资产:Bank").unwrap()],
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
    app.wait_for("Account added")?;
    app.press("label:New entry")?;
    app.type_text("label:What would you like to record?", "Lunch 32 yuan")?;
    app.press("label:Send")?;
    app.wait_for("Which account was used?")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_draft BEFORE UPDATE ON capture_drafts BEGIN SELECT RAISE(ABORT,'disk failure'); END;").unwrap();
    app.press("label:Account, Choose account")?;
    app.press("label:Cash")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    let body: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let kept: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
    let naviwealth_app::domain::capture::Record::Money { draft, .. } = &kept.records[0] else {
        panic!("money draft");
    };
    assert!(
        draft.account.is_none(),
        "failed selection did not change the stored draft"
    );
    db.execute_batch("DROP TRIGGER reject_draft").unwrap();
    app.press("label:Cash")?;
    app.wait_for("label:Account, Cash")?;
    app.press("Edit amount")?;
    app.clear("label:Amount")?;
    app.type_text("label:Amount", "35.05")?;
    app.press("Done")?;
    app.wait_for("text:¥35.05")?;
    assert!(app.screen().enabled("Confirm and save")?);
    app.press("label:Close")?;
    app.wait_for("Draft kept; no records saved")?;
    assert_eq!(stub.requests().len(), 1, "account selection never calls AI");
    assert!(
        navi_finance::repository::transactions(&db)
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
    app.wait_for("Saved Spending · ¥35.05")?;
    app.press("View")?;
    app.wait_for("label:/^Lunch shop, −¥35.05/")?;
    assert_eq!(
        navi_finance::repository::transactions(&db).unwrap().len(),
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
    app.press("label:Send")?;
    app.wait_for("Which account was used?")?;
    assert!(!app.shows("text:/^Confirm and save/"));
    app.press("Add details")?;
    app.type_text(
        "label:What would you like to record?",
        "Use Cash; the amount is 32 yuan",
    )?;
    app.press("label:Send")?;
    app.wait_for("text:¥32.00")?;
    app.press("Edit meal name")?;
    app.clear("label:Name")?;
    app.type_text("label:Name", "Lunch noodles")?;
    app.press("Done")?;
    app.wait_for("text:Lunch noodles")?;
    app.press("Edit weight")?;
    app.clear("label:Weight")?;
    app.type_text("label:Weight", "74.3")?;
    app.press("Done")?;
    app.wait_for("text:74.3 kg")?;
    assert!(app.screen().enabled("text:/^Confirm and save/")?);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    assert!(stored_meals(dir.path()).is_empty());
    db.execute_batch("CREATE TRIGGER reject_meal BEFORE INSERT ON meals BEGIN SELECT RAISE(ABORT,'disk failure'); END;").unwrap();
    app.press("text:/^Confirm and save/")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(
        navi_finance::repository::transactions(&db)
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
        !navi_finance::repository::accounts(&db)
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
    let entries = navi_finance::repository::transactions(&db).unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].postings[0].amount, 3200);
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert_eq!(
        db.query_row("SELECT kg FROM weights", [], |r| r.get::<_, f64>(0))
            .unwrap(),
        74.3
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
    assert!(
        body.contains("assistant") && body.contains("Use Cash"),
        "the follow-up replays the thread: the earlier reply as an assistant turn and the new message"
    );
    drop(app);
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        None,
    );
    app.wait_for("label:/^Lunch shop, −¥32.00/")?;
    assert_eq!(
        navi_finance::repository::transactions(&db).unwrap(),
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
    app.press("label:Send")?;
    app.wait_for("Open settings…")?;
    assert!(!app.shows("text:/^Confirm and save/"));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    Ok(())
}

#[test]
fn compact_photo_and_text_composer_keeps_the_same_draft_across_back_and_reopen()
-> Result<(), String> {
    use nsh_core::geometry::{Points, Size};
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), account(true), None);
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.set_environment("small phone with IME", |e| {
        e.font_scale = 1.3;
        e.keyboard_height = Points(280.0);
    })?;
    app.press("label:New entry")?;
    app.type_text(
        "label:What would you like to record?",
        "Lunch with a receipt",
    )?;
    picks_a_photo(&mut app);
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    let action = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("task-actions"))
        .unwrap();
    assert!(
        action.bounds.origin.y.0 + action.bounds.size.height.0 <= 360.5,
        "recognition and photo actions stay above the IME: {:?}",
        action.bounds
    );
    assert!(app.screen().enabled("label:Send")?);
    app.back()?;
    app.wait_for("task-sheet")?;
    app.set_environment("IME dismissed", |e| e.keyboard_height = Points(0.0))?;
    app.back()?;
    app.wait_for_gone("task-sheet", GONE)?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let before: (String, String) = db
        .query_row("SELECT id,body FROM capture_drafts", [], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })
        .unwrap();
    let kept: naviwealth_app::domain::capture::Draft = serde_json::from_str(&before.1).unwrap();
    assert_eq!(kept.input, "Lunch with a receipt");
    assert!(kept.photo.is_some());
    app.set_environment("IME dismissed", |e| e.keyboard_height = Points(0.0))?;
    app.press("label:What would you like to record?")?;
    assert_eq!(
        app.screen()
            .input_text("label:What would you like to record?")?,
        Some("Lunch with a receipt")
    );
    app.wait_for("Remove image")?;
    app.press("label:Close")?;
    app.wait_for_gone("task-sheet", GONE)?;
    let after: (String, String) = db
        .query_row("SELECT id,body FROM capture_drafts", [], |r| {
            Ok((r.get(0)?, r.get(1)?))
        })
        .unwrap();
    assert_eq!(
        before, after,
        "reopening and closing preserves the durable draft identity and data"
    );
    assert_eq!(
        db.query_row("SELECT COUNT(*) FROM capture_drafts", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        1
    );
    Ok(())
}

fn ask_reply(call_id: &str, question: &str, options: Vec<Value>) -> Value {
    json!({"model":"test-model","stop_reason":"tool_use","content":[{
        "type":"tool_use","id":call_id,"name":"ask_user","input":{"questions":[{
            "id":"decision","text":question,"reason":"This decision changes the proposed record.",
            "required":true,"options":options
        }]}
    }]})
}

#[test]
fn thread_questions_answer_by_tap_and_reopen_keeps_the_conversation() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let calls = Arc::new(AtomicUsize::new(0));
    let calls_in = calls.clone();
    let stub = Arc::new(StubNetwork::new([(
        MESSAGES.into(),
        StubRoute::Handler(Arc::new(move |_, reply| {
            let index = calls_in.fetch_add(1, Ordering::SeqCst);
            let body = if index == 0 {
                ask_reply(
                    "call-account",
                    "Which account was used?",
                    vec![
                        json!({"id":"cash","label":"Cash","description":"Pay from your cash account"}),
                        json!({"id":"bank","label":"Bank","description":"Pay from your bank account"}),
                    ],
                )
            } else {
                record_reply(vec![money_record("32.00")])
            };
            reply.send(response(200, body));
        })),
    )]));
    let (mut app, storage) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    app.set_viewport(nsh_core::geometry::Size::new(
        nsh_core::geometry::Points(390.0),
        nsh_core::geometry::Points(844.0),
    ))?;
    app.press("label:New entry")?;
    app.type_text("label:What would you like to record?", "Lunch 32 yuan")?;
    app.press("label:Send")?;
    app.wait_for("Which account was used?")?;
    app.wait_for("text:Bank")?;
    let sheet = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some("task-sheet"))
        .unwrap();
    assert!(
        sheet.bounds.size.height.0 > 700.0,
        "review uses the available phone height"
    );
    app.wait_for("text:Submit answers")?;
    assert!(
        !app.screen().enabled("Submit answers")?,
        "required choice is never preselected"
    );
    assert!(
        !app.shows("label:Attach image"),
        "reply tools are collapsed while choosing"
    );
    app.press("label:Bank")?;
    app.press("label:Cash")?;
    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "selection and changing it stay local"
    );
    assert!(app.screen().enabled("Submit answers")?);
    assert!(!app.shows("text:/^Confirm and save/"));
    app.press("label:Close")?;
    app.wait_for("Draft kept; no records saved")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let body: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let kept: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
    assert_eq!(kept.transcript.len(), 2, "pending call remains suspended");
    assert_eq!(kept.answers.len(), 1);
    assert_eq!(kept.answers[0].option_id.as_deref(), Some("cash"));
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    drop(app);

    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(stub.clone()),
    );
    app.press("label:Review records")?;
    app.wait_for("Which account was used?")?;
    assert!(
        app.screen().enabled("Submit answers")?,
        "staged selection survives restart"
    );
    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "reopening never resumes the model"
    );
    app.press("Submit answers")?;
    app.wait_for("text:¥32.00")?;
    assert!(app.screen().enabled("text:/^Confirm and save/")?);
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    let body: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let kept: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
    assert_eq!(kept.transcript.len(), 4);
    assert!(kept.answers.is_empty());
    assert!(
        matches!(&kept.transcript[2], naviwealth_app::domain::capture::Turn::ToolAnswer {call_id,..} if call_id == "call-account")
    );
    let requests = stub.requests();
    let nsh_core::platform::HttpBody::Bytes(bytes) = &requests[1].body else {
        panic!("JSON request")
    };
    let body: Value = serde_json::from_slice(bytes).unwrap();
    assert_eq!(body["tools"][0]["name"], "ask_user");
    assert_eq!(body["messages"][1]["content"][0]["type"], "tool_use");
    let result = &body["messages"][2]["content"][0];
    assert_eq!(result["type"], "tool_result");
    assert_eq!(result["tool_use_id"], "call-account");
    let answer: Value = serde_json::from_str(result["content"].as_str().unwrap()).unwrap();
    assert_eq!(answer["answers"][0]["question_id"], "decision");
    assert_eq!(answer["answers"][0]["option_id"], "cash");
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    app.press("Confirm and save")?;
    app.wait_for("Saved Spending · ¥32.00")?;
    assert_eq!(
        navi_finance::repository::transactions(&db).unwrap().len(),
        1
    );
    Ok(())
}

#[test]
fn image_only_followup_replays_each_view_in_its_original_turn_after_restart() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let question = "Is this another view of the same meal?";
    let first = network(200, ask_reply("call-image", question, Vec::new()));
    let (mut app, storage) = start_in(Some(dir.path()), account(true), Some(first.clone()));
    app.press("label:New entry")?;
    picks_a_photo(&mut app);
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    app.press("label:Send")?;
    app.wait_for(question)?;
    assert!(
        !app.shows("text:/^Confirm and save/"),
        "unresolved image relationships block saving"
    );
    assert!(stored_meals(dir.path()).is_empty());
    app.press("label:Close")?;
    app.wait_for("Draft kept; no records saved")?;
    drop(app);

    let second = network(200, record_reply(vec![meal_record()]));
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(second.clone()),
    );
    app.press("label:Review records")?;
    app.wait_for(question)?;
    let mut detail = Cursor::new(Vec::new());
    RgbImage::from_pixel(48, 128, image::Rgb([240, 240, 240]))
        .write_to(&mut detail, ImageFormat::Png)
        .unwrap();
    app.on_pick(move |_| {
        vec![PickedFile::new(
            "label.png",
            "image/png",
            ImageData::new(detail.get_ref().clone()),
        )]
    });
    app.press("Add details")?;
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    assert!(
        app.screen().enabled("Submit answers")?,
        "an image-only answer can be sent"
    );
    app.press("Submit answers")?;
    app.wait_for("Confirm and save")?;
    assert!(stored_meals(dir.path()).is_empty());

    let requests = second.requests();
    assert_eq!(requests.len(), 1);
    let nsh_core::platform::HttpBody::Bytes(bytes) = &requests[0].body else {
        panic!("JSON request")
    };
    let body: Value = serde_json::from_slice(bytes).unwrap();
    let messages = body["messages"].as_array().unwrap();
    assert_eq!(
        messages.len(),
        4,
        "first image, assistant tool call, tool result, supporting image"
    );
    assert_eq!(messages[0]["role"], "user");
    assert_eq!(messages[1]["role"], "assistant");
    assert_eq!(messages[2]["role"], "user");
    assert_eq!(messages[2]["content"][0]["type"], "tool_result");
    assert_eq!(messages[2]["content"][0]["tool_use_id"], "call-image");
    assert_eq!(messages[3]["role"], "user");
    for index in [0, 3] {
        let images: Vec<_> = messages[index]["content"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|block| block["type"] == "image")
            .collect();
        assert_eq!(images.len(), 1, "each image belongs to its own owner turn");
        assert_eq!(images[0]["source"]["media_type"], "image/png");
    }
    let image_data = |message: &Value| {
        message["content"]
            .as_array()
            .unwrap()
            .iter()
            .find(|block| block["type"] == "image")
            .unwrap()["source"]["data"]
            .clone()
    };
    assert_ne!(
        image_data(&messages[0]),
        image_data(&messages[3]),
        "the later view must not replace the original image bytes"
    );
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let body: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let kept: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
    assert_eq!(
        kept.image_names().len(),
        2,
        "new attachments never overwrite the earlier view"
    );
    assert!(!kept.has_staged_images());
    app.press("Confirm and save")?;
    app.wait_for_gone("task-sheet", GONE)?;
    assert_eq!(
        stored_meals(dir.path()).len(),
        1,
        "two views produce one confirmed meal"
    );
    Ok(())
}

#[test]
fn failed_tool_continuation_retries_the_submitted_answer_without_duplicate_turns()
-> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let calls = Arc::new(AtomicUsize::new(0));
    let calls_in = calls.clone();
    let stub = Arc::new(StubNetwork::new([(
        MESSAGES.into(),
        StubRoute::Handler(Arc::new(move |_, reply| {
            match calls_in.fetch_add(1, Ordering::SeqCst) {
                0 => reply.send(response(200, ask_reply("call-retry", "Which account was used?", vec![
                    json!({"id":"cash","label":"Cash","description":"Cash account"})
                ]))),
                1 => reply.send(response(400,json!({"error":{"type":"invalid_request_error","message":"Temporary test rejection"}}))),
                _ => reply.send(response(200, record_reply(vec![money_record("32.00")]))),
            }
        })),
    )]));
    let (mut app, _) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    app.press("label:New entry")?;
    app.type_text("label:What would you like to record?", "Lunch 32 yuan")?;
    app.press("label:Send")?;
    app.wait_for("Which account was used?")?;
    app.press("label:Cash")?;
    app.press("Submit answers")?;
    app.wait_for("Open settings…")?;
    assert!(!app.shows("text:/^Confirm and save/"));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    app.press("Try again")?;
    app.wait_for("Confirm and save")?;
    let requests = stub.requests();
    assert_eq!(requests.len(), 3);
    for request in &requests[1..] {
        let nsh_core::platform::HttpBody::Bytes(bytes) = &request.body else {
            panic!("JSON")
        };
        let body: Value = serde_json::from_slice(bytes).unwrap();
        assert_eq!(body["messages"].as_array().unwrap().len(), 3);
        let result = &body["messages"][2]["content"][0];
        assert_eq!(result["type"], "tool_result");
        assert_eq!(result["tool_use_id"], "call-retry");
    }
    let body: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let draft: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
    assert_eq!(
        draft.transcript.len(),
        4,
        "retry replays the original answer instead of appending another"
    );
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    Ok(())
}

#[test]
fn optional_refinement_can_be_skipped_without_fabricating_an_answer() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let calls = Arc::new(AtomicUsize::new(0));
    let calls_in = calls.clone();
    let stub = Arc::new(StubNetwork::new([(
        MESSAGES.into(),
        StubRoute::Handler(Arc::new(move |_, reply| {
            let body = if calls_in.fetch_add(1, Ordering::SeqCst) == 0 {
                let mut ask = ask_reply(
                    "call-optional",
                    "Any preparation detail to add?",
                    Vec::new(),
                );
                ask["content"][0]["input"]["questions"][0]["required"] = json!(false);
                ask
            } else {
                record_reply(vec![meal_record()])
            };
            reply.send(response(200, body));
        })),
    )]));
    let (mut app, _) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    app.press("label:New entry")?;
    app.type_text(
        "label:What would you like to record?",
        "I ate a bowl of noodles",
    )?;
    app.press("label:Send")?;
    app.wait_for("Any preparation detail to add?")?;
    assert!(
        app.screen().enabled("Submit answers")?,
        "optional details can be skipped explicitly"
    );
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    app.press("Submit answers")?;
    app.wait_for("Confirm and save")?;
    let requests = stub.requests();
    assert_eq!(requests.len(), 2);
    let nsh_core::platform::HttpBody::Bytes(bytes) = &requests[1].body else {
        panic!("JSON")
    };
    let body: Value = serde_json::from_slice(bytes).unwrap();
    let result = &body["messages"][2]["content"][0];
    assert_eq!(result["tool_use_id"], "call-optional");
    let answer: Value = serde_json::from_str(result["content"].as_str().unwrap()).unwrap();
    assert_eq!(
        answer["answers"],
        json!([]),
        "no default choice or invented detail is sent"
    );
    assert_eq!(answer["message"], "");
    assert!(
        stored_meals(dir.path()).is_empty(),
        "submitting an optional answer is not confirmation"
    );
    Ok(())
}

#[test]
fn unknown_or_malformed_tool_calls_cannot_write_business_records() -> Result<(), String> {
    for unknown_name in [false, true] {
        let dir = tempfile::tempdir().unwrap();
        let mut body = ask_reply("call-invalid", "Which account was used?", Vec::new());
        if unknown_name {
            body["content"][0]["name"] = json!("save_records");
        } else {
            body["content"][0]["input"]["questions"][0]["text"] = json!("");
        }
        let (mut app, _) = start_in(Some(dir.path()), account(true), Some(network(200, body)));
        app.press("label:New entry")?;
        app.type_text("label:What would you like to record?", "Lunch 32 yuan")?;
        app.press("label:Send")?;
        app.wait_for("Open settings…")?;
        assert!(!app.shows("text:/^Confirm and save/"));
        let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
        assert!(
            navi_finance::repository::transactions(&db)
                .unwrap()
                .is_empty()
        );
        assert!(stored_meals(dir.path()).is_empty());
        let body: String = db
            .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
            .unwrap();
        let draft: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
        assert!(
            draft.pending_ask_user().is_none(),
            "invalid tools never become user-facing decisions"
        );
        assert_eq!(draft.transcript.len(), 1);
    }
    Ok(())
}

#[test]
fn unsent_views_can_be_removed_and_four_views_survive_reopen_without_recognition()
-> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let quiet = Arc::new(StubNetwork::new([] as [(String, StubResponse); 0]));
    let (mut app, _) = start_in(Some(dir.path()), account(true), Some(quiet.clone()));
    app.press("label:New entry")?;
    picks_a_photo(&mut app);
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    app.press("Remove image")?;
    app.wait_for_gone("Remove image", GONE)?;
    assert!(!app.screen().enabled("label:Send")?);
    let bytes = photo();
    app.on_pick(move |pick| {
        let nsh_core::picker::Pick::Images(request) = pick else {
            panic!("capture opens the image picker")
        };
        assert_eq!(request.limit, 4);
        assert_eq!(
            request.max_dimension, None,
            "the picker must preserve small text before capture preparation"
        );
        assert_eq!(request.quality, None, "avoid an extra lossy encoding pass");
        (0..4)
            .map(|index| {
                PickedFile::new(
                    format!("view-{index}.png"),
                    "image/png",
                    ImageData::new(bytes.clone()),
                )
            })
            .collect()
    });
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    assert!(
        !app.screen().enabled("Attach image")?,
        "four views fill the draft's image allowance"
    );
    app.press("label:Close")?;
    app.wait_for("Draft kept; no records saved")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let body: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    let kept: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
    assert_eq!(kept.image_names().len(), 4);
    assert_eq!(kept.staged_images().len(), 4);
    app.press("label:What would you like to record?")?;
    app.wait_for("Remove image")?;
    assert!(!app.screen().enabled("Attach image")?);
    assert!(app.screen().enabled("label:Send")?);
    assert!(
        quiet.requests().is_empty(),
        "choosing and reopening images never calls recognition"
    );
    assert!(stored_meals(dir.path()).is_empty());
    Ok(())
}

#[test]
fn an_image_that_cannot_be_kept_is_not_attached_or_sent() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let stub = network(200, record_reply(vec![meal_record()]));
    let (mut app, _) = start_in(Some(dir.path()), account(true), Some(stub.clone()));
    let folder = database_in(dir.path())
        .parent()
        .unwrap()
        .join("meal-photos");
    std::fs::write(&folder, b"not a directory").unwrap();
    picks_a_photo(&mut app);
    app.press("label:New entry")?;
    app.press("Attach image")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    assert!(!app.shows("Remove image"));
    assert!(stub.requests().is_empty());
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let bodies: Vec<String> = db
        .prepare("SELECT body FROM capture_drafts")
        .unwrap()
        .query_map([], |row| row.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    for body in bodies {
        let draft: naviwealth_app::domain::capture::Draft = serde_json::from_str(&body).unwrap();
        assert!(draft.image_names().is_empty());
    }
    std::fs::remove_file(&folder).unwrap();
    picks_a_photo(&mut app);
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    assert!(
        stub.requests().is_empty(),
        "successful attachment still needs an explicit send"
    );
    Ok(())
}
