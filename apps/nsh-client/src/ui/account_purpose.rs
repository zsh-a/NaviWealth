use navi_finance::{
    account::{Account, AccountKind, AccountPurpose},
    currency::Currency,
};
use nsh_core::prelude::*;

use super::{Icon, Type, Typo, color, icon, surface::row_button};
use crate::{
    data::finance,
    i18n::{catalog::copy, s},
};

pub fn label(purpose: AccountPurpose) -> &'static str {
    match purpose {
        AccountPurpose::Cash => copy("Cash", "现金"),
        AccountPurpose::Bank => copy("Bank account", "银行账户"),
        AccountPurpose::Wallet => copy("Digital wallet", "电子钱包"),
        AccountPurpose::Brokerage => copy("Brokerage cash", "证券资金"),
        AccountPurpose::Credit => copy("Consumer credit", "消费信用"),
        AccountPurpose::Loan => copy("Loan", "借款"),
    }
}

pub fn description(account: &Account, purpose: Option<AccountPurpose>) -> &'static str {
    match purpose {
        Some(purpose) => label(purpose),
        None if account.kind() == AccountKind::Liabilities => s().liability_account,
        None => s().asset_account,
    }
}

pub fn picker(
    selected: Option<AccountPurpose>,
    kind: Option<AccountKind>,
    choose: impl Fn(AccountPurpose) + Copy + 'static,
) -> impl IntoElement {
    view().gap_3().children(
        [AccountKind::Assets, AccountKind::Liabilities]
            .into_iter()
            .filter(move |group| kind.is_none_or(|k| *group == k))
            .map(move |group| {
                view()
                    .child(
                        text(if group == AccountKind::Assets {
                            s().cash_accounts
                        } else {
                            s().debt_accounts
                        })
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .role(AccessibilityRole::Header),
                    )
                    .children(
                        AccountPurpose::ALL
                            .into_iter()
                            .filter(move |p| p.kind() == group)
                            .map(move |p| {
                                let checked = selected == Some(p);
                                row_button(move || choose(p))
                                    .px_0()
                                    .py_2()
                                    .min_h(px(48.0))
                                    .accessibility_label(Some(label(p).into()))
                                    .selected(checked)
                                    .child(
                                        text(label(p))
                                            .typo(Type::Body)
                                            .text_color(if checked {
                                                color::ACCENT_INK
                                            } else {
                                                color::INK
                                            })
                                            .flex_1(),
                                    )
                                    .child(
                                        checked.then(|| icon(Icon::Check, 18.0, color::ACCENT_INK)),
                                    )
                            }),
                    )
            }),
    )
}

/// Keep the ledger's name order within each preference group.
pub fn daily_accounts() -> Vec<Account> {
    let mut accounts: Vec<_> = finance::active_accounts()
        .into_iter()
        .filter(Account::is_cash)
        .collect();
    accounts.sort_by_cached_key(|account| match finance::account_purpose(account) {
        Some(
            AccountPurpose::Bank
            | AccountPurpose::Wallet
            | AccountPurpose::Cash
            | AccountPurpose::Credit,
        ) => 0,
        None => 1,
        Some(AccountPurpose::Brokerage | AccountPurpose::Loan) => 2,
    });
    accounts
}

pub fn settlement_accounts(currency: Currency) -> Vec<Account> {
    let mut accounts: Vec<_> = finance::active_accounts()
        .into_iter()
        .filter(|account| account.can_settle(currency, finance::account_purpose(account)))
        .collect();
    accounts.sort_by_cached_key(|a| match finance::account_purpose(a) {
        Some(AccountPurpose::Brokerage) => 0,
        Some(AccountPurpose::Bank) => 1,
        _ => 2,
    });
    accounts
}
