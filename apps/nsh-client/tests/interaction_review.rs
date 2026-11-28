//! Recovery and navigation contracts for record cards in persistent conversations.
mod common;
use common::*;
use naviwealth_app::domain::capture::{Draft, Record, Status};

fn seed(dir: &Path, later_messages: usize) -> Draft {
    let (app, _) = start_in(Some(dir), Vec::new(), None);
    drop(app);
    let draft = Draft {
        id: "review-draft".into(),
        created_at_ms: 1,
        input: "Weight and note".into(),
        correction: String::new(),
        photo: None,
        attachments: vec![],
        answers: vec![],
        records: vec![
            Record::Weight {
                day: today(),
                kg: 72.3,
            },
            Record::Note {
                day: today(),
                text: "After lunch".into(),
            },
        ],
        evidence: vec![],
        question: String::new(),
        transcript: vec![],
        status: Status::Ready,
        model: String::new(),
    };
    let mut messages = vec![
        json!({"id":"review-card", "role":"assistant", "text":"Your pending records", "capture_id":draft.id, "created_at_ms":1}),
    ];
    for n in 0..later_messages {
        messages.push(json!({"id":format!("later-{n}"), "role":"assistant", "text":format!("Later conversation message {n}. Some detail that takes space."), "created_at_ms":1}));
    }
    let session = json!({"id":"review-session", "title":"Daily records", "created_at_ms":1, "updated_at_ms":1,
        "messages":messages, "history":[], "status":"idle"});
    let db = rusqlite::Connection::open(database_in(dir)).unwrap();
    db.execute(
        "INSERT INTO capture_drafts(id,created_at_ms,body) VALUES(?1,1,?2)",
        rusqlite::params![draft.id, serde_json::to_string(&draft).unwrap()],
    )
    .unwrap();
    db.execute(
        "INSERT INTO assistant_sessions(id,updated_at_ms,body) VALUES('review-session',1,?1)",
        [session.to_string()],
    )
    .unwrap();
    draft
}

fn stored_draft(db: &rusqlite::Connection) -> Option<Draft> {
    db.query_row(
        "SELECT body FROM capture_drafts WHERE id='review-draft'",
        [],
        |row| row.get::<_, String>(0),
    )
    .ok()
    .map(|text| serde_json::from_str(&text).unwrap())
}

fn session(db: &rusqlite::Connection) -> Value {
    let text: String = db
        .query_row(
            "SELECT body FROM assistant_sessions WHERE id='review-session'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    serde_json::from_str(&text).unwrap()
}

#[test]
fn discarded_batch_restores_atomically_and_preserves_new_composer_input() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let original = seed(dir.path(), 0);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Conversation")?;
    app.press("text:Discard draft (2)")?;
    app.wait_for("Restore draft")?;
    assert!(stored_draft(&db).is_none());
    assert_eq!(session(&db)["record_actions"][0]["status"], "discarded");
    app.type_text("label:Message", "Keep this unsent message")?;
    db.execute_batch("CREATE TRIGGER fail_restore BEFORE INSERT ON capture_drafts BEGIN SELECT RAISE(ABORT,'test write failure'); END;").unwrap();
    app.press("Restore draft")?;
    assert!(stored_draft(&db).is_none());
    assert_eq!(
        session(&db)["record_actions"][0]["status"],
        "discarded",
        "failed restore rolls back receipt removal"
    );
    db.execute_batch("DROP TRIGGER fail_restore").unwrap();
    app.press("Restore draft")?;
    app.wait_for("text:Confirm and save (2)")?;
    assert_eq!(stored_draft(&db), Some(original));
    assert!(
        session(&db)["record_actions"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("Keep this unsent message")
    );
    assert!(stored_meals(dir.path()).is_empty());
    assert!(
        navi_finance::repository::transactions(&db)
            .unwrap()
            .is_empty()
    );
    Ok(())
}

#[test]
fn removing_one_record_has_undo_and_never_overwrites_a_newer_draft() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let original = seed(dir.path(), 0);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Conversation")?;
    app.press("label:/^Remove from draft.*72.3/")?;
    app.wait_for("text:Undo")?;
    assert_eq!(stored_draft(&db).unwrap().records.len(), 1);
    app.press("text:Undo")?;
    app.wait_for("text:Confirm and save (2)")?;
    assert_eq!(stored_draft(&db), Some(original));
    app.press("label:/^Remove from draft.*72.3/")?;
    app.wait_for("text:Undo")?;
    let mut newer = stored_draft(&db).unwrap();
    newer.correction = "A newer correction must survive".into();
    db.execute(
        "UPDATE capture_drafts SET body=?1 WHERE id='review-draft'",
        [serde_json::to_string(&newer).unwrap()],
    )
    .unwrap();
    app.press("text:Undo")?;
    assert_eq!(stored_draft(&db), Some(newer));
    Ok(())
}

#[test]
fn opening_an_old_pending_card_loads_and_scrolls_to_it_then_returns_to_latest() -> Result<(), String>
{
    let dir = tempfile::tempdir().unwrap();
    seed(dir.path(), 85);
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:Review records")?;
    app.wait_for("id:conversation-message-review-card")?;
    app.wait(Duration::from_millis(250))?;
    let card = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("conversation-message-review-card"))
        .unwrap();
    assert!(
        card.bounds.origin.y.0 >= 90.0 && card.bounds.origin.y.0 < 250.0,
        "target card is in the viewport: {:?}",
        card.bounds
    );
    app.press("text:Modify this record")?;
    app.wait_for("id:conversation-composer >> text:/72.3 kg/")?;
    app.press("text:Locate")?;
    app.wait(Duration::from_millis(100))?;
    app.press("text:Back to latest")?;
    app.wait(Duration::from_millis(100))?;
    let last = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|node| node.test_id.as_deref() == Some("conversation-message-later-84"))
        .unwrap();
    assert!(
        last.bounds.origin.y.0 > 0.0 && last.bounds.origin.y.0 < 844.0,
        "latest message is visible: {:?}",
        last.bounds
    );
    Ok(())
}

#[test]
fn favorite_meals_are_available_without_a_model_and_keep_unsent_text() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let network = Arc::new(StubNetwork::new(Vec::<(String, StubResponse)>::new()));
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), Some(network.clone()));
    app.press("Tomato pasta")?;
    app.press("label:Save as favorite")?;
    app.press("label:Back")?;
    app.press("label:Conversation")?;
    app.type_text("label:Message", "A note for later")?;
    app.press("label:Attach or add manually")?;
    app.press("text:Favorite meals")?;
    app.wait_for("id:favorites >> label:Tomato pasta, 300 kcal")?;
    app.press("id:favorites >> label:Tomato pasta, 300 kcal")?;
    app.wait_for("Logged Tomato pasta")?;
    assert_eq!(stored_meals(dir.path()).len(), 2);
    assert_eq!(
        app.screen().input_text("label:Message")?,
        Some("A note for later")
    );
    app.press("text:Undo")?;
    assert_eq!(stored_meals(dir.path()).len(), 1);
    assert!(network.requests().is_empty());
    Ok(())
}
