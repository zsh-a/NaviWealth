//! The manual entry editor's main panel.

use navi_finance::{account::Account, currency::Currency};
use nsh_core::prelude::*;

use super::{form::*, panels::*, rows::*};
use crate::{
    data::clock,
    i18n::s,
    ui::{
        Type, Typo, color,
        field::{field, text_input},
        segmented::{Segment, segmented},
    },
};

/// The main body: kind, amount, account and category (or transfer accounts),
/// the received amount of an exchange, date and details.
pub(super) fn main_panel(
    form: Form,
    panel: Signal<Panel>,
    last: (Signal<String>, Signal<String>),
    focus: nsh_core::element::ElementRef,
    editable: bool,
) -> View {
    let (last_expense, last_income) = last;
    view()
        .gap_3()
        .child(segmented(
            vec![
                Segment::new(Kind::Expense, || s().spending.into()),
                Segment::new(Kind::Income, || s().income.into()),
                Segment::new(Kind::Transfer, || s().transfer.into()),
            ],
            move || form.kind.get(),
            move |kind| {
                match form.kind.get_untracked() {
                    Kind::Expense => last_expense.set(form.category.get_untracked()),
                    Kind::Income => last_income.set(form.category.get_untracked()),
                    _ => {}
                }
                form.kind.set(kind);
                if kind != Kind::Transfer {
                    form.category.set(if kind == Kind::Expense {
                        last_expense.get_untracked()
                    } else {
                        last_income.get_untracked()
                    });
                }
            },
        ))
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    text(move || {
                        form.own
                            .account()
                            .map_or(Currency::CNY, |a| a.currency())
                            .code()
                    })
                    .typo(Type::Title)
                    .text_color(color::MUTED),
                )
                .child(
                    text_input(form.amount)
                        .label(|| s().money_amount)
                        .placeholder("0.00")
                        .element_ref(&focus)
                        .keyboard_type(nsh_core::element::KeyboardType::Decimal)
                        .typo(Type::Lead)
                        .tabular_nums()
                        .h(px(68.0))
                        .flex_1()
                        .min_w(px(0.0)),
                ),
        )
        .child(
            view()
                .flex_row()
                .gap_3()
                .child(
                    choice(
                        move || {
                            if form.kind.get() == Kind::Transfer {
                                s().from_account
                            } else {
                                s().own_account
                            }
                        },
                        move || {
                            form.own
                                .account()
                                .map(|a| crate::ui::currency::account_label(&a))
                                .unwrap_or_else(|| s().choose_account.into())
                        },
                        move || {
                            dismiss_keyboard();
                            panel.set(Panel::Own);
                        },
                    )
                    .flex_1()
                    .min_w(px(0.0)),
                )
                .child(
                    choice(
                        move || {
                            if form.kind.get() == Kind::Transfer {
                                s().to_account
                            } else {
                                s().category
                            }
                        },
                        move || {
                            if form.kind.get() == Kind::Transfer {
                                form.other
                                    .account()
                                    .map(|a| crate::ui::currency::account_label(&a))
                                    .unwrap_or_else(|| s().choose_account.into())
                            } else {
                                Account::parse(&form.category.get())
                                    .map(|a| category_label(&a))
                                    .unwrap_or_default()
                            }
                        },
                        move || {
                            dismiss_keyboard();
                            panel.set(if form.kind.get() == Kind::Transfer {
                                Panel::Other
                            } else {
                                Panel::Category
                            });
                        },
                    )
                    .flex_1()
                    .min_w(px(0.0)),
                ),
        )
        .child(when(
            move || {
                form.kind.get() == Kind::Transfer
                    && form
                        .own
                        .account()
                        .zip(form.other.account())
                        .is_some_and(|(a, b)| a.currency() != b.currency())
            },
            move || {
                field(
                    || crate::i18n::statement_import::copy("Amount received", "实际到账金额"),
                    text_input(form.received)
                        .label(|| {
                            crate::i18n::statement_import::copy("Amount received", "实际到账金额")
                        })
                        .keyboard_type(nsh_core::element::KeyboardType::Decimal),
                )
            },
        ))
        .child(choice(
            || s().transaction_date,
            move || {
                form.day
                    .get()
                    .parse()
                    .ok()
                    .map(|d| s().day_title(crate::domain::meal::Day(d), clock::today()))
                    .unwrap_or_default()
            },
            move || {
                dismiss_keyboard();
                panel.set(Panel::Date);
            },
        ))
        .child(choice(
            || s().transaction_details,
            move || {
                let values = [form.payee.get(), form.memo.get()];
                let text = values
                    .iter()
                    .filter(|v| !v.is_empty())
                    .cloned()
                    .collect::<Vec<_>>()
                    .join(" · ");
                if text.is_empty() {
                    s().add_details.into()
                } else {
                    text
                }
            },
            move || {
                dismiss_keyboard();
                panel.set(Panel::Details);
            },
        ))
        .child((!editable).then(|| {
            text(|| s().error_transaction)
                .typo(Type::Subhead)
                .text_color(color::DANGER)
        }))
}
