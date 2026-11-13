//! Meal logging: by hand, from a photo with consent, editing, recent
//! foods, and the meals' storage. Favorites are in `favorites.rs`.

mod common;

use common::*;

#[test]
fn an_empty_day_explains_what_to_do() -> Result<(), String> {
    let (app, _) = start(Vec::new(), None);
    assert!(app.shows("No meals logged today"));
    assert!(app.shows("Connect a vision model"));
    assert!(app.shows("Nothing logged yet"));
    Ok(())
}

#[test]
fn logging_without_an_account_explains_the_setup() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.press("label:New entry")?;
    app.press("Log a meal")?;
    app.wait_until("the setup sheet", GONE, |screen| {
        screen.count("text:Set up…").unwrap_or(0) == 2
    })?;
    assert!(app.picks().is_empty(), "no picker without an account");
    Ok(())
}

#[test]
fn a_meal_added_by_hand_counts_toward_today() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("label:New entry")?;
    app.press("label:Add manually")?;
    app.wait_for("text:e.g. Beef noodle soup")?;
    app.type_text("text:e.g. Beef noodle soup", "Rice")?;
    app.type_text("label:Amount eaten", "250")?;
    app.type_text("label:Energy", "130")?;
    app.press("Done")?;
    app.wait_for("text:Rice")?;
    app.press("text:/^Save meal/")?;
    // Today's own count: the review page has closed and the meal is kept.
    app.wait_for("text:1 meal")?;
    app.wait_for("text:325")?;
    assert!(app.shows("Rice"));
    let kept = stored_meals(dir.path());
    assert_eq!(kept.len(), 1);
    assert_eq!(
        kept[0]["foods"][0]["name"], "Rice",
        "the meal is kept: {kept:?}"
    );
    Ok(())
}

#[test]
fn a_photo_is_sent_only_after_consent_and_becomes_editable_foods() -> Result<(), String> {
    let stub = network(200, estimate());
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), account(false), Some(stub.clone()));
    picks_a_photo(&mut app);
    app.press("label:New entry")?;
    app.press("Log a meal")?;
    app.wait_for("Send this photo for analysis?")?;
    assert!(app.shows("api.anthropic.com"));
    assert!(stub.requests().is_empty(), "nothing is sent before consent");

    app.press("Send photo")?;
    app.wait_for("text:White rice")?;
    let requests = stub.requests();
    assert_eq!(requests.len(), 1);
    let request = &requests[0];
    let header = |name: &str| {
        request
            .headers
            .iter()
            .find(|(n, _)| n.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.clone())
    };
    assert_eq!(header("x-api-key").as_deref(), Some("sk-test-key"));
    let body: Value = match &request.body {
        nsh_core::platform::HttpBody::Bytes(bytes) => serde_json::from_slice(bytes).expect("JSON"),
        _ => panic!("a JSON body"),
    };
    let images: Vec<_> = body["messages"][0]["content"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|block| block["type"] == "image")
        .collect();
    assert_eq!(images.len(), 1);
    assert_eq!(images[0]["source"]["media_type"], "image/jpeg");

    // 480 g × 92 + 150 g × 130 (the catalog's rice, not the model's 1) per 100 g;
    // the total counts up to it.
    app.wait_for("text:637")?;
    app.press("text:/^Save meal/")?;
    app.wait_for("text:1 meal")?;
    app.wait_for("text:Beef noodle soup")?;
    app.wait_for("text:637")?;
    let saved = stored_meals(dir.path());
    assert_eq!(
        saved[0]["prompt_version"],
        health_core::recognition::PROMPT_VERSION
    );
    Ok(())
}

#[test]
fn declining_consent_sends_nothing() -> Result<(), String> {
    let stub = network(200, estimate());
    let (mut app, _) = start(account(false), Some(stub.clone()));
    picks_a_photo(&mut app);
    app.press("label:New entry")?;
    app.press("Log a meal")?;
    app.wait_for("Send this photo for analysis?")?;
    app.press("Cancel")?;
    app.wait_for("Photo not sent")?;
    assert!(stub.requests().is_empty());
    assert!(app.shows("Send photo…"));
    Ok(())
}

#[test]
fn a_rejected_key_points_to_settings() -> Result<(), String> {
    let stub = network(401, json!({ "error": { "message": "invalid x-api-key" } }));
    let (mut app, _) = start(account(true), Some(stub));
    picks_a_photo(&mut app);
    app.press("label:New entry")?;
    app.press("Log a meal")?;
    app.wait_for("The API key was rejected")?;
    assert!(app.shows("Open settings…"));
    assert!(app.shows("Add manually"));
    Ok(())
}

#[test]
fn a_failed_whole_body_fetch_is_not_automatically_replayed() -> Result<(), String> {
    let mut reply = StubResponse::default();
    reply.error = Some("Connection reset while receiving the reply".into());
    let stub = Arc::new(StubNetwork::new([(MESSAGES.to_owned(), reply)]));
    let (mut app, _) = start(account(true), Some(stub.clone()));
    picks_a_photo(&mut app);
    app.press("label:New entry")?;
    app.press("Log a meal")?;
    app.wait_for("Can't reach the model")?;
    assert_eq!(stub.requests().len(), 1);
    app.wait(Duration::from_secs(3))?;
    assert_eq!(stub.requests().len(), 1);
    assert!(app.shows("Try again"));
    Ok(())
}

#[test]
fn deleting_a_meal_can_be_undone() -> Result<(), String> {
    let meal = Meal {
        id: "m1".into(),
        day: today(),
        logged_at_ms: jiff::Timestamp::now().as_millisecond(),
        slot: MealSlot::Lunch,
        title: Some("Tomato pasta".into()),
        foods: vec![Food {
            id: 7,
            name: "Pasta".into(),
            grams: 200.0,
            per_100g: Nutrients::new(150.0, 5.0, 30.0, 1.0),
            source: FoodSource::Manual,
            confidence: None,
            estimated_grams: None,
        }],
        photo: None,
        model: None,
        prompt_version: None,
    };
    let (mut app, _) = start(vec![("meals.v1".to_owned(), encode_meals(&[meal]))], None);
    app.wait_for("text:300")?;
    app.press("Tomato pasta")?;
    app.wait_for("Edit meal")?;
    app.press("label:Delete meal")?;
    app.wait_for("Meal deleted")?;
    app.wait_for("No meals logged today")?;
    app.press("Undo")?;
    app.wait_for("Tomato pasta")?;
    app.wait_for_gone("Meal deleted", GONE)?;
    Ok(())
}

#[test]
fn legacy_meals_move_into_the_database_and_survive_a_restart() -> Result<(), String> {
    let first = Meal {
        id: "m1".to_owned(),
        day: today(),
        logged_at_ms: jiff::Timestamp::now().as_millisecond(),
        slot: MealSlot::Lunch,
        title: Some("Tomato pasta".to_owned()),
        foods: vec![Food {
            id: 1,
            name: "Pasta".to_owned(),
            grams: 300.0,
            per_100g: Nutrients::new(100.0, 4.0, 20.0, 1.0),
            source: FoodSource::Manual,
            confidence: None,
            estimated_grams: None,
        }],
        photo: None,
        model: None,
        prompt_version: None,
    };
    let second = Meal {
        id: "m2".to_owned(),
        logged_at_ms: first.logged_at_ms + 1,
        title: Some("Second".to_owned()),
        ..first.clone()
    };
    let dir = tempfile::tempdir().unwrap();
    let entries = vec![("meals.v1".to_owned(), encode_meals(&[first, second]))];

    let (mut app, storage) = start_in(Some(dir.path()), entries, None);
    app.wait_for("Tomato pasta")?;
    assert!(app.shows("Second"));
    assert!(
        !storage.entries().contains_key("meals.v1"),
        "the legacy entry goes once the meals are in the database"
    );
    assert_eq!(stored_meals(dir.path()).len(), 2);
    drop(app);

    let (app, _) = start_in(Some(dir.path()), Vec::new(), None);
    assert!(
        app.shows("Tomato pasta"),
        "meals come back from the database"
    );
    assert!(app.shows("Second"));
    Ok(())
}

#[test]
fn a_recent_food_fills_the_new_food() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    app.wait_for("text:300")?;
    app.press("label:New entry")?;
    app.press("label:Add manually")?;
    app.wait_for("Recent")?;
    app.press("text:Pasta")?;
    app.press("Done")?;
    app.press("text:/^Save meal/")?;
    app.wait_for("text:2 meals")?;
    app.wait_for("text:600")?;
    let kept = stored_meals(dir.path());
    assert_eq!(kept.len(), 2);
    assert_eq!(kept[1]["foods"][0]["grams"], 300.0);
    assert_eq!(
        kept[1]["foods"][0]["source"], kept[0]["foods"][0]["source"],
        "an unchanged recent food keeps its catalog source"
    );
    Ok(())
}

#[test]
fn the_api_key_is_kept_apart_from_the_settings() -> Result<(), String> {
    let (mut app, storage) = start(Vec::new(), None);
    app.press("label:Settings")?;
    app.wait_for("Vision model")?;
    app.type_text("text:Paste your key", "sk-ant-secret")?;
    app.press("Save")?;
    app.wait_for("label:New entry")?;
    app.wait_for_gone("Connect a vision model", GONE)?;
    let entries = storage.entries();
    assert_eq!(
        entries.get("secret.model-key.v1").map(String::as_str),
        Some("sk-ant-secret")
    );
    let settings = entries.get("settings.v1").cloned().unwrap_or_default();
    assert!(settings.contains("claude-opus-5-5"));
    assert!(
        !settings.contains("sk-ant-secret"),
        "the key never sits with the settings"
    );
    Ok(())
}

#[test]
fn a_food_without_nutrition_is_not_saved_as_zero() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.press("label:New entry")?;
    app.press("label:Add manually")?;
    app.wait_for("text:e.g. Beef noodle soup")?;
    app.type_text("text:e.g. Beef noodle soup", "Tea")?;
    app.type_text("label:Amount eaten", "300")?;
    app.press("Done")?;
    app.wait_for("Check the values per 100 g.")?;
    assert!(app.shows("Add food"), "the editor stays open");
    app.type_text("label:Energy", "1")?;
    app.press("Done")?;
    app.wait_for("text:Tea")?;
    assert!(app.screen().enabled("text:/^Save meal/")?);
    Ok(())
}
