//! Currency is explicit at input and presentation boundaries.
use super::segmented::{Segment, segmented};
use finance_core::{account::Account, currency::Currency, money};
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
        money::format(amount)
    )
}
pub fn account_label(account: &Account) -> String {
    if account.currency() == Currency::CNY {
        account.name().to_owned()
    } else {
        format!("{} · {}", account.name(), account.currency().code())
    }
}
