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
    format!(
        "{}{}",
        if currency == Currency::CNY {
            "¥".into()
        } else {
            format!("{} ", currency.code())
        },
        grouped(amount)
    )
}

/// Exact minor units, grouped for reading only. Editors and serialization
/// continue to use `navi_finance::money` without grouping separators.
pub fn grouped(amount: i64) -> String {
    let written = money::format(amount);
    let (whole, fraction) = written
        .split_once('.')
        .expect("minor units have two decimals");
    let (sign, digits) = whole.strip_prefix('-').map_or(("", whole), |v| ("-", v));
    let mut result = String::from(sign);
    for (index, ch) in digits.chars().enumerate() {
        if index > 0 && (digits.len() - index).is_multiple_of(3) {
            result.push(',');
        }
        result.push(ch);
    }
    format!("{result}.{fraction}")
}

/// A readable native amount. The smaller currency shares its baseline and
/// can wrap if the surrounding row has too little room.
pub fn amount(value: String, currency: Currency, style: Type, tint: AdaptiveColor) -> View {
    view()
        .flex_row()
        .items_baseline()
        .flex_wrap()
        .gap(px(4.0))
        .min_w(px(0.0))
        .child(
            text(value)
                .typo(style)
                .tabular_nums()
                .text_color(tint)
                .min_w(px(0.0))
                .flex_shrink(1.0_f32),
        )
        .child(
            text(currency.code())
                .typo(Type::Caption)
                .text_color(super::color::MUTED),
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
    fn grouped_display_preserves_exact_minor_units_and_signs() {
        for value in [0, 1, -1, 99_999, 100_000, -1_000_000, i64::MAX, i64::MIN] {
            assert_eq!(grouped(value).replace(',', ""), money::format(value));
        }
        assert_eq!(grouped(10_000_000), "100,000.00");
        assert_eq!(format(-123_456, Currency::USD), "USD -1,234.56");
    }
}
