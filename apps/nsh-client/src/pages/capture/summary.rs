//! Readable record previews. No inputs until the owner chooses a correction.
use crate::{
    data::{finance, weights},
    domain::{
        capture::{Draft, Record, Status},
        format,
    },
    i18n::s,
    ui::{Icon, Type, Typo, color, icon, surface::hairline},
};
use navi_finance::{
    account::Account,
    journal::{Entry, Source},
    recognition::{Kind, Missing},
};
use nsh_core::prelude::*;

pub fn common_day(draft: &Draft) -> Option<crate::domain::meal::Day> {
    let day_of = |r: &Record| match r {
        Record::Money { day, .. } | Record::Meal { day, .. } | Record::Weight { day, .. } => *day,
    };
    let first = draft.records.first().map(day_of)?;
    draft
        .records
        .iter()
        .all(|r| day_of(r) == first)
        .then_some(first)
}

pub fn saved_message(draft: &Draft) -> String {
    let [record] = draft.records.as_slice() else {
        return s().capture_saved_count(draft.records.len());
    };
    let (label, value) = match record {
        Record::Money { draft, .. } => (
            match draft.kind {
                Kind::Expense => s().spending,
                Kind::Income => s().income,
                Kind::Transfer => s().transfer,
            },
            amount_text(&draft.currency, draft.amount.as_deref().unwrap_or("—")),
        ),
        Record::Meal { estimate, .. } => (
            s().meals,
            format!(
                "{} {}",
                format::kcal(crate::domain::nutrition::total(&estimate.foods).kcal),
                s().kcal
            ),
        ),
        Record::Weight { kg, .. } => (s().weight, format!("{kg:.1} kg")),
    };
    s().capture_saved_detail(label, &value)
}

pub fn records(draft: &Draft, choosing: Signal<Option<super::accounts::Choice>>) -> AnyElement {
    view()
        .gap_4()
        .children(draft.records.iter().enumerate().map(|(index, record)| {
            record_view(record, index, choosing, draft.status == Status::Ready)
        }))
        .into_element()
}

fn line(label: impl IntoReactive<SharedString>, value: String, missing: bool) -> View {
    view()
        .flex_row()
        .gap_3()
        .items_start()
        .child(text(label).typo(Type::Subhead).text_color(color::MUTED))
        .child(
            text(value)
                .typo(Type::Body)
                .text_color(if missing { color::CAUTION } else { color::INK })
                .flex_1()
                .text_right(),
        )
}

fn account(account: &Option<Account>) -> String {
    match account {
        None => s().capture_unspecified.to_owned(),
        Some(a) if finance::accounts().contains(a) => a.name().to_owned(),
        Some(a) => format!("{} · {}", a.name(), s().capture_new_account),
    }
}

fn account_line(
    label: &'static str,
    value: &Option<Account>,
    index: usize,
    destination: bool,
    choosing: Signal<Option<super::accounts::Choice>>,
    editable: bool,
) -> AnyElement {
    if !editable {
        return line(label, account(value), value.is_none()).into_element();
    }
    let value = value
        .as_ref()
        .map(|_| account(value))
        .unwrap_or_else(|| s().capture_choose_account.into());
    nsh_base::button()
        .on_press(move || {
            dismiss_keyboard();
            choosing.set(Some(super::accounts::Choice { index, destination }));
        })
        .accessibility_label(Some(format!("{label}, {value}").into()))
        .flex_row()
        .gap_2()
        .items_center()
        .min_h(px(48.0))
        .rounded(px(8.0))
        .active(|s| s.bg(color::SUNKEN))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
        .child(text(label).typo(Type::Subhead).text_color(color::MUTED))
        .child(
            text(value)
                .typo(Type::Body)
                .text_color(color::INK)
                .flex_1()
                .text_right(),
        )
        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
        .into_element()
}

fn record_view(
    record: &Record,
    index: usize,
    choosing: Signal<Option<super::accounts::Choice>>,
    editable: bool,
) -> AnyElement {
    match record {
        Record::Money { day, draft } => {
            let title = match draft.kind {
                Kind::Expense => s().spending,
                Kind::Income => s().income,
                Kind::Transfer => s().transfer,
            };
            let missing = draft
                .transaction(
                    Entry {
                        id: "preview".into(),
                        at: day.0.at(12, 0, 0, 0),
                        payee: String::new(),
                        note: String::new(),
                        source: Source::Manual,
                    },
                    day.0,
                )
                .err();
            view()
                .gap_3()
                .child(
                    view()
                        .flex_row()
                        .items_baseline()
                        .gap_3()
                        .child(
                            text(title)
                                .typo(Type::Headline)
                                .text_color(color::INK)
                                .flex_1(),
                        )
                        .child(
                            text(
                                draft
                                    .amount
                                    .as_ref()
                                    .map(|a| amount_text(&draft.currency, a))
                                    .unwrap_or_else(|| "—".into()),
                            )
                            .typo(Type::LargeTitle)
                            .tabular_nums()
                            .text_color(color::INK),
                        ),
                )
                .child(line(|| s().transaction_date, s().long_date(*day), false))
                .child(account_line(
                    if draft.kind == Kind::Transfer {
                        s().from_account
                    } else {
                        s().own_account
                    },
                    &draft.account,
                    index,
                    false,
                    choosing,
                    editable,
                ))
                .child(if draft.kind == Kind::Transfer {
                    account_line(
                        s().to_account,
                        &draft.other_account,
                        index,
                        true,
                        choosing,
                        editable,
                    )
                    .into_element()
                } else {
                    line(
                        s().category,
                        draft
                            .category
                            .as_ref()
                            .map(super::super::finance::category_label)
                            .unwrap_or_else(|| s().category.into()),
                        draft.category.is_none(),
                    )
                    .into_element()
                })
                .child(
                    (!draft.payee.is_empty())
                        .then(|| line(s().capture_payee, draft.payee.clone(), false)),
                )
                .child((!draft.note.is_empty()).then(|| {
                    text(draft.note.clone())
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                }))
                .child(missing.map(|missing| {
                    text(match missing {
                        Missing::Invalid => s().error_transaction,
                        Missing::Amount => s().capture_need_amount,
                        Missing::Account => s().capture_need_account,
                        Missing::Category => s().capture_need_category,
                        Missing::OtherAccount => s().capture_need_destination,
                    })
                    .typo(Type::Body)
                    .text_color(color::CAUTION)
                }))
                .child(hairline(0.0))
                .into_element()
        }
        Record::Meal {
            day,
            slot,
            estimate,
        } => {
            let total = crate::domain::nutrition::total(&estimate.foods);
            view()
                .gap_3()
                .child(
                    text(estimate.title.clone().unwrap_or_else(|| s().meals.into()))
                        .typo(Type::Title)
                        .text_color(color::INK),
                )
                .child(
                    text(format!(
                        "{} · {}",
                        s().long_date(*day),
                        super::super::today::slot_name(s(), *slot)
                    ))
                    .typo(Type::Subhead)
                    .text_color(color::MUTED),
                )
                .child(
                    text(format!("{} {}", format::kcal(total.kcal), s().kcal))
                        .typo(Type::LargeTitle)
                        .tabular_nums()
                        .text_color(color::INK),
                )
                .children(estimate.foods.iter().map(|food| {
                    line(
                        food.name.clone(),
                        format!(
                            "{} g · {} {}",
                            format::grams(food.grams),
                            format::kcal(food.amount().kcal),
                            s().kcal
                        ),
                        false,
                    )
                }))
                .child(
                    text(|| s().estimate_hint)
                        .typo(Type::Subhead)
                        .text_color(color::CAUTION),
                )
                .child(hairline(0.0))
                .into_element()
        }
        Record::Weight { day, kg } => view()
            .gap_3()
            .child(
                text(|| s().weight)
                    .typo(Type::Headline)
                    .text_color(color::INK),
            )
            .child(
                text(format!("{kg:.1} kg"))
                    .typo(Type::LargeTitle)
                    .tabular_nums()
                    .text_color(color::INK),
            )
            .child(
                text(s().long_date(*day))
                    .typo(Type::Subhead)
                    .text_color(color::MUTED),
            )
            .child(weights::on(*day).map(|_| {
                text(|| s().capture_weight_replace)
                    .typo(Type::Subhead)
                    .text_color(color::CAUTION)
            }))
            .child(hairline(0.0))
            .into_element(),
    }
}

fn amount_text(currency: &str, amount: &str) -> String {
    if currency == "CNY" {
        format!("¥{amount}")
    } else {
        format!("{currency} {amount}")
    }
}
