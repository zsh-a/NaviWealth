//! The manual entry sheet: one compact editor for a new or saved expense,
//! income or transfer, with in-sheet panels and a guarded dismissal.
//! Investment entries open their trade receipt and balance entries their
//! summary instead.

use std::sync::atomic::{AtomicU64, Ordering};

use jiff::civil::Time;
use navi_finance::{
    account::{Account, AccountKind, defaults},
    journal::Source,
    money,
};
use nsh_core::prelude::*;

use super::{delete::*, form::*, main_panel::*, panels::*};
use crate::{
    data::{clock, finance, settings},
    i18n::s,
    ui::{
        Btn, Size, Type, Typo, color,
        field::note,
        sheet::{initial_focus, retained, task_sheet},
    },
};

/// Owns its sheet, including dirty dismissal. `Some("")` starts a new entry.
pub fn finance_editor(open: Signal<Option<String>>) -> impl IntoElement {
    retained(
        move || open.get(),
        move |id| editor(id, open).into_element(),
    )
}

static NEXT: AtomicU64 = AtomicU64::new(0);

fn editor(id: String, open: Signal<Option<String>>) -> impl IntoElement {
    let existing = finance::transactions().into_iter().find(|t| t.id == id);
    if let Some(Source::Investment { trade_id }) = existing.as_ref().map(|t| &t.source) {
        return crate::pages::holdings::trade_receipt(trade_id, move || open.set(None));
    }
    if let Some(entry) = existing
        .as_ref()
        .filter(|t| crate::pages::assets::balance_title(t).is_some())
    {
        return crate::pages::assets::balance_entry(entry.clone(), open);
    }
    let parsed = existing.as_ref().and_then(parts);
    let editable = id.is_empty() || parsed.is_some();
    let preferences = settings::current().ledger;
    let accounts = finance::accounts();
    let valid = |value: &Option<String>| {
        value
            .as_ref()
            .and_then(|v| Account::parse(v).ok())
            .filter(|a| accounts.contains(a))
    };
    let own_accounts: Vec<_> = accounts.iter().filter(|a| a.is_cash()).cloned().collect();
    let first_own = valid(&preferences.own)
        .filter(|a| a.is_cash())
        .or_else(|| (own_accounts.len() == 1).then(|| own_accounts[0].clone()));
    let now = clock::zoned(clock::now_ms()).datetime();
    let at = existing.as_ref().map_or(now, |t| t.at);
    let kind = parsed.as_ref().map_or(Kind::Expense, |p| p.0);
    let form = Form {
        kind: signal(kind),
        received: signal(
            existing
                .as_ref()
                .and_then(|t| t.own_postings().find(|p| p.amount > 0))
                .map(|p| money::format(p.amount))
                .unwrap_or_default(),
        ),
        amount: signal(
            parsed
                .as_ref()
                .map(|p| money::format(p.3))
                .unwrap_or_default(),
        ),
        day: signal(at.date().to_string()),
        time: signal(if existing.is_some() {
            at.time().to_string()
        } else {
            format!("{:02}:{:02}", at.hour(), at.minute())
        }),
        own: Own::new(parsed.as_ref().map(|p| p.1.clone()).or(first_own)),
        other: Own::new(
            parsed
                .as_ref()
                .filter(|p| p.0 == Kind::Transfer)
                .map(|p| p.2.clone())
                .or_else(|| valid(&preferences.other).filter(|a| a.is_cash())),
        ),
        category: signal(
            parsed
                .as_ref()
                .filter(|p| p.0 != Kind::Transfer)
                .map(|p| p.2.to_string())
                .unwrap_or_else(|| {
                    valid(&preferences.expense)
                        .filter(|a| a.kind() == AccountKind::Expenses)
                        .unwrap_or_else(defaults::other_expense)
                        .to_string()
                }),
        ),
        payee: signal(
            existing
                .as_ref()
                .map(|t| t.payee.clone())
                .unwrap_or_default(),
        ),
        memo: signal(
            existing
                .as_ref()
                .map(|t| t.note.clone())
                .unwrap_or_default(),
        ),
    };
    let last_expense = signal(if kind == Kind::Expense {
        form.category.get_untracked()
    } else {
        preferences
            .expense
            .clone()
            .unwrap_or_else(|| defaults::other_expense().to_string())
    });
    let last_income = signal(if kind == Kind::Income {
        form.category.get_untracked()
    } else {
        preferences
            .income
            .clone()
            .unwrap_or_else(|| defaults::other_income().to_string())
    });
    let panel = signal(Panel::Main);
    let autofocus = stored(id.is_empty());
    let initial = stored(form.values());
    let error = signal(None::<String>);
    let asking = signal(false);
    let close = move || {
        if asking.get_untracked() {
            return;
        }
        if panel.get_untracked() != Panel::Main {
            panel.set(match panel.get_untracked() {
                Panel::NewOwn => Panel::Own,
                Panel::NewOther => Panel::Other,
                _ => Panel::Main,
            });
            dismiss_keyboard();
            return;
        }
        if untracked(|| initial.with(|v| *v == form.values())) {
            open.set(None);
            return;
        }
        crate::ui::feedback::confirm_discard(asking, move || open.set(None));
    };
    let kept = stored(existing.clone());
    let delete = move || {
        if let Some(entry) = kept.with(|t| t.clone()) {
            confirm_delete(entry, open, error, asking);
        }
    };
    let save = move || {
        if !editable {
            return;
        }
        let id = kept
            .with(|t| t.as_ref().map(|t| t.id.clone()))
            .unwrap_or_else(|| {
                format!(
                    "manual:{}:{}",
                    clock::now_ms(),
                    NEXT.fetch_add(1, Ordering::Relaxed)
                )
            });
        let source = kept
            .with(|t| t.as_ref().map(|t| t.source.clone()))
            .unwrap_or(Source::Manual);
        match untracked(|| form.build(id, source)) {
            Err(message) => error.set(Some(message.to_owned())),
            Ok(t) => match finance::save(t) {
                Ok(()) => {
                    let mut defaults = settings::current().ledger;
                    defaults.own = form.own.account().map(|a| a.to_string());
                    match form.kind.get() {
                        Kind::Expense => defaults.expense = Some(form.category.get()),
                        Kind::Income => defaults.income = Some(form.category.get()),
                        Kind::Transfer => {
                            defaults.other = form.other.account().map(|a| a.to_string())
                        }
                    }
                    settings::save_ledger_defaults(defaults);
                    dismiss_keyboard();
                    open.set(None);
                }
                Err(cause) => {
                    log::error!("finance: save failed: {cause}");
                    error.set(Some(s().error_transaction_storage.to_owned()));
                }
            },
        }
    };
    let header = view()
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            text(move || match panel.get() {
                Panel::Main => {
                    if kept.with(|t| t.is_some()) {
                        s().edit_transaction
                    } else {
                        s().log_transaction
                    }
                }
                Panel::Own => s().own_account,
                Panel::Other => s().to_account,
                Panel::Category => s().category,
                Panel::Date => s().transaction_date,
                Panel::Details => s().transaction_details,
                Panel::NewOwn | Panel::NewOther => s().add_account,
            })
            .typo(Type::Title)
            .text_color(color::INK)
            .flex_1()
            .min_w(px(0.0))
            .role(AccessibilityRole::Header),
        )
        .child(when(
            move || panel.get() == Panel::Main && kept.with(|t| t.is_some()),
            move || {
                Btn::ghost()
                    .size(Size::Small)
                    .label(|| s().delete_transaction_action.into())
                    .disabled(move || asking.get())
                    .on_press(delete)
                    .accessibility_label(|| Some(s().delete_transaction.into()))
                    .min_h(px(48.0))
            },
        ))
        .child(
            Btn::ghost()
                .size(Size::Small)
                .label(move || {
                    if panel.get() == Panel::Main {
                        s().cancel
                    } else {
                        s().back
                    }
                    .into()
                })
                .disabled(move || asking.get())
                .on_press(close),
        );
    let body = dynamic(move || {
        let selected = panel.get();
        untracked(move || match selected {
            Panel::Main => {
                let focus = if autofocus.replace(false) {
                    initial_focus()
                } else {
                    element_ref()
                };
                main_panel(form, panel, (last_expense, last_income), focus, editable).into_element()
            }
            Panel::Own | Panel::Other => accounts_panel(
                if selected == Panel::Own {
                    form.own
                } else {
                    form.other
                },
                panel,
                selected == Panel::Other,
            )
            .into_element(),
            Panel::NewOwn | Panel::NewOther => new_account(
                if selected == Panel::NewOwn {
                    form.own
                } else {
                    form.other
                },
                panel,
            )
            .into_element(),
            Panel::Category => category_panel(form, panel).into_element(),
            Panel::Date => date_picker(form.day, move || panel.set(Panel::Main)).into_element(),
            Panel::Details => {
                details_panel(form, kept.with(|t| t.is_some()), asking, delete).into_element()
            }
        })
    });
    let actions = view()
        .gap_2()
        .child(note(move || error.get().map(Into::into), || true))
        .child(
            when(
                move || panel.get() == Panel::Main,
                move || {
                    Btn::primary()
                        .label(|| s().save_transaction.into())
                        .disabled(move || !editable || asking.get())
                        .on_press(save)
                },
            )
            .otherwise(move || {
                Btn::secondary()
                    .label(|| s().done.into())
                    .on_press(move || {
                        if panel.get() == Panel::Details && form.time.get().parse::<Time>().is_err()
                        {
                            error.set(Some(s().error_time.into()));
                            return;
                        }
                        error.set(None);
                        dismiss_keyboard();
                        panel.set(Panel::Main);
                    })
                    .style_when(
                        move || matches!(panel.get(), Panel::NewOwn | Panel::NewOther),
                        |s| s.hidden(),
                    )
            }),
        );
    task_sheet(move || open.get().is_some(), close, header, body, actions).into_element()
}
