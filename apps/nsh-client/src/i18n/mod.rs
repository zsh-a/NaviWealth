//! Interface copy in English and Simplified Chinese, picked from the
//! device's language. Each language is written as natural interface text,
//! not translated word for word. Read it in bindings (`move || s().today`)
//! so a language change follows.

mod en;
mod zh;

use nsh_core::prelude::*;

use crate::domain::{format, meal::Day, recognition::Lang};

/// Every string of the interface.
pub struct Strings {
    pub lang: Lang,
    // Today
    pub today: &'static str,
    pub yesterday: &'static str,
    pub settings: &'static str,
    pub kcal: &'static str,
    pub kcal_today: &'static str,
    pub protein: &'static str,
    pub carbs: &'static str,
    pub fat: &'static str,
    pub nothing_logged: &'static str,
    pub meals: &'static str,
    pub empty_today: &'static str,
    pub empty_day: &'static str,
    pub empty_body: &'static str,
    pub log_meal: &'static str,
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
    pub analyzing_steps: [&'static str; 3],
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
    pub log_again: &'static str,
    pub recent_foods: &'static str,
    pub weight: &'static str,
    pub weight_not_logged: &'static str,
    pub weight_hint: &'static str,
    pub error_weight: &'static str,
    pub weight_deleted: &'static str,
    pub delete_weight: &'static str,
    pub save_weight: &'static str,
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
    pub source_manual: &'static str,
    pub done: &'static str,
    pub remove: &'static str,
    pub error_name: &'static str,
    pub error_grams: &'static str,
    pub error_nutrients: &'static str,
    // Settings
    pub vision_model: &'static str,
    pub provider: &'static str,
    pub anthropic: &'static str,
    pub openai_compatible: &'static str,
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
    pub daily_goal: &'static str,
    pub goal_note: &'static str,
    pub privacy: &'static str,
    pub ask_each_photo: &'static str,
    pub ask_each_photo_note: &'static str,
    pub save: &'static str,
    pub error_url: &'static str,
    pub error_model: &'static str,
    pub error_key: &'static str,
    pub error_goal: &'static str,
    pub unsaved_title: &'static str,
    pub discard_changes: &'static str,
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
    pub fn kg(&self, kg: f64) -> String {
        format!("{kg:.1}")
    }

    /// The change over about a week, signed.
    pub fn weight_change(&self, delta: f64) -> String {
        let sign = if delta > 0.0 {
            "+"
        } else if delta < 0.0 {
            "−"
        } else {
            "±"
        };
        let value = format!("{sign}{:.1} kg", delta.abs());
        if self.zh() {
            format!("近一周 {value}")
        } else {
            format!("{value} this week")
        }
    }

    /// When the shown weight was logged, `days` before the chosen day.
    pub fn weight_days_ago(&self, days: i32) -> String {
        match (self.zh(), days) {
            (true, 1) => "昨天记录".to_owned(),
            (true, _) => format!("{days} 天前记录"),
            (false, 1) => "Logged yesterday".to_owned(),
            (false, _) => format!("Logged {days} days ago"),
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

    /// `n` foods.
    pub fn food_count(&self, n: usize) -> String {
        match (self.zh(), n) {
            (true, _) => format!("{n} 种食物"),
            (false, 1) => "1 food".to_owned(),
            (false, _) => format!("{n} foods"),
        }
    }

    /// The goal line under the day's figure.
    pub fn of_goal(&self, goal: f64) -> String {
        if self.zh() {
            format!("目标 {} 千卡", format::kcal(goal))
        } else {
            format!("of {} kcal", format::kcal(goal))
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

    /// The connection test's success.
    pub fn connected(&self, model: &str, seconds: f64) -> String {
        if self.zh() {
            format!("已连接 · {model} 用时 {seconds:.1} 秒")
        } else {
            format!("Connected · {model} answered in {seconds:.1} s")
        }
    }

    /// A day's title: Today, Yesterday, or the weekday.
    pub fn day_title(&self, day: Day, today: Day) -> String {
        match today.days_since(day) {
            0 => self.today.to_owned(),
            1 => self.yesterday.to_owned(),
            _ => self.weekday(day).to_owned(),
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
        assert_eq!(zh.meal_count(3), "3 餐");
        assert_eq!(en.goal_status(1240.0, 2000.0), "760 kcal left");
        assert_eq!(zh.goal_status(2120.0, 2000.0), "超出 120 千卡");
        assert_eq!(en.of_goal(2000.0), "of 2,000 kcal");
    }

    #[test]
    fn dates_and_day_titles() {
        let today: Day = "2026-11-12".parse().unwrap();
        let (en, zh) = (strings(Lang::En), strings(Lang::Zh));
        assert_eq!(en.long_date(today), "Thursday, November 12");
        assert_eq!(zh.long_date(today), "11月12日 星期四");
        assert_eq!(en.day_title(today, today), "Today");
        assert_eq!(zh.day_title(today.plus_days(-1), today), "昨天");
        assert_eq!(en.day_title(today.plus_days(-3), today), "Monday");
    }
}
