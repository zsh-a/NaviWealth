//! Unsent text and stored examples have independently scoped permissions.
mod common;
use common::*;
use nsh_core::platform::HttpBody;

fn preferences(live: bool, recent: bool, profile: &str) -> Vec<(String, String)> {
    let mut settings = account(true);
    let mut value: Value = serde_json::from_str(&settings[0].1).unwrap();
    let target = json!(["anthropic", "https://api.anthropic.com/v1", profile]).to_string();
    value["capture_options"][target] =
        json!({"live_text":live,"recent_context":recent,"preview_model":"fast-preview"});
    settings[0].1 = value.to_string();
    settings
}

fn request(stub: &StubNetwork, index: usize) -> Value {
    let HttpBody::Bytes(bytes) = &stub.requests()[index].body else {
        panic!("JSON request")
    };
    serde_json::from_slice(bytes).unwrap()
}

fn payload(body: &Value) -> Value {
    let blocks = body["messages"][0]["content"].as_array().unwrap();
    serde_json::from_str(
        blocks.iter().find(|v| v["type"] == "text").unwrap()["text"]
            .as_str()
            .unwrap(),
    )
    .unwrap()
}

#[test]
fn defaults_and_permissions_for_another_model_keep_unsent_text_local() -> Result<(), String> {
    for settings in [account(true), preferences(true, true, "other-model")] {
        let stub = network(200, record_reply(vec![meal_record()]));
        let (mut app, _) = start_legacy(settings, Some(stub.clone()));
        app.press("label:New entry")?;
        app.type_text("label:What would you like to record?", "my lunch")?;
        app.wait(Duration::from_millis(850))?;
        assert!(stub.requests().is_empty());
        app.press("label:Send")?;
        app.wait_for("Confirm and save")?;
        let data = payload(&request(&stub, 0));
        assert!(data["context"].get("recent_records").is_none());
        assert!(data["context"].get("favorites").is_none());
        assert!(data["context"].get("known_securities").is_none());
    }
    Ok(())
}

#[test]
fn typing_previews_only_the_latest_text_and_submit_sends_separately() -> Result<(), String> {
    let stub = network(200, record_reply(vec![meal_record()]));
    let (mut app, _) = start_legacy(
        preferences(true, true, "claude-opus-5-5"),
        Some(stub.clone()),
    );
    picks_a_photo(&mut app);
    app.press("label:New entry")?;
    app.press("label:Attach image")?;
    app.type_text("label:What would you like to record?", "morning")?;
    app.clear("label:What would you like to record?")?;
    app.type_text("label:What would you like to record?", "usual breakfast")?;
    app.wait_for("Typing preview")?;
    app.wait(Duration::from_millis(120))?;
    assert_eq!(stub.requests().len(), 1);
    let preview = request(&stub, 0);
    assert_eq!(preview["model"], "fast-preview");
    assert_eq!(payload(&preview)["input"], "usual breakfast");
    assert_eq!(
        preview["messages"][0]["content"].as_array().unwrap().len(),
        1
    );
    assert!(payload(&preview)["context"].get("recent_records").is_none());
    assert!(!app.shows("Confirm and save"));
    app.press("label:Send")?;
    app.wait_for("Confirm and save")?;
    assert_eq!(stub.requests().len(), 2);
    let final_call = request(&stub, 1);
    assert_eq!(final_call["model"], "claude-opus-5-5");
    assert!(
        final_call["messages"][0]["content"]
            .as_array()
            .unwrap()
            .iter()
            .any(|b| b["type"] == "image")
    );
    let data = payload(&final_call);
    assert!(data["context"]["recent_records"].is_array());
    assert!(data["context"]["favorites"].is_array());
    Ok(())
}

#[test]
fn model_settings_can_opt_in_independently_and_changing_the_preview_model_disarms_it()
-> Result<(), String> {
    let (mut app, storage) = start_legacy(account(true), None);
    app.press("label:Settings")?;
    app.press("label:/^Recognition model, /")?;
    app.press("Preview as I type")?;
    let options = || {
        let value: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
        value["capture_options"]
            .as_object()
            .unwrap()
            .values()
            .next()
            .unwrap()
            .clone()
    };
    assert_eq!(options()["live_text"], true);
    assert_eq!(options()["recent_context"], false);
    app.press("Use recent records and favorites")?;
    app.type_text("label:Preview model (optional)", "fast-model")?;
    app.press("Done")?;
    assert_eq!(
        options(),
        json!({"live_text":false,"recent_context":true,"preview_model":"fast-model"})
    );
    Ok(())
}

#[test]
fn leaving_before_the_preview_and_reopening_untouched_text_makes_no_request() -> Result<(), String>
{
    let stub = network(200, record_reply(vec![meal_record()]));
    let (mut app, _) = start_legacy(
        preferences(true, true, "claude-opus-5-5"),
        Some(stub.clone()),
    );
    app.press("label:New entry")?;
    app.type_text("label:What would you like to record?", "private lunch")?;
    app.press("label:Close")?;
    app.wait(Duration::from_millis(850))?;
    assert!(stub.requests().is_empty());
    app.press("text:/private lunch/")?;
    app.wait_for("label:What would you like to record?")?;
    app.wait(Duration::from_millis(850))?;
    assert!(stub.requests().is_empty());
    Ok(())
}
