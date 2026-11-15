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
    // Tests never depend on reaching the public quote and FX providers,
    // nor on the releases API the update check reads.
    naviwealth_app::disable_live_market_data();
    naviwealth_app::set_live_updates(false);
    let storage = MemoryStorage::new(entries);
    let mut config = EngineConfig::new(Root::of::<App>());
    config.storage = Some(storage.clone());
    config.data_dir = dir.map(Path::to_path_buf);
    if let Some(network) = network {
        config.network = Some(network);
    }
    let mut app = Headless::start(config).expect("the app starts");
    app.wait_for("label:New entry").expect("the home shows");
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
    response.body = body.to_string().into_bytes();
    response.delay = Duration::from_millis(40);
    response
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

/// The database the app keeps under `dir`.
pub fn database_in(dir: &Path) -> PathBuf {
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
        .to_zoned(jiff::tz::TimeZone::UTC)
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
    json!({"model":"test-model","stop_reason":"end_turn","content":[{"type":"text","text":json!({"records":records,"questions":[]}).to_string()}]})
}

pub fn meal_record() -> Value {
    let meal: Value =
        serde_json::from_str(estimate()["content"][0]["text"].as_str().unwrap()).unwrap();
    json!({"kind":"meal","day":today().to_string(),"slot":"lunch","meal":meal,"money":null,"weight_kg":null})
}

pub fn money_record(amount: &str) -> Value {
    json!({"kind":"money","day":today().to_string(),"slot":null,"meal":null,"weight_kg":null,
        "money":{"kind":"expense","amount":amount,"currency":"CNY","account":"资产:Cash","other_account":null,
            "category":"支出:餐饮","time":null,"payee":"Lunch shop","note":""}})
}

pub fn open_manual(app: &mut Headless, kind: &str) -> Result<(), String> {
    app.press("label:New entry")?;
    app.press("Enter manually")?;
    app.press(kind)?;
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

/// Writes the sample catalog seed beside the database under `dir` (the
/// engine nests instance data, and so the seed, below `default/`).
pub fn seed_catalog(dir: &Path) {
    let seed = dir.join("default").join("catalog-seed.ndjson");
    std::fs::create_dir_all(seed.parent().unwrap()).expect("the instance dir");
    std::fs::write(seed, CATALOG_SAMPLE).expect("the catalog seed is written");
}
