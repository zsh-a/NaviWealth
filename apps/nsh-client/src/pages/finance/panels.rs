//! The editor's secondary panels, each replacing the sheet body: account
//! and category choices, a new account, the calendar and details.

use navi_finance::{
    account::{Account, AccountKind},
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
        segmented::{Segment, segmented},
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

pub(super) fn accounts_panel(own: Own, panel: Signal<Panel>, other: bool) -> impl IntoElement {
    view()
        .gap_1()
        .children(
            finance::accounts()
                .into_iter()
                .filter(|a| a.is_cash())
                .map(move |a| {
                    let name = account_label(&a);
                    let chosen = own.account().as_ref() == Some(&a);
                    row_button(move || {
                        own.selected.set(a.to_string());
                        own.creating.set(false);
                        panel.set(Panel::Main);
                    })
                    .min_h(px(48.0))
                    .py_2()
                    .px_2()
                    .child(text(name).typo(Type::Body).text_color(color::INK).flex_1())
                    .child(chosen.then(|| icon(Icon::Check, 18.0, color::INK)))
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

pub(super) fn new_account(own: Own, panel: Signal<Panel>) -> impl IntoElement {
    let name = signal(own.name.get_untracked());
    let kind = signal(own.kind.get_untracked());
    let currency = signal(own.currency.get_untracked());
    let invalid = signal(false);
    view()
        .gap_4()
        .child(field(
            || s().account_type,
            segmented(
                vec![
                    Segment::new(AccountKind::Assets, || s().asset_account.into()),
                    Segment::new(AccountKind::Liabilities, || s().liability_account.into()),
                ],
                move || kind.get(),
                move |k| kind.set(k),
            ),
        ))
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
            if Account::new_in(kind.get(), &name.get(), currency.get()).is_err() {
                invalid.set(true);
                return;
            }
            own.kind.set(kind.get());
            own.currency.set(currency.get());
            own.name.set(name.get());
            own.creating.set(true);
            dismiss_keyboard();
            panel.set(Panel::Main);
        }))
}

pub(crate) fn date_picker(
    day: Signal<String>,
    selected: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    view()
        .gap_3()
        .child(
            view()
                .flex_row()
                .gap_2()
                .child(
                    Btn::tonal()
                        .label(|| s().today.into())
                        .on_press(move || {
                            day.set(clock::today().to_string());
                            selected();
                        })
                        .flex_1(),
                )
                .child(
                    Btn::tonal()
                        .label(|| s().yesterday.into())
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
