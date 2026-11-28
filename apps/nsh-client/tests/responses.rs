//! Responses protocol settings and durable, explicitly confirmed capture flows.
mod common;
use common::*;
use nsh_testing::StubRoute;
use std::sync::atomic::{AtomicUsize, Ordering};

const RESPONSES: &str = "POST https://api.openai.com/v1/responses";

fn responses_account() -> Vec<(String, String)> {
    let fingerprint = json!([
        "openai_responses",
        "https://api.openai.com/v1",
        "responses-test"
    ])
    .to_string();
    vec![
        ("settings.v1".into(), json!({
            "account": {"provider":"open_ai_responses", "base_url":"https://api.openai.com/v1", "model":"responses-test"},
            "trusted_capture":[fingerprint],
        }).to_string()),
        ("secret.model-key.v1".into(), "sk-synthetic".into()),
    ]
}

fn output_response(output: Value) -> Value {
    json!({"id":"resp-test", "object":"response", "status":"completed", "model":"responses-test", "output":output})
}

fn message_response(text: String) -> Value {
    output_response(
        json!([{"type":"message", "id":"msg-final", "role":"assistant", "status":"completed",
        "content":[{"type":"output_text", "text":text, "annotations":[]}]}]),
    )
}

fn body(request: &HttpRequest) -> Value {
    let nsh_core::platform::HttpBody::Bytes(bytes) = &request.body else {
        panic!("JSON request")
    };
    serde_json::from_slice(bytes).unwrap()
}

#[test]
fn settings_keep_custom_values_and_test_the_selected_responses_endpoint() -> Result<(), String> {
    let endpoint = "POST https://models.example.test/custom/v1/responses";
    let stub = Arc::new(StubNetwork::new([(
        endpoint.into(),
        response(200, message_response("OK".into())),
    )]));
    let mut entries = responses_account();
    let settings: Value = json!({"account": {"provider":"open_ai_compatible", "base_url":"https://models.example.test/custom/v1", "model":"custom-image-model"}});
    entries[0].1 = settings.to_string();
    let (mut app, storage) = start(entries, Some(stub.clone()));
    app.press("label:Settings")?;
    app.press("label:/^Recognition model, /")?;
    app.press("label:API protocol")?;
    app.press_key("escape")?;
    let unchanged: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert_eq!(unchanged["account"]["provider"], "open_ai_compatible");
    app.press("label:API protocol")?;
    app.press("role:option[Anthropic]")?;
    app.press("label:API protocol")?;
    app.press("role:option[OpenAI Responses]")?;
    app.press("Test connection")?;
    app.wait_for("text:/^Connected/")?;
    assert_eq!(stub.requests().len(), 1);
    let request = body(&stub.requests()[0]);
    assert_eq!(request["model"], "custom-image-model");
    assert_eq!(request["store"], false);
    assert!(request.get("messages").is_none());
    app.press("label:Back")?;
    app.wait_for("label:/^Recognition model, OpenAI Responses/")?;
    let entries = storage.entries();
    let settings: Value = serde_json::from_str(&entries["settings.v1"]).unwrap();
    assert_eq!(settings["account"]["provider"], "open_ai_responses");
    assert_eq!(
        settings["account"]["base_url"],
        "https://models.example.test/custom/v1"
    );
    assert_eq!(settings["account"]["model"], "custom-image-model");
    assert_eq!(entries["secret.model-key.v1"], "sk-synthetic");
    assert!(!entries["settings.v1"].contains("sk-synthetic"));
    app.press("label:Back")?;
    drop(app);
    let (mut app, _) = start(entries.into_iter().collect(), None);
    app.press("label:Settings")?;
    app.wait_for("label:/^Recognition model, OpenAI Responses/")?;
    Ok(())
}

#[test]
fn responses_defaults_require_an_explicit_model_and_allow_a_keyless_local_server()
-> Result<(), String> {
    let endpoint = "POST http://localhost:8080/v1/responses";
    let stub = Arc::new(StubNetwork::new([(
        endpoint.into(),
        response(200, message_response("OK".into())),
    )]));
    let (mut app, storage) = start(Vec::new(), Some(stub.clone()));
    app.press("label:Settings")?;
    app.press("label:/^Recognition model, /")?;
    app.press("label:API protocol")?;
    app.press("role:option[OpenAI Responses]")?;
    let kept: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert_eq!(
        kept["account"]["model"], "",
        "the inherited Anthropic model is cleared"
    );
    app.clear("text:https://api.openai.com/v1")?;
    app.type_text("text:https://api.openai.com/v1", "http://localhost:8080/v1")?;
    app.type_text("text:A model that accepts images", "local-image-model")?;
    let entered: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert_eq!(entered["account"]["base_url"], "http://localhost:8080/v1");
    assert_eq!(entered["account"]["model"], "local-image-model");
    app.press("Test connection")?;
    app.wait_for("text:/^Connected/")?;
    let request = body(&stub.requests()[0]);
    assert_eq!(request["model"], "local-image-model");
    assert_eq!(request["store"], false);
    let entries = storage.entries();
    let settings: Value = serde_json::from_str(&entries["settings.v1"]).unwrap();
    assert_eq!(settings["account"]["provider"], "open_ai_responses");
    Ok(())
}

#[test]
fn responses_choice_and_native_reasoning_survive_restart_and_image_followup() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    let native_output = json!([
        {"id":"reasoning-1", "type":"reasoning", "summary":[], "encrypted_content":"opaque-reasoning"},
        {"id":"fc_item", "type":"function_call", "call_id":"call_1", "name":"ask_user", "arguments":json!({"questions":[{
            "id":"decision", "text":"Does the label describe this meal?", "reason":"The serving size needs confirmation.", "required":true,
            "options":[{"id":"same", "label":"Same meal", "description":"The label belongs to the photographed meal"}]
        }]}).to_string()}
    ]);
    let calls = Arc::new(AtomicUsize::new(0));
    let calls_in = calls.clone();
    let first_output = native_output.clone();
    let stub = Arc::new(StubNetwork::new([(
        RESPONSES.into(),
        StubRoute::Handler(Arc::new(move |_, reply| {
            let index = calls_in.fetch_add(1, Ordering::SeqCst);
            reply.send(response(
                200,
                if index == 0 {
                    output_response(first_output.clone())
                } else {
                    message_response(
                        json!({"destination":null,"records":[meal_record()]}).to_string(),
                    )
                },
            ));
        })),
    )]));
    let (mut app, storage) =
        start_legacy_in(Some(dir.path()), responses_account(), Some(stub.clone()));
    attach_capture(&mut app)?;
    app.wait_for("Does the label describe this meal?")?;
    assert!(!app.screen().enabled("Continue")?);
    app.press("label:Same meal")?;
    assert!(app.screen().enabled("Continue")?);
    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "selection is staged locally"
    );
    assert!(stored_meals(dir.path()).is_empty());
    app.press("label:Close")?;
    app.wait_for("Draft kept")?;
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let kept: Value = serde_json::from_str(
        &db.query_row::<String, _, _>("SELECT body FROM capture_drafts", [], |r| r.get(0))
            .unwrap(),
    )
    .unwrap();
    assert_eq!(kept["answers"][0]["option_id"], "same");
    assert!(kept.to_string().contains("opaque-reasoning"));
    drop(app);
    let (mut app, _) = start_legacy_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(stub.clone()),
    );
    app.press("label:Review records")?;
    app.wait_for("Does the label describe this meal?")?;
    assert!(app.screen().enabled("Continue")?);
    assert_eq!(calls.load(Ordering::SeqCst), 1);
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
    app.press("Add text or photos")?;
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    app.press("Continue")?;
    app.wait_for("Confirm and save")?;
    assert_eq!(calls.load(Ordering::SeqCst), 2);
    assert!(
        stored_meals(dir.path()).is_empty(),
        "recognition remains a draft"
    );
    let requests = stub.requests();
    let initial = body(&requests[0]);
    assert_eq!(initial["store"], false);
    assert!(initial["instructions"].is_string());
    let request = body(&requests[1]);
    let input = request["input"].as_array().unwrap();
    assert_eq!(
        input[1], native_output[0],
        "encrypted reasoning is replayed unchanged"
    );
    assert_eq!(
        input[2], native_output[1],
        "native tool item retains both identifiers"
    );
    assert_eq!(input[3]["type"], "function_call_output");
    assert_eq!(
        input[3]["call_id"], "call_1",
        "result references call_id, never fc_item"
    );
    let answer: Value = serde_json::from_str(input[3]["output"].as_str().unwrap()).unwrap();
    assert_eq!(answer["answers"][0]["option_id"], "same");
    let image_url = |item: &Value| {
        item["content"]
            .as_array()
            .unwrap()
            .iter()
            .find(|part| part["type"] == "input_image")
            .unwrap()["image_url"]
            .clone()
    };
    assert_ne!(
        image_url(&input[0]),
        image_url(&input[4]),
        "each view keeps its original turn and bytes"
    );
    let completed: String = db
        .query_row("SELECT body FROM capture_drafts", [], |r| r.get(0))
        .unwrap();
    assert!(
        completed.contains("msg-final"),
        "the final native assistant output is durable too"
    );
    app.press("Confirm and save")?;
    app.wait_for_gone("task-sheet", GONE)?;
    assert_eq!(
        stored_meals(dir.path()).len(),
        1,
        "both views create one confirmed record atomically"
    );
    Ok(())
}
