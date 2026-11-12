//! The day at a glance: the energy ring with the day's figure in its
//! middle, where the energy came from beside it, and the goal under it.

use nsh_core::prelude::*;

use crate::{
    data::{meals, settings},
    domain::{format, meal::Day, nutrition::Nutrients},
    i18n::s,
    ui::{
        Type, Typo, color,
        feedback::appear,
        ring::{RingData, energy_ring},
        space,
        surface::{card, hairline},
    },
};

const RING: f32 = 136.0;
const STROKE: f32 = 13.0;

/// The hero card of `day`.
pub fn hero(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let summary = computed(move || meals::summary(day()));
    let goal = computed(settings::goal);
    let total = move || summary.with(|summary| summary.total);
    let logged = move || summary.with(|summary| summary.meals > 0);
    let ring = move || {
        let total = total();
        let shares = total.energy_split().shares().map(|share| share as f32);
        let fill = match goal.get() {
            Some(goal) if goal > 0.0 => (total.kcal / goal).clamp(0.0, 1.0) as f32,
            _ if total.kcal > 0.0 => 1.0,
            _ => 0.0,
        };
        RingData { shares, fill }
    };
    card()
        .p(px(space::CARD))
        .gap_4()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap(px(space::CARD + 2.0))
                .child(
                    view()
                        .size(px(RING))
                        .child(energy_ring(RING, STROKE, ring))
                        .child(center(total, logged)),
                )
                .child(legend(total, logged)),
        )
        .child(when(
            move || logged() && goal.get().is_some(),
            move || goal_footer(total, move || goal.get().unwrap_or_default()),
        ))
}

/// The figure in the ring: it rises in again whenever it changes.
fn center(
    total: impl Fn() -> Nutrients + Copy + 'static,
    logged: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    let figure = computed(move || {
        if logged() {
            format::kcal(total().kcal)
        } else {
            "—".to_owned()
        }
    });
    view()
        .absolute()
        .inset_0()
        .items_center()
        .justify_center()
        .px_4()
        .child(dynamic(move || {
            let value = figure.get();
            untracked(|| {
                appear(
                    0,
                    text(value)
                        .typo(Type::Display)
                        .tabular_nums()
                        .text_color(color::INK)
                        .number_of_lines(1),
                )
            })
        }))
        .child(
            text(move || {
                if logged() {
                    s().kcal_today
                } else {
                    s().nothing_logged
                }
            })
            .typo(Type::Caption)
            .text_color(color::MUTED)
            .text_center(),
        )
}

/// Protein, carbs and fat: grams eaten and their share of the energy.
fn legend(
    total: impl Fn() -> Nutrients + Copy + 'static,
    logged: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    let shares = move || total().energy_split().shares();
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap_2()
        .child(legend_row(
            || s().protein,
            color::PROTEIN,
            move || logged().then(|| total().protein),
            move || shares()[0],
        ))
        .child(legend_row(
            || s().carbs,
            color::CARBS,
            move || logged().then(|| total().carbs),
            move || shares()[1],
        ))
        .child(legend_row(
            || s().fat,
            color::FAT,
            move || logged().then(|| total().fat),
            move || shares()[2],
        ))
}

fn legend_row(
    label: fn() -> &'static str,
    tint: AdaptiveColor,
    grams: impl Fn() -> Option<f64> + Copy + 'static,
    share: impl Fn() -> f64 + Copy + 'static,
) -> impl IntoElement {
    view()
        .gap(px(2.0))
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(view().size(px(8.0)).rounded_full().bg(tint))
                .child(
                    text(label)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .flex_1()
                        .number_of_lines(1),
                )
                .child(
                    text(move || match grams() {
                        Some(_) => format::percent(share()),
                        None => String::new(),
                    })
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_color(color::FAINT),
                ),
        )
        .child(
            view()
                .flex_row()
                .items_end()
                .gap_1()
                .pl(px(16.0))
                .child(
                    text(move || grams().map(format::grams).unwrap_or_else(|| "—".into()))
                        .typo(Type::Headline)
                        .tabular_nums()
                        .text_color(color::INK),
                )
                .child(
                    text(move || if grams().is_some() { "g" } else { "" })
                        .typo(Type::Caption)
                        .text_color(color::MUTED)
                        .pb(px(2.0)),
                ),
        )
}

/// The goal and what is left of it.
fn goal_footer(
    total: impl Fn() -> Nutrients + Copy + 'static,
    goal: impl Fn() -> f64 + Copy + 'static,
) -> impl IntoElement {
    view().gap_3().child(hairline(0.0)).child(
        view()
            .flex_row()
            .items_center()
            .justify_between()
            .child(
                text(move || s().of_goal(goal()))
                    .typo(Type::Subhead)
                    .text_color(color::MUTED),
            )
            .child(
                text(move || s().goal_status(total().kcal, goal()))
                    .typo(Type::Subhead)
                    .font_weight(FontWeight::SEMIBOLD)
                    .tabular_nums()
                    .text_color(color::INK),
            ),
    )
}
