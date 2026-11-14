//! Body weight: at most one entry per day, in kilograms. A day without an
//! entry is unknown, never carried over or interpolated.

use super::meal::Day;

/// The lightest and heaviest weight accepted, in kg.
pub const MIN_KG: f64 = 20.0;
pub const MAX_KG: f64 = 400.0;

/// The weight logged for one day.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Weight {
    pub day: Day,
    pub kg: f64,
    pub logged_at_ms: i64,
}

/// Whether `kg` can be kept.
pub fn valid_kg(kg: f64) -> bool {
    kg.is_finite() && (MIN_KG..=MAX_KG).contains(&kg)
}

/// `kg` to one decimal, as weights are shown and kept.
pub fn rounded(kg: f64) -> f64 {
    (kg * 10.0).round() / 10.0
}

/// The latest entry on or before `day`; `weights` in day order.
pub fn latest_until(weights: &[Weight], day: Day) -> Option<Weight> {
    weights.iter().rev().find(|w| w.day <= day).copied()
}

/// The trailing seven-day trend, requiring at least three recent measurements.
pub fn trend_weight(weights: &[Weight], day: Day) -> Option<f64> {
    health_core::weight::trend_weight(&offsets(weights, day), 0)
}

/// One definition of change for Today and Review: the difference between
/// trailing seven-day means at `start` and `end`, rounded to 0.1 kg.
pub fn trend_change(weights: &[Weight], start: Day, end: Day) -> Option<f64> {
    health_core::weight::trend_change(&offsets(weights, start), 0, end.days_since(start))
}

fn offsets(weights: &[Weight], origin: Day) -> Vec<(i32, f64)> {
    weights
        .iter()
        .map(|w| (w.day.days_since(origin), w.kg))
        .collect()
}

/// The entries in the `days` days ending on `day`, in day order.
pub fn window(weights: &[Weight], day: Day, days: i32) -> Vec<Weight> {
    let first = day.plus_days(1 - days);
    weights
        .iter()
        .filter(|w| w.day >= first && w.day <= day)
        .copied()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(text: &str) -> Day {
        Day(text.parse().unwrap())
    }

    fn w(text: &str, kg: f64) -> Weight {
        Weight {
            day: day(text),
            kg,
            logged_at_ms: 0,
        }
    }

    #[test]
    fn weights_outside_the_human_range_are_refused() {
        assert!(valid_kg(72.4));
        assert!(!valid_kg(0.0));
        assert!(!valid_kg(f64::NAN));
        assert!(!valid_kg(401.0));
        assert_eq!(rounded(72.449), 72.4);
    }

    #[test]
    fn dates_adapt_to_the_shared_trend_without_losing_prior_history() {
        let first = day("2026-10-26");
        let weights: Vec<_> = (0..14)
            .map(|d| Weight {
                day: first.plus_days(d),
                kg: 80.0 - f64::from(d) * 0.1,
                logged_at_ms: 0,
            })
            .collect();
        assert_eq!(latest_until(&weights, first).unwrap().kg, 80.0);
        assert_eq!(latest_until(&weights, first.plus_days(-1)), None);
        assert_eq!(
            trend_change(&weights, first.plus_days(6), first.plus_days(13)),
            Some(-0.7)
        );
        assert!((trend_weight(&weights, first.plus_days(6)).unwrap() - 79.7).abs() < 1e-9);
    }

    #[test]
    fn a_window_holds_only_its_days() {
        let weights = [
            w("2026-10-14", 75.0),
            w("2026-10-15", 74.8),
            w("2026-11-13", 72.4),
        ];
        let days: Vec<_> = window(&weights, day("2026-11-13"), 30)
            .into_iter()
            .map(|w| w.kg)
            .collect();
        assert_eq!(days, [74.8, 72.4]);
    }
}
