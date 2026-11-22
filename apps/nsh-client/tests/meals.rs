//! Meal logging: by hand, from a photo with consent, editing, recent
//! foods, and the meals' storage. Favorites are in `favorites.rs`.

mod common;

use common::*;

#[test]
fn an_empty_day_explains_what_to_do() -> Result<(), String> {
    let (app, _) = start(Vec::new(), None);
    assert!(app.shows("Nothing recorded today"));
    assert!(app.shows("Connect a recognition model"));
    assert!(app.shows("Nothing logged yet"));
    Ok(())
}

#[test]
fn logging_without_an_account_explains_the_setup() -> Result<(), String> {
    let (mut app, _) = start(Vec::new(), None);
    app.press("label:New entry")?;
    app.wait_for("Connect a model to recognize entries.")?;
    assert!(app.picks().is_empty());
    Ok(())
}

#[test]
fn a_meal_added_by_hand_counts_toward_today() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    open_manual(&mut app, "Manual meal")?;
    app.wait_for("text:e.g. Beef noodle soup")?;
    app.type_text("text:e.g. Beef noodle soup", "Rice")?;
    app.type_text("label:Amount eaten", "250")?;
    app.type_text("label:Energy", "130")?;
    app.press("Done")?;
    app.wait_for("text:Rice")?;
    app.press("text:Breakfast")?;
    app.press("text:/^Save meal/")?;
    // Today's own count: the review page has closed and the meal is kept.
    app.wait_for("text:1 meal")?;
    app.wait_for("text:325")?;
    assert!(app.shows("Rice"));
    app.wait_for("text:/^Breakfast ·/")?;
    let kept = stored_meals(dir.path());
    assert_eq!(kept.len(), 1);
    assert_eq!(
        kept[0]["foods"][0]["name"], "Rice",
        "the meal is kept: {kept:?}"
    );
    app.set_viewport(nsh_core::Size::new(
        nsh_core::Points(360.0),
        nsh_core::Points(640.0),
    ))?;
    app.set_environment("large text", |e| e.font_scale = 1.3)?;
    app.press("label:Rice, 325 kcal")?;
    app.press("text:Dinner")?;
    app.press("text:/^Save meal/")?;
    app.wait_for("text:/^Dinner ·/")?;
    assert_eq!(stored_meals(dir.path())[0]["slot"], "dinner");
    Ok(())
}

#[test]
fn a_photo_is_sent_only_after_consent_and_becomes_editable_foods() -> Result<(), String> {
    let stub = network(200, record_reply(vec![meal_record()]));
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), account(false), Some(stub.clone()));
    attach_capture(&mut app)?;
    app.wait_for("Send to your model?")?;
    app.wait_for("text:/api.anthropic.com/")?;
    assert!(stub.requests().is_empty(), "nothing is sent before consent");

    app.press("Recognize")?;
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
    // The small fixture fits the lossless capture budget.
    assert_eq!(images[0]["source"]["media_type"], "image/png");

    // 480 g × 92 + 150 g × 130 (the catalog's rice, not the model's 1) per 100 g;
    // the total counts up to it.
    app.wait_for("text:637 kcal")?;
    assert!(stored_meals(dir.path()).is_empty());
    app.press("Confirm and save")?;
    app.wait_for("text:1 meal")?;
    app.wait_for("text:Beef noodle soup")?;
    app.wait_for("text:637")?;
    let saved = stored_meals(dir.path());
    assert_eq!(
        saved[0]["prompt_version"],
        naviwealth_app::domain::capture::PROMPT_VERSION
    );
    Ok(())
}

#[test]
fn declining_consent_sends_nothing() -> Result<(), String> {
    let stub = network(200, record_reply(vec![meal_record()]));
    let (mut app, _) = start(account(false), Some(stub.clone()));
    attach_capture(&mut app)?;
    app.wait_for("Send to your model?")?;
    app.press("label:Back")?;
    app.wait_for("Attach image")?;
    assert!(stub.requests().is_empty());
    assert!(app.screen().enabled("label:Send")?);
    Ok(())
}

#[test]
fn a_rejected_key_points_to_settings() -> Result<(), String> {
    let stub = network(401, json!({ "error": { "message": "invalid x-api-key" } }));
    let (mut app, _) = start(account(true), Some(stub));
    attach_capture(&mut app)?;
    app.wait_for("The API key was rejected")?;
    assert!(app.shows("Open settings…"));
    assert!(app.shows("Enter manually"));
    Ok(())
}

#[test]
fn a_failed_whole_body_fetch_is_not_automatically_replayed() -> Result<(), String> {
    let mut reply = StubResponse::default();
    reply.error = Some("Connection reset while receiving the reply".into());
    let stub = Arc::new(StubNetwork::new([(MESSAGES.to_owned(), reply)]));
    let (mut app, _) = start(account(true), Some(stub.clone()));
    attach_capture(&mut app)?;
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
    app.wait_for("Nothing recorded today")?;
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
    open_manual(&mut app, "Manual meal")?;
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
    app.press("label:/^Recognition model, /")?;
    app.type_text("text:Paste your key", "sk-ant-secret")?;
    // Kept as typed: no Save.
    app.press("label:Back")?;
    app.wait_for("label:/^Recognition model, Anthropic · /")?;
    app.press("label:Back")?;
    app.wait_for("label:New entry")?;
    app.wait_for_gone("Connect a recognition model", GONE)?;
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
    open_manual(&mut app, "Manual meal")?;
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

#[test]
fn more_nutrition_edits_save_and_persist() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    open_manual(&mut app, "Manual meal")?;
    app.wait_for("text:e.g. Beef noodle soup")?;
    app.type_text("text:e.g. Beef noodle soup", "Oats")?;
    app.type_text("label:Amount eaten", "100")?;
    app.type_text("label:Energy", "379")?;
    app.type_text("label:Protein", "13.2")?;
    app.type_text("label:Carbs", "67.7")?;
    app.type_text("label:Fat", "6.5")?;
    app.press("text:More nutrition")?;
    app.type_text("label:Fiber", "10.1")?;
    app.type_text("label:Sugars", "1")?;
    app.type_text("label:Sodium", "6")?;
    app.type_text("label:Sat. fat", "1.1")?;
    app.press("Done")?;
    app.wait_for("text:Fiber 10 g · Sugars 1 g · Sodium 6 mg · Sat. fat 1.1 g")?;
    app.press("text:/^Save meal/")?;
    app.wait_for("text:1 meal")?;
    let kept = stored_meals(dir.path());
    let extra = &kept[0]["foods"][0]["per_100g"]["extra"];
    assert_eq!(extra["fiber"], 10.1);
    assert_eq!(extra["sugars"], 1.0);
    assert_eq!(extra["sodium"], 0.006, "the sodium was typed in mg");
    assert_eq!(extra["sat_fat"], 1.1);
    Ok(())
}

#[test]
fn portions_keep_one_selected_factor_when_grams_round_to_the_same_value() -> Result<(), String> {
    let mut seed = pasta_today();
    let mut meals = navi_health::meal::decode_meals(&seed[0].1);
    meals[0].foods[0].grams = 2.0;
    meals[0].foods[0].estimated_grams = Some(2.0);
    seed[0].1 = encode_meals(&meals);
    let (mut app, _) = start(seed, None);
    app.set_viewport(nsh_core::Size::new(
        nsh_core::Points(320.0),
        nsh_core::Points(640.0),
    ))?;
    app.press("Tomato pasta")?;
    app.press("text:Pasta")?;
    app.wait_for("text:1×")?;
    assert!(app.screen().selected("role:button[1×]")?);
    app.press("text:¾×")?;
    assert!(app.screen().selected("role:button[¾×]")?);
    assert!(!app.screen().selected("role:button[1×]")?);
    app.press("text:2×")?;
    assert_eq!(app.screen().input_text("label:Amount eaten")?, Some("4"));
    app.clear("label:Amount eaten")?;
    app.type_text("label:Amount eaten", "7")?;
    assert!(!app.screen().selected("role:button[2×]")?);
    Ok(())
}

#[test]
fn a_meal_with_more_nutrition_shows_its_sums_and_editor() -> Result<(), String> {
    // 200 g of pasta whose per-100 g extras are fibre 3, sugars 1,
    // sodium 0.005 g and saturated fat 0.2 g.
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
            per_100g: Nutrients::new(150.0, 5.0, 30.0, 1.0).with_extra(ExtraNutrients {
                fiber: 3.0,
                sugars: 1.0,
                sodium: 0.005,
                sat_fat: 0.2,
            }),
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
    app.wait_for("text:Fiber 6 g · Sugars 2 g · Sodium 10 mg · Sat. fat 0.4 g")?;
    app.press("text:Pasta")?;
    app.wait_for("More nutrition")?;
    // The editor's own preview counts the eaten 200 g, same numbers.
    app.wait_for("text:200 g · 300 kcal")?;
    Ok(())
}

#[test]
fn settings_keep_the_goal_as_typed_without_save() -> Result<(), String> {
    let (mut app, storage) = start(Vec::new(), None);
    app.press("label:Settings")?;
    app.press("label:/^Daily calorie goal, /")?;
    app.type_text("label:Daily calorie goal", "1800")?;
    app.press("label:Back")?;
    app.wait_for("label:New entry")?;
    let settings = storage
        .entries()
        .get("settings.v1")
        .cloned()
        .unwrap_or_default();
    assert!(settings.contains("1800"), "the goal is kept: {settings}");
    assert!(!app.shows("text:Save"));
    Ok(())
}

#[test]
fn body_profile_saves_in_its_own_page_and_shows_only_completion_in_settings() -> Result<(), String>
{
    let (mut app, storage) = start(Vec::new(), None);
    app.press("label:Settings")?;
    app.press("label:Body profile, Incomplete")?;
    app.wait_for("label:Height")?;
    app.type_text("label:Height", "170")?;
    app.type_text("label:Birth date", "1991-11-19")?;
    app.press("Male")?;
    app.press("label:Back")?;
    app.wait_for("label:Body profile, Complete")?;
    assert!(!app.shows("text:170 cm"));
    app.press("label:Body profile, Complete")?;
    app.wait_for("label:Height")?;
    assert_eq!(app.screen().input_text("label:Height")?, Some("170"));
    assert_eq!(
        app.screen().input_text("label:Birth date")?,
        Some("1991-11-19")
    );
    assert!(!app.shows("label:Age"));
    let saved: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert_eq!(saved["birth_date"], "1991-11-19");
    assert!(saved.get("age_years").is_none());
    let entries = storage.entries().into_iter().collect();
    drop(app);
    let (mut app, _) = start(entries, None);
    app.press("label:Settings")?;
    app.press("label:Body profile, Complete")?;
    assert_eq!(
        app.screen().input_text("label:Birth date")?,
        Some("1991-11-19")
    );
    Ok(())
}

#[test]
fn body_profile_requests_birth_date_without_inventing_one_from_legacy_age() -> Result<(), String> {
    let (mut app, storage) = start(
        vec![(
            "settings.v1".into(),
            json!({"height_cm":170,"age_years":35,"sex":"male"}).to_string(),
        )],
        None,
    );
    app.press("label:Settings")?;
    app.press("label:Body profile, Incomplete")?;
    app.wait_for("text:/^Legacy age: 35/")?;
    assert_eq!(app.screen().input_text("label:Birth date")?, Some(""));
    let original = storage.entries()["settings.v1"].clone();
    for invalid in [
        "1991-02-29",
        "2030-01-01",
        "2025-01-01",
        "1800-01-01",
        "not a date",
    ] {
        app.clear("label:Birth date")?;
        app.type_text("label:Birth date", invalid)?;
        app.wait_for("text:/^Enter a real birth date/")?;
        assert_eq!(
            storage.entries()["settings.v1"],
            original,
            "invalid: {invalid}"
        );
    }
    app.clear("label:Birth date")?;
    app.type_text("label:Birth date", "2000-02-29")?;
    let saved: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert_eq!(saved["birth_date"], "2000-02-29");
    assert!(saved.get("age_years").is_none());
    let saved_raw = storage.entries()["settings.v1"].clone();
    app.type_text("label:Birth date", "-bad")?;
    app.wait_for("text:/^Enter a real birth date/")?;
    assert_eq!(storage.entries()["settings.v1"], saved_raw);
    app.clear("label:Birth date")?;
    let saved: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert!(saved.get("birth_date").is_none());
    assert!(
        saved.get("age_years").is_none(),
        "clearing DOB cannot revive stale age"
    );
    Ok(())
}

#[test]
fn body_profile_malformed_birth_date_does_not_discard_other_settings() -> Result<(), String> {
    let (mut app, _) = start(
        vec![(
            "settings.v1".into(),
            json!({"height_cm":170,"age_years":35,"sex":"male","birth_date":"1991-02-29"})
                .to_string(),
        )],
        None,
    );
    app.press("label:Settings")?;
    app.press("label:Body profile, Incomplete")?;
    assert_eq!(app.screen().input_text("label:Height")?, Some("170"));
    assert_eq!(app.screen().input_text("label:Birth date")?, Some(""));
    app.wait_for("text:/^Legacy age: 35/")?;
    Ok(())
}

#[test]
fn body_profile_age_advances_at_the_local_birthday_after_resume() -> Result<(), String> {
    use nsh_core::{platform::Lifecycle, time::Clock};
    naviwealth_app::disable_live_market_data();
    naviwealth_app::set_live_updates(false);
    let original =
        json!({"height_cm":170,"age_years":99,"sex":"male","birth_date":"1991-11-19"}).to_string();
    let storage = MemoryStorage::new(vec![("settings.v1".into(), original.clone())]);
    let at: jiff::Timestamp = "2026-11-18T15:59:00Z".parse().unwrap();
    let now = std::time::SystemTime::UNIX_EPOCH + Duration::from_secs(at.as_second() as u64);
    let mut config = EngineConfig::new(Root::of::<App>());
    config.storage = Some(storage.clone());
    config.clock = Clock::manual(now);
    let mut app = Headless::start(config).unwrap();
    app.set_environment("Shanghai", |e| {
        e.locale_settings.time_zone = nsh_core::platform::TimeZone::parse("Asia/Shanghai").unwrap()
    })?;
    app.set_environment("background", |e| e.lifecycle = Lifecycle::Background)?;
    app.set_environment("resume", |e| e.lifecycle = Lifecycle::Active)?;
    app.press("label:Settings")?;
    app.press("label:Body profile, Complete")?;
    app.wait_for("text:Age · 34")?;
    app.set_environment("background", |e| e.lifecycle = Lifecycle::Background)?;
    app.set_system_time(now + Duration::from_secs(60))?;
    app.set_environment("resume", |e| e.lifecycle = Lifecycle::Active)?;
    app.wait_for("text:Age · 35")?;
    assert_eq!(
        storage.entries()["settings.v1"],
        original,
        "age is derived, not rewritten"
    );
    Ok(())
}

#[test]
fn body_profile_birth_date_copy_and_calendar_are_available_in_chinese() -> Result<(), String> {
    use nsh_core::platform::{Locale, LocaleSettings};
    let (mut app, storage) = start(Vec::new(), None);
    let locale = Locale::parse("zh-CN").unwrap();
    app.set_environment("Chinese", |e| {
        e.locale = locale;
        e.locale_settings = LocaleSettings::of(locale);
    })?;
    app.press("label:设置")?;
    app.press("label:身体档案, 资料待补全")?;
    app.wait_for("label:出生日期")?;
    app.press("label:选择出生日期")?;
    app.press("label:选择出生日期")?;
    assert!(
        !storage.entries().contains_key("settings.v1"),
        "opening the calendar must not save a date"
    );
    app.type_text("label:出生日期", "2000-02-29")?;
    app.wait_for("text:/^年龄 · /")?;
    app.press("label:选择出生日期")?;
    app.press("label:2000-02-28")?;
    app.wait_for("label:出生日期")?;
    let saved: Value = serde_json::from_str(&storage.entries()["settings.v1"]).unwrap();
    assert_eq!(saved["birth_date"], "2000-02-28");
    Ok(())
}

#[test]
fn failed_manual_save_preserves_the_editor_and_can_be_retried() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    let dialogs = storage_dialogs(&mut app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_meal BEFORE INSERT ON meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    open_manual(&mut app, "Manual meal")?;
    app.wait_for("text:e.g. Beef noodle soup")?;
    app.type_text("text:e.g. Beef noodle soup", "Rice")?;
    app.type_text("label:Amount eaten", "250")?;
    app.type_text("label:Energy", "130")?;
    app.press("Done")?;
    app.press("text:/^Save meal/")?;
    assert_eq!(dialogs.load(std::sync::atomic::Ordering::Relaxed), 1);
    assert!(stored_meals(dir.path()).is_empty());
    app.wait_for("text:Rice")?;
    assert!(app.screen().enabled("text:/^Save meal/")?);
    db.execute_batch("DROP TRIGGER reject_meal").unwrap();
    app.press("text:/^Save meal/")?;
    app.wait_for("text:1 meal")?;
    assert_eq!(stored_meals(dir.path()).len(), 1);
    Ok(())
}

#[test]
fn failed_delete_keeps_the_meal_and_failed_undo_offers_retry() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    let dialogs = storage_dialogs(&mut app);
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute_batch("CREATE TRIGGER reject_delete BEFORE DELETE ON meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("Tomato pasta")?;
    app.press("label:Delete meal")?;
    assert_eq!(dialogs.load(std::sync::atomic::Ordering::Relaxed), 1);
    assert_eq!(stored_meals(dir.path()).len(), 1);
    app.wait_for("Edit meal")?;
    db.execute_batch("DROP TRIGGER reject_delete; CREATE TRIGGER reject_undo BEFORE INSERT ON meals BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
    app.press("label:Delete meal")?;
    app.wait_for("Meal deleted")?;
    assert!(stored_meals(dir.path()).is_empty());
    app.set_viewport(nsh_core::Size::new(
        nsh_core::Points(360.0),
        nsh_core::Points(640.0),
    ))?;
    app.set_environment("large text", |e| e.font_scale = 1.3)?;
    app.press("Undo")?;
    app.wait_for("Could not save changes. Check device storage and try again.")?;
    for label in [
        "Could not save changes. Check device storage and try again.",
        "Try again",
    ] {
        let nodes = app.screen().layout_nodes();
        let node = nodes
            .iter()
            .find(|node| {
                !node.hidden
                    && node
                        .text
                        .as_ref()
                        .is_some_and(|text| text.text.text.as_str() == label)
            })
            .expect("toast copy and recovery action are mounted");
        assert!(
            node.bounds.origin.x.0 >= 16.0
                && node.bounds.origin.x.0 + node.bounds.size.width.0 <= 344.0,
            "toast text must fit the narrow viewport: {node:?}"
        );
    }
    assert!(stored_meals(dir.path()).is_empty());
    db.execute_batch("DROP TRIGGER reject_undo").unwrap();
    app.press("Try again")?;
    app.wait_for("Tomato pasta")?;
    assert_eq!(stored_meals(dir.path()).len(), 1);
    Ok(())
}

#[test]
fn unreadable_health_records_block_startup_without_sweeping_photos() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (app, _) = start_in(Some(dir.path()), pasta_today(), None);
    drop(app);
    let folder = database_in(dir.path())
        .parent()
        .unwrap()
        .join("meal-photos");
    std::fs::create_dir_all(&folder).unwrap();
    let photo = folder.join("kept.jpg");
    std::fs::write(&photo, b"recoverable photo").unwrap();
    let db = rusqlite::Connection::open(database_in(dir.path())).unwrap();
    db.execute("UPDATE meals SET body='{}'", []).unwrap();
    drop(db);
    let mut config = EngineConfig::new(Root::of::<App>());
    config.storage = Some(MemoryStorage::new(Vec::new()));
    config.data_dir = Some(dir.path().to_owned());
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Local data unavailable")?;
    app.wait(Duration::from_millis(100))?;
    assert!(
        photo.exists(),
        "a failed load must not classify photos as orphans"
    );
    Ok(())
}

#[test]
fn malformed_legacy_meals_remain_available_for_recovery() -> Result<(), String> {
    let raw = json!({"version":1,"meals":[{"id":"malformed"}]}).to_string();
    let storage = MemoryStorage::new(vec![("meals.v1".into(), raw.clone())]);
    let mut config = EngineConfig::new(Root::of::<App>());
    config.storage = Some(storage.clone());
    let mut app = Headless::start(config).unwrap();
    app.wait_for("Local data unavailable")?;
    assert_eq!(storage.entries()["meals.v1"], raw);
    Ok(())
}
