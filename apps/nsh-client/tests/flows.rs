//! The user's flows on the real engine, headless: a stub network stands in
//! for the model provider and a stub picker for the photo library.

use std::{
    io::Cursor,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use image::{ImageFormat, RgbImage};
use nsh_app_naviwealth_health::{
    App,
    domain::{
        meal::{Day, Meal, MealSlot, encode_meals},
        nutrition::{Food, FoodSource, Nutrients},
    },
};
use nsh_core::{ImageData, picker::PickedFile};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::{Headless, MemoryStorage, StubNetwork, StubResponse};
use serde_json::{Value, json};

const MESSAGES: &str = "POST https://api.anthropic.com/v1/messages";
const GONE: Duration = Duration::from_secs(5);

fn start(
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
) -> (Headless, Arc<MemoryStorage>) {
    start_in(None, entries, network)
}

/// Starts the app keeping its files (the database) under `dir`; without
/// one the database lives in memory.
fn start_in(
    dir: Option<&Path>,
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
) -> (Headless, Arc<MemoryStorage>) {
    let storage = MemoryStorage::new(entries);
    let mut config = EngineConfig::new(Root::of::<App>());
    config.storage = Some(storage.clone());
    config.data_dir = dir.map(Path::to_path_buf);
    if let Some(network) = network {
        config.network = Some(network);
    }
    let mut app = Headless::start(config).expect("the app starts");
    app.wait_for("Log a meal").expect("Today shows");
    (app, storage)
}

fn account(trusted: bool) -> Vec<(String, String)> {
    let fingerprint = json!([
        "anthropic",
        "https://api.anthropic.com/v1",
        "claude-opus-5-5"
    ])
    .to_string();
    let settings = json!({
        "account": {
            "provider": "anthropic",
            "base_url": "https://api.anthropic.com/v1",
            "model": "claude-opus-5-5"
        },
        "trusted": if trusted { vec![fingerprint] } else { vec![] },
    });
    vec![
        ("settings.v1".to_owned(), settings.to_string()),
        ("secret.model-key.v1".to_owned(), "sk-test-key".to_owned()),
    ]
}

fn response(status: u16, body: Value) -> StubResponse {
    let mut response = StubResponse::default();
    response.status = status;
    response.body = body.to_string().into_bytes();
    response.delay = Duration::from_millis(40);
    response
}

fn estimate() -> Value {
    let answer = json!({
        "title": "Beef noodle soup",
        "foods": [
            { "name": "Beef noodle soup", "grams": 480, "catalog_id": null, "confidence": "medium",
              "per_100g": { "kcal": 92, "protein": 5.6, "carbs": 11.8, "fat": 2.6 } },
            { "name": "White rice", "grams": 150, "catalog_id": "168878", "confidence": "high",
              "per_100g": { "kcal": 1, "protein": 1, "carbs": 1, "fat": 1 } }
        ]
    });
    json!({
        "model": "claude-opus-5-5",
        "stop_reason": "end_turn",
        "content": [{ "type": "text", "text": answer.to_string() }]
    })
}

fn network(status: u16, body: Value) -> Arc<StubNetwork> {
    Arc::new(StubNetwork::new([(
        MESSAGES.to_owned(),
        response(status, body),
    )]))
}

fn photo() -> Vec<u8> {
    let image = RgbImage::from_fn(96, 72, |x, y| {
        image::Rgb([(x * 2) as u8, (y * 3) as u8, 120])
    });
    let mut bytes = Cursor::new(Vec::new());
    image.write_to(&mut bytes, ImageFormat::Png).expect("a PNG");
    bytes.into_inner()
}

fn picks_a_photo(app: &mut Headless) {
    let bytes = photo();
    app.on_pick(move |_| {
        vec![PickedFile::new(
            "meal.png",
            "image/png",
            ImageData::new(bytes.clone()),
        )]
    });
}

/// The database the app keeps under `dir`.
fn database_in(dir: &Path) -> PathBuf {
    fn find(dir: &Path) -> Option<PathBuf> {
        for entry in std::fs::read_dir(dir).ok()?.flatten() {
            let path = entry.path();
            if path
                .file_name()
                .is_some_and(|name| name == "naviwealth.sqlite")
            {
                return Some(path);
            }
            if path.is_dir()
                && let Some(found) = find(&path)
            {
                return Some(found);
            }
        }
        None
    }
    find(dir).expect("the app keeps a database")
}

/// The stored meal bodies under `dir`, oldest first.
fn stored_meals(dir: &Path) -> Vec<Value> {
    let connection = rusqlite::Connection::open(database_in(dir)).expect("the database opens");
    let mut statement = connection
        .prepare("SELECT body FROM meals ORDER BY logged_at_ms")
        .unwrap();
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .map(|body| serde_json::from_str(&body.unwrap()).unwrap())
        .collect()
}

fn today() -> Day {
    Day(jiff::Timestamp::now()
        .to_zoned(jiff::tz::TimeZone::UTC)
        .date())
}

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

/// A saved 300 kcal pasta lunch today, as the legacy entry that moves in.
fn pasta_today() -> Vec<(String, String)> {
    let meal = Meal {
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
            source: FoodSource::Catalog {
                fdc_id: "168927".to_owned(),
            },
            confidence: None,
            estimated_grams: None,
        }],
        photo: None,
        model: None,
        prompt_version: None,
    };
    vec![("meals.v1".to_owned(), encode_meals(&[meal]))]
}

#[test]
fn a_saved_meal_can_be_logged_again_today() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    app.wait_for("text:300")?;
    app.press("Tomato pasta")?;
    app.wait_for("Edit meal")?;
    app.press("Log again today")?;
    app.wait_for("New meal")?;
    app.press("text:/^Save meal/")?;
    app.wait_for("text:2 meals")?;
    app.wait_for("text:600")?;
    let kept = stored_meals(dir.path());
    assert_eq!(kept.len(), 2, "a second meal, the first unchanged");
    assert_ne!(kept[0]["id"], kept[1]["id"]);
    assert_ne!(kept[0]["foods"][0]["id"], kept[1]["foods"][0]["id"]);
    assert_eq!(kept[1]["foods"][0]["name"], "Pasta");
    Ok(())
}

#[test]
fn a_recent_food_fills_the_new_food() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), pasta_today(), None);
    app.wait_for("text:300")?;
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

fn stored_weights(dir: &Path) -> Vec<(String, f64)> {
    let connection = rusqlite::Connection::open(database_in(dir)).expect("the database opens");
    let mut statement = connection
        .prepare("SELECT day, kg FROM weights ORDER BY day")
        .unwrap();
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

#[test]
fn todays_weight_is_logged_kept_and_checked() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("text:Tap to log today's weight")?;
    app.press("text:Tap to log today's weight")?;
    app.wait_for("Save weight")?;
    app.type_text("label:Weight", "5")?;
    app.press("Save weight")?;
    app.wait_for("text:Enter a weight between 20 and 400 kg.")?;
    assert!(
        stored_weights(dir.path()).is_empty(),
        "nothing out of range is kept"
    );

    // Typing appends: the field now reads 52.44, kept to one decimal.
    app.type_text("label:Weight", "2.44")?;
    app.press("Save weight")?;
    app.wait_for("text:52.4")?;
    assert_eq!(stored_weights(dir.path()), [(today().to_string(), 52.4)]);
    drop(app);

    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.wait_for("text:52.4")?;
    Ok(())
}

#[test]
fn deleting_a_weight_can_be_undone() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, _) = start_in(Some(dir.path()), Vec::new(), None);
    app.press("text:Tap to log today's weight")?;
    app.type_text("label:Weight", "70")?;
    app.press("Save weight")?;
    app.wait_for("text:70.0")?;
    app.press("text:70.0")?;
    app.press("Delete")?;
    app.wait_for("Weight deleted")?;
    assert!(stored_weights(dir.path()).is_empty());
    app.press("Undo")?;
    app.wait_for("text:70.0")?;
    assert_eq!(stored_weights(dir.path()).len(), 1);
    Ok(())
}

fn raw(status: u16, body: &str) -> StubResponse {
    let mut response = StubResponse::default();
    response.status = status;
    response.body = body.as_bytes().to_vec();
    response.delay = Duration::from_millis(20);
    response
}

const GARMIN_COM: &str = "https://personal.connectapi.garmin.com";
const GARMIN_CN: &str = "https://personal.connectapi.garmin.cn";

/// Garmin as a garmin.cn account sees it: the global host does not know
/// the key, the China host gives a token and today's numbers.
fn garmin_cn() -> Arc<StubNetwork> {
    let day = today().to_string();
    let not_here =
        r#"{"message":"Personal API Key with ID x does not exist.","error":"NotFoundException"}"#;
    let daily = json!({"data": [{"calendarDate": day, "heartRate": {"restingValue": 44},
        "bodyBattery": {"maxValue": 97}, "stress": {"avgLevel": 26},
        "movement": {"steps": {"value": 13794}}}]});
    let sleep = json!([{"calendarDate": day, "sleepTimeSeconds": 27120,
        "sleepScores": {"overall": {"value": 89}}}]);
    let hrv =
        json!({"hrvSummaries": [{"calendarDate": day, "lastNightAvg": 75, "status": "BALANCED"}]});
    Arc::new(StubNetwork::new([
        (
            format!("POST {GARMIN_COM}/personalapitoken-service/*"),
            raw(404, not_here),
        ),
        (
            format!("POST {GARMIN_CN}/personalapitoken-service/*"),
            raw(200, "aaa.bbb.ccc"),
        ),
        (
            format!("GET {GARMIN_CN}/usersummary-service/v2/dailysummaries*"),
            raw(200, &daily.to_string()),
        ),
        (
            format!("GET {GARMIN_CN}/sleep-service/*"),
            raw(200, &sleep.to_string()),
        ),
        (
            format!("GET {GARMIN_CN}/hrv-service/*"),
            raw(200, &hrv.to_string()),
        ),
    ]))
}

#[test]
fn a_garmin_key_connects_in_its_region_and_brings_todays_numbers() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let stub = garmin_cn();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), Some(stub.clone()));
    app.press("label:Settings")?;
    app.wait_for("Personal API key")?;
    app.type_text("text:Paste your Garmin key", "GCDC-test-key")?;
    app.press("Connect")?;
    app.wait_for("text:Connected · garmin.cn")?;
    assert_eq!(
        storage
            .entries()
            .get("secret.garmin-key.v1")
            .map(String::as_str),
        Some("GCDC-test-key")
    );
    app.press("label:Back")?;
    app.wait_for("text:7h 32m")?;
    let data: Vec<_> = stub
        .requests()
        .into_iter()
        .filter(|r| r.method == "GET")
        .collect();
    assert_eq!(data.len(), 3, "daily, sleep and HRV");
    assert!(data.iter().all(|r| {
        r.url.starts_with(GARMIN_CN)
            && r.headers
                .iter()
                .any(|(n, v)| n.eq_ignore_ascii_case("authorization") && v == "Bearer aaa.bbb.ccc")
    }));

    app.wait_for("text:Score 89")?;
    app.wait_for("text:44 bpm")?;
    app.wait_for("text:75 ms")?;
    app.wait_for("text:13,794")?;
    drop(app);

    // Kept: a restart within 30 minutes shows them without asking Garmin.
    let quiet = Arc::new(StubNetwork::new([] as [(String, StubResponse); 0]));
    let (mut app, _) = start_in(
        Some(dir.path()),
        storage.entries().into_iter().collect(),
        Some(quiet.clone()),
    );
    app.wait_for("text:7h 32m")?;
    assert!(quiet.requests().is_empty());
    Ok(())
}

#[test]
fn a_garmin_key_neither_region_knows_is_refused_and_not_kept() -> Result<(), String> {
    let gone = r#"{"message":"does not exist","error":"NotFoundException"}"#;
    let stub = Arc::new(StubNetwork::new([
        (
            format!("POST {GARMIN_COM}/personalapitoken-service/*"),
            raw(404, gone),
        ),
        (
            format!("POST {GARMIN_CN}/personalapitoken-service/*"),
            raw(404, gone),
        ),
    ]));
    let (mut app, storage) = start(Vec::new(), Some(stub));
    app.press("label:Settings")?;
    app.type_text("text:Paste your Garmin key", "GCDC-old")?;
    app.press("Connect")?;
    app.wait_for("text:Garmin did not accept the key. It may have expired; create a new one.")?;
    assert!(!storage.entries().contains_key("secret.garmin-key.v1"));
    Ok(())
}

#[test]
fn the_api_key_is_kept_apart_from_the_settings() -> Result<(), String> {
    let (mut app, storage) = start(Vec::new(), None);
    app.press("label:Settings")?;
    app.wait_for("Vision model")?;
    app.type_text("text:Paste your key", "sk-ant-secret")?;
    app.press("Save")?;
    app.wait_for("Log a meal")?;
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
