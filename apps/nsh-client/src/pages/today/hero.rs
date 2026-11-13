//! The day at a glance: the energy so far as a large figure counting up,
//! what is left of the goal, a compact ring of where the energy came from,
//! and the macros in grams.

use nsh_core::prelude::*;

use crate::{
    data::{meals, settings},
    domain::{format, meal::Day, nutrition::Nutrients},
    i18n::s,
    ui::{
        Type, Typo, color,
        figures::counting,
        ring::{RingData, energy_ring},
        space,
        surface::card,
    },
};

const RING: f32 = 84.0;
const STROKE: f32 = 9.0;

/// The glance card of `day`.
pub fn hero(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let summary = computed(move || meals::summary(day()));
    let goal = computed(settings::goal);
    let total = move || summary.with(|summary| summary.total);
    let logged = move || summary.with(|summary| summary.meals > 0);
    let fill = move || match goal.get() {
        Some(goal) if goal > 0.0 => (total().kcal / goal).clamp(0.0, 1.0) as f32,
        _ if total().kcal > 0.0 => 1.0,
        _ => 0.0,
    };
    let ring = move || RingData {
        shares: total().energy_split().shares().map(|share| share as f32),
        fill: fill(),
    };
    card()
        .px(px(space::CARD))
        .pt(px(22.0))
        .pb(px(space::CARD))
        .gap(px(18.0))
        .child(
            view()
                .flex_row()
                .items_start()
                .justify_between()
                .gap_4()
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
                        .child(figure(total, logged))
                        .child(
                            text(move || caption(total(), logged(), goal.get()))
                                .typo(Type::Subhead)
                                .tabular_nums()
                                .text_color(color::MUTED)
                                .number_of_lines(1),
                        ),
                )
                .child(
                    view()
                        .size(px(RING))
                        .child(energy_ring(RING, STROKE, ring))
                        .child(
                            view()
                                .absolute()
                                .inset_0()
                                .items_center()
                                .justify_center()
                                .child(
                                    text(move || match goal.get() {
                                        Some(g) if g > 0.0 && logged() => {
                                            format!("{:.0}%", total().kcal / g * 100.0)
                                        }
                                        _ => String::new(),
                                    })
                                    .typo(Type::Callout)
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .tabular_nums()
                                    .text_color(color::INK),
                                ),
                        ),
                ),
        )
        .child(
            view()
                .flex_row()
                .gap_4()
                .child(macro_mark(
                    color::PROTEIN,
                    || s().protein,
                    move || total().protein,
                ))
                .child(macro_mark(
                    color::CARBS,
                    || s().carbs,
                    move || total().carbs,
                ))
                .child(macro_mark(color::FAT, || s().fat, move || total().fat)),
        )
}

/// The energy counting up, or a dash before anything is logged (missing
/// records never read as zero).
fn figure(
    total: impl Fn() -> Nutrients + Copy + 'static,
    logged: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    view()
        .flex_row()
        .items_baseline()
        .gap_1()
        .child(
            when(logged, move || {
                counting(move || total().kcal, format::kcal)
                    .typo(Type::Display)
                    .text_color(color::INK)
                    .number_of_lines(1)
            })
            .otherwise(|| text("—").typo(Type::Display).text_color(color::FAINT)),
        )
        .child(
            text(|| s().kcal)
                .typo(Type::Callout)
                .text_color(color::MUTED),
        )
}

/// What is left of the goal (the ring shows how much of it is eaten), or
/// that nothing is logged yet.
fn caption(total: Nutrients, logged: bool, goal: Option<f64>) -> String {
    match (logged, goal) {
        (false, _) => s().nothing_logged.to_owned(),
        (true, Some(goal)) if goal > 0.0 => s().goal_status(total.kcal, goal),
        (true, _) => s().kcal_today.to_owned(),
    }
}

fn macro_mark(
    tint: AdaptiveColor,
    name: fn() -> &'static str,
    grams: impl Fn() -> f64 + 'static,
) -> impl IntoElement {
    view()
        .flex_row()
        .items_center()
        .gap(px(6.0))
        .child(view().size(px(6.0)).rounded_full().bg(tint))
        .child(
            text(move || format!("{} {}g", name(), format::grams(grams())))
                .typo(Type::Caption)
                .tabular_nums()
                .text_color(color::MUTED),
        )
}
