//! Phrases built from values: drafts, favorites, weights and the review.

use super::Strings;
use crate::domain::{format, meal::Day};

impl Strings {
    /// The seven days' span: `Nov 7 – Nov 13`.
    pub fn week_span(&self, first: Day, last: Day) -> String {
        let (a, b) = (first.0, last.0);
        if self.zh() {
            format!(
                "{}月{}日 – {}月{}日",
                a.month(),
                a.day(),
                b.month(),
                b.day()
            )
        } else {
            format!(
                "{} {} – {} {}",
                self.month_short(a.month()),
                a.day(),
                self.month_short(b.month()),
                b.day()
            )
        }
    }

    /// Chinese uses Monday; other locales follow the platform, ISO by default.
    pub fn week_start(&self) -> crate::domain::review::WeekStart {
        use crate::domain::review::WeekStart;
        if !self.zh()
            && nsh_core::prelude::locale().region().is_some()
            && nsh_core::prelude::locale_settings().first_day_of_week
                == nsh_core::platform::Weekday::Sunday
        {
            WeekStart::Sunday
        } else {
            WeekStart::Monday
        }
    }

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
        let enough = logged >= 3;
        let logged = if self.zh() {
            format!("记录 {logged}/{of} 天")
        } else {
            format!("{logged} of {of} days logged")
        };
        match goal {
            Some(goal) if !enough => {
                if self.zh() {
                    format!("目标 {} · {logged}", format::kcal(goal))
                } else {
                    format!("Goal {} · {logged}", format::kcal(goal))
                }
            }
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
            format!("7天 {}", self.signed_kg(delta))
        } else {
            format!("{} · 7d", self.signed_kg(delta))
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

#[cfg(test)]
mod tests {
    use crate::{domain::recognition::Lang, i18n::strings};

    #[test]
    fn goal_counts_need_three_logged_days_in_both_languages() {
        for lang in [Lang::En, Lang::Zh] {
            let s = strings(lang);
            for logged in 1..=2 {
                let caption = s.intake_caption(Some(2000.0), logged, logged, 7);
                assert!(!caption.contains("over"));
                assert!(!caption.contains("超出"));
            }
            let caption = s.intake_caption(Some(2000.0), 2, 3, 7);
            assert!(caption.contains(if lang == Lang::En {
                "2 over"
            } else {
                "超出 2 天"
            }));
        }
    }

    #[test]
    fn vital_captions_are_compact_in_both_languages() {
        assert_eq!(strings(Lang::En).week_change(-0.1), "−0.1 · 7d");
        assert_eq!(strings(Lang::Zh).week_change(-0.1), "7天 −0.1");
    }
}
