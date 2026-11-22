//! Local shortcuts fill the composer. The owner can edit or send the text.
use super::*;
use crate::{
    data::{finance, meals, weights},
    domain::meal::Day,
    i18n::catalog::copy,
    ui::currency,
};
use navi_finance::account::AccountKind;

struct Recent {
    day: Day,
    icon: Icon,
    text: String,
}

fn recent() -> Vec<Recent> {
    let mut rows = Vec::new();
    let book = finance::transactions_snapshot();
    if let Some((t, category, own)) = book
        .iter()
        .filter_map(|t| {
            let category = t
                .postings
                .iter()
                .find(|p| p.account.kind() == AccountKind::Expenses && p.amount > 0)?;
            // Split, refund and cross-currency entries cannot be repeated as a
            // single expense from this label without losing accounting details.
            let own = t.own_postings().next()?;
            (t.postings.len() == 2
                && own.account.is_cash()
                && own.account.currency() == category.account.currency())
            .then_some((t, category, own))
        })
        .max_by_key(|(t, _, _)| t.at)
    {
        rows.push(Recent {
            day: Day(t.at.date()),
            icon: Icon::Wallet,
            text: format!(
                "{} · {} · {} · {}",
                s().spending,
                if t.payee.is_empty() {
                    category.account.name()
                } else {
                    &t.payee
                },
                currency::format(category.amount, category.account.currency()),
                own.account.name()
            ),
        });
    }
    if let Some(meal) = meals::all()
        .into_iter()
        .max_by_key(|meal| (meal.day, meal.logged_at_ms))
    {
        rows.push(Recent {
            day: meal.day,
            icon: Icon::Utensils,
            text: format!(
                "{} · {}",
                crate::pages::today::slot_name(s(), meal.slot),
                crate::pages::today::meal_title(&meal)
            ),
        });
    }
    if let Some(weight) = weights::latest_until(clock::today()) {
        rows.push(Recent {
            day: weight.day,
            icon: Icon::Scale,
            text: format!("{} · {:.1} kg", s().weight, weight.kg),
        });
    }
    rows.sort_by_key(|r| std::cmp::Reverse(r.day));
    rows
}

pub(super) fn list(input: Signal<String>) -> AnyElement {
    let recent = recent();
    if recent.is_empty() {
        return view().into_element();
    }
    let rows = stored(recent);
    when(
        move || input.with(|text| text.trim().is_empty()),
        move || {
            view()
                .gap_1()
                .child(
                    text(copy("Recently recorded", "最近记过"))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                )
                .children(rows.with(|items| {
                    items
                        .iter()
                        .map(|r| {
                            let sentence = r.text.clone();
                            nsh_base::button()
                                .flex_row()
                                .gap_2()
                                .items_center()
                                .min_h(px(44.0))
                                .accessibility_label(Some(
                                    format!("{} · {}", copy("Use again", "再次使用"), sentence)
                                        .into(),
                                ))
                                .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
                                .active(|s| s.bg(color::SUNKEN))
                                .child(icon(r.icon, 18.0, color::MUTED))
                                .child(
                                    text(sentence.clone())
                                        .typo(Type::Body)
                                        .text_color(color::BODY)
                                        .number_of_lines(2)
                                        .flex_1(),
                                )
                                .child(
                                    text(s().long_date(r.day))
                                        .typo(Type::Caption)
                                        .text_color(color::MUTED),
                                )
                                .on_press(move || input.set(sentence.clone()))
                                .into_element()
                        })
                        .collect::<Vec<_>>()
                }))
        },
    )
    .into_element()
}
