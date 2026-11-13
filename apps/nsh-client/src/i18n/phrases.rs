//! Phrases built from values: drafts, favorites, weights and the review.

use super::Strings;
use crate::domain::{format, meal::Day};

impl Strings {
    /// `n` foods.
    /// Beside the favorites' title: what a tap and a hold do.
    pub fn favorites_hint(&self) -> &'static str {
        if self.zh() {
            "轻点即记 · 长按更多"
        } else {
            "Tap to log · Hold for more"
        }
    }

    /// The last weight, under Log weight.
    pub fn last_weight(&self, kg: f64) -> String {
        if self.zh() {
            format!("上次 {} kg", self.kg(kg))
        } else {
            format!("Last {} kg", self.kg(kg))
        }
    }

    /// A draft's headline: what its recognition reached, for `slot`'s meal.
    pub fn draft_headline(
        &self,
        slot: &str,
        status: crate::domain::pending::PendingStatus,
    ) -> String {
        use crate::domain::pending::PendingStatus as S;
        match (self.zh(), status) {
            (true, S::Analyzing) => format!("正在识别{slot}照片…"),
            (true, S::Ready) => format!("{slot} · 识别好了"),
            (true, S::NoFood) => format!("{slot} · 没认出食物"),
            (true, S::Failed) => format!("{slot} · 识别失败"),
            (false, S::Analyzing) => format!("Reading your {} photo…", slot.to_lowercase()),
            (false, S::Ready) => format!("{slot} is ready"),
            (false, S::NoFood) => format!("{slot}: no food found"),
            (false, S::Failed) => format!("{slot}: couldn't read the photo"),
        }
    }

    /// Under a ready draft: its foods and about how much energy.
    pub fn draft_detail(&self, foods: usize, kcal: f64) -> String {
        if self.zh() {
            format!(
                "{} · 约 {} 千卡",
                self.food_count(foods),
                format::kcal(kcal)
            )
        } else {
            format!(
                "{} · about {} kcal",
                self.food_count(foods),
                format::kcal(kcal)
            )
        }
    }

    /// The change of the daily average from the period before.
    pub fn vs_previous(&self, delta: f64, month: bool) -> String {
        let sign = if delta > 0.0 {
            "+"
        } else if delta < 0.0 {
            "−"
        } else {
            "±"
        };
        let value = format!("{sign}{}", format::kcal(delta.abs()));
        match (self.zh(), month) {
            (true, false) => format!("较上周 {value}"),
            (true, true) => format!("较上月 {value}"),
            (false, false) => format!("{value} vs last week"),
            (false, true) => format!("{value} vs last month"),
        }
    }

    /// Under the intake chart: the goal and the days past it, and how many
    /// days have meals.
    pub fn intake_caption(
        &self,
        goal: Option<f64>,
        over: usize,
        logged: usize,
        of: usize,
    ) -> String {
        let logged = if self.zh() {
            format!("记录 {logged}/{of} 天")
        } else {
            format!("{logged} of {of} days logged")
        };
        match goal {
            Some(goal) if self.zh() => {
                format!("目标 {} · 超出 {over} 天 · {logged}", format::kcal(goal))
            }
            Some(goal) => format!("Goal {} · {over} over · {logged}", format::kcal(goal)),
            None => logged,
        }
    }

    /// A month's name (`November 2026`, `2026年11月`).
    pub fn month_name(&self, day: Day) -> String {
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
        let date = day.0;
        if self.zh() {
            format!("{}年{}月", date.year(), date.month())
        } else {
            format!("{} {}", MONTHS[date.month() as usize - 1], date.year())
        }
    }

    /// After a favorite is logged.
    pub fn logged(&self, name: &str) -> String {
        if self.zh() {
            format!("已记下{name}")
        } else {
            format!("Logged {name}")
        }
    }

    /// The change over about a week, short enough for a vital's caption.
    pub fn week_change(&self, delta: f64) -> String {
        if self.zh() {
            format!("本周 {}", self.signed_kg(delta))
        } else {
            format!("{} this week", self.signed_kg(delta))
        }
    }

    /// A change in kg, signed, to one decimal.
    pub fn signed_kg(&self, delta: f64) -> String {
        let sign = if delta > 0.0 {
            "+"
        } else if delta < 0.0 {
            "−"
        } else {
            "±"
        };
        format!("{sign}{:.1}", delta.abs())
    }
}
