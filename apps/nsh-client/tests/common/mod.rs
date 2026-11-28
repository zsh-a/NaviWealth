//! Helpers shared by the flow tests: starting the app headless with a
//! stub network, reading what it kept, and the fixtures.
#![allow(dead_code, unused_imports)]

pub use std::{
    io::Cursor,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

pub use image::{ImageFormat, RgbImage};
pub use naviwealth_app::{
    App,
    domain::{
        meal::{Day, Meal, MealSlot, encode_meals},
        nutrition::{ExtraNutrients, Food, FoodSource, Nutrients},
    },
};
pub use nsh_core::{ImageData, picker::PickedFile, platform::HttpRequest};
pub use nsh_engine::{EngineConfig, Root};
pub use nsh_testing::{Headless, MemoryStorage, StubNetwork, StubResponse};
pub use serde_json::{Value, json};

pub const MESSAGES: &str = "POST https://api.anthropic.com/v1/messages";
pub const GONE: Duration = Duration::from_secs(5);

pub fn start(
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
) -> (Headless, Arc<MemoryStorage>) {
    start_in(None, entries, network)
}

/// Starts the app keeping its files (the database) under `dir`; without
/// one the database lives in memory.
pub fn start_in(
    dir: Option<&Path>,
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
) -> (Headless, Arc<MemoryStorage>) {
    start_in_with_clock(dir, entries, network, nsh_core::time::Clock::system())
}

pub fn start_in_with_clock(
    dir: Option<&Path>,
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
    clock: nsh_core::time::Clock,
) -> (Headless, Arc<MemoryStorage>) {
    start_root(dir, entries, network, clock, false)
}

pub fn start_legacy(
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
) -> (Headless, Arc<MemoryStorage>) {
    start_legacy_in(None, entries, network)
}

pub fn start_legacy_in(
    dir: Option<&Path>,
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
) -> (Headless, Arc<MemoryStorage>) {
    start_root(dir, entries, network, nsh_core::time::Clock::system(), true)
}

pub fn start_legacy_in_with_clock(
    dir: Option<&Path>,
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
    clock: nsh_core::time::Clock,
) -> (Headless, Arc<MemoryStorage>) {
    start_root(dir, entries, network, clock, true)
}

fn start_root(
    dir: Option<&Path>,
    entries: Vec<(String, String)>,
    network: Option<Arc<StubNetwork>>,
    clock: nsh_core::time::Clock,
    legacy: bool,
) -> (Headless, Arc<MemoryStorage>) {
    // Tests never depend on reaching the public quote and FX providers,
    // nor on the releases API the update check reads.
    naviwealth_app::disable_live_market_data();
    naviwealth_app::use_host_capture_transport();
    naviwealth_app::set_live_updates(false);
    let storage = MemoryStorage::new(entries);
    let mut config = EngineConfig::new(if legacy {
        Root::of::<naviwealth_app::LegacyCaptureHarness>()
    } else {
        Root::of::<App>()
    });
    config.clock = clock;
    config.storage = Some(storage.clone());
    config.data_dir = dir.map(Path::to_path_buf);
    if let Some(network) = network {
        config.network = Some(network);
    }
    let mut app = Headless::start(config).expect("the app starts");
    app.wait_for(if legacy {
        "label:New entry"
    } else {
        "label:Conversation"
    })
    .expect("the home shows");
    (app, storage)
}

pub fn account(trusted: bool) -> Vec<(String, String)> {
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
        "trusted": if trusted { vec![fingerprint.clone()] } else { vec![] },
        "trusted_capture": if trusted { vec![fingerprint] } else { vec![] },
    });
    vec![
        ("settings.v1".to_owned(), settings.to_string()),
        ("secret.model-key.v1".to_owned(), "sk-test-key".to_owned()),
    ]
}

pub fn response(status: u16, body: Value) -> StubResponse {
    let mut response = StubResponse::default();
    response.status = status;
    // Feed fixtures through the real pi provider SSE parser. The headless
    // network relay changes only the destination, never model wire content.
    if status == 200 && (body.get("stop_reason").is_some() || body["object"] == "response") {
        response
            .headers
            .push(("content-type".into(), "text/event-stream".into()));
        response.body = model_events(&body).into_bytes();
    } else {
        response.body = body.to_string().into_bytes();
    }
    response.delay = Duration::from_millis(40);
    response
}

fn model_events(body: &Value) -> String {
    let mut events = String::new();
    let mut emit = |kind: &str, mut value: Value| {
        value["type"] = kind.into();
        events.push_str(&format!("event: {kind}\ndata: {value}\n\n"));
    };
    if body["object"] == "response" {
        for (index, item) in body["output"].as_array().unwrap().iter().enumerate() {
            emit(
                "response.output_item.added",
                json!({"output_index":index,"item":item}),
            );
            emit(
                "response.output_item.done",
                json!({"output_index":index,"item":item}),
            );
        }
        emit("response.completed", json!({"response":body}));
        return events;
    }
    emit(
        "message_start",
        json!({"message":{"id":"msg-fixture","type":"message",
        "role":"assistant","model":body["model"],"content":[],"stop_reason":null,
        "usage":{"input_tokens":10,"output_tokens":0}}}),
    );
    for (index, block) in body["content"].as_array().unwrap().iter().enumerate() {
        let mut start = block.clone();
        let delta = match block["type"].as_str() {
            Some("text") => {
                start["text"] = "".into();
                Some(json!({"type":"text_delta","text":block["text"]}))
            }
            Some("tool_use") => {
                start["input"] = json!({});
                Some(json!({"type":"input_json_delta","partial_json":block["input"].to_string()}))
            }
            Some("thinking") => {
                start["thinking"] = "".into();
                start["signature"] = "".into();
                Some(json!({"type":"thinking_delta","thinking":block["thinking"]}))
            }
            _ => None,
        };
        emit(
            "content_block_start",
            json!({"index":index,"content_block":start}),
        );
        if let Some(delta) = delta {
            emit("content_block_delta", json!({"index":index,"delta":delta}));
        }
        if block["type"] == "thinking" {
            emit(
                "content_block_delta",
                json!({"index":index,"delta":{
                "type":"signature_delta","signature":block["signature"]}}),
            );
        }
        emit("content_block_stop", json!({"index":index}));
    }
    emit(
        "message_delta",
        json!({"delta":{"stop_reason":body["stop_reason"],"stop_sequence":null},
        "usage":{"output_tokens":20}}),
    );
    emit("message_stop", json!({}));
    events
}

pub fn estimate() -> Value {
    let answer = json!({
        "title": "Beef noodle soup",
        "foods": [
            { "name": "Beef noodle soup", "grams": 480, "catalog_id": null, "confidence": "medium",
              "per_100g": { "kcal": 92, "protein": 5.6, "carbs": 11.8, "fat": 2.6,
                            "fiber": 1.2, "sugars": 1.5, "sat_fat": 1.0, "sodium_mg": 480.0 } },
            { "name": "White rice", "grams": 150, "catalog_id": "168878", "confidence": "high",
              "per_100g": { "kcal": 1, "protein": 1, "carbs": 1, "fat": 1,
                            "fiber": null, "sugars": null, "sat_fat": null, "sodium_mg": null } }
        ]
    });
    json!({
        "model": "claude-opus-5-5",
        "stop_reason": "end_turn",
        "content": [{ "type": "text", "text": answer.to_string() }]
    })
}

pub fn network(status: u16, body: Value) -> Arc<StubNetwork> {
    Arc::new(StubNetwork::new([(
        MESSAGES.to_owned(),
        response(status, body),
    )]))
}

pub fn photo() -> Vec<u8> {
    let image = RgbImage::from_fn(96, 72, |x, y| {
        image::Rgb([(x * 2) as u8, (y * 3) as u8, 120])
    });
    let mut bytes = Cursor::new(Vec::new());
    image.write_to(&mut bytes, ImageFormat::Png).expect("a PNG");
    bytes.into_inner()
}

pub fn picks_a_photo(app: &mut Headless) {
    let bytes = photo();
    app.on_pick(move |_| {
        vec![PickedFile::new(
            "meal.png",
            "image/png",
            ImageData::new(bytes.clone()),
        )]
    });
}

/// NSH uses the configured app data directory as supplied.
pub fn database_in(dir: &Path) -> PathBuf {
    let path = dir.join("naviwealth.sqlite");
    assert!(path.is_file(), "the app keeps its database at {path:?}");
    path
}

/// The stored meal bodies under `dir`, oldest first.
pub fn stored_meals(dir: &Path) -> Vec<Value> {
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

pub fn today() -> Day {
    Day(jiff::Timestamp::now()
        .to_zoned_datetime(jiff::tz::TimeZone::UTC)
        .date())
}

/// A saved 300 kcal pasta lunch today, as the legacy entry that moves in.
pub fn pasta_today() -> Vec<(String, String)> {
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
            per_100g: Nutrients::new(100.0, 4.0, 20.0, 1.0).with_extra(ExtraNutrients {
                fiber: 2.5,
                sugars: 1.2,
                sodium: 0.004,
                sat_fat: 0.3,
            }),
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

pub fn stored_weights(dir: &Path) -> Vec<(String, f64)> {
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

pub fn raw(status: u16, body: &str) -> StubResponse {
    let mut response = StubResponse::default();
    response.status = status;
    response.body = body.as_bytes().to_vec();
    response.delay = Duration::from_millis(20);
    response
}

pub const GARMIN_COM: &str = "https://personal.connectapi.garmin.com";
pub const GARMIN_CN: &str = "https://personal.connectapi.garmin.cn";

/// Garmin as a garmin.cn account sees it: the global host does not know
/// the key, the China host gives a token and today's numbers.
pub fn garmin_cn() -> Arc<StubNetwork> {
    garmin_cn_with_delay(Duration::from_millis(20))
}

pub fn garmin_cn_with_delay(delay: Duration) -> Arc<StubNetwork> {
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
    let data = |body: &str| {
        let mut response = raw(200, body);
        response.delay = delay;
        response
    };
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
            data(&daily.to_string()),
        ),
        (
            format!("GET {GARMIN_CN}/sleep-service/*"),
            data(&sleep.to_string()),
        ),
        (
            format!("GET {GARMIN_CN}/hrv-service/*"),
            data(&hrv.to_string()),
        ),
    ]))
}

pub fn record_reply(records: Vec<Value>) -> Value {
    static NEXT_RESULT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(1);
    let id = NEXT_RESULT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    json!({"model":"test-model","stop_reason":"tool_use","content":[{
        "type":"tool_use","id":format!("result-{id}"),"name":"emit_result",
        "input":{"destination":null,"records":records}
    }]})
}

pub fn meal_record() -> Value {
    let mut meal: Value =
        serde_json::from_str(estimate()["content"][0]["text"].as_str().unwrap()).unwrap();
    meal["source_image"] = Value::Null;
    json!({"kind":"meal","day":today().to_string(),"slot":"lunch","meal":meal,"money":null,"trade":null,"balance":null,"price":null,"note":null,"evidence":[],"weight_kg":null})
}

pub fn money_record(amount: &str) -> Value {
    json!({"kind":"money","day":today().to_string(),"slot":null,"meal":null,"trade":null,"balance":null,"price":null,"note":null,"evidence":[],"weight_kg":null,
        "money":{"kind":"expense","amount":amount,"currency":"CNY","account":"资产:Cash","other_account":null,
            "category":"支出:餐饮","time":null,"payee":"Lunch shop","note":""}})
}

pub fn open_manual(app: &mut Headless, kind: &str) -> Result<(), String> {
    if app.screen().enabled("label:New entry").is_ok() {
        app.press("label:New entry")?;
        app.press("Enter manually")?;
        app.press(kind)?;
    } else {
        if app.screen().enabled("label:Message").is_err() {
            app.press("label:Conversation")?;
        }
        app.press("label:Attach or add manually")?;
        app.press(match kind {
            "Meal" | "Manual meal" => "Meal by hand",
            "Weight" | "Log weight" => "Weight by hand",
            _ => "Transaction by hand",
        })?;
    }
    Ok(())
}

pub fn attach_capture(app: &mut Headless) -> Result<(), String> {
    picks_a_photo(app);
    app.press("label:New entry")?;
    app.press("Attach image")?;
    app.wait_for("Remove image")?;
    app.press("label:Send")?;
    Ok(())
}

/// The sample catalog shipped with the tests; a data dir seeded with it
/// installs the catalog offline so search and link flows work.
pub const CATALOG_SAMPLE: &str =
    include_str!("../../../../tool/asset_catalog/tests/fixtures/catalog-sample.ndjson");

/// Writes the sample catalog seed beside the database in the app data directory.
pub fn seed_catalog(dir: &Path) {
    std::fs::write(dir.join("catalog-seed.ndjson"), CATALOG_SAMPLE)
        .expect("the catalog seed is written");
}

/// Check the native failure dialog while allowing the editor to keep its state.
pub fn storage_dialogs(app: &mut Headless) -> Arc<std::sync::atomic::AtomicUsize> {
    let count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let observed = count.clone();
    app.on_dialog(move |dialog| {
        assert_eq!(dialog.title.as_deref(), Some("Local data unavailable"));
        assert_eq!(
            dialog.message.as_deref(),
            Some("Could not save changes. Check device storage and try again.")
        );
        observed.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        nsh_testing::DialogAnswer::Press("Close".into())
    });
    count
}

/// Manual editors return to the conversation that launched them. Tests that
/// inspect home records explicitly leave that conversation after saving.
pub trait ConversationNavigation {
    fn conversation_home(&mut self) -> Result<(), String>;
}
impl ConversationNavigation for Headless {
    fn conversation_home(&mut self) -> Result<(), String> {
        if self.screen().enabled("label:Message").is_ok() {
            self.press("label:Back")?;
            self.wait_for("label:Conversation")?;
        }
        Ok(())
    }
}
