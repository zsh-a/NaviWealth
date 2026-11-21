//! Currency is explicit at input and presentation boundaries.
use super::segmented::{Segment, segmented};
use super::{Type, Typo};
use navi_finance::{account::Account, currency::Currency, money};
use nsh_core::prelude::*;

pub fn picker(selected: Signal<Currency>) -> impl IntoElement {
    segmented(
        Currency::ALL
            .into_iter()
            .map(|c| Segment::new(c, move || c.code().into()))
            .collect(),
        move || selected.get(),
        move |c| selected.set(c),
    )
}
pub fn format(amount: i64, currency: Currency) -> String {
    decorate(&grouped(amount), currency)
}

/// Exact millionths for holding prices and unit costs, with up to six decimals.
pub fn unit_price(value: i64, currency: Currency) -> String {
    decorate(
        &group_decimal(&navi_finance::holdings::format_units(value)),
        currency,
    )
}

/// Archived observations without an identifiable native unit retain their digits.
pub fn observed_price(value: i64, currency: Option<Currency>) -> String {
    match currency {
        Some(currency) => unit_price(value, currency),
        None => format!(
            "{} · {}",
            navi_finance::holdings::format_units(value),
            crate::i18n::catalog::copy("Unknown currency", "币种未知"),
        ),
    }
}

/// Explicit sign for changes and gains, using the same exact display path.
pub fn signed(amount: i64, currency: Currency) -> String {
    let formatted = format(amount, currency);
    if amount > 0 {
        format!("+{formatted}")
    } else {
        formatted
    }
}

/// Magnitude of an exact difference, including the full i64 endpoint range.
pub fn difference_magnitude(current: i64, previous: i64, currency: Currency) -> String {
    let minor = (i128::from(current) - i128::from(previous)).abs();
    decorate(
        &group_decimal(&format!("{}.{:02}", minor / 100, minor % 100)),
        currency,
    )
}

pub(crate) fn decorate(value: &str, currency: Currency) -> String {
    let (sign, digits) = value
        .strip_prefix('-')
        .or_else(|| value.strip_prefix('−'))
        .map_or_else(
            || value.strip_prefix('+').map_or(("", value), |v| ("+", v)),
            |v| ("−", v),
        );
    let prefix = if currency == Currency::CNY {
        "¥".to_owned()
    } else {
        format!("{} ", currency.code())
    };
    format!("{sign}{prefix}{digits}")
}

/// Exact minor units, grouped for reading only. Editors and serialization
/// continue to use `navi_finance::money` without grouping separators.
pub fn grouped(amount: i64) -> String {
    group_decimal(&money::format(amount))
}

fn group_decimal(written: &str) -> String {
    let (whole, fraction) = written
        .split_once('.')
        .map_or((written, None), |(whole, fraction)| (whole, Some(fraction)));
    let (sign, digits) = whole.strip_prefix('-').map_or(("", whole), |v| ("-", v));
    let mut result = String::from(sign);
    for (index, ch) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index).is_multiple_of(3) {
            result.push(',');
        }
        result.push(ch);
    }
    if let Some(fraction) = fraction {
        result.push('.');
        result.push_str(fraction);
    }
    result
}

/// A readable signed native amount, using the shared currency presentation.
pub fn amount(value: String, currency: Currency, style: Type, tint: AdaptiveColor) -> View {
    view().min_w(px(0.0)).child(
        text(decorate(&value, currency))
            .typo(style)
            .tabular_nums()
            .text_color(tint)
            .min_w(px(0.0))
            .flex_shrink(1.0_f32),
    )
}

pub fn account_label(account: &Account) -> String {
    if account.currency() == Currency::CNY {
        account.name().to_owned()
    } else {
        format!("{} · {}", account.name(), account.currency().code())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unit_prices_keep_exact_precision_and_currency_conventions() {
        assert_eq!(unit_price(4_125_000, Currency::CNY), "¥4.125");
        assert_eq!(unit_price(1, Currency::CNY), "¥0.000001");
        assert_eq!(unit_price(1_234_567_891, Currency::USD), "USD 1,234.567891");
        assert_eq!(unit_price(12_000_000, Currency::HKD), "HKD 12");
    }

    #[test]
    fn grouped_display_preserves_exact_minor_units_and_signs() {
        for value in [0, 1, -1, 99_999, 100_000, -1_000_000, i64::MAX, i64::MIN] {
            assert_eq!(grouped(value).replace(',', ""), money::format(value));
        }
        assert_eq!(grouped(10_000_000), "100,000.00");
        assert_eq!(format(-123_456, Currency::CNY), "−¥1,234.56");
        assert_eq!(signed(25_500, Currency::CNY), "+¥255.00");
        assert_eq!(
            difference_magnitude(i64::MAX, i64::MIN, Currency::CNY),
            "¥184,467,440,737,095,516.15"
        );
        assert_eq!(
            format(i64::MIN, Currency::CNY),
            "−¥92,233,720,368,547,758.08"
        );
        assert_eq!(format(-123_456, Currency::USD), "−USD 1,234.56");
    }
}
