//! Explicit local account selection updates only the draft, never the ledger.
use navi_finance::{
    account::{Account, AccountKind},
    recognition::Kind,
};
use nsh_core::prelude::*;

use crate::{
    data::{capture, finance},
    domain::capture::{Draft, Record, Status},
    i18n::s,
    ui::{Icon, Type, Typo, color, icon, surface::row_button},
};

#[derive(Clone, Copy, PartialEq)]
pub enum Choice {
    Account { index: usize, destination: bool },
    Category(usize),
    Value(usize),
}

pub fn picker(
    draft: Signal<Draft>,
    input: Signal<String>,
    error: Signal<Option<String>>,
    choosing: Signal<Option<Choice>>,
    index: usize,
    destination: bool,
) -> impl IntoElement {
    let current = draft.get_untracked();
    let (field, selected, other, currency) = match current.records.get(index) {
        Some(Record::Money { draft: money, .. }) => (
            if destination {
                "other_account"
            } else {
                "account"
            },
            if destination {
                money.other_account.clone()
            } else {
                money.account.clone()
            },
            if destination {
                money.account.clone()
            } else {
                money.other_account.clone()
            },
            navi_finance::currency::Currency::parse(&money.currency),
        ),
        Some(Record::Trade { cash, currency, .. }) if !destination => {
            ("cash", cash.clone(), None, Some(*currency))
        }
        Some(Record::Balance { account, .. }) if !destination => (
            "account",
            Some(account.clone()),
            None,
            Some(account.currency()),
        ),
        _ => return view().into_element(),
    };
    let balance_kind = match current.records.get(index) {
        Some(Record::Balance { account, .. }) => Some(account.kind()),
        _ => None,
    };
    let selected = selected.filter(|_| !current.account_needs_approval(index, field));
    let accounts: Vec<_> = finance::accounts()
        .into_iter()
        .filter(|a| {
            a.is_cash()
                && Some(a.currency()) == currency
                && Some(a) != other.as_ref()
                && balance_kind.is_none_or(|kind| a.kind() == kind)
        })
        .collect();
    view()
        .gap_2()
        .child(
            text(if destination {
                s().capture_need_destination
            } else {
                s().capture_need_account
            })
            .typo(Type::Body)
            .text_color(color::MUTED),
        )
        .child(accounts.is_empty().then(|| {
            text(s().capture_no_accounts)
                .typo(Type::Body)
                .text_color(color::MUTED)
        }))
        .children(accounts.into_iter().map(move |account| {
            let name = account.name().to_owned();
            let checked = selected.as_ref() == Some(&account);
            row_button(move || {
                let mut next = draft.get_untracked();
                if next.status != Status::Ready {
                    return;
                }
                if !finance::accounts().contains(&account) || !account.is_cash() {
                    return;
                }
                match next.records.get_mut(index) {
                    Some(Record::Money { draft: money, .. }) => {
                        let (target, other) = if destination {
                            (&mut money.other_account, &money.account)
                        } else {
                            (&mut money.account, &money.other_account)
                        };
                        if other.as_ref() == Some(&account)
                            || account.currency().code() != money.currency
                        {
                            return;
                        }
                        *target = Some(account.clone());
                    }
                    Some(Record::Trade { cash, currency, .. })
                        if !destination && *currency == account.currency() =>
                    {
                        *cash = Some(account.clone());
                    }
                    Some(Record::Balance {
                        account: target, ..
                    }) if !destination
                        && target.currency() == account.currency()
                        && target.kind() == account.kind() =>
                    {
                        *target = account.clone();
                    }
                    _ => return,
                }
                next.mark_owner_field(index, field);
                next.correction = input.get_untracked();
                match capture::put(next.clone()) {
                    Ok(()) => {
                        error.set(None);
                        draft.set(next);
                        choosing.set(None);
                    }
                    Err(cause) => {
                        log::error!("capture: account selection could not be kept: {cause}");
                        error.set(Some(s().error_transaction_storage.into()));
                    }
                }
            })
            .px_0()
            .accessibility_label(Some(name.clone().into()))
            .child(
                text(name)
                    .typo(Type::Headline)
                    .text_color(color::INK)
                    .flex_1(),
            )
            .child(checked.then(|| icon(Icon::Check, 20.0, color::INK)))
        }))
        .into_element()
}

/// Chooses the category of a recognized spending or income record from the
/// existing categories in its currency; the draft alone changes.
pub fn category_picker(
    draft: Signal<Draft>,
    input: Signal<String>,
    error: Signal<Option<String>>,
    choosing: Signal<Option<Choice>>,
    index: usize,
) -> impl IntoElement {
    let current = draft.get_untracked();
    let Some(Record::Money { draft: money, .. }) = current.records.get(index) else {
        return view().into_element();
    };
    let kind = if money.kind == Kind::Income {
        AccountKind::Income
    } else {
        AccountKind::Expenses
    };
    let currency = navi_finance::currency::Currency::parse(&money.currency)
        .unwrap_or(navi_finance::currency::Currency::CNY);
    let selected = money.category.clone();
    let categories: std::collections::BTreeSet<Account> = finance::accounts()
        .into_iter()
        .filter(|a| a.kind() == kind)
        .map(|a| a.in_currency(currency))
        .collect();
    view()
        .gap_1()
        .children(categories.into_iter().map(move |category| {
            let name = super::super::finance::category_label(&category);
            let checked = selected.as_ref() == Some(&category);
            row_button(move || {
                let mut next = draft.get_untracked();
                if next.status != Status::Ready {
                    return;
                }
                let Some(Record::Money { draft: money, .. }) = next.records.get_mut(index) else {
                    return;
                };
                money.category = Some(category.clone());
                next.mark_owner_field(index, "category");
                next.correction = input.get_untracked();
                match capture::put(next.clone()) {
                    Ok(()) => {
                        error.set(None);
                        draft.set(next);
                        choosing.set(None);
                    }
                    Err(cause) => {
                        log::error!("capture: category selection could not be kept: {cause}");
                        error.set(Some(s().error_transaction_storage.into()));
                    }
                }
            })
            .px_0()
            .accessibility_label(Some(name.clone().into()))
            .child(
                text(name)
                    .typo(Type::Headline)
                    .text_color(color::INK)
                    .flex_1(),
            )
            .child(checked.then(|| icon(Icon::Check, 20.0, color::INK)))
        }))
        .into_element()
}
