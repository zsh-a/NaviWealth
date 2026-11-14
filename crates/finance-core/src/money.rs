//! Money as an integer count of minor units (fen): never binary floating
//! point. Parsing is exact: more than two decimals, or anything outside
//! `i64`, is refused rather than rounded.

/// An amount in minor units; negative is money out of an account.
pub type Minor = i64;

/// The exact minor units of a decimal (`31.5`, `.5`, `-1000.00`); `None`
/// for anything else, including more than two decimals or a sign when
/// `allow_negative` is false.
pub fn parse(input: &str, allow_negative: bool) -> Option<Minor> {
    let text = input.trim();
    let (negative, unsigned) = match text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, text),
    };
    if negative && !allow_negative {
        return None;
    }
    let (major, fraction) = match unsigned.split_once('.') {
        Some((major, fraction)) => (major, Some(fraction)),
        None => (unsigned, None),
    };
    let digits = |s: &str| s.chars().all(|c| c.is_ascii_digit());
    if !digits(major) {
        return None;
    }
    let fraction = match fraction {
        None if major.is_empty() => return None,
        None => "",
        // `.5` needs a digit after the point; `5.` is accepted.
        Some(f) if major.is_empty() && f.is_empty() => return None,
        Some(f) if f.len() > 2 || !digits(f) => return None,
        Some(f) => f,
    };
    let mut value: i128 = 0;
    for c in major.chars() {
        value = value
            .checked_mul(10)?
            .checked_add(i128::from(c as u8 - b'0'))?;
        if value > i128::from(i64::MAX) / 100 + 1 {
            return None;
        }
    }
    let cents: i128 = match fraction.len() {
        0 => 0,
        1 => i128::from(fraction.as_bytes()[0] - b'0') * 10,
        _ => fraction.parse::<i128>().ok()?,
    };
    let unsigned = value * 100 + cents;
    let signed = if negative { -unsigned } else { unsigned };
    i64::try_from(signed).ok()
}

/// `minor` with exactly two decimals (`-31.50`).
pub fn format(minor: Minor) -> String {
    let sign = if minor < 0 { "-" } else { "" };
    let magnitude = minor.unsigned_abs();
    format!("{sign}{}.{:02}", magnitude / 100, magnitude % 100)
}

/// Adds amounts without overflow: the sum saturates at `i64`'s ends (far
/// beyond any personal ledger).
pub fn sum(amounts: impl IntoIterator<Item = Minor>) -> Minor {
    saturate(amounts.into_iter().map(i128::from).sum())
}

/// A wide total as minor units, saturating at `i64`'s ends.
pub fn saturate(total: i128) -> Minor {
    i64::try_from(total).unwrap_or(if total < 0 { i64::MIN } else { i64::MAX })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decimals_parse_exactly_or_not_at_all() {
        assert_eq!(parse("31.50", false), Some(3150));
        assert_eq!(parse("31.5", false), Some(3150));
        assert_eq!(parse("31", false), Some(3100));
        assert_eq!(parse("31.", false), Some(3100));
        assert_eq!(parse(".5", false), Some(50));
        assert_eq!(parse(" 0.07 ", false), Some(7));
        assert_eq!(parse("-1000.00", true), Some(-100_000));
        assert_eq!(parse("-1", false), None);
        assert_eq!(parse("1.005", true), None, "never rounded");
        assert_eq!(parse("1,000.00", true), None);
        assert_eq!(parse("", true), None);
        assert_eq!(parse(".", true), None);
        assert_eq!(parse("-", true), None);
        assert_eq!(parse("1e3", true), None);
        assert_eq!(parse("92233720368547758.07", true), Some(i64::MAX));
        assert_eq!(parse("92233720368547758.08", true), None);
        assert_eq!(parse("-92233720368547758.08", true), Some(i64::MIN));
        assert_eq!(parse("99999999999999999999999", true), None);
    }

    #[test]
    fn amounts_format_with_two_decimals_and_sum_without_overflow() {
        assert_eq!(format(3150), "31.50");
        assert_eq!(format(-7), "-0.07");
        assert_eq!(format(0), "0.00");
        assert_eq!(format(i64::MIN), "-92233720368547758.08");
        assert_eq!(sum([3150, -3150, 7]), 7);
        assert_eq!(sum([i64::MAX, 1]), i64::MAX);
        assert_eq!(sum([i64::MIN, -1]), i64::MIN);
    }
}
