//! Deleting a saved entry: a confirmation naming the record, then Undo that
//! restores it atomically or explains why it cannot.

use std::rc::Rc;

use navi_finance::{journal::Transaction, repository::RemovedTransaction};
use nsh_base::alert_dialog;
use nsh_core::prelude::*;

use super::rows::*;
use crate::{
    data::{clock, finance},
    i18n::s,
    ui::toast::show_toast,
};

pub(crate) fn confirm_delete(
    entry: Transaction,
    open: Signal<Option<String>>,
    error: Signal<Option<String>>,
    asking: Signal<bool>,
) {
    if asking.get_untracked() {
        return;
    }
    asking.set(true);
    error.set(None);
    dismiss_keyboard();
    let balance = crate::pages::assets::balance_title(&entry).is_some();
    let accounts = entry
        .own_postings()
        .map(|p| {
            format!(
                "{} · {}",
                crate::ui::currency::account_label(&p.account),
                crate::ui::currency::format(p.amount, p.account.currency()),
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    let summary = format!(
        "{}\n{} · {}\n{}\n\n{}",
        transaction_title(&entry),
        s().long_date(crate::domain::meal::Day(entry.at.date())),
        clock::clock_time(entry.at.hour() as u8, entry.at.minute() as u8),
        accounts,
        if balance {
            s().revoke_balance_body
        } else {
            s().delete_transaction_body
        },
    );
    let answer = alert_dialog()
        .title(if balance {
            s().revoke_balance_title
        } else {
            s().delete_transaction_title
        })
        .description(summary)
        .cancel("keep", s().cancel)
        .destructive(
            "delete",
            if balance {
                s().revoke_balance
            } else {
                s().delete_transaction
            },
        )
        .show();
    spawn(async move {
        let confirmed = answer
            .await
            .is_ok_and(|a| a.action.as_deref() == Some("delete"));
        asking.set(false);
        if !confirmed || open.get_untracked().as_deref() != Some(entry.id.as_str()) {
            return;
        }
        match finance::remove(&entry) {
            Ok(removed) => {
                open.set(None);
                offer_undo(removed, false);
            }
            Err(cause) => error.set(Some(
                match cause {
                    finance::RemovalError::Missing => s().error_transaction_missing,
                    finance::RemovalError::Changed => s().error_transaction_changed,
                    finance::RemovalError::Unavailable => s().error_transaction_delete,
                }
                .into(),
            )),
        }
    });
}

fn offer_undo(removed: RemovedTransaction, retry: bool) {
    let message = if retry {
        s().error_transaction_restore
    } else if crate::pages::assets::balance_title(&removed.entry).is_some() {
        s().balance_entry_removed
    } else {
        s().transaction_deleted
    };
    show_toast(
        message,
        Some((
            if retry { s().try_again } else { s().undo }.into(),
            Rc::new(move || match finance::restore_removed(&removed) {
                Ok(()) => {}
                Err(finance::RemovalError::Unavailable) => offer_undo(removed.clone(), true),
                Err(finance::RemovalError::Missing | finance::RemovalError::Changed) => {
                    show_toast(s().error_transaction_undo_changed, None);
                }
            }),
        )),
    );
}
