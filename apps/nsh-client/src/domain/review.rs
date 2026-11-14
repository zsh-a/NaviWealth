//! The week or month in review: intake, weight and Garmin numbers,
//! averaged over the days that have them. A day without records is
//! unknown: it is left out of averages, never counted as zero.

use health_core::garmin::GarminDay;

use super::{
    meal::{Day, DaySummary},
    nutrition::Nutrients,
    weight::{self, Weight},
};

/// Days in a review.
pub const DAYS: i32 = 7;

/// The seven days ending on `last`, oldest first.
pub fn days_ending(last: Day) -> Vec<Day> {
    (0..DAYS).rev().map(|back| last.plus_days(-back)).collect()
}

/// The span a review covers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Period {
    /// A calendar week, up to today while it is the current one.
    #[default]
    Week,
    /// A calendar month, up to today while it is the current one.
    Month,
}

/// First weekday for calendar reviews. ISO Monday is the fallback.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum WeekStart {
    #[default]
    Monday,
    Sunday,
}

/// The days of the `period` that is `back` periods before the current one
/// (the current period stops at `today`), oldest first.
pub fn period_days(period: Period, today: Day, back: i32) -> Vec<Day> {
    period_days_starting(period, today, back, WeekStart::Monday)
}

/// Locale-aligned calendar periods; negative offsets cannot show the future.
pub fn period_days_starting(period: Period, today: Day, back: i32, start: WeekStart) -> Vec<Day> {
    let back = back.max(0);
    match period {
        Period::Week => {
            let offset = i32::from(today.0.weekday().to_monday_zero_offset());
            let offset = if start == WeekStart::Sunday {
                (offset + 1) % 7
            } else {
                offset
            };
            let first = today.plus_days(-offset - DAYS * back);
            let last = first.plus_days(6).min(today);
            (0..=last.days_since(first))
                .map(|d| first.plus_days(d))
                .collect()
        }
        Period::Month => {
            let month = today
                .0
                .first_of_month()
                .checked_sub(jiff::Span::new().months(back))
                .unwrap_or_else(|_| today.0.first_of_month());
            let last = month.last_of_month().min(today.0);
            let first = Day(month);
            (0..=Day(last).days_since(first))
                .map(|offset| first.plus_days(offset))
                .collect()
        }
    }
}

/// Days whose energy passed `goal`.
pub fn over_goal(kcal: &[Option<f64>], goal: f64) -> usize {
    kcal.iter().flatten().filter(|&&k| k > goal).count()
}

/// What the period's meals add up to.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Intake {
    /// Each day's energy, `None` where nothing was logged.
    pub kcal: Vec<Option<f64>>,
    /// Days with at least one meal.
    pub logged_days: usize,
    /// The average per logged day.
    pub average: Option<Nutrients>,
}

pub fn intake(summaries: &[DaySummary]) -> Intake {
    let kcal: Vec<Option<f64>> = summaries
        .iter()
        .map(|day| (day.meals > 0).then_some(day.total.kcal))
        .collect();
    let logged: Vec<&DaySummary> = summaries.iter().filter(|day| day.meals > 0).collect();
    let average = (!logged.is_empty()).then(|| {
        let n = logged.len() as f64;
        let sum = logged
            .iter()
            .fold(Nutrients::ZERO, |sum, day| sum + day.total);
        Nutrients::new(sum.kcal / n, sum.protein / n, sum.carbs / n, sum.fat / n)
    });
    Intake {
        kcal,
        logged_days: logged.len(),
        average,
    }
}

/// The same trend comparison as Today, anchored at the period's start.
/// Pass full history so the first day's trailing average includes earlier days.
pub fn weight_change(weights: &[Weight], first: Day, last: Day) -> Option<f64> {
    weight::trend_change(weights, first, last)
}

/// Garmin's week: averages over the days it measured.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Recovery {
    pub sleep_seconds: Option<f64>,
    pub sleep_score: Option<f64>,
    pub resting_hr: Option<f64>,
    pub hrv_ms: Option<f64>,
    pub steps: Option<f64>,
    /// Days with any Garmin number.
    pub days: usize,
}

pub fn recovery(days: &[GarminDay]) -> Recovery {
    fn average(values: impl Iterator<Item = Option<f64>>) -> Option<f64> {
        let present: Vec<f64> = values.flatten().collect();
        (!present.is_empty()).then(|| present.iter().sum::<f64>() / present.len() as f64)
    }
    Recovery {
        sleep_seconds: average(days.iter().map(|d| d.sleep_seconds.map(f64::from))),
        sleep_score: average(days.iter().map(|d| d.sleep_score.map(f64::from))),
        resting_hr: average(days.iter().map(|d| d.resting_hr.map(f64::from))),
        hrv_ms: average(days.iter().map(|d| d.hrv_ms.map(f64::from))),
        steps: average(days.iter().map(|d| d.steps.map(f64::from))),
        days: days.iter().filter(|d| !d.is_empty()).count(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(text: &str) -> Day {
        Day(text.parse().unwrap())
    }

    #[test]
    fn a_week_ends_on_its_last_day() {
        let days = days_ending(day("2026-11-13"));
        assert_eq!(days.len(), 7);
        assert_eq!(days[0], day("2026-11-07"));
        assert_eq!(days[6], day("2026-11-13"));
    }

    #[test]
    fn a_month_runs_from_its_first_day_to_today_or_its_end() {
        let today = day("2026-11-13");
        let current = period_days(Period::Month, today, 0);
        assert_eq!(current.len(), 13);
        assert_eq!(current[0], day("2026-11-01"));
        assert_eq!(current[12], today);
        let october = period_days(Period::Month, today, 1);
        assert_eq!(october.len(), 31);
        assert_eq!(october[30], day("2026-10-31"));
        let week = period_days(Period::Week, today, 1);
        assert_eq!((week[0], week[6]), (day("2026-11-02"), day("2026-11-08")));
        assert_eq!(over_goal(&[Some(2100.0), None, Some(1900.0)], 2000.0), 1);
    }

    #[test]
    fn calendar_weeks_use_monday_by_default_and_sunday_when_requested() {
        let today = day("2026-11-14");
        let iso = period_days(Period::Week, today, 0);
        assert_eq!((iso[0], *iso.last().unwrap()), (day("2026-11-09"), today));
        let sunday = period_days_starting(Period::Week, today, 0, WeekStart::Sunday);
        assert_eq!((sunday[0], sunday[6]), (day("2026-11-08"), today));
        let monday = period_days(Period::Week, day("2026-11-09"), 0);
        assert_eq!(monday, [day("2026-11-09")]);
        let year = period_days(Period::Week, day("2027-01-01"), 1);
        assert_eq!((year[0], year[6]), (day("2026-12-21"), day("2026-12-27")));
        assert_eq!(period_days(Period::Week, today, -1), iso);
    }

    #[test]
    fn review_and_today_share_the_trend_and_need_history_before_the_period() {
        let first = day("2026-11-01");
        let weights: Vec<_> = (0..21)
            .map(|d| Weight {
                day: first.plus_days(d),
                kg: 80.0 - f64::from(d) * 0.1,
                logged_at_ms: 0,
            })
            .collect();
        let start = first.plus_days(7);
        let end = start.plus_days(7);
        assert_eq!(weight_change(&weights, start, end), Some(-0.7));
        assert_eq!(
            weight_change(&weights, start, end),
            weight::trend_change(&weights, start, end)
        );
        assert_eq!(weight_change(&weights[7..], start, end), None);
    }

    #[test]
    fn month_start_trend_uses_previous_month_and_leap_month_is_complete() {
        let february = period_days(Period::Month, day("2024-03-10"), 1);
        assert_eq!(february.len(), 29);
        assert_eq!(february[28], day("2024-02-29"));
        let first = day("2026-10-26");
        let weights: Vec<_> = (0..20)
            .map(|d| Weight {
                day: first.plus_days(d),
                kg: 80.0 - f64::from(d) * 0.1,
                logged_at_ms: 0,
            })
            .collect();
        assert_eq!(
            weight_change(&weights, day("2026-11-01"), day("2026-11-14")),
            Some(-1.3)
        );
    }

    #[test]
    fn unlogged_days_are_left_out_not_zero() {
        let logged = |kcal: f64| DaySummary {
            total: Nutrients::new(kcal, 100.0, 200.0, 50.0),
            meals: 2,
        };
        let week = [
            logged(2000.0),
            DaySummary::default(),
            logged(1600.0),
            DaySummary::default(),
            DaySummary::default(),
            DaySummary::default(),
            DaySummary::default(),
        ];
        let intake = intake(&week);
        assert_eq!(intake.logged_days, 2);
        assert_eq!(intake.kcal[0], Some(2000.0));
        assert_eq!(intake.kcal[1], None);
        let average = intake.average.unwrap();
        assert_eq!((average.kcal, average.protein), (1800.0, 100.0));
        assert_eq!(super::intake(&[DaySummary::default(); 7]).average, None);
    }

    #[test]
    fn garmin_uses_what_was_measured() {
        let g = |sleep: Option<u32>, hr: Option<u16>| GarminDay {
            sleep_seconds: sleep,
            resting_hr: hr,
            ..GarminDay::default()
        };
        let week = recovery(&[
            g(Some(27000), Some(44)),
            g(None, Some(40)),
            g(Some(25200), None),
        ]);
        assert_eq!(week.sleep_seconds, Some(26100.0));
        assert_eq!(week.resting_hr, Some(42.0));
        assert_eq!(week.hrv_ms, None);
        assert_eq!(week.days, 3);
    }
}
