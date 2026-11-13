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

/// The change from the latest entry at least `days` days before `latest`
/// to `latest`, if there is one within twice that span (an old entry says
/// nothing about this week).
pub fn change_since(weights: &[Weight], latest: Weight, days: i32) -> Option<f64> {
    let before = latest_until(weights, latest.day.plus_days(-days))?;
    (latest.day.days_since(before.day) <= days * 2).then(|| rounded(latest.kg - before.kg))
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
    fn the_latest_entry_and_the_weekly_change() {
        let weights = [
            w("2026-11-01", 74.0),
            w("2026-11-06", 73.0),
            w("2026-11-13", 72.4),
        ];
        let latest = latest_until(&weights, day("2026-11-13")).unwrap();
        assert_eq!(latest.kg, 72.4);
        assert_eq!(latest_until(&weights, day("2026-11-05")).unwrap().kg, 74.0);
        assert_eq!(latest_until(&weights, day("2026-10-31")), None);
        // Seven days back is Nov 6.
        assert_eq!(change_since(&weights, latest, 7), Some(-0.6));
        // Nothing within two weeks before an entry on Dec 13.
        let later = w("2026-12-13", 71.0);
        assert_eq!(change_since(&weights, later, 7), None);
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
