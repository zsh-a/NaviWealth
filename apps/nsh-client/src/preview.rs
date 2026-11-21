//! Desktop-only previews for design review: environment variables seed a
//! fresh data directory and open a page, so every state can be shown and
//! captured without a picker or a real account. Not compiled for phones.
//!
//! ```sh
//! NW_PREVIEW=account,trust,meals,goal,weights,dark   # what to seed
//! NW_PREVIEW_BASE_URL=http://127.0.0.1:8799/v1
//! NW_PREVIEW_PHOTOS=/a.jpg:/b.jpg:/c.jpg     # photos of the seeded meals
//! NW_PREVIEW_ROUTE=new:/meal.jpg | manual | edit | settings | model | review | review-month | records-jump | records-day
//! NW_PREVIEW_EDITOR=1                        # open the first food once foods arrive
//! NW_PREVIEW_GARMIN_KEY_FILE=/path/garmin.key # connect a real Garmin key
//! ```

use std::env;

use nsh_core::{platform::Appearance, prelude::*};

use crate::{
    data::{
        body_metrics, clock, favorites, finance, garmin, meals, pending, photos, settings, weights,
    },
    domain::{
        account::{ModelAccount, Provider},
        catalog,
        meal::{Day, Meal, MealSlot},
        nutrition::{Confidence, Food, FoodSource, Nutrients},
        pending::{PendingMeal, PendingStatus},
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
        let mut account = ModelAccount::new(if has("responses") {
            Provider::OpenAiResponses
        } else {
            Provider::Anthropic
        });
        if account.model.is_empty() {
            account.model = "preview-vision-model".into();
        }
        if let Ok(base) = env::var("NW_PREVIEW_BASE_URL") {
            account.base_url = base;
        }
        account.api_key = "sk-ant-preview-0000".into();
        let goal = has("goal").then_some(2000.0);
        settings::save_account(account.clone());
        settings::save_goal(goal);
        settings::set_trusted(&account, has("trust"));
    }
    if has("meals") && untracked(meals::all).is_empty() {
        seed_meals();
    }
    if has("finance") && untracked(finance::transactions).is_empty() {
        use navi_finance::{
            account::{Account, AccountKind, defaults},
            journal::{self, Entry, Source},
        };
        let cash = Account::new(AccountKind::Assets, "Wallet").unwrap();
        let bank = Account::new(AccountKind::Assets, "Bank").unwrap();
        let today = untracked(clock::today).0;
        for (id, day, hour, payee, amount) in [
            ("preview-lunch", today, 12, "Lunch", 3150),
            ("preview-groceries", today, 16, "Groceries", 6800),
            (
                "preview-earlier",
                today.yesterday().unwrap(),
                18,
                "Dinner",
                4250,
            ),
        ] {
            let t = journal::spend(
                Entry {
                    id: id.into(),
                    at: day.at(hour, 30, 0, 0),
                    payee: payee.into(),
                    note: String::new(),
                    source: Source::Manual,
                },
                &cash,
                &defaults::expense("餐饮"),
                amount,
            )
            .unwrap();
            let _ = finance::save(t);
        }
        let t = journal::transfer(
            Entry {
                id: "preview-transfer".into(),
                at: today.at(9, 0, 0, 0),
                payee: String::new(),
                note: String::new(),
                source: Source::Manual,
            },
            &bank,
            &cash,
            20000,
        )
        .unwrap();
        let _ = finance::save(t);
    }
    if has("assets") {
        use navi_finance::{
            account::{Account, AccountKind},
            repository::BalanceCheck,
        };
        for (name, kind, actual) in [
            ("Wallet", AccountKind::Assets, 120000),
            ("Bank", AccountKind::Assets, 5234080),
            ("Credit card", AccountKind::Liabilities, -234560),
        ] {
            let a = Account::new(kind, name).unwrap();
            if !finance::accounts().contains(&a) {
                let _ = finance::create_account(a.clone());
            }
            let day = clock::today().plus_days(-20);
            let check = BalanceCheck {
                id: format!("preview-opening-{name}"),
                account: a,
                day: day.0,
                actual,
                checked_at: clock::zoned(clock::now_ms()).datetime(),
            };
            let _ = finance::confirm_balance(check, 0);
        }
    }
    if has("holdings") && finance::holdings().securities.is_empty() {
        use navi_finance::holdings::{Kind, Quote, Security, Trade};
        let name = if crate::i18n::s().lang == Lang::Zh {
            "沪深300ETF"
        } else {
            "CSI 300 ETF"
        };
        let sec = Security::new("preview-etf", name).unwrap();
        let day = clock::today().plus_days(-18);
        let opening = Trade {
            id: "preview-units".into(),
            security: sec.id.clone(),
            at: day.0.at(12, 0, 0, 0),
            kind: Kind::Opening,
            quantity: 1_000_000_000,
            price: 4_125_000,
            amount: 0,
            fee: 0,
            cash: None,
        };
        finance::add_trade(Some(&sec), &opening).unwrap();
        if !has("unpriced") {
            finance::set_quote(&Quote {
                security: sec.id.clone(),
                day: clock::today().plus_days(-1).0,
                price: 4_380_000,
            })
            .unwrap();
        }
        if route.as_deref() == Some("closed-holdings") {
            finance::add_trade(
                None,
                &Trade {
                    id: "preview-close".into(),
                    security: sec.id,
                    at: clock::today().0.at(12, 0, 0, 0),
                    kind: Kind::Sell,
                    quantity: opening.quantity,
                    price: 4_380_000,
                    cash: Some(navi_finance::account::Account::parse("资产:Bank").unwrap()),
                    ..opening
                },
            )
            .unwrap();
        }
    }
    if route.as_deref().is_some_and(|r| r.starts_with("capture-")) {
        use crate::domain::capture::{Question, Record, Status, Turn};
        use navi_finance::{
            account::{Account, defaults},
            recognition::{Kind, MoneyDraft},
        };
        let zh = Lang::from_language(locale().language()) == Lang::Zh;
        let t = |en: &'static str, cn: &'static str| if zh { cn } else { en };
        let missing = route.as_deref() == Some("capture-missing");
        let mut draft = crate::data::capture::new();
        draft.input = if route.as_deref() == Some("capture-ask") {
            t("Lunch was 32 yuan", "午餐花了 32 元。")
        } else {
            t(
                "Lunch 32 yuan, paid from Wallet",
                "午餐花了 32 元，用钱包付的。",
            )
        }
        .into();
        draft.model = "preview-model".into();
        draft.status = Status::Ready;
        draft.records = vec![Record::Money {
            day: clock::today(),
            draft: MoneyDraft {
                kind: Kind::Expense,
                amount: Some("32.00".into()),
                currency: "CNY".into(),
                account: if missing {
                    None
                } else {
                    Some(Account::parse("资产:Wallet").unwrap())
                },
                other_account: None,
                category: Some(defaults::expense("餐饮")),
                time: None,
                payee: t("Lunch", "午餐").into(),
                note: String::new(),
            },
        }];
        // The thread the sheet shows: the owner's message, then the model's
        // turn with the records and, while the account is missing, the
        // question with its tap-first answers. The reply is a display stub;
        // a preview never sends it back to a model.
        let questions: Vec<Question> = if missing {
            vec![Question {
                text: "Which account was used?".into(),
                options: vec!["Wallet".into(), "Cash".into(), "Bank".into()],
            }]
        } else {
            Vec::new()
        };
        draft.transcript = vec![
            Turn::Owner {
                text: draft.input.clone(),
                photo: false,
                images: Vec::new(),
            },
            Turn::Assistant {
                provider_output: None,
                reply: serde_json::json!({"records":[], "questions": questions}).to_string(),
                records: draft.records.len(),
                questions,
            },
        ];
        if route.as_deref() == Some("capture-ask") {
            let input = serde_json::json!({"questions":[{
                "id":"account", "text":t("Which account paid for lunch?", "这笔午餐从哪个账户支付？"),
                "reason":"",
                "required":true, "options":[
                    {"id":"wallet","label":t("Wallet", "钱包"),"description":""},
                    {"id":"bank","label":t("Bank card", "银行卡"),"description":""}
                ]
            }]});
            let blocks = serde_json::json!([{"type":"tool_use","id":"preview-ask","name":"ask_user","input":input}]);
            let request =
                crate::domain::capture::AskUser::parse("preview-ask", &input, blocks).unwrap();
            draft.transcript.truncate(1);
            draft.transcript.push(Turn::AskUser { request });
        }
        // Optional unsent evidence for desktop layout review, never sent automatically.
        if let Ok(paths) = env::var("NW_PREVIEW_CAPTURE_IMAGES") {
            for (index, path) in paths.split(':').take(4).enumerate() {
                if let Ok(source) = std::fs::read(path)
                    && let Some((bytes, _)) = photos::prepare_capture(&source)
                {
                    let name = format!("{}-preview-{index}.png", draft.id);
                    photos::keep(&name, &bytes).expect("preview image");
                    draft.attachments.push(name);
                }
            }
        }
        let _ = crate::data::capture::put(draft);
    }
    if has("favorites") && !untracked(favorites::any) {
        for meal in untracked(meals::all).iter().take(4) {
            favorites::save_from(meal).expect("preview favorite");
        }
    }
    if has("drafts") && untracked(pending::all).is_empty() {
        seed_drafts();
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
        // Scale estimates for most weighed days, drifting down a little
        // faster than the weight itself.
        for back in (0..30).rev().filter(|back| back % 4 != 1) {
            let day = today.plus_days(-back);
            let Some(entry) = weights::on(day) else {
                continue;
            };
            let fat = 21.5 - f64::from(29 - back) * 0.05;
            body_metrics::set(
                day,
                navi_health::bodycomp::estimate(
                    entry.kg,
                    175.0,
                    33,
                    navi_health::bodycomp::Sex::Male,
                    Some(506.0),
                )
                .map(|metrics| navi_health::bodycomp::BodyMetrics {
                    body_fat_percent: fat,
                    ..metrics
                })
                .expect("the preview profile estimates"),
            );
        }
        settings::save_height(Some(175));
        settings::save_age(Some(33));
        settings::save_sex(Some(navi_health::bodycomp::Sex::Male));
        settings::save_goal_kg(Some(72.0));
    }
    if has("multicurrency") {
        use navi_finance::{
            account::{Account, AccountKind},
            currency::{Currency, FxRate},
            holdings::{Kind, Quote, Security, Trade},
            journal::{self, Entry, Source},
        };
        let day = clock::today().0;
        let usd = Account::new_in(AccountKind::Assets, "Broker cash", Currency::USD).unwrap();
        if !finance::accounts().contains(&usd) {
            let entry = Entry {
                id: "preview-usd-cash".into(),
                at: day.at(9, 0, 0, 0),
                payee: String::new(),
                note: String::new(),
                source: Source::Manual,
            };
            finance::save(journal::opening(entry, &usd, 100000).unwrap()).unwrap();
            let security = Security::new_in("preview-us", "Apple", Currency::USD).unwrap();
            finance::add_trade(
                Some(&security),
                &Trade {
                    id: "preview-us-open".into(),
                    security: security.id.clone(),
                    at: day.at(10, 0, 0, 0),
                    kind: Kind::Opening,
                    quantity: 10_000_000,
                    price: 200_000_000,
                    amount: 0,
                    fee: 0,
                    cash: None,
                },
            )
            .unwrap();
            finance::set_quote(&Quote {
                security: security.id,
                day,
                price: 210_000_000,
            })
            .unwrap();
        }
        if has("fx") {
            finance::save_rate(FxRate {
                currency: Currency::USD,
                day,
                rate: 7_000_000,
                source: "manual".into(),
            })
            .unwrap();
        }
    }
    if has("history") {
        use navi_finance::{
            catalog::{self, SecurityBinding},
            history::{self, DailyBar},
        };
        crate::data::db::with(|c| {
            let binding = SecurityBinding {
                security: "preview-etf".into(),
                market: "cn_a".into(),
                symbol: "510300".into(),
                currency: "CNY".into(),
            };
            catalog::bind(c, &binding).unwrap();
            let now = jiff::Timestamp::now();
            let day = clock::today().plus_days(-2).0;
            let first = now.checked_sub(jiff::Span::new().minutes(5)).unwrap();
            let mut bar = DailyBar {
                market: "cn_a".into(),
                symbol: "510300.SH".into(),
                currency: "CNY".into(),
                provider: "tencent:raw".into(),
                day,
                open: 4_020_000,
                high: 4_120_000,
                low: 3_990_000,
                close: 4_080_000,
                volume: Some(658140),
                fetched_at: first,
            };
            history::save_bars(c, &binding, &[bar.clone()], now).unwrap();
            bar.close = 4_090_000;
            bar.fetched_at = now;
            history::save_bars(c, &binding, &[bar], now).unwrap();
        });
        finance::load().unwrap();
        crate::data::valuation::capture(true).unwrap();
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
        Some("model") => {
            nav::push(Route::Settings);
            nav::push(Route::ModelSettings);
        }
        Some("review" | "review-month") => nav::select(nav::Tab::Review),
        Some("records") => nav::select(nav::Tab::Records),
        Some("price-history") => nav::push(Route::PriceHistory(None)),
        Some("exchange-rates") => nav::push(Route::ExchangeRates),
        Some("statement-import") => {
            if let Ok(path) = env::var("NW_PREVIEW_STATEMENT")
                && let Ok(bytes) = std::fs::read(&path)
            {
                crate::data::tasks::spawn_app(async move {
                    let name = std::path::Path::new(&path)
                        .file_name()
                        .unwrap()
                        .to_string_lossy()
                        .into_owned();
                    let _ = crate::data::statement_import::open_file(name, bytes).await;
                });
            }
            nav::select(nav::Tab::Records);
            nav::push(Route::StatementImport);
        }
        Some("assets" | "assets-empty" | "assets-manage") => nav::select(nav::Tab::Assets),
        Some("asset-history") => {
            nav::select(nav::Tab::Assets);
            nav::push(Route::AssetHistory);
        }
        Some("closed-holdings") => {
            nav::select(nav::Tab::Assets);
            nav::push(Route::ClosedHoldings);
        }
        Some("holdings" | "holding-new") => nav::select(nav::Tab::Assets),
        Some("holding" | "holding-trade" | "holding-price") => {
            nav::select(nav::Tab::Assets);
            nav::push(Route::Holding("preview-etf".into()));
        }
        Some("asset-account" | "asset-balance") => {
            nav::select(nav::Tab::Assets);
            nav::push(Route::Account("资产:Wallet".into()));
        }
        Some("asset-debt-balance") => {
            nav::select(nav::Tab::Assets);
            nav::push(Route::Account("负债:Credit card".into()));
        }
        _ => {}
    }
}

pub fn assets_opened(manage: Signal<bool>, open: Signal<Option<String>>) {
    if env::var("NW_PREVIEW_ROUTE").as_deref() == Ok("assets-manage") {
        manage.set(true);
    }
    if env::var("NW_PREVIEW_ROUTE").as_deref() == Ok("holding-new") {
        open.set(Some(String::new()));
    }
}
pub fn holding_detail_opened(trade: Signal<Option<String>>, price: Signal<bool>) {
    match env::var("NW_PREVIEW_ROUTE").as_deref() {
        Ok("holding-trade") => trade.set(Some("preview-etf".into())),
        Ok("holding-price") => price.set(true),
        _ => {}
    }
}

pub fn balance_opened(open: Signal<bool>) {
    if matches!(
        env::var("NW_PREVIEW_ROUTE").as_deref(),
        Ok("asset-balance" | "asset-debt-balance")
    ) {
        open.set(true);
    }
}

pub fn balance_value() -> Option<i64> {
    match env::var("NW_PREVIEW_ROUTE").as_deref() {
        Ok("asset-balance") => Some(130000),
        Ok("asset-debt-balance") => Some(-240000),
        _ => None,
    }
}

/// A ready draft and one still being read, on the seeded meals' photos.
fn seed_drafts() {
    let photos: Vec<String> = untracked(meals::all)
        .into_iter()
        .filter_map(|meal| meal.photo)
        .collect();
    let today = untracked(clock::today);
    for (index, (status, slot)) in [
        (PendingStatus::Ready, MealSlot::Dinner),
        (PendingStatus::Analyzing, MealSlot::Snack),
    ]
    .into_iter()
    .enumerate()
    {
        let Some(photo) = photos.get(index).cloned() else {
            return;
        };
        let foods = untracked(meals::all)
            .first()
            .filter(|_| status == PendingStatus::Ready)
            .map(|meal| meal.foods.clone())
            .unwrap_or_default();
        pending::put(PendingMeal {
            id: format!("dpreview{index}"),
            day: today,
            slot,
            title: None,
            foods,
            photo,
            model: None,
            prompt_version: None,
            skipped: 0,
            status,
            created_at_ms: clock::now_ms() - index as i64,
        })
        .expect("preview draft");
    }
}

/// Opens the capture sheet (`NW_PREVIEW_ROUTE=capture`) or the Records
/// calendar (`records-jump`) once the home is up.
pub fn home_opened(
    capture: Signal<bool>,
    capture_id: Signal<Option<String>>,
    jump: Signal<bool>,
    jump_to: Signal<Option<Day>>,
    finance: Signal<Option<String>>,
) {
    let sheet = match env::var("NW_PREVIEW_ROUTE").as_deref() {
        Ok("capture") => capture,
        Ok("capture-ready" | "capture-missing" | "capture-ask") => {
            capture_id.set(crate::data::capture::all().first().map(|d| d.id.clone()));
            capture
        }
        Ok("transaction" | "transaction-new") => {
            let new = env::var("NW_PREVIEW_ROUTE").as_deref() == Ok("transaction-new");
            set_timeout(std::time::Duration::from_millis(600), move || {
                finance.set(Some(if new {
                    String::new()
                } else {
                    "preview-lunch".into()
                }));
            });
            return;
        }
        Ok("records-day") => {
            nav::select(nav::Tab::Records);
            let day = untracked(clock::today).plus_days(-1);
            set_timeout(std::time::Duration::from_millis(600), move || {
                jump_to.set(Some(day))
            });
            return;
        }
        Ok("records-jump") => {
            nav::select(nav::Tab::Records);
            jump
        }
        _ => return,
    };
    set_timeout(std::time::Duration::from_millis(600), move || {
        sheet.set(true)
    });
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
        photos::keep(&name, &keep).ok()?;
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
        })
        .expect("preview meal");
    }
}

/// Whether Review opens on the month (`NW_PREVIEW_ROUTE=review-month`).
pub fn review_month() -> bool {
    env::var("NW_PREVIEW_ROUTE").is_ok_and(|route| route == "review-month")
}
