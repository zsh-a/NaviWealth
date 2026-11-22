//! Compact spending review and the exact editable rows behind it.
use crate::{
    data::{clock, finance},
    domain::meal::Day,
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Type, Typo, chip, color,
        figures::counted,
        space,
        surface::{card, hairline, row_button},
    },
};
use navi_finance::{account::Account, currency::Currency, review};
use nsh_base::nav_page;
use nsh_core::{element::Screen, prelude::*};

/// The currencies the ledger holds, as chips beside the card's title.
fn currency_chips(selected: Signal<Currency>) -> impl IntoElement {
    view()
        .flex_row()
        .gap_2()
        .children(Currency::ALL.into_iter().map(move |c| {
            chip(
                move || c.code().into(),
                move || selected.get() == c,
                move || selected.set(c),
            )
        }))
}

pub fn spending_section(
    days: Memo<Vec<Day>>,
    before: Memo<Vec<Day>>,
    period: Signal<crate::domain::review::Period>,
) -> impl IntoElement {
    let more = signal(false);
    let selected = signal(Currency::CNY);
    // The card's figure lives above the rebuild boundary so an edited
    // ledger rolls the number instead of jumping it.
    let total = computed(move || {
        let d = days.get();
        let from = d[0];
        let to = Day(d[d.len() - 1].0.min(clock::today().0));
        review::spending_in(
            &finance::transactions_snapshot(),
            from.0,
            to.0,
            selected.get(),
        )
        .total
    });
    let shown = counted(move || total.get() as f64);
    when(
        || !finance::transactions_snapshot().is_empty(),
        move || {
            dynamic(move || {
                let d = days.get();
                let p = before.get();
                let from = d[0];
                let to = Day(d[d.len() - 1].0.min(clock::today().0));
                let full_end = match period.get() {
                    crate::domain::review::Period::Week => from.plus_days(6).0,
                    crate::domain::review::Period::Month => from.0.last_of_month(),
                };
                let previous_to = review::comparison_end(
                    from.0,
                    full_end,
                    p[0].0,
                    p[p.len() - 1].0,
                    clock::today().0,
                );
                let currency = selected.get();
                let entries = finance::transactions_snapshot();
                let current = review::spending_in(&entries, from.0, to.0, currency);
                let previous = review::spending_in(&entries, p[0].0, previous_to, currency);
                let expanded = more.get();
                // One caption: the delta sentence names the compared span
                // instead of a second line under it.
                let mut comparison = s().spending_comparison(
                    current.total,
                    (previous.records > 0).then_some(previous.total),
                    currency,
                );
                if previous.records > 0 {
                    comparison.push_str(&format!(
                        " · {} – {}",
                        s().short_date(p[0]),
                        s().short_date(Day(previous_to))
                    ));
                }
                untracked(move || {
                    card()
                        .p(px(space::CARD))
                        .gap_3()
                        .child(
                            view()
                                .flex_row()
                                .items_center()
                                .gap_2()
                                .child(
                                    text(s().recorded_spending())
                                        .typo(Type::Headline)
                                        .text_color(color::INK)
                                        .flex_1(),
                                )
                                .child(when(
                                    || {
                                        finance::accounts()
                                            .iter()
                                            .any(|a| a.currency() != Currency::CNY)
                                    },
                                    move || currency_chips(selected),
                                )),
                        )
                        .child(if current.records == 0 {
                            text(s().spending_empty())
                                .typo(Type::Subhead)
                                .text_color(color::MUTED)
                                .into_element()
                        } else {
                            view()
                                .gap_3()
                                .child(
                                    row_button(move || {
                                        nav::push(Route::Spending {
                                            from,
                                            to,
                                            category: None,
                                            currency,
                                        })
                                    })
                                    .min_h(px(48.0))
                                    .px(px(0.0))
                                    .py(px(4.0))
                                    .child(
                                        text(move || {
                                            crate::ui::currency::format(
                                                shown.get() as i64,
                                                currency,
                                            )
                                        })
                                        .typo(Type::LargeTitle)
                                        .tabular_nums()
                                        .text_color(color::INK),
                                    ),
                                )
                                .child(
                                    text(comparison)
                                        .typo(Type::Caption)
                                        .text_color(color::MUTED),
                                )
                                .children(
                                    current
                                        .categories
                                        .into_iter()
                                        .take(if expanded { usize::MAX } else { 3 })
                                        .map(move |(category, amount)| {
                                            let title = Account::parse(&category)
                                                .map(|a| super::finance::category_label(&a))
                                                .unwrap_or_else(|_| category.clone());
                                            let share = if current.total > 0 {
                                                (amount as f64 / current.total as f64)
                                                    .clamp(0.0, 1.0)
                                                    as f32
                                            } else {
                                                0.0
                                            };
                                            row_button(move || {
                                                nav::push(Route::Spending {
                                                    from,
                                                    to,
                                                    category: Some(category.clone()),
                                                    currency,
                                                })
                                            })
                                            .flex_col()
                                            .items_stretch()
                                            .min_h(px(48.0))
                                            .px(px(0.0))
                                            .py(px(8.0))
                                            .gap_2()
                                            .child(
                                                view()
                                                    .flex_row()
                                                    .items_baseline()
                                                    .gap_3()
                                                    .child(
                                                        text(title)
                                                            .typo(Type::Body)
                                                            .text_color(color::INK)
                                                            .flex_1()
                                                            .min_w(px(0.0)),
                                                    )
                                                    .child(
                                                        text(crate::ui::currency::format(
                                                            amount, currency,
                                                        ))
                                                        .typo(Type::Subhead)
                                                        .tabular_nums()
                                                        .text_color(color::BODY),
                                                    ),
                                            )
                                            .child(
                                                view()
                                                    .h(px(4.0))
                                                    .flex_row()
                                                    .rounded_full()
                                                    .overflow_hidden()
                                                    .bg(color::SUNKEN)
                                                    .accessibility_elements_hidden(true)
                                                    .child(
                                                        view()
                                                            .h_full()
                                                            .basis(px(0.0))
                                                            .flex_grow(share)
                                                            // Ink, not the macro ramp: money
                                                            // shares are data, not nutrition.
                                                            .bg(color::INK.opacity(0.5)),
                                                    )
                                                    .child(
                                                        view()
                                                            .h_full()
                                                            .basis(px(0.0))
                                                            .flex_grow(1.0 - share),
                                                    ),
                                            )
                                        }),
                                )
                                .child(
                                    (!expanded
                                        && review::spending_in(&entries, from.0, to.0, currency)
                                            .categories
                                            .len()
                                            > 3)
                                    .then(|| {
                                        Btn::ghost()
                                            .label(|| s().spending_more().into())
                                            .on_press(move || more.set(true))
                                    }),
                                )
                                .into_element()
                        })
                        .child(
                            text(|| s().spending_basis())
                                .typo(Type::Caption)
                                .text_color(color::MUTED),
                        )
                })
            })
        },
    )
}

pub fn spending_page(from: Day, to: Day, category: Option<String>, currency: Currency) -> Screen {
    let edit = signal(None::<String>);
    let shown = signal(50usize);
    let title = category
        .as_deref()
        .and_then(|c| Account::parse(c).ok())
        .map(|a| super::finance::category_label(&a))
        .unwrap_or_else(|| s().recorded_spending().into());
    nav_page()
        .title(title.clone())
        .header_visible(false)
        .status_bar(super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::parts::top_bar(
                    move || title.clone().into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pb_safe_area_plus(px(32.0))
                            .gap_3()
                            .child(
                                text(format!("{} – {}", s().short_date(from), s().short_date(to)))
                                    .typo(Type::Subhead)
                                    .text_color(color::MUTED),
                            )
                            .child(dynamic(move || {
                                let entries = review::transactions_in(
                                    &finance::transactions(),
                                    from.0,
                                    to.0,
                                    category.as_deref(),
                                    currency,
                                );
                                let more = entries.len() > shown.get();
                                let limit = shown.get();
                                untracked(move || {
                                    view()
                                        .gap_2()
                                        .child(entries.is_empty().then(|| {
                                            text(s().spending_empty())
                                                .typo(Type::Body)
                                                .text_color(color::MUTED)
                                        }))
                                        .children(entries.into_iter().take(limit).map(move |t| {
                                            let id = t.id.clone();
                                            view()
                                                .child(super::finance::transaction_row(
                                                    t,
                                                    super::rows::ICON_COLUMN,
                                                    move || edit.set(Some(id.clone())),
                                                ))
                                                .child(hairline(0.0))
                                        }))
                                        .child(more.then(|| {
                                            Btn::secondary()
                                                .label(|| s().show_earlier.into())
                                                .on_press(move || shown.update(|n| *n += 50))
                                        }))
                                })
                            })),
                    ),
                )
                .child(super::finance::finance_editor(edit)),
        )
}
