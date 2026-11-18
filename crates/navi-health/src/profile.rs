//! Calendar age for body profiles. Hosts validate dates and supply their
//! current local day; this module has no clock or date-library dependency.

/// The age range supported by the body profile and scale protocol.
pub const AGE_RANGE: std::ops::RangeInclusive<u16> = 5..=120;

/// Completed years on `today`, within [`AGE_RANGE`]. Both tuples must be
/// valid Gregorian `(year, month, day)` dates, validated by the host.
/// A February 29 birthday completes another year on March 1 in a non-leap
/// year. Future birth dates and ages outside the supported range return None.
pub fn age_years_on(birth_date: (i16, i8, i8), today: (i16, i8, i8)) -> Option<u16> {
    if birth_date > today {
        return None;
    }
    let before_birthday = (today.1, today.2) < (birth_date.1, birth_date.2);
    let years = i32::from(today.0) - i32::from(birth_date.0) - i32::from(before_birthday);
    u16::try_from(years)
        .ok()
        .filter(|age| AGE_RANGE.contains(age))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn completed_years_change_on_the_birthday() {
        let birth = (1991, 11, 19);
        assert_eq!(age_years_on(birth, (2026, 11, 18)), Some(34));
        assert_eq!(age_years_on(birth, (2026, 11, 19)), Some(35));
        assert_eq!(age_years_on(birth, (2026, 11, 20)), Some(35));
        assert_eq!(age_years_on((1991, 12, 31), (2027, 1, 1)), Some(35));
        assert_eq!(age_years_on((1991, 1, 1), (2027, 1, 1)), Some(36));
    }

    #[test]
    fn leap_day_birthdays_use_march_first_in_common_years() {
        let birth = (2000, 2, 29);
        assert_eq!(age_years_on(birth, (2025, 2, 28)), Some(24));
        assert_eq!(age_years_on(birth, (2025, 3, 1)), Some(25));
        assert_eq!(age_years_on(birth, (2028, 2, 28)), Some(27));
        assert_eq!(age_years_on(birth, (2028, 2, 29)), Some(28));
        assert_eq!(age_years_on(birth, (2100, 2, 28)), Some(99));
        assert_eq!(age_years_on(birth, (2100, 3, 1)), Some(100));
    }

    #[test]
    fn future_dates_and_unsupported_ages_are_rejected_at_the_boundaries() {
        let today = (2026, 11, 19);
        assert_eq!(age_years_on((2026, 11, 20), today), None);
        assert_eq!(age_years_on((2027, 1, 1), today), None);
        assert_eq!(age_years_on(today, today), None);
        assert_eq!(age_years_on((2021, 11, 20), today), None);
        assert_eq!(age_years_on((2021, 11, 19), today), Some(5));
        assert_eq!(age_years_on((1906, 11, 19), today), Some(120));
        assert_eq!(age_years_on((1905, 11, 20), today), Some(120));
        assert_eq!(age_years_on((1905, 11, 19), today), None);
        assert_eq!(age_years_on((-9999, 1, 1), (9999, 1, 1)), None);
    }
}
