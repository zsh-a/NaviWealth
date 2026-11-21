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

    /// A chart-axis day (`Oct 23`, `10月23日`), with its year when asked
    /// (`Oct 23, 2025`, `2025年10月23日`).
    pub fn axis_date(&self, day: Day, with_year: bool) -> String {
        let date = day.0;
        match (self.zh(), with_year) {
            (true, true) => format!("{}年{}月{}日", date.year(), date.month(), date.day()),
            (true, false) => format!("{}月{}日", date.month(), date.day()),
            (false, true) => format!(
                "{} {}, {}",
                self.month_short(date.month()),
                date.day(),
                date.year()
            ),
            (false, false) => format!("{} {}", self.month_short(date.month()), date.day()),
        }
    }

    /// A day in brief (`Fri, Nov 13`, `11月13日 周五`).
    pub fn short_date(&self, day: Day) -> String {
        let date = day.0;
        if self.zh() {
            format!(
                "{}月{}日 {}",
                date.month(),
                date.day(),
                self.weekday_short(day)
            )
        } else {
            format!(
                "{}, {} {}",
                self.weekday_short(day),
                self.month_short(date.month()),
                date.day()
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

    /// Lead with one measured change, using comparable intake when weight is unavailable.
    pub fn review_summary(&self, change: Option<f64>, weight: Option<f64>) -> Option<String> {
        if let Some(weight) = weight.filter(|v| v.is_finite()) {
            let phrase = if (weight * 10.0).round() == 0.0 {
                self.review_weight_same
            } else if weight > 0.0 {
                self.review_weight_up
            } else {
                self.review_weight_down
            };
            return Some(phrase.replace("{value}", &self.kg(weight.abs())));
        }
        let change = change.filter(|v| v.is_finite())?;
        let phrase = if change.round() == 0.0 {
            self.review_intake_same
        } else if change > 0.0 {
            self.review_intake_more
        } else {
            self.review_intake_less
        };
        Some(phrase.replace("{value}", &format::kcal(change.abs())))
    }

    /// Coverage beside the average and, for a calendar, its goal context.
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
        let arrow = if delta < 0.0 {
            "↓"
        } else if delta > 0.0 {
            "↑"
        } else {
            ""
        };
        format!("{arrow}{} kg · {}", self.kg(delta.abs()), self.seven_days)
    }

    /// A newer release found, by its version.
    pub fn update_found(&self, version: &str) -> String {
        if self.zh() {
            format!("发现新版本 v{version}")
        } else {
            format!("Update available · v{version}")
        }
    }

    /// When the last check ran.
    pub fn update_checked_at(&self, when: &str) -> String {
        if self.zh() {
            format!("上次检查 {when}")
        } else {
            format!("Last checked {when}")
        }
    }

    /// Running the newest release.
    pub fn update_uptodate(&self, version: &str) -> String {
        if self.zh() {
            format!("已是最新 v{version}")
        } else {
            format!("Up to date · v{version}")
        }
    }

    /// The signed distance from a weight to the goal weight; positive is
    /// above the goal, negative below.
    pub fn to_goal(&self, delta_kg: f64) -> String {
        if self.zh() {
            format!("距目标 {}", self.signed_kg(delta_kg))
        } else {
            format!("{} kg to goal", self.signed_kg(delta_kg))
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
    fn review_sentence_does_not_invent_a_missing_comparison() {
        for lang in [Lang::En, Lang::Zh] {
            let s = strings(lang);
            assert!(s.review_summary(None, None).is_none());
            let line = s.review_summary(Some(-100.0), Some(-0.5)).unwrap();
            assert!(line.contains("0.5"));
            assert!(!line.contains("100"));
            let compared = s.review_summary(Some(-100.0), None).unwrap();
            assert!(compared.contains("100"));
        }
    }

    #[test]
    fn vital_captions_are_compact_in_both_languages() {
        assert_eq!(strings(Lang::En).week_change(-0.1), "↓0.1 kg · 7d");
        assert_eq!(strings(Lang::Zh).week_change(-0.1), "↓0.1 kg · 7天");
    }
}
