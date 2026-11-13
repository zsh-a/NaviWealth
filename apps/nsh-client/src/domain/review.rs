//! The week or month in review: intake, weight and Garmin numbers,
//! averaged over the days that have them. A day without records is
//! unknown: it is left out of averages, never counted as zero.

use health_core::garmin::GarminDay;

use super::{
    meal::{Day, DaySummary},
    nutrition::Nutrients,
    weight::{Weight, rounded},
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
    /// Seven days ending on a day.
    #[default]
    Week,
    /// A calendar month, up to today while it is the current one.
    Month,
}

/// The days of the `period` that is `back` periods before the current one
/// (`today` ends the current week; the current month stops at `today`),
/// oldest first.
pub fn period_days(period: Period, today: Day, back: i32) -> Vec<Day> {
    match period {
        Period::Week => days_ending(today.plus_days(-DAYS * back)),
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

/// The first and last weight of the week and the change between them.
pub fn weight_change(weights: &[Weight]) -> Option<(Weight, Weight, f64)> {
    let first = *weights.first()?;
    let last = *weights.last()?;
    (first.day != last.day).then(|| (first, last, rounded(last.kg - first.kg)))
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
        assert_eq!((week[0], week[6]), (day("2026-10-31"), day("2026-11-06")));
        assert_eq!(over_goal(&[Some(2100.0), None, Some(1900.0)], 2000.0), 1);
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
    fn weight_and_garmin_use_what_was_measured() {
        let w = |text: &str, kg: f64| Weight {
            day: day(text),
            kg,
            logged_at_ms: 0,
        };
        let change = weight_change(&[w("2026-11-08", 73.0), w("2026-11-13", 72.4)]).unwrap();
        assert_eq!(change.2, -0.6);
        assert_eq!(weight_change(&[w("2026-11-13", 72.4)]), None);

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
