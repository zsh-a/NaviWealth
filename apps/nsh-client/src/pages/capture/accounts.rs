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
    let Some(record) = current.records.get(index) else {
        return view().into_element();
    };
    let (field, selected) = match record {
        Record::Money { draft, .. } if destination => {
            ("other_account", draft.other_account.as_ref())
        }
        Record::Money { draft, .. } => ("account", draft.account.as_ref()),
        Record::Trade { cash, .. } if !destination => ("cash", cash.as_ref()),
        Record::Balance { account, .. } if !destination => ("account", Some(account)),
        _ => return view().into_element(),
    };
    let active = match record {
        Record::Trade { currency, .. } => {
            crate::ui::account_purpose::settlement_accounts(*currency)
        }
        Record::Money { draft, .. } if draft.kind == Kind::Expense => {
            crate::ui::account_purpose::daily_accounts()
        }
        _ => finance::active_accounts(),
    };
    let selected = selected
        .filter(|_| !current.account_needs_approval(index, field, &active))
        .cloned();
    let swap = can_swap(record);
    let save = move |mut next: Draft| {
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
    };
    let accounts: Vec<_> = active
        .into_iter()
        .filter(|a| capture::accepts_account(record, destination, a))
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
            let checked = selected.as_ref() == Some(&account);
            crate::pages::finance::account_option(account, checked, move |account| {
                let mut next = draft.get_untracked();
                if next.status != Status::Ready || !finance::active_accounts().contains(account) {
                    return;
                }
                let Some(record) = next.records.get_mut(index) else {
                    return;
                };
                if !capture::accepts_account(record, destination, account) {
                    return;
                }
                match record {
                    Record::Money { draft, .. } if destination => {
                        draft.other_account = Some(account.clone())
                    }
                    Record::Money { draft, .. } => draft.account = Some(account.clone()),
                    Record::Trade { cash, .. } => *cash = Some(account.clone()),
                    Record::Balance {
                        account: target, ..
                    } => *target = account.clone(),
                    _ => return,
                }
                next.mark_owner_field(index, field);
                save(next);
            })
        }))
        .child(swap.then(|| {
            crate::ui::Btn::ghost()
                .label(|| crate::i18n::catalog::copy("Swap accounts", "交换账户").into())
                .on_press(move || {
                    let mut next = draft.get_untracked();
                    if next.status != Status::Ready
                        || !next.records.get(index).is_some_and(can_swap)
                    {
                        return;
                    }
                    next.swap_transfer_accounts(index);
                    save(next);
                })
        }))
        .into_element()
}

fn can_swap(record: &Record) -> bool {
    let Record::Money { draft, .. } = record else {
        return false;
    };
    draft.kind == Kind::Transfer
        && draft
            .account
            .as_ref()
            .zip(draft.other_account.as_ref())
            .is_some_and(|(from, to)| {
                capture::accepts_account(record, false, from)
                    && capture::accepts_account(record, true, to)
            })
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
