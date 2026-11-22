//! The day at a glance, flat on the canvas: the energy so far as a large
//! light figure counting up,
//! what is left of the goal, a compact goal progress ring, the macros in
//! grams and, once the ledger is in use, the day's spending.

use nsh_core::prelude::*;

use crate::{
    data::{finance, meals, settings},
    domain::{format, meal::Day, nutrition::Nutrients},
    i18n::s,
    ui::{
        Type, Typo, color,
        figures::{Scale, counted, stat},
        ring::goal_ring,
        surface::hairline,
    },
};

const RING: f32 = 84.0;
const STROKE: f32 = 9.0;

/// The glance of `day`: intake is the one headline number; the day's
/// spending sits beneath it once the ledger has any entry.
pub fn hero(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let summary = computed(move || meals::summary(day()));
    let goal = computed(settings::goal);
    let total = move || summary.with(|summary| summary.total);
    let logged = move || summary.with(|summary| summary.meals > 0);
    let progress = move || goal.get().filter(|g| *g > 0.0).map(|g| total().kcal / g);
    // The page's one headline figure lies on the canvas, not in a card.
    view()
        .pt(px(4.0))
        .gap(px(18.0))
        .child(
            view()
                .flex_row()
                .items_center()
                .justify_between()
                .gap_4()
                .style_when(|| font_scale() > 1.2, |s| s.flex_col().items_start())
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap(px(6.0))
                        .child(
                            text(|| s().intake)
                                .typo(Type::Caption)
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(color::MUTED),
                        )
                        .child(
                            when(logged, move || figure(total, logged))
                                // Before the first meal: a sentence, not a
                                // dash the size of a figure.
                                .otherwise(|| {
                                    text(|| s().nothing_logged)
                                        .typo(Type::Title)
                                        .text_color(color::INK)
                                        .pt_1()
                                }),
                        )
                        .child(when(
                            move || !logged() || goal.get().is_some_and(|goal| goal > 0.0),
                            move || {
                                text(move || caption(total(), logged(), goal.get()))
                                    .typo(Type::Subhead)
                                    .tabular_nums()
                                    .text_color(color::MUTED)
                            },
                        )),
                )
                .child(when(
                    move || logged() && progress().is_some(),
                    move || {
                        view()
                            .size(px(RING))
                            .flex_shrink_0()
                            .child(goal_ring(RING, STROKE, move || {
                                progress().unwrap_or_default() as f32
                            }))
                            .child(
                                view()
                                    .absolute()
                                    .inset_0()
                                    .items_center()
                                    .justify_center()
                                    .child(
                                        text(move || {
                                            format!(
                                                "{:.0}%",
                                                progress().unwrap_or_default() * 100.0
                                            )
                                        })
                                        .typo(Type::Callout)
                                        .font_weight(FontWeight::SEMIBOLD)
                                        .tabular_nums()
                                        .text_color(color::INK),
                                    ),
                            )
                    },
                )),
        )
        .child(when(logged, move || {
            view()
                .flex_row()
                .gap_4()
                .flex_wrap()
                .child(macro_mark(|| s().protein, move || total().protein))
                .child(macro_mark(|| s().carbs, move || total().carbs))
                .child(macro_mark(|| s().fat, move || total().fat))
        }))
        .child(spending(day))
}

/// The day's spending in each currency (exact, never converted; opening
/// balances, adjustments, income and transfers are not spending). A dash
/// when nothing was spent; absent until the ledger has any entry.
fn spending(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let ledger = computed(|| !finance::transactions_snapshot().is_empty());
    let spent = computed(move || {
        let entries = finance::transactions_snapshot();
        let date = day().0;
        navi_finance::currency::Currency::ALL
            .into_iter()
            .filter_map(|currency| {
                let spending = navi_finance::review::spending_in(&entries, date, date, currency);
                (spending.records > 0)
                    .then(|| crate::ui::currency::format(spending.total, currency))
            })
            .collect::<Vec<_>>()
    });
    let value = move || {
        spent.with(|spent| {
            if spent.is_empty() {
                "—".to_owned()
            } else {
                spent.join(" / ")
            }
        })
    };
    when(
        move || ledger.get(),
        move || {
            view().gap(px(14.0)).child(hairline(0.0)).child(
                view()
                    .flex_row()
                    .items_center()
                    .justify_between()
                    .gap_3()
                    .flex_wrap()
                    .accessible(true)
                    .label(move || format!("{}, {}", s().spent_today, value()))
                    .child(
                        text(|| s().spent_today)
                            .typo(Type::Subhead)
                            .text_color(color::MUTED),
                    )
                    .child(
                        text(value)
                            .typo(Type::Headline)
                            .tabular_nums()
                            .text_color(move || {
                                if spent.with(Vec::is_empty) {
                                    color::MUTED
                                } else {
                                    color::INK
                                }
                            }),
                    ),
            )
        },
    )
}

/// The energy counting up, or a dash before anything is logged (missing
/// records never read as zero).
fn figure(
    total: impl Fn() -> Nutrients + Copy + 'static,
    logged: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    let shown = counted(move || total().kcal);
    stat(
        move || logged().then(|| format::kcal(shown.get())),
        || s().kcal.to_owned(),
        Scale::Hero,
    )
}

/// What is left of the goal (the ring shows how much of it is eaten), or
/// that nothing is logged yet.
fn caption(total: Nutrients, logged: bool, goal: Option<f64>) -> String {
    match (logged, goal) {
        (false, _) => s().intake_hint.to_owned(),
        (true, Some(goal)) if goal > 0.0 => s().goal_status(total.kcal, goal),
        (true, _) => s().kcal_today.to_owned(),
    }
}

fn macro_mark(name: fn() -> &'static str, grams: impl Fn() -> f64 + 'static) -> impl IntoElement {
    text(move || format!("{} {} g", name(), format::grams(grams())))
        .typo(Type::Subhead)
        .tabular_nums()
        .text_color(color::BODY)
}
