//! Explicit local account selection updates only the draft, never the ledger.
use navi_finance::account::Account;
use nsh_core::prelude::*;

use crate::{
    data::{capture, finance},
    domain::capture::{Draft, Record, Status},
    i18n::s,
    ui::{Icon, Type, Typo, color, icon, surface::row_button},
};

#[derive(Clone, Copy, PartialEq)]
pub struct Choice {
    pub index: usize,
    pub destination: bool,
}

pub fn picker(
    draft: Signal<Draft>,
    input: Signal<String>,
    error: Signal<Option<String>>,
    choosing: Signal<Option<Choice>>,
    choice: Choice,
) -> impl IntoElement {
    let current = draft.get_untracked();
    let (selected, other) = match current.records.get(choice.index) {
        Some(Record::Money { draft: money, .. }) if choice.destination => {
            (money.other_account.clone(), money.account.clone())
        }
        Some(Record::Money { draft: money, .. }) => {
            (money.account.clone(), money.other_account.clone())
        }
        _ => (None, None),
    };
    let currency = match current.records.get(choice.index) {
        Some(Record::Money { draft: money, .. }) => {
            navi_finance::currency::Currency::parse(&money.currency)
        }
        _ => None,
    };
    let accounts: Vec<_> = finance::accounts()
        .into_iter()
        .filter(|a| a.is_cash() && Some(a.currency()) == currency && Some(a) != other.as_ref())
        .collect();
    view()
        .gap_2()
        .child(
            text(if choice.destination {
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
                let Some(Record::Money { draft: money, .. }) = next.records.get_mut(choice.index)
                else {
                    return;
                };
                let other = if choice.destination {
                    &money.account
                } else {
                    &money.other_account
                };
                // Recheck against current state when the user taps, not just
                // the list snapshot. A transfer cannot fund itself.
                if other.as_ref() == Some(&account)
                    || account.currency().code() != money.currency
                    || !finance::accounts().contains(&account)
                {
                    return;
                }
                let target: &mut Option<Account> = if choice.destination {
                    &mut money.other_account
                } else {
                    &mut money.account
                };
                *target = Some(account.clone());
                next.correction = input.get_untracked();
                if capture::ready(&next) {
                    next.question.clear();
                }
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
}
