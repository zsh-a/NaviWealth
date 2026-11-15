//! Weight trends over measured days. Missing days are never filled in.
//! Hosts supply calendar-day offsets and one measurement per day.

/// Trailing seven-calendar-day mean. At least three measured days and a
/// measurement in the last three days are needed to call it a trend.
pub fn trend_weight(entries: &[(i32, f64)], day: i32) -> Option<f64> {
    let measured: Vec<_> = entries
        .iter()
        .filter(|(d, kg)| *d > day - 7 && *d <= day && kg.is_finite())
        .collect();
    if measured.len() < 3 || measured.iter().all(|(d, _)| *d < day - 2) {
        return None;
    }
    Some(measured.iter().map(|(_, kg)| kg).sum::<f64>() / measured.len() as f64)
}

/// Difference between trend weights at two dates, rounded once to 0.1 kg.
/// A gap longer than a week in between makes the comparison unknown too.
pub fn trend_change(entries: &[(i32, f64)], start: i32, end: i32) -> Option<f64> {
    if end <= start {
        return None;
    }
    let before = trend_weight(entries, start)?;
    let after = trend_weight(entries, end)?;
    if (start..=end).any(|day| {
        !entries
            .iter()
            .any(|(d, kg)| *d > day - 7 && *d <= day && kg.is_finite())
    }) {
        return None;
    }
    Some(((after - before) * 10.0).round() / 10.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seven_calendar_days_not_seven_entries() {
        let entries = [(0, 100.0), (1, 74.0), (3, 73.0), (7, 72.0), (8, 99.0)];
        assert_eq!(trend_weight(&entries, 7), Some(73.0));
    }

    #[test]
    fn single_sparse_and_stale_windows_are_unknown() {
        assert_eq!(trend_weight(&[], 7), None);
        assert_eq!(trend_weight(&[(7, 72.0)], 7), None);
        assert_eq!(trend_weight(&[(0, 74.0), (7, 72.0)], 7), None);
        assert_eq!(trend_weight(&[(1, 74.0), (2, 73.0), (3, 72.0)], 7), None);
    }

    #[test]
    fn gaps_are_allowed_without_carrying_forward_or_interpolating() {
        let entries = [
            (0, 75.0),
            (2, 74.0),
            (4, 73.0),
            (7, 73.0),
            (9, 72.0),
            (11, 71.0),
        ];
        assert_eq!(trend_change(&entries, 4, 11), Some(-2.0));
        assert_eq!(trend_change(&entries, 4, 4), None);
        assert_eq!(trend_change(&entries, 4, 20), None);
    }

    #[test]
    fn long_interior_gaps_do_not_imply_a_continuous_trend() {
        let entries = [
            (0, 75.0),
            (1, 74.0),
            (2, 73.0),
            (28, 73.0),
            (29, 72.0),
            (30, 71.0),
        ];
        assert_eq!(trend_change(&entries, 2, 30), None);
    }

    #[test]
    fn change_uses_averages_and_rounds_only_the_difference() {
        let entries: Vec<_> = (0..14)
            .map(|day| (day, 80.0 - f64::from(day) * 0.1))
            .collect();
        assert_eq!(trend_change(&entries, 6, 13), Some(-0.7));
        assert_eq!(trend_change(&[(0, 75.0), (7, 74.0)], 0, 7), None);
    }
}
