//! The assistant's local navigation, memory lifecycle and explicit model consent.
mod common;

use common::*;
use nsh_testing::DialogAnswer;

#[test]
fn assistant_opens_without_a_model_and_keeps_the_four_home_tabs() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.press("text:Assistant")?;
    app.wait_for("What would you like to work on?")?;
    app.wait_for("Set up model")?;
    app.press("text:Conversations")?;
    app.wait_for("No conversations yet.")?;
    app.press("label:Back")?;
    app.wait_for("label:Message Assistant")?;
    app.press("label:Back")?;
    app.wait_for("label:New entry")?;
    for tab in ["Today", "Records", "Assets", "Review"] {
        assert!(app.shows(tab), "{tab} remains a home tab");
    }
    Ok(())
}

#[test]
fn saved_memories_survive_restart_and_deletion_requires_confirmation() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("text:Assistant")?;
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
    app.press("text:Assistant")?;
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
    app.press("text:Assistant")?;
    app.type_text("label:Message Assistant", "Review my recent spending")?;
    app.on_dialog(|dialog| {
        assert!(format!("{dialog:?}").contains("Use this model for Assistant?"));
        DialogAnswer::Press("Cancel".into())
    });
    app.press("label:Send message")?;
    app.wait_for("label:Message Assistant")?;
    assert!(network.requests().is_empty());
    assert_eq!(
        app.screen().input_text("label:Message Assistant")?,
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
    app.press("text:Assistant")?;
    app.press("text:Memory & search")?;
    app.type_text("label:Search API key", "test-brave-secret")?;
    app.type_text("label:Memory text", "A local note")?;
    app.press("label:Back")?;
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
