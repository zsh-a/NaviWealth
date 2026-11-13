//! Desktop-only previews for design review: environment variables seed a
//! fresh data directory and open a page, so every state can be shown and
//! captured without a picker or a real account. Not compiled for phones.
//!
//! ```sh
//! NW_PREVIEW=account,trust,meals,goal,weights,dark   # what to seed
//! NW_PREVIEW_BASE_URL=http://127.0.0.1:8799/v1
//! NW_PREVIEW_PHOTOS=/a.jpg:/b.jpg:/c.jpg     # photos of the seeded meals
//! NW_PREVIEW_ROUTE=new:/meal.jpg | manual | edit | settings
//! NW_PREVIEW_EDITOR=1                        # open the first food once foods arrive
//! NW_PREVIEW_GARMIN_KEY_FILE=/path/garmin.key # connect a real Garmin key
//! ```

use std::env;

use nsh_core::{platform::Appearance, prelude::*};

use crate::{
    data::{clock, garmin, meals, photos, settings, weights},
    domain::{
        account::{ModelAccount, Provider},
        catalog,
        meal::{Day, Meal, MealSlot},
        nutrition::{Confidence, Food, FoodSource, Nutrients},
        recognition::Lang,
    },
    nav::{self, Route},
};

/// Applies what the environment asks for; nothing without it.
pub fn apply() {
    let flags = env::var("NW_PREVIEW").unwrap_or_default();
    let route = env::var("NW_PREVIEW_ROUTE").ok();
    if flags.is_empty() && route.is_none() {
        return;
    }
    let has = |flag: &str| flags.split(',').any(|f| f.trim() == flag);
    if has("dark") {
        set_color_scheme(Appearance::Dark);
    } else if has("light") {
        set_color_scheme(Appearance::Light);
    }
    if has("account") {
        let mut account = ModelAccount::new(Provider::Anthropic);
        if let Ok(base) = env::var("NW_PREVIEW_BASE_URL") {
            account.base_url = base;
        }
        account.api_key = "sk-ant-preview-0000".into();
        let goal = has("goal").then_some(2000.0);
        settings::save(account.clone(), goal);
        settings::set_trusted(&account, has("trust"));
    }
    if has("meals") && untracked(meals::all).is_empty() {
        seed_meals();
    }
    if let Ok(path) = env::var("NW_PREVIEW_GARMIN_KEY_FILE")
        && !untracked(garmin::connected)
        && let Ok(key) = std::fs::read_to_string(path)
    {
        spawn(async move {
            if let Err(failure) = garmin::connect(key).await {
                log::warn!("preview: Garmin did not connect: {failure:?}");
            }
        });
    }
    if has("weights") && untracked(|| weights::latest_until(clock::today())).is_none() {
        // A month drifting down, with a few days skipped.
        let today = untracked(clock::today);
        for back in (0..30).rev().filter(|back| back % 4 != 2) {
            let kg = 74.6 - f64::from(29 - back) * 0.07 + [0.3, -0.2, 0.1, -0.1][back as usize % 4];
            weights::set(today.plus_days(-back), kg);
        }
    }
    match route.as_deref() {
        Some(r) if r.starts_with("new:") => {
            if let Ok(bytes) = std::fs::read(&r[4..]) {
                let capture = photos::hold(bytes);
                nav::push(Route::NewMeal {
                    day: untracked(clock::today),
                    capture: Some(capture),
                });
            }
        }
        Some("manual") => nav::push(Route::NewMeal {
            day: untracked(clock::today),
            capture: None,
        }),
        Some("edit") => {
            if let Some(meal) = untracked(|| meals::on(clock::today())).into_iter().nth(1) {
                nav::push(Route::EditMeal(meal.id));
            }
        }
        Some("settings") => nav::push(Route::Settings),
        _ => {}
    }
}

/// Whether to open the first food's editor once foods arrive.
pub fn wants_editor() -> bool {
    env::var("NW_PREVIEW_EDITOR").is_ok()
}

fn at(day: Day, hour: i8, minute: i8) -> i64 {
    day.0
        .at(hour, minute, 0, 0)
        .to_zoned(clock::zone())
        .map(|time| time.timestamp().as_millisecond())
        .unwrap_or_else(|_| clock::now_ms())
}

fn food(name: &str, grams: f64, per_100g: Nutrients, source: FoodSource) -> Food {
    Food {
        id: meals::new_food_id(),
        name: name.to_owned(),
        grams,
        per_100g,
        source,
        confidence: None,
        estimated_grams: Some(grams),
    }
}

fn catalog_food(id: &str, name: &str, grams: f64) -> Food {
    let record = catalog::by_id(id).expect("a catalog id");
    food(
        name,
        grams,
        record.per_100g,
        FoodSource::Catalog {
            fdc_id: id.to_owned(),
        },
    )
}

fn seed_meals() {
    let zh = Lang::from_language(locale().language()) == Lang::Zh;
    let t = |en: &'static str, cn: &'static str| if zh { cn } else { en };
    let today = untracked(clock::today);
    let photo_paths: Vec<String> = env::var("NW_PREVIEW_PHOTOS")
        .map(|list| list.split(':').map(str::to_owned).collect())
        .unwrap_or_default();
    let photo = |index: usize, id: &str| -> Option<String> {
        let bytes = std::fs::read(photo_paths.get(index)?).ok()?;
        let (_, keep) = photos::prepare(&bytes)?;
        let name = format!("{id}.jpg");
        photos::keep(&name, &keep);
        Some(name)
    };
    let mut noodles = food(
        t("Beef noodle soup", "红烧牛肉面"),
        520.0,
        Nutrients::new(95.0, 5.8, 11.5, 2.9),
        FoodSource::Estimate,
    );
    noodles.confidence = Some(Confidence::Medium);
    let seeded = [
        (
            today,
            8,
            10,
            MealSlot::Breakfast,
            t("Banana oatmeal", "香蕉燕麦粥"),
            vec![
                food(
                    t("Oatmeal, cooked", "燕麦粥"),
                    240.0,
                    Nutrients::new(71.0, 2.5, 12.0, 1.5),
                    FoodSource::Estimate,
                ),
                catalog_food("173944", t("Banana", "香蕉"), 110.0),
                catalog_food("171265", t("Whole milk", "全脂牛奶"), 180.0),
            ],
            Some(1),
        ),
        (
            today,
            12,
            35,
            MealSlot::Lunch,
            t("Beef noodle soup", "红烧牛肉面"),
            vec![
                noodles,
                food(
                    t("Marinated egg", "卤蛋"),
                    50.0,
                    Nutrients::new(155.0, 12.6, 1.1, 10.6),
                    FoodSource::Estimate,
                ),
            ],
            Some(0),
        ),
        (
            today.plus_days(-1),
            19,
            5,
            MealSlot::Dinner,
            t("Curry chicken with rice", "咖喱鸡饭"),
            vec![
                food(
                    t("Curry chicken", "咖喱鸡"),
                    220.0,
                    Nutrients::new(150.0, 13.0, 6.0, 8.0),
                    FoodSource::Estimate,
                ),
                catalog_food("168878", t("White rice", "白米饭"), 200.0),
            ],
            Some(2),
        ),
    ];
    for (day, hour, minute, slot, title, foods, photo_index) in seeded {
        let id = meals::new_meal_id();
        let photo = photo_index.and_then(|index| photo(index, &id));
        meals::save(Meal {
            id,
            day,
            logged_at_ms: at(day, hour, minute),
            slot,
            title: Some(title.to_owned()),
            foods,
            photo,
            model: Some("claude-opus-5-5".into()),
            prompt_version: None,
        });
    }
}
