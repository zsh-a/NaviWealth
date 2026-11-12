//! Presentation only. Grouping and minimum currency digits never round Decimal.
use super::*;
use rust_decimal::Decimal;

#[derive(Clone, Copy)]
pub enum MoneySign {
    Natural,
    Inflow,
    Outflow,
}

pub fn money(value: Decimal) -> String {
    format_money(value, "", MoneySign::Natural)
}
pub fn money_for(value: Decimal, currency: &str) -> String {
    if currency.is_empty() {
        money(value)
    } else {
        format_money(value, currency, MoneySign::Natural)
    }
}
pub fn format_money(value: Decimal, currency: &str, sign: MoneySign) -> String {
    let negative = match sign {
        MoneySign::Outflow => !value.is_zero(),
        _ => value.is_sign_negative() && !value.is_zero(),
    };
    let positive = matches!(sign, MoneySign::Inflow) && value > Decimal::ZERO;
    let normalized = value.abs().normalize().to_string();
    let (whole, digits) = normalized.split_once('.').unwrap_or((&normalized, ""));
    let normalized_currency = currency.trim().to_ascii_uppercase();
    let minimum = match normalized_currency.as_str() {
        "BIF" | "CLP" | "DJF" | "GNF" | "ISK" | "JPY" | "KMF" | "KRW" | "PYG" | "RWF" | "UGX"
        | "UYI" | "VND" | "VUV" | "XAF" | "XOF" | "XPF" => 0,
        "BHD" | "IQD" | "JOD" | "KWD" | "LYD" | "OMR" | "TND" => 3,
        "CLF" | "UYW" => 4,
        _ => 2,
    };
    let mut result = String::new();
    if negative {
        result.push('-');
    } else if positive {
        result.push('+');
    }
    for (i, c) in whole.chars().enumerate() {
        if i > 0 && (whole.len() - i).is_multiple_of(3) {
            result.push(',');
        }
        result.push(c);
    }
    let precision = digits.len().max(minimum);
    if precision > 0 {
        result.push('.');
        result.push_str(digits);
        result.extend(std::iter::repeat_n('0', precision - digits.len()));
    }
    result
}
/// Only correctly grouped paste is ungrouped. Malformed input remains invalid;
/// e.g. 1,23 must never silently become 123.
pub fn raw_decimal_input(value: &str) -> String {
    if !value.contains(',') {
        return value.to_owned();
    }
    let trimmed = value.trim();
    let unsigned = trimmed.strip_prefix(['-', '+']).unwrap_or(trimmed);
    let (whole, fraction) = unsigned.split_once('.').unwrap_or((unsigned, ""));
    let groups = whole.split(',').collect::<Vec<_>>();
    let valid = !groups[0].is_empty()
        && groups[0].len() <= 3
        && groups.iter().all(|g| g.bytes().all(|c| c.is_ascii_digit()))
        && groups[1..].iter().all(|g| g.len() == 3)
        && fraction.bytes().all(|c| c.is_ascii_digit());
    if valid {
        trimmed.replace(',', "")
    } else {
        value.to_owned()
    }
}
#[derive(Clone, Copy)]
pub(crate) struct MoneyCurrency(pub Signal<String>);
/// Unfocused echo is grouped; the draft remains raw while editing and saving.
pub fn money_input(
    value: Signal<String>,
    currency: impl Fn() -> String + 'static,
) -> nsh_core::element::Input {
    money_input_when(value, move || Some(currency()))
}
/// A mixed quantity/cash field formats cash only, leaving unit precision alone.
pub fn money_input_when(
    value: Signal<String>,
    currency: impl Fn() -> Option<String> + 'static,
) -> nsh_core::element::Input {
    let focused = signal(false);
    let currency = std::rc::Rc::new(currency);
    let placeholder_currency = currency.clone();
    themed_input()
        .placeholder(move || {
            placeholder_currency()
                .map(|c| money_for(Decimal::ZERO, &c))
                .unwrap_or_default()
        })
        .value(move || {
            let raw = value.get();
            if focused.get() {
                return raw;
            }
            match (raw.parse::<Decimal>(), currency()) {
                (Ok(n), Some(currency)) => money_for(n, &currency),
                _ => raw,
            }
        })
        .on_change(move |s: &str| value.set(raw_decimal_input(s)))
        .on_focus(move || focused.set(true))
        .on_blur(move || focused.set(false))
        .tabular_nums()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[component]
    fn MoneyProbe() -> impl IntoElement {
        let raw = signal("1234.567".to_owned());
        let saved = signal(String::new());
        let currency = signal("USD".to_owned());
        view()
            .gap_3()
            .child(
                money_input(raw, move || currency.get())
                    .test_id("money-input")
                    .on_submit(move |_: &str| {
                        saved.set(raw.get().parse::<Decimal>().unwrap().to_string())
                    }),
            )
            .child(primary_button(
                "完成输入",
                dismiss_keyboard,
                "money-blur",
                None,
            ))
            .child(secondary_button(
                "JPY",
                move || currency.set("JPY".into()),
                "money-jpy",
                None,
            ))
            .child(text(move || format!("draft:{}", raw.get())))
            .child(text(move || format!("saved:{}", saved.get())))
    }
    #[test]
    fn native_echo_groups_without_mutating_the_raw_draft_or_submission() {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        let mut app = Headless::start(EngineConfig::new(Root::of::<MoneyProbe>())).unwrap();
        app.wait_for("id:money-input").unwrap();
        assert_eq!(
            app.screen().input_text("id:money-input").unwrap(),
            Some("1,234.567")
        );
        app.clear("id:money-input").unwrap();
        app.type_text("id:money-input", "5678.9").unwrap();
        app.submit("id:money-input").unwrap();
        app.wait_for("text:saved:5678.9").unwrap();
        app.press("id:money-blur").unwrap();
        app.wait_for("text:draft:5678.9").unwrap();
        assert_eq!(
            app.screen().input_text("id:money-input").unwrap(),
            Some("5,678.90")
        );
        app.press("id:money-jpy").unwrap();
        assert_eq!(
            app.screen().input_text("id:money-input").unwrap(),
            Some("5,678.9")
        );
        app.wait_for("text:draft:5678.9").unwrap();
    }
    fn d(s: &str) -> Decimal {
        s.parse().unwrap()
    }
    #[test]
    fn exact_grouping_sign_zero_and_large_values() {
        assert_eq!(money(d("12731.5")), "12,731.50");
        assert_eq!(money(d("-68.50")), "-68.50");
        assert_eq!(money(d("-0.00")), "0.00");
        assert_eq!(
            money(Decimal::MAX),
            "79,228,162,514,264,337,593,543,950,335.00"
        );
        assert_eq!(format_money(d("68.5"), "CNY", MoneySign::Outflow), "-68.50");
        assert_eq!(format_money(d("68.5"), "CNY", MoneySign::Inflow), "+68.50");
        assert_eq!(
            format_money(Decimal::ZERO, "USD", MoneySign::Inflow),
            "0.00"
        );
    }
    #[test]
    fn currency_digits_are_a_floor_never_rounding() {
        assert_eq!(money_for(d("12731"), "JPY"), "12,731");
        assert_eq!(money_for(d("12731.5"), "JPY"), "12,731.5");
        assert_eq!(money_for(d("42.5"), "KWD"), "42.500");
        assert_eq!(money_for(d("42.5"), "CLF"), "42.5000");
        assert_eq!(money_for(d("42.5"), "USD"), "42.50");
        assert_eq!(money_for(d("0.000001"), "CNY"), "0.000001");
        let original = d("-1234567.890123456789");
        assert_eq!(money_for(original, "USD"), "-1,234,567.890123456789");
        assert_eq!(original, d("-1234567.890123456789"));
    }
    #[test]
    fn grouped_input_round_trips_without_accepting_bad_separators() {
        assert_eq!(raw_decimal_input("-1,234.567"), "-1234.567");
        assert_eq!(raw_decimal_input("1,23"), "1,23");
        assert_eq!(raw_decimal_input("1,,234"), "1,,234");
        assert_eq!(raw_decimal_input("1,234.5.6"), "1,234.5.6");
        assert_eq!(raw_decimal_input("0."), "0.");
    }
}
