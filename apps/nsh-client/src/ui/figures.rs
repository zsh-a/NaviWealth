//! Figures: numbers that count to their new value, and the macro tiles that
//! show where the energy comes from.

use std::time::Duration;

use nsh_core::prelude::*;

use super::{
    Typo,
    theme::{Type, color, motion, radius},
};
use crate::domain::{format, nutrition::Nutrients};

/// A text of `value` (written by `format`) that counts from what it showed
/// to each new value, easing out; it jumps with reduced motion.
pub fn counting(value: impl Fn() -> f64 + 'static, format: fn(f64) -> String) -> Text {
    let target = computed(value);
    let shown = signal(0.0_f64);
    effect(move || {
        let to = target.get();
        let from = shown.get_untracked();
        if untracked(reduce_motion) || (to - from).abs() < 0.5 {
            shown.set(to);
            return;
        }
        // The effect's next run (a newer value) cancels this count.
        spawn(async move {
            let started = nsh_core::time::now();
            loop {
                timer(Duration::from_millis(16)).await;
                let t =
                    (started.elapsed().as_secs_f64() * 1000.0 / f64::from(motion::SLOWER)).min(1.0);
                let eased = 1.0 - (1.0 - t).powi(3);
                shown.set(from + (to - from) * eased);
                if t >= 1.0 {
                    break;
                }
            }
        });
    });
    text(move || format(shown.get())).tabular_nums()
}

/// The macronutrients of `total` as three tiles: grams, share of the
/// energy as a bar and a percentage. Dashes while nothing is `logged`.
pub fn macro_tiles(
    labels: [fn() -> &'static str; 3],
    total: impl Fn() -> Nutrients + Copy + 'static,
    logged: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    let tints = [color::PROTEIN, color::CARBS, color::FAT];
    view()
        .flex_row()
        .gap(px(10.0))
        .children((0..3).map(move |part| {
            let grams = move || {
                let total = total();
                [total.protein, total.carbs, total.fat][part]
            };
            let split = move || total().energy_split();
            let share = move || split().shares()[part] as f32;
            let percent = move || split().percents()[part];
            tile(labels[part], tints[part], grams, (share, percent), logged)
        }))
}

fn tile(
    label: fn() -> &'static str,
    tint: AdaptiveColor,
    grams: impl Fn() -> f64 + Copy + 'static,
    (share, percent): (
        impl Fn() -> f32 + Copy + 'static,
        impl Fn() -> u32 + Copy + 'static,
    ),
    logged: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap(px(6.0))
        .px_3()
        .pt_3()
        .pb(px(14.0))
        .rounded(px(radius::WELL))
        .bg(color::SURFACE_2)
        .child(
            view()
                .flex_row()
                .items_center()
                .gap(px(6.0))
                .child(view().size(px(7.0)).rounded_full().bg(tint))
                .child(
                    text(label)
                        .typo(Type::Caption)
                        .text_color(color::MUTED)
                        .number_of_lines(1)
                        .flex_1(),
                ),
        )
        .child(
            view()
                .flex_row()
                .items_end()
                .justify_between()
                .gap(px(4.0))
                .child(
                    view()
                        .flex_row()
                        .items_end()
                        .gap(px(2.0))
                        .child(
                            text(move || {
                                if logged() {
                                    format::grams(grams())
                                } else {
                                    "—".into()
                                }
                            })
                            .typo(Type::Figure)
                            .tabular_nums()
                            .text_color(color::INK)
                            .number_of_lines(1),
                        )
                        .child(
                            text(move || if logged() { "g" } else { "" })
                                .typo(Type::Caption)
                                .text_color(color::MUTED)
                                .pb(px(3.0)),
                        ),
                )
                .child(
                    text(move || {
                        if logged() {
                            format::percent(percent())
                        } else {
                            String::new()
                        }
                    })
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_color(color::FAINT)
                    .pb(px(3.0)),
                ),
        )
        .child(
            view()
                .flex_row()
                .h(px(4.0))
                .rounded_full()
                .overflow_hidden()
                .bg(color::LINE)
                .child(
                    view()
                        .h_full()
                        .rounded_full()
                        .bg(tint)
                        .flex_grow(move || if logged() { share() } else { 0.0 })
                        .w(px(0.0)),
                )
                .child(
                    view()
                        .flex_grow(move || if logged() { 1.0 - share() } else { 1.0 })
                        .w(px(0.0)),
                ),
        )
}
