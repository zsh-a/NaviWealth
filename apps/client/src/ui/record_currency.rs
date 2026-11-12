//! Currency visibility is presentation only; source values stay untouched.
use std::collections::BTreeMap;

#[derive(Clone, Default, PartialEq)]
pub struct RecordCurrencies {
    pub base: String,
    pub accounts: BTreeMap<String, String>,
}
pub struct RowCurrency {
    pub code: String,
    pub inline: Option<String>,
}
impl RecordCurrencies {
    pub fn row(&self, code: String, account_id: &str) -> RowCurrency {
        let matches = |other: &str| {
            !other.trim().is_empty() && code.trim().eq_ignore_ascii_case(other.trim())
        };
        let local = matches(&self.base)
            || self
                .accounts
                .get(account_id)
                .is_some_and(|account| matches(account));
        let inline = (!local && !code.is_empty()).then(|| code.clone());
        RowCurrency { code, inline }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn hides_account_or_base_currency_but_keeps_foreign_or_unknown_units() {
        let context = RecordCurrencies {
            base: "CNY".into(),
            accounts: BTreeMap::from([("bank".into(), "CNY".into()), ("usd".into(), "USD".into())]),
        };
        for (currency, account, expected) in [
            ("CNY", "bank", None),
            ("CNY", "usd", None),
            ("USD", "usd", None),
            ("USD", "bank", Some("USD")),
            ("JPY", "unknown", Some("JPY")),
            ("CNY", "unknown", None),
        ] {
            let row = context.row(currency.into(), account);
            assert_eq!(row.inline.as_deref(), expected);
            assert_eq!(row.code, currency);
        }
        assert_eq!(
            RecordCurrencies::default()
                .row("USD".into(), "unknown")
                .inline
                .as_deref(),
            Some("USD")
        );
    }
}

#[cfg(test)]
mod render_tests {
    use crate::ui::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    #[component]
    fn CurrencyRows() -> impl IntoElement {
        let currencies = RecordCurrencies {
            base: "CNY".into(),
            accounts: std::collections::BTreeMap::from([("bank".into(), "CNY".into())]),
        };
        view()
            .child(transaction_row(
                "本币".into(),
                "账户".into(),
                "餐饮",
                "-68.50".into(),
                currencies.row("CNY".into(), "bank"),
                "local".into(),
                || {},
            ))
            .child(transaction_row(
                "外币".into(),
                "账户".into(),
                "餐饮",
                "-18.00".into(),
                currencies.row("USD".into(), "bank"),
                "foreign".into(),
                || {},
            ))
    }
    #[test]
    fn native_text_has_no_repeated_local_unit_and_foreign_unit_is_inline() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<CurrencyRows>())).unwrap();
        app.wait_for("text:-68.50").unwrap();
        app.wait_for("text:-18.00 USD").unwrap();
        assert_eq!(app.screen().count("text:CNY").unwrap(), 0);
        assert_eq!(app.screen().count("text:USD").unwrap(), 0);
    }
}
