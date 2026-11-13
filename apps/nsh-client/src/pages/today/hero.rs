//! The day at a glance: a large ring with the day's energy counting up in
//! its middle, the goal under it, and where the energy came from.

use nsh_core::prelude::*;

use crate::{
    data::{meals, settings},
    domain::{format, meal::Day, nutrition::Nutrients},
    i18n::s,
    ui::{
        Icon, Type, Typo, color,
        figures::{counting, macro_tiles},
        icon,
        ring::{RingData, energy_ring},
        space,
        surface::card,
    },
};

const RING: f32 = 204.0;
const STROKE: f32 = 17.0;

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
        .px(px(space::CARD))
        .pt_6()
        .pb(px(space::CARD))
        .items_center()
        .gap_5()
        .child(
            view()
                .size(px(RING))
                .child(energy_ring(RING, STROKE, ring))
                .child(center(total, logged)),
        )
        .child(goal_pill(total, logged, move || goal.get()))
        .child(view().self_stretch().child(macro_tiles(
            [|| s().protein, || s().carbs, || s().fat],
            total,
            logged,
        )))
}

/// The figure in the ring.
fn center(
    total: impl Fn() -> Nutrients + Copy + 'static,
    logged: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    view()
        .absolute()
        .inset_0()
        .items_center()
        .justify_center()
        .gap(px(2.0))
        .child(
            when(logged, move || {
                counting(move || total().kcal, format::kcal)
                    .typo(Type::Hero)
                    .text_color(color::INK)
                    .number_of_lines(1)
            })
            .otherwise(|| {
                view()
                    .size(px(56.0))
                    .mb_2()
                    .items_center()
                    .justify_center()
                    .rounded_full()
                    .bg(color::SURFACE_2)
                    .child(icon(Icon::Utensils, 26.0, color::FAINT))
            }),
        )
        .child(
            text(move || {
                if logged() {
                    s().kcal_today
                } else {
                    s().nothing_logged
                }
            })
            .typo(Type::Subhead)
            .text_color(color::MUTED)
            .text_center(),
        )
}

/// What is left of the goal (or how far past it), in a quiet pill.
fn goal_pill(
    total: impl Fn() -> Nutrients + Copy + 'static,
    logged: impl Fn() -> bool + Copy + 'static,
    goal: impl Fn() -> Option<f64> + Copy + 'static,
) -> impl IntoElement {
    when(
        move || goal().is_some(),
        move || {
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .px_4()
                .py(px(7.0))
                .rounded_full()
                .bg(color::SURFACE_2)
                .child(
                    text(move || {
                        let goal = goal().unwrap_or_default();
                        if logged() {
                            s().goal_status(total().kcal, goal)
                        } else {
                            s().of_goal(goal)
                        }
                    })
                    .typo(Type::Subhead)
                    .font_weight(FontWeight::SEMIBOLD)
                    .tabular_nums()
                    .text_color(color::INK),
                )
                .child(when(logged, move || {
                    text(move || s().of_goal(goal().unwrap_or_default()))
                        .typo(Type::Subhead)
                        .tabular_nums()
                        .text_color(color::MUTED)
                }))
        },
    )
}
