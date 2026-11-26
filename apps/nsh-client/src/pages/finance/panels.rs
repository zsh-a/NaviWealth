//! The editor's secondary panels, each replacing the sheet body: account
//! and category choices, a new account, the calendar and details.

use navi_finance::{
    account::{Account, AccountKind, AccountPurpose},
    currency::Currency,
};
use nsh_base::{CalendarEntry, CalendarItemKind, calendar};
use nsh_core::prelude::*;

use super::{form::*, rows::*};
use crate::{
    data::{clock, finance},
    i18n::s,
    ui::{
        Btn, Icon, Type, Typo, Variant, color,
        field::{field, note, text_input},
        icon,
        surface::{hairline, row_button},
    },
};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum Panel {
    Main,
    Own,
    Other,
    Category,
    Date,
    Details,
    NewOwn,
    NewOther,
}

pub(super) fn choice(
    label: impl Fn() -> &'static str + Copy + 'static,
    value: impl Fn() -> String + 'static,
    press: impl Fn() + 'static,
) -> View {
    view()
        .child(
            row_button(press)
                .accessibility_label(move || Some(label().into()))
                .px_2()
                .py_2()
                .min_h(px(56.0))
                .child(
                    view()
                        .gap_1()
                        .flex_1()
                        .min_w(px(0.0))
                        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
                        .child(
                            text(value)
                                .typo(Type::Body)
                                .text_color(color::INK)
                                .number_of_lines(1),
                        ),
                )
                .child(icon(Icon::ChevronDown, 16.0, color::MUTED)),
        )
        .child(hairline(0.0))
}

fn account_fields(form: Form, destination: bool) -> (Own, Option<Account>) {
    if destination {
        (form.other, form.own.account())
    } else {
        (
            form.own,
            (form.kind.get() == Kind::Transfer)
                .then(|| form.other.account())
                .flatten(),
        )
    }
}

pub(super) fn accounts_panel(form: Form, panel: Signal<Panel>, other: bool) -> impl IntoElement {
    let (own, excluded) = account_fields(form, other);
    view()
        .gap_1()
        .children(
            crate::ui::account_purpose::daily_accounts()
                .into_iter()
                .filter(|a| a.is_cash() && Some(a) != excluded.as_ref())
                .map(move |a| {
                    let chosen = own.account().as_ref() == Some(&a);
                    account_option(a, chosen, move |a| {
                        own.selected.set(a.to_string());
                        own.creating.set(false);
                        panel.set(Panel::Main);
                    })
                }),
        )
        .child(
            (form.kind.get() == Kind::Transfer
                && own.account().zip(excluded).is_some_and(|(a, b)| {
                    a != b
                        && !finance::archived_accounts().contains(&a)
                        && !finance::archived_accounts().contains(&b)
                }))
            .then(|| {
                Btn::ghost()
                    .label(|| crate::i18n::catalog::copy("Swap accounts", "交换账户").into())
                    .on_press(move || {
                        form.swap_accounts();
                        panel.set(Panel::Main);
                    })
            }),
        )
        .child(
            Btn::ghost()
                .icon(Icon::Plus)
                .label(|| s().add_account.into())
                .on_press(move || {
                    panel.set(if other {
                        Panel::NewOther
                    } else {
                        Panel::NewOwn
                    })
                }),
        )
}

/// Opens the six purpose choices in the running account draft, preserving its other fields.
pub(crate) fn purpose_field(purpose: Signal<AccountPurpose>) -> impl IntoElement {
    let expanded = signal(false);
    let value = move || crate::ui::account_purpose::label(purpose.get());
    nsh_base::collapsible()
        .open(expanded)
        .child(
            row_button(move || {
                dismiss_keyboard();
                expanded.update(|open| *open = !*open);
            })
            .accessibility_label(move || Some(format!("{}, {}", s().account_type, value()).into()))
            .px_0()
            .min_h(px(48.0))
            .child(
                text(|| s().account_type)
                    .typo(Type::Body)
                    .text_color(color::INK)
                    .flex_1(),
            )
            .child(text(value).typo(Type::Body).text_color(color::INK))
            .child(crate::ui::surface::disclosure_chevron(expanded)),
        )
        .content(dynamic(move || {
            crate::ui::account_purpose::picker(Some(purpose.get()), None, move |p| {
                purpose.set(p);
                expanded.set(false);
            })
        }))
}

pub(super) fn new_account(form: Form, panel: Signal<Panel>, other: bool) -> impl IntoElement {
    let (own, excluded) = account_fields(form, other);
    let name = signal(own.name.get_untracked());
    let purpose = signal(own.purpose.get_untracked());
    let currency = signal(own.currency.get_untracked());
    let invalid = signal(false);
    view()
        .gap_4()
        .child(purpose_field(purpose))
        .child(field(
            || s().currency_label,
            crate::ui::currency::picker(currency),
        ))
        .child(
            text_input(name)
                .auto_focus(true)
                .label(|| s().account_name)
                .placeholder(|| s().account_name),
        )
        .child(note(
            move || invalid.get().then(|| s().error_account.into()),
            || true,
        ))
        .child(Btn::primary().label(|| s().done.into()).on_press(move || {
            let account = Account::new_in(purpose.get().kind(), &name.get(), currency.get())
                .ok()
                .filter(|a| {
                    a.is_cash()
                        && Some(a) != excluded.as_ref()
                        && !finance::archived_accounts().contains(a)
                });
            let Some(account) = account else {
                invalid.set(true);
                return;
            };
            if finance::accounts_snapshot().contains(&account) {
                own.selected.set(account.to_string());
                own.creating.set(false);
            } else {
                own.purpose.set(purpose.get());
                own.currency.set(currency.get());
                own.name.set(name.get());
                own.creating.set(true);
            }
            dismiss_keyboard();
            panel.set(Panel::Main);
        }))
}

pub(crate) fn date_picker(
    day: Signal<String>,
    selected: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    date_picker_through(day, None, selected)
}

pub(crate) fn date_picker_through(
    day: Signal<String>,
    latest: Option<crate::domain::meal::Day>,
    selected: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    let matcher = latest
        .and_then(|last| last.to_string().parse().ok())
        .map(|last| nsh_base::Matcher::interval(None, Some(last)));
    view()
        .gap_3()
        .child(
            view()
                .flex_row()
                .gap_2()
                .child(
                    Btn::tonal()
                        .label(|| s().today.into())
                        .disabled(move || latest.is_some_and(|last| clock::today() > last))
                        .on_press(move || {
                            day.set(clock::today().to_string());
                            selected();
                        })
                        .flex_1(),
                )
                .child(
                    Btn::tonal()
                        .label(|| s().yesterday.into())
                        .disabled(move || {
                            latest.is_some_and(|last| clock::today().plus_days(-1) > last)
                        })
                        .on_press(move || {
                            day.set(clock::today().plus_days(-1).to_string());
                            selected();
                        })
                        .flex_1(),
                ),
        )
        .child(
            calendar()
                .default_value(nsh_base::Date::Single(day.get().parse().ok()))
                .disabled_matcher(matcher)
                .first_day_of_week(
                    if s().week_start() == crate::domain::review::WeekStart::Monday {
                        1
                    } else {
                        0
                    },
                )
                .previous_accessibility_label(|| Some(s().previous_month.into()))
                .next_accessibility_label(|| Some(s().next_month.into()))
                .header_style(|s| s.gap_2().pb_3())
                .row_style(|s| s.gap_1())
                .month_style(|s| s.gap_1())
                .item_style(|s| {
                    s.min_h(px(40.0))
                        .rounded(px(8.0))
                        .text_color(color::INK)
                        .selected(|s| s.bg(color::SURFACE_2))
                })
                .render_item(|item: &CalendarEntry| match item.kind {
                    CalendarItemKind::Previous => {
                        icon(Icon::ChevronLeft, 18.0, color::INK).into_element()
                    }
                    CalendarItemKind::Next => {
                        icon(Icon::ChevronRight, 18.0, color::INK).into_element()
                    }
                    CalendarItemKind::Weekday => text(
                        s().weekday_short(
                            crate::domain::meal::Day(jiff::civil::date(2026, 11, 1))
                                .plus_days(item.value),
                        ),
                    )
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .into_element(),
                    CalendarItemKind::MonthToggle | CalendarItemKind::Month => {
                        text(if s().lang == crate::domain::recognition::Lang::Zh {
                            format!("{}月", item.month)
                        } else {
                            [
                                "January",
                                "February",
                                "March",
                                "April",
                                "May",
                                "June",
                                "July",
                                "August",
                                "September",
                                "October",
                                "November",
                                "December",
                            ][(item.month.clamp(1, 12) - 1) as usize]
                                .into()
                        })
                        .typo(Type::Subhead)
                        .into_element()
                    }
                    _ => text(item.value.to_string())
                        .typo(Type::Body)
                        .tabular_nums()
                        .into_element(),
                })
                .on_change(move |value: &nsh_base::Date| {
                    if let Some(date) = value.start() {
                        day.set(date.to_string());
                        selected();
                    }
                }),
        )
}

/// Expense or income categories in the own account's currency.
pub(super) fn category_panel(form: Form, panel: Signal<Panel>) -> View {
    view().gap_1().children(
        finance::accounts()
            .into_iter()
            .filter(|a| {
                a.kind()
                    == if form.kind.get() == Kind::Income {
                        AccountKind::Income
                    } else {
                        AccountKind::Expenses
                    }
            })
            .map(|a| a.in_currency(form.own.account().map_or(Currency::CNY, |a| a.currency())))
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .map(move |a| {
                let name = category_label(&a);
                let chosen = form.category.get() == a.as_str();
                row_button(move || {
                    form.category.set(a.to_string());
                    panel.set(Panel::Main);
                })
                .min_h(px(48.0))
                .py_2()
                .px_2()
                .child(text(name).typo(Type::Body).text_color(color::INK).flex_1())
                .child(chosen.then(|| icon(Icon::Check, 18.0, color::INK)))
            }),
    )
}

/// Payee, note and time; a saved entry also offers Delete here.
pub(super) fn details_panel(
    form: Form,
    saved: bool,
    asking: Signal<bool>,
    delete: impl Fn() + Copy + 'static,
) -> View {
    view()
        .gap_4()
        .child(field(
            || s().transaction_payee,
            text_input(form.payee).label(|| s().transaction_payee),
        ))
        .child(field(
            || s().transaction_note,
            text_input(form.memo).label(|| s().transaction_note),
        ))
        .child(field(
            || s().transaction_time,
            text_input(form.time)
                .label(|| s().transaction_time)
                .placeholder("18:30"),
        ))
        .child(saved.then(|| {
            Btn::new(Variant::Danger)
                .label(|| s().delete_transaction.into())
                .disabled(move || asking.get())
                .on_press(delete)
        }))
}
