//! The assistant's local navigation, memory lifecycle and explicit model consent.
mod common;

use common::*;
use nsh_testing::DialogAnswer;

#[test]
fn assistant_opens_without_a_model_and_keeps_the_four_home_tabs() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.press("label:Conversation")?;
    app.wait_for("A place for your day")?;
    app.wait_for("Set up model")?;
    app.press("text:Conversations")?;
    app.wait_for("No conversations yet.")?;
    app.press("label:Back")?;
    app.wait_for("label:Message")?;
    app.press("label:Back")?;
    app.wait_for("label:Conversation")?;
    for tab in ["Today", "Records", "Assets", "Review"] {
        assert!(app.shows(tab), "{tab} remains a home tab");
    }
    Ok(())
}

#[test]
fn saved_memories_survive_restart_and_deletion_requires_confirmation() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Conversation")?;
    app.press("text:Conversations")?;
    app.press("text:Memory & search")?;
    app.type_text("label:Memory text", "Prefer walking to short taxi rides.")?;
    app.press("text:Save memory")?;
    app.wait_for("Prefer walking to short taxi rides.")?;
    assert_eq!(memory_count(dir.path()), 1);
    app.press("label:Edit memory")?;
    app.clear("label:Memory text")?;
    app.type_text("label:Memory text", "Prefer walking for trips under 2 km.")?;
    app.press("text:Save memory")?;
    app.wait_for("Prefer walking for trips under 2 km.")?;
    assert_eq!(
        memory_count(dir.path()),
        1,
        "editing preserves memory identity"
    );
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("label:Conversation")?;
    app.press("text:Conversations")?;
    app.press("text:Memory & search")?;
    app.wait_for("Prefer walking for trips under 2 km.")?;
    app.on_dialog(|_| DialogAnswer::Press("Cancel".into()));
    app.press("label:Delete memory")?;
    app.wait_for("Prefer walking for trips under 2 km.")?;
    assert_eq!(memory_count(dir.path()), 1);
    app.on_dialog(|_| DialogAnswer::Press("Delete".into()));
    app.press("label:Delete memory")?;
    app.wait_for("No saved memories.")?;
    assert_eq!(memory_count(dir.path()), 0);
    Ok(())
}

#[test]
fn capture_consent_does_not_authorize_assistant_and_cancel_keeps_input() -> Result<(), String> {
    let network = Arc::new(StubNetwork::new(Vec::<(String, StubResponse)>::new()));
    let (mut app, storage) = start(account(true), Some(network.clone()));
    app.press("label:Conversation")?;
    app.type_text("label:Message", "Review my recent spending")?;
    app.on_dialog(|dialog| {
        assert!(format!("{dialog:?}").contains("Send to your configured model?"));
        DialogAnswer::Press("Cancel".into())
    });
    app.press("label:Send message")?;
    app.wait_for("label:Message")?;
    assert!(network.requests().is_empty());
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("Review my recent spending")
    );
    assert!(
        !storage
            .entries()
            .iter()
            .any(|(key, value)| key.contains("assistant") && value.contains("anthropic"))
    );
    Ok(())
}

fn memory_count(dir: &Path) -> i64 {
    rusqlite::Connection::open(database_in(dir))
        .unwrap()
        .query_row("SELECT count(*) FROM assistant_memories", [], |row| {
            row.get(0)
        })
        .unwrap()
}

#[test]
fn search_key_is_saved_separately_from_chat_data() -> Result<(), String> {
    let (mut app, storage) = start(Vec::new(), None);
    app.press("label:Conversation")?;
    app.press("text:Conversations")?;
    app.press("text:Memory & search")?;
    app.type_text("label:Search API key", "test-brave-secret")?;
    app.type_text("label:Memory text", "A local note")?;
    app.press("label:Back")?;
    app.press("text:Conversations")?;
    app.press("text:Memory & search")?;
    assert_eq!(
        app.screen().input_text("label:Memory text")?,
        Some("A local note")
    );
    app.wait(Duration::from_millis(50))?;
    assert!(
        storage
            .entries()
            .iter()
            .any(|(key, value)| key.starts_with("secret.") && value == "test-brave-secret")
    );
    assert!(
        storage
            .entries()
            .iter()
            .filter(|(key, _)| !key.starts_with("secret."))
            .all(|(_, value)| !value.contains("test-brave-secret"))
    );
    Ok(())
}

#[test]
fn composer_survives_back_restart_and_new_conversation_keeps_old_draft() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Conversation")?;
    app.type_text("label:Message", "Lunch to record later")?;
    app.press("label:Back")?;
    app.press("label:Conversation")?;
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("Lunch to record later")
    );
    app.press("text:New conversation")?;
    assert_eq!(app.screen().input_text("label:Message")?, Some(""));
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.press("label:Conversation")?;
    assert_eq!(app.screen().input_text("label:Message")?, Some(""));
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let drafts: Vec<String> = db
        .prepare("SELECT body FROM assistant_sessions")
        .unwrap()
        .query_map([], |row| row.get(0))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert!(
        drafts
            .iter()
            .any(|body| body.contains("Lunch to record later"))
    );
    assert_eq!(drafts.len(), 2);
    Ok(())
}

#[test]
fn photos_are_staged_locally_without_a_model_and_can_be_removed() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let network = Arc::new(StubNetwork::new(Vec::<(String, StubResponse)>::new()));
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), Some(network.clone()));
    picks_a_photo(&mut app);
    app.press("label:Conversation")?;
    app.press("label:Attach or add manually")?;
    app.press("text:Add photos")?;
    app.wait_for("label:Remove photo")?;
    app.press("label:Back")?;
    app.press("label:Conversation")?;
    app.wait_for("label:Remove photo")?;
    app.press("label:Remove photo")?;
    assert!(network.requests().is_empty());
    app.press("label:Attach or add manually")?;
    app.wait_for("Meal by hand")?;
    app.wait_for("Transaction by hand")?;
    app.wait_for("Weight by hand")?;
    Ok(())
}

#[test]
fn conversation_settings_keep_unsent_input_local_and_hide_typing_previews() -> Result<(), String> {
    let (mut app, _) = start(account(true), None);
    app.press("label:Settings")?;
    app.press("label:/^Recognition model, /")?;
    app.wait_for("Use recent records and favorites")?;
    assert!(!app.shows("Preview as I type"));
    assert!(!app.shows("Preview model (optional)"));
    app.wait_for(
        "Unsent messages and photos stay on this device. They are sent only when you press Send.",
    )?;
    Ok(())
}

#[test]
fn composer_stays_in_a_small_keyboard_sized_viewport_with_large_text() -> Result<(), String> {
    use nsh_core::{Points, Size};
    let (mut app, _) = start(Vec::new(), None);
    app.set_viewport(Size::new(Points(360.0), Points(640.0)))?;
    app.set_environment("large text", |environment| environment.font_scale = 1.3)?;
    app.press("label:Conversation")?;
    app.type_text("label:Message", "A note to finish later")?;
    app.set_viewport(Size::new(Points(360.0), Points(360.0)))?;
    let composer = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("conversation-composer") && !node.hidden)
        .expect("visible composer");
    assert!(composer.bounds.origin.y.0 >= 60.0);
    assert!(
        composer.bounds.origin.y.0 + composer.bounds.size.height.0 <= 361.0,
        "composer stays above keyboard: {:?}",
        composer.bounds
    );
    assert!(app.screen().enabled("label:Attach or add manually")?);
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("A note to finish later")
    );
    Ok(())
}

#[test]
fn reported_keyboard_lifts_composer_when_android_keeps_full_root_height() -> Result<(), String> {
    use nsh_core::{Points, Size};
    let (mut app, _) = start(Vec::new(), None);
    app.set_viewport(Size::new(Points(390.0), Points(844.0)))?;
    app.set_environment("navigation inset", |environment| {
        environment.safe_area.bottom = Points(24.0)
    })?;
    app.press("label:Conversation")?;
    app.type_text("label:Message", "A photo correction to send")?;
    let bottom = |app: &Headless| {
        let composer = app
            .screen()
            .layout_nodes()
            .into_iter()
            .find(|node| node.test_id.as_deref() == Some("conversation-composer") && !node.hidden)
            .expect("visible composer");
        composer.bounds.origin.y.0 + composer.bounds.size.height.0
    };
    assert!((bottom(&app) - 844.0).abs() < 1.0);
    // Reproduce Android adjustNothing: IME changes, window/root do not shrink.
    app.set_environment("keyboard visible", |environment| {
        environment.keyboard_height = Points(300.0)
    })?;
    assert!(
        (bottom(&app) - 544.0).abs() < 1.0,
        "composer must meet IME, got {}",
        bottom(&app)
    );
    assert!(app.screen().enabled("label:Attach or add manually")?);
    app.set_environment("keyboard hidden", |environment| {
        environment.keyboard_height = Points(0.0)
    })?;
    assert!((bottom(&app) - 844.0).abs() < 1.0);
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("A photo correction to send")
    );
    Ok(())
}
