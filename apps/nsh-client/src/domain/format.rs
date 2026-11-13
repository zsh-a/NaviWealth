//! How figures read: whole kcal with grouping, grams to a useful precision.

/// Whole kilocalories with thousands grouped: `1,240`.
pub fn kcal(value: f64) -> String {
    group(value.max(0.0).round() as i64)
}

/// Grams: one decimal below 10 (`7.5`), whole above (`62`).
pub fn grams(value: f64) -> String {
    let value = value.max(0.0);
    if value < 10.0 {
        let tenths = (value * 10.0).round() / 10.0;
        if tenths.fract() == 0.0 {
            format!("{tenths:.0}")
        } else {
            format!("{tenths:.1}")
        }
    } else {
        group(value.round() as i64)
    }
}

/// A whole percentage: `45%`.
pub fn percent(whole: u32) -> String {
    format!("{}%", whole.min(100))
}

/// A value for a number field: at most one decimal, no trailing zeros.
pub fn field_number(value: f64) -> String {
    let rounded = (value * 10.0).round() / 10.0;
    if rounded.fract() == 0.0 {
        format!("{rounded:.0}")
    } else {
        format!("{rounded:.1}")
    }
}

/// A number typed into a field: digits with an optional decimal point or
/// comma. Empty or malformed text is no number.
pub fn parse_number(text: &str) -> Option<f64> {
    let cleaned = text.trim().replace(',', ".");
    if cleaned.is_empty() {
        return None;
    }
    cleaned.parse::<f64>().ok().filter(|n| n.is_finite())
}

fn group(value: i64) -> String {
    let digits = value.unsigned_abs().to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3 + 1);
    if value < 0 {
        out.push('-');
    }
    for (index, digit) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index).is_multiple_of(3) {
            out.push(',');
        }
        out.push(digit);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kcal_rounds_and_groups() {
        assert_eq!(kcal(1239.6), "1,240");
        assert_eq!(kcal(0.4), "0");
        assert_eq!(kcal(-5.0), "0");
        assert_eq!(kcal(1_234_567.0), "1,234,567");
        assert_eq!(kcal(999.0), "999");
    }

    #[test]
    fn grams_keep_useful_precision() {
        assert_eq!(grams(7.46), "7.5");
        assert_eq!(grams(3.0), "3");
        assert_eq!(grams(62.4), "62");
        assert_eq!(grams(1500.0), "1,500");
    }

    #[test]
    fn percents_and_fields() {
        assert_eq!(percent(45), "45%");
        assert_eq!(percent(170), "100%");
        assert_eq!(field_number(149.0), "149");
        assert_eq!(field_number(6.94), "6.9");
        assert_eq!(parse_number(" 12,5 "), Some(12.5));
        assert_eq!(parse_number("abc"), None);
        assert_eq!(parse_number(""), None);
    }
}
