//! Interface copy in English and Simplified Chinese, picked from the
//! device's language. Each language is written as natural interface text,
//! not translated word for word. Read it in bindings (`move || s().today`)
//! so a language change follows.

pub(crate) mod backup_file;
pub(crate) mod capture_options;
pub(crate) mod catalog;
mod en;
pub(crate) mod incoming;
pub(crate) mod market;
pub(crate) mod net_worth;
mod phrases;
pub(crate) mod statement_import;
mod zh;

use nsh_core::prelude::*;

use crate::domain::{format, meal::Day, nutrition::ExtraNutrients, recognition::Lang};

/// Every string of the interface.
pub struct Strings {
    pub lang: Lang,
    // Holdings
    pub manage_assets: &'static str,
    pub asset_history: &'static str,
    pub closed_holdings: &'static str,
    pub manage_add_account_note: &'static str,
    pub manage_add_holding_note: &'static str,
    pub no_closed_holdings: &'static str,
    pub cash_accounts: &'static str,
    pub debt_accounts: &'static str,
    pub valuation_recorded: &'static str,
    pub valuation_book: &'static str,
    pub value_range: &'static str,
    pub holdings: &'static str,
    pub add_holding: &'static str,
    pub security_name: &'static str,
    pub security_hint: &'static str,
    pub opening_holding: &'static str,
    pub buy: &'static str,
    pub sell: &'static str,
    pub dividend: &'static str,
    pub quantity: &'static str,
    pub unit_cost: &'static str,
    pub trade_price: &'static str,
    pub holding_price: &'static str,
    pub holding_cost: &'static str,
    pub market_value: &'static str,
    pub unrealized: &'static str,
    pub realized: &'static str,
    pub dividends: &'static str,
    pub price_history: &'static str,
    pub record_trade: &'static str,
    pub holding_link_action: &'static str,
    pub holding_trade_action: &'static str,
    pub holding_prices_action: &'static str,
    pub save_trade: &'static str,
    pub save_holding: &'static str,
    pub trade_saved: &'static str,
    pub trade_deleted: &'static str,
    pub update_price: &'static str,
    pub price_saved: &'static str,
    pub price_date: &'static str,
    pub manual_source: &'static str,
    pub unpriced: &'static str,
    pub holding_closed: &'static str,
    pub fee: &'static str,
    pub cash_account: &'static str,
    pub dividend_amount: &'static str,
    pub trade_details: &'static str,
    pub holding_history: &'static str,
    pub holding_error: &'static str,
    pub holding_oversell: &'static str,
    pub holding_cash_error: &'static str,
    pub holding_duplicate: &'static str,
    pub holding_delete_title: &'static str,
    pub holding_delete_body: &'static str,
    pub opening_hint: &'static str,
    pub portfolio_basis: &'static str,
    pub portfolio_net: &'static str,
    pub remove_trade: &'static str,
    // Assets
    pub create_account: &'static str,
    pub save_account_changes: &'static str,
    pub view_account: &'static str,
    pub assets: &'static str,
    pub total_assets: &'static str,
    pub total_debt: &'static str,
    pub assets_empty: &'static str,
    pub assets_basis: &'static str,
    pub account_unchecked: &'static str,
    pub account_balance: &'static str,
    pub account_debt: &'static str,
    pub check_balance: &'static str,
    pub actual_balance: &'static str,
    pub actual_debt: &'static str,
    pub debt_hint: &'static str,
    pub balance_date_hint: &'static str,
    pub balance_preview: &'static str,
    pub balance_difference: &'static str,
    pub balance_equal: &'static str,
    pub balance_explanation: &'static str,
    pub balance_confirm: &'static str,
    pub balance_saved: &'static str,
    pub balance_changed: &'static str,
    pub opening_balance: &'static str,
    pub balance_adjustment: &'static str,
    pub account_activity: &'static str,
    pub account_activity_empty: &'static str,
    pub edit_account: &'static str,
    pub account_updated: &'static str,
    pub account_exists: &'static str,
    pub rename_running: &'static str,
    pub account_created: &'static str,
    pub balance_readonly: &'static str,
    pub close: &'static str,
    // Ledger
    pub capture_unspecified: &'static str,
    pub capture_need_account: &'static str,
    pub capture_need_amount: &'static str,
    pub capture_need_category: &'static str,
    pub capture_need_destination: &'static str,
    pub capture_payee: &'static str,
    pub capture_prompt: &'static str,
    pub capture_placeholder: &'static str,
    pub capture_photo: &'static str,
    pub capture_remove_photo: &'static str,
    pub capture_images: &'static str,
    pub capture_submit_answers: &'static str,
    pub capture_skipped_optional: &'static str,
    pub capture_answer_needed: &'static str,
    pub capture_required: &'static str,
    pub capture_optional: &'static str,
    pub capture_generate: &'static str,
    pub capture_review: &'static str,
    pub capture_reading: &'static str,
    pub capture_later: &'static str,
    pub capture_send: &'static str,
    pub capture_edit_amount: &'static str,
    pub capture_edit_meal: &'static str,
    pub capture_clarify: &'static str,
    pub capture_add_detail: &'static str,
    pub capture_history: &'static str,
    pub capture_reply_hint: &'static str,
    pub capture_confirm: &'static str,
    pub capture_retained: &'static str,
    pub capture_choose_account: &'static str,
    pub capture_no_accounts: &'static str,
    pub view_records: &'static str,
    pub goal_unset: &'static str,
    pub garmin_disconnected: &'static str,
    pub capture_failed: &'static str,
    pub capture_retry: &'static str,
    pub capture_keep_result: &'static str,
    pub capture_manual: &'static str,
    pub capture_new_account: &'static str,
    pub capture_setup: &'static str,
    pub capture_consent: &'static str,
    pub capture_consent_body: &'static str,
    pub capture_too_long: &'static str,
    pub capture_weight_replace: &'static str,
    pub transaction_details: &'static str,
    pub add_details: &'static str,
    pub error_time: &'static str,
    pub log_transaction: &'static str,
    pub edit_transaction: &'static str,
    pub save_transaction: &'static str,
    pub delete_transaction: &'static str,
    pub delete_transaction_action: &'static str,
    pub delete_transaction_title: &'static str,
    pub delete_transaction_body: &'static str,
    pub revoke_balance: &'static str,
    pub revoke_balance_title: &'static str,
    pub revoke_balance_body: &'static str,
    pub balance_entry_removed: &'static str,
    pub error_transaction_delete: &'static str,
    pub error_transaction_missing: &'static str,
    pub error_transaction_changed: &'static str,
    pub error_transaction_restore: &'static str,
    pub error_transaction_undo_changed: &'static str,
    pub transaction_deleted: &'static str,
    pub transactions: &'static str,
    pub spending: &'static str,
    pub income: &'static str,
    pub transfer: &'static str,
    pub money_amount: &'static str,
    pub transaction_date: &'static str,
    pub transaction_time: &'static str,
    pub own_account: &'static str,
    pub from_account: &'static str,
    pub to_account: &'static str,
    pub category: &'static str,
    pub choose_account: &'static str,
    pub add_account: &'static str,
    pub account_type: &'static str,
    pub currency_label: &'static str,
    pub account_name: &'static str,
    pub asset_account: &'static str,
    pub liability_account: &'static str,
    pub transaction_payee: &'static str,
    pub transaction_note: &'static str,
    pub error_money: &'static str,
    pub error_transaction_date: &'static str,
    pub error_account: &'static str,
    pub error_transfer: &'static str,
    pub error_transaction: &'static str,
    pub error_transaction_storage: &'static str,
    pub discard_changes: &'static str,
    pub storage_unavailable: &'static str,
    pub storage_unavailable_body: &'static str,
    // Today
    pub today: &'static str,
    pub yesterday: &'static str,
    pub settings: &'static str,
    // Appearance
    pub appearance: &'static str,
    pub appearance_system: &'static str,
    pub appearance_light: &'static str,
    pub appearance_dark: &'static str,
    pub kcal: &'static str,
    pub kcal_today: &'static str,
    pub protein: &'static str,
    pub carbs: &'static str,
    pub fat: &'static str,
    pub nothing_logged: &'static str,
    pub meals: &'static str,
    pub empty_today: &'static str,
    pub empty_day: &'static str,
    pub add_manually: &'static str,
    pub setup_title: &'static str,
    pub setup_body: &'static str,
    pub set_up: &'static str,
    pub breakfast: &'static str,
    pub lunch: &'static str,
    pub dinner: &'static str,
    pub snack: &'static str,
    pub meal_deleted: &'static str,
    pub undo: &'static str,
    // Review
    pub new_meal: &'static str,
    pub edit_meal: &'static str,
    pub back: &'static str,
    pub preparing_photo: &'static str,
    pub analyzing: &'static str,
    pub still_working: &'static str,
    pub estimate_hint: &'static str,
    pub foods: &'static str,
    pub no_foods_title: &'static str,
    pub no_foods_body: &'static str,
    pub add_food: &'static str,
    pub badge_estimate: &'static str,
    pub badge_check: &'static str,
    pub badge_edited: &'static str,
    pub total: &'static str,
    pub save_meal: &'static str,
    pub delete_meal: &'static str,
    pub records: &'static str,
    pub review: &'static str,
    pub new_entry: &'static str,
    pub log_weight: &'static str,
    pub tap_to_log: &'static str,
    pub resting: &'static str,
    pub todays_records: &'static str,
    pub spent_today: &'static str,
    pub intake_hint: &'static str,
    pub capture_choose_category: &'static str,
    pub all_records: &'static str,
    pub show_earlier: &'static str,
    pub no_records: &'static str,
    pub meal_day: &'static str,
    pub discard_draft: &'static str,
    pub draft_kept: &'static str,
    pub draft_discarded: &'static str,
    pub to_confirm: &'static str,
    pub confirm: &'static str,
    pub draft_retry: &'static str,
    pub draft_add: &'static str,
    pub week_label: &'static str,
    pub month_label: &'static str,
    pub previous_day: &'static str,
    pub next_day: &'static str,
    pub all_days: &'static str,
    pub go_to_day: &'static str,
    pub previous_month: &'static str,
    pub next_month: &'static str,
    pub daily_intake: &'static str,
    pub favorites: &'static str,
    pub save_favorite: &'static str,
    pub remove_favorite: &'static str,
    pub favorite_saved: &'static str,
    pub favorite_removed: &'static str,
    pub recent_foods: &'static str,
    pub weight: &'static str,
    pub edit_weight: &'static str,
    pub error_weight: &'static str,
    pub weight_deleted: &'static str,
    pub delete_weight: &'static str,
    pub save_weight: &'static str,
    pub body_fat: &'static str,
    pub weight_only_days: &'static str,
    pub expand_records: &'static str,
    pub collapse_records: &'static str,
    pub body_overview: &'static str,
    pub seven_days: &'static str,
    pub body_metrics: &'static str,
    pub body_more: &'static str,
    pub body_missing: &'static str,
    pub fat_mass: &'static str,
    pub fat_free_mass: &'static str,
    pub muscle_mass: &'static str,
    pub water_mass: &'static str,
    pub measurement_profile: &'static str,
    pub resistance: &'static str,
    pub muscle: &'static str,
    pub water: &'static str,
    pub bmi: &'static str,
    pub body_and_weight: &'static str,
    pub settings_connections: &'static str,
    pub settings_data: &'static str,
    pub settings_about: &'static str,
    pub body_profile_complete: &'static str,
    pub body_profile_incomplete: &'static str,
    pub body_profile: &'static str,
    pub body_profile_note: &'static str,
    pub height: &'static str,
    pub age_years: &'static str,
    pub birth_date: &'static str,
    pub pick_birth_date: &'static str,
    pub legacy_age: &'static str,
    pub birth_date_legacy_note: &'static str,
    pub error_birth_date: &'static str,
    pub sex: &'static str,
    pub male: &'static str,
    pub female: &'static str,
    pub error_height: &'static str,
    pub goal_weight: &'static str,
    pub goal_weight_note: &'static str,
    pub scale_estimate: &'static str,
    pub scale_algorithm: &'static str,
    pub algorithm_details: &'static str,
    pub scale_algorithm_note: &'static str,
    pub algorithm_experimental: &'static str,
    pub algorithm_segal_note: &'static str,
    pub algorithm_wu_note: &'static str,
    pub algorithm_sun_note: &'static str,
    pub algorithm_save_failed: &'static str,
    pub range_30d: &'static str,
    pub range_90d: &'static str,
    pub garmin: &'static str,
    pub sleep: &'static str,
    pub resting_hr: &'static str,
    pub hrv: &'static str,
    pub body_battery: &'static str,
    pub steps: &'static str,
    pub stress: &'static str,
    pub garmin_key: &'static str,
    pub garmin_key_placeholder: &'static str,
    pub garmin_connect: &'static str,
    pub garmin_disconnect: &'static str,
    pub review_note: &'static str,
    pub review_note_hint: &'static str,
    pub garmin_note: &'static str,
    pub garmin_key_rejected: &'static str,
    pub garmin_network: &'static str,
    pub garmin_unreadable: &'static str,
    pub garmin_syncing: &'static str,
    pub garmin_no_data: &'static str,
    pub backup: &'static str,
    pub backup_auto_enabled: &'static str,
    pub backup_auto_disabled: &'static str,
    pub backup_group_folder: &'static str,
    pub backup_group_encryption: &'static str,
    pub backup_group_restore: &'static str,
    pub update: &'static str,
    pub update_check: &'static str,
    pub update_open: &'static str,
    pub update_never: &'static str,
    pub update_failed: &'static str,
    pub update_note: &'static str,
    pub previous_week: &'static str,
    pub next_week: &'static str,
    pub intake: &'static str,
    pub trend_average: &'static str,
    pub weight_week: &'static str,
    pub recovery: &'static str,
    pub avg_sleep: &'static str,
    pub no_week_data: &'static str,
    pub webdav_url: &'static str,
    pub webdav_user: &'static str,
    pub webdav_password: &'static str,
    pub backup_passphrase: &'static str,
    pub backup_passphrase_kept: &'static str,
    pub backup_passphrase_note: &'static str,
    pub backup_note: &'static str,
    pub with_photos: &'static str,
    pub backup_save: &'static str,
    pub restore: &'static str,
    pub backup_never: &'static str,
    pub backup_running: &'static str,
    pub backup_network: &'static str,
    pub backup_unauthorized: &'static str,
    pub backup_wrong_passphrase: &'static str,
    pub backup_not_backup: &'static str,
    pub backup_newer: &'static str,
    pub backup_storage: &'static str,
    pub backup_not_configured: &'static str,
    pub restore_title: &'static str,
    pub restore_body: &'static str,
    pub restore_confirm: &'static str,
    pub restored: &'static str,
    pub no_backups: &'static str,
    pub discard_title: &'static str,
    pub discard_body: &'static str,
    pub discard: &'static str,
    pub keep_editing: &'static str,
    pub not_sent_title: &'static str,
    pub not_sent_body: &'static str,
    pub send_photo_ellipsis: &'static str,
    pub no_food_title: &'static str,
    pub no_food_body: &'static str,
    pub choose_another: &'static str,
    pub try_again: &'static str,
    pub open_settings: &'static str,
    pub failure_offline: (&'static str, &'static str),
    pub failure_timeout: (&'static str, &'static str),
    pub failure_unauthorized: (&'static str, &'static str),
    pub failure_forbidden: (&'static str, &'static str),
    pub failure_not_found: (&'static str, &'static str),
    pub failure_rate_limited: (&'static str, &'static str),
    pub failure_busy: (&'static str, &'static str),
    pub failure_rejected: (&'static str, &'static str),
    pub failure_unreadable: (&'static str, &'static str),
    pub failure_refused: (&'static str, &'static str),
    pub failure_photo: (&'static str, &'static str),
    pub photo_label: &'static str,
    // Consent
    pub consent_title: &'static str,
    pub consent_body: &'static str,
    pub consent_server: &'static str,
    pub consent_model: &'static str,
    pub consent_privacy: &'static str,
    pub consent_cleartext: &'static str,
    pub dont_ask_again: &'static str,
    pub cancel: &'static str,
    pub send_photo: &'static str,
    // Food editor
    pub edit_food: &'static str,
    pub name: &'static str,
    pub name_placeholder: &'static str,
    pub amount_eaten: &'static str,
    pub grams_unit: &'static str,
    pub decrease: &'static str,
    pub increase: &'static str,
    pub per_100g: &'static str,
    pub energy: &'static str,
    pub fiber: &'static str,
    pub sugars: &'static str,
    pub sodium: &'static str,
    pub sat_fat: &'static str,
    pub mg_unit: &'static str,
    pub more_nutrition: &'static str,
    pub source_manual: &'static str,
    pub edit: &'static str,
    pub done: &'static str,
    pub remove: &'static str,
    pub error_name: &'static str,
    pub error_grams: &'static str,
    pub error_nutrients: &'static str,
    // Settings
    pub recognition: &'static str,
    pub not_set_up: &'static str,
    pub vision_model: &'static str,
    pub provider: &'static str,
    pub anthropic: &'static str,
    pub openai_compatible: &'static str,
    pub openai_responses: &'static str,
    pub base_url: &'static str,
    pub model: &'static str,
    pub model_placeholder: &'static str,
    pub api_key: &'static str,
    pub key_placeholder: &'static str,
    pub key_optional: &'static str,
    pub key_note: &'static str,
    pub show_key: &'static str,
    pub hide_key: &'static str,
    pub test_connection: &'static str,
    pub kcal_per_logged_day: &'static str,
    pub review_intake_more: &'static str,
    pub review_intake_less: &'static str,
    pub review_intake_same: &'static str,
    pub review_weight_up: &'static str,
    pub review_weight_down: &'static str,
    pub review_weight_same: &'static str,
    pub net_change_30d: &'static str,
    pub chart_goal: &'static str,
    pub daily_goal: &'static str,
    pub goal_note: &'static str,
    pub ask_each_photo: &'static str,
    pub ask_each_photo_note: &'static str,
    pub error_url: &'static str,
    pub error_model: &'static str,
    pub error_key: &'static str,
    pub error_goal: &'static str,
}

/// The strings for the device's language (tracked where it is read).
pub fn s() -> &'static Strings {
    strings(Lang::from_language(locale().language()))
}

/// The strings of `lang`.
pub fn strings(lang: Lang) -> &'static Strings {
    match lang {
        Lang::En => &en::STRINGS,
        Lang::Zh => &zh::STRINGS,
    }
}

impl Strings {
    fn zh(&self) -> bool {
        self.lang == Lang::Zh
    }

    /// A weight in kg, to one decimal.
    pub fn capture_saved_count(&self, n: usize) -> String {
        if self.zh() {
            format!("已保存 {n} 条记录")
        } else {
            format!("Saved {n} records")
        }
    }

    pub fn capture_saved_detail(&self, kind: &str, value: &str) -> String {
        if self.zh() {
            format!("已记{kind} · {value}")
        } else {
            format!("Saved {kind} · {value}")
        }
    }

    /// A past thread turn whose records the current draft replaced.
    pub fn capture_thread_updated(&self, n: usize) -> String {
        if self.zh() {
            format!("已更新 {n} 条记录")
        } else {
            format!("Updated {n} records")
        }
    }

    pub fn kg(&self, kg: f64) -> String {
        format!("{kg:.1}")
    }

    /// A sleep duration: `7h 32m`.
    pub fn sleep_time(&self, seconds: u32) -> String {
        let minutes = (seconds + 30) / 60;
        let (h, m) = (minutes / 60, minutes % 60);
        if self.zh() {
            format!("{h}小时{m}分")
        } else {
            format!("{h}h {m}m")
        }
    }

    /// The sleep score line.
    pub fn sleep_score(&self, score: u8) -> String {
        if self.zh() {
            format!("评分 {score}")
        } else {
            format!("Score {score}")
        }
    }

    /// Which Garmin site the key belongs to.
    pub fn garmin_connected(&self, host: &str) -> String {
        if self.zh() {
            format!("已连接 · {host}")
        } else {
            format!("Connected · {host}")
        }
    }

    fn month_short(&self, month: i8) -> &'static str {
        [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ][(month.clamp(1, 12) - 1) as usize]
    }

    /// When the last backup was put.
    pub fn backup_last(&self, when: &str) -> String {
        if self.zh() {
            format!("上次备份：{when}")
        } else {
            format!("Last backup: {when}")
        }
    }

    /// A server status nothing else explains.
    pub fn backup_server(&self, status: u16) -> String {
        if self.zh() {
            format!("WebDAV 服务器返回 {status}。")
        } else {
            format!("The WebDAV server answered {status}.")
        }
    }

    /// `n` meals.
    pub fn meal_count(&self, n: usize) -> String {
        match (self.zh(), n) {
            (true, _) => format!("{n} 餐"),
            (false, 1) => "1 meal".to_owned(),
            (false, _) => format!("{n} meals"),
        }
    }

    /// Today's records header: how many (the day's spending is in the
    /// summary card above).
    pub fn records_summary(&self, n: usize, meals_only: bool) -> String {
        match (meals_only, self.zh(), n) {
            (true, _, _) => self.meal_count(n),
            (false, true, _) => format!("{n} 条"),
            (false, false, 1) => "1 record".to_owned(),
            (false, false, _) => format!("{n} records"),
        }
    }

    pub fn food_count(&self, n: usize) -> String {
        match (self.zh(), n) {
            (true, _) => format!("{n} 种食物"),
            (false, 1) => "1 food".to_owned(),
            (false, _) => format!("{n} foods"),
        }
    }

    /// What is left of the goal, or how far past it the day is.
    pub fn goal_status(&self, eaten: f64, goal: f64) -> String {
        let left = goal - eaten;
        match (self.zh(), left >= 0.0) {
            (true, true) => format!("还剩 {} 千卡", format::kcal(left)),
            (true, false) => format!("超出 {} 千卡", format::kcal(-left)),
            (false, true) => format!("{} kcal left", format::kcal(left)),
            (false, false) => format!("{} kcal over", format::kcal(-left)),
        }
    }

    /// Where the photo went.
    pub fn sent_to(&self, host: &str, model: &str) -> String {
        if self.zh() {
            format!("已发送至 {host} · {model}")
        } else {
            format!("Sent to {host} · {model}")
        }
    }

    /// Items the model returned that could not be used.
    pub fn skipped(&self, n: usize) -> String {
        match (self.zh(), n) {
            (true, _) => format!("有 {n} 项无法读取，已略过。"),
            (false, 1) => "1 item couldn't be read and was left out.".to_owned(),
            (false, _) => format!("{n} items couldn't be read and were left out."),
        }
    }

    /// A food's source, for its editor.
    pub fn source_estimate(&self, model: &str) -> String {
        if self.zh() {
            format!("由 {model} 估算")
        } else {
            format!("Estimated by {model}")
        }
    }

    pub fn source_catalog(&self, id: &str) -> String {
        if self.zh() {
            format!("USDA 食物数据库 #{id}")
        } else {
            format!("USDA FoodData Central #{id}")
        }
    }

    /// What `grams` of a food hold, as its editor shows it.
    pub fn portion(&self, grams: f64, kcal: f64) -> String {
        if self.zh() {
            format!("{} 克 · {} 千卡", format::grams(grams), format::kcal(kcal))
        } else {
            format!("{} g · {} kcal", format::grams(grams), format::kcal(kcal))
        }
    }

    /// The fibre, sugars, sodium and saturated fat a food or meal holds,
    /// for the review pages. `complete` is false when some of the foods
    /// keep no extra values, so the sum is partial.
    pub fn extras_line(&self, extra: &ExtraNutrients, complete: bool) -> String {
        let partial: &str = if complete {
            ""
        } else if self.zh() {
            "（部分记录）"
        } else {
            " (partial)"
        };
        let mg = extra.sodium.max(0.0) * 1000.0;
        if self.zh() {
            format!(
                "膳食纤维 {} 克 · 糖 {} 克 · 钠 {} 毫克 · 饱和脂肪 {} 克{}",
                format::grams(extra.fiber),
                format::grams(extra.sugars),
                format::grams(mg),
                format::grams(extra.sat_fat),
                partial
            )
        } else {
            format!(
                "Fiber {} g · Sugars {} g · Sodium {} mg · Sat. fat {} g{}",
                format::grams(extra.fiber),
                format::grams(extra.sugars),
                format::grams(mg),
                format::grams(extra.sat_fat),
                partial
            )
        }
    }

    /// The connection test's success.
    pub fn connected(&self, model: &str, seconds: f64) -> String {
        if self.zh() {
            format!("已连接 · {model} 用时 {seconds:.1} 秒")
        } else {
            format!("Connected · {model} answered in {seconds:.1} s")
        }
    }

    /// A day's title: Today, Yesterday, or its date.
    pub fn day_title(&self, day: Day, today: Day) -> String {
        match today.days_since(day) {
            0 => self.today.to_owned(),
            1 => self.yesterday.to_owned(),
            _ => self.long_date(day),
        }
    }

    /// A day's full date (`Thursday, November 12`, `11月12日 星期四`).
    pub fn long_date(&self, day: Day) -> String {
        let date = day.0;
        if self.zh() {
            format!("{}月{}日 {}", date.month(), date.day(), self.weekday(day))
        } else {
            const MONTHS: [&str; 12] = [
                "January",
                "February",
                "March",
                "April",
                "May",
                "June",
                "July",
                "August",
                "September",
                "October",
                "November",
                "December",
            ];
            let month = MONTHS[(date.month().clamp(1, 12) - 1) as usize];
            format!("{}, {month} {}", self.weekday(day), date.day())
        }
    }

    /// A day's short weekday, for the day strip (`Mon`, `周一`).
    pub fn weekday_short(&self, day: Day) -> &'static str {
        let index = day.0.weekday().to_monday_zero_offset() as usize;
        if self.zh() {
            ["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index]
        } else {
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][index]
        }
    }

    fn weekday(&self, day: Day) -> &'static str {
        let index = day.0.weekday().to_monday_zero_offset() as usize;
        if self.zh() {
            [
                "星期一",
                "星期二",
                "星期三",
                "星期四",
                "星期五",
                "星期六",
                "星期日",
            ][index]
        } else {
            [
                "Monday",
                "Tuesday",
                "Wednesday",
                "Thursday",
                "Friday",
                "Saturday",
                "Sunday",
            ][index]
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn both_languages_read_naturally() {
        let (en, zh) = (strings(Lang::En), strings(Lang::Zh));
        assert_eq!(en.meal_count(1), "1 meal");
        assert_eq!(en.meal_count(3), "3 meals");
        assert_eq!(en.records_summary(1, false), "1 record");
        assert_eq!(en.records_summary(3, false), "3 records");
        assert_eq!(zh.records_summary(3, false), "3 条");
        assert_eq!(zh.meal_count(3), "3 餐");
        assert_eq!(en.goal_status(1240.0, 2000.0), "760 kcal left");
        assert_eq!(zh.goal_status(2120.0, 2000.0), "超出 120 千卡");
    }

    #[test]
    fn dates_and_day_titles() {
        let today: Day = "2026-11-12".parse().unwrap();
        let (en, zh) = (strings(Lang::En), strings(Lang::Zh));
        assert_eq!(en.long_date(today), "Thursday, November 12");
        assert_eq!(zh.long_date(today), "11月12日 星期四");
        assert_eq!(en.day_title(today, today), "Today");
        assert_eq!(zh.day_title(today.plus_days(-1), today), "昨天");
        assert_eq!(
            en.day_title(today.plus_days(-3), today),
            "Monday, November 9"
        );
    }
}
pub mod finance_review;
