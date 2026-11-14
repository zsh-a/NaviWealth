//! Figures: the one way numbers are shown (whole part, quieter decimals,
//! muted unit), numbers that count to their new value, and the macro tiles
//! that show where the energy comes from.

use std::time::Duration;

use nsh_core::prelude::*;

use super::{
    Typo,
    theme::{Type, color, motion, radius},
};
use crate::domain::{format, nutrition::Nutrients};

/// A number that eases from what it showed to each new `value`; it jumps
/// with reduced motion.
pub fn counted(value: impl Fn() -> f64 + 'static) -> Signal<f64> {
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
    shown
}

/// How large a [`stat`] is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scale {
    /// The one headline number of a card or page.
    Hero,
    /// A number among others in a row or grid.
    Tile,
}

impl Scale {
    fn number(self) -> Type {
        match self {
            Scale::Hero => Type::Display,
            Scale::Tile => Type::Figure,
        }
    }

    fn unit(self) -> Type {
        match self {
            Scale::Hero => Type::Callout,
            Scale::Tile => Type::Caption,
        }
    }
}

/// Splits a written number into its whole part and its decimals
/// (`72.9` → `72`, `.9`); grouping commas stay with the whole part.
pub fn split_decimals(written: &str) -> (&str, &str) {
    match written.rfind('.') {
        Some(at)
            if written[at + 1..].chars().all(|c| c.is_ascii_digit()) && at + 1 < written.len() =>
        {
            written.split_at(at)
        }
        _ => (written, ""),
    }
}

/// Every number the app shows on its own: the whole part in ink, decimals
/// one step quieter, the unit muted on the same baseline. A faint dash and
/// no unit when there is no value, so a missing record never reads as zero.
pub fn stat(
    value: impl Fn() -> Option<String> + Copy + 'static,
    unit: impl Fn() -> String + Copy + 'static,
    scale: Scale,
) -> View {
    let part = move |decimals: bool| {
        move || match value() {
            Some(written) => {
                let (whole, rest) = split_decimals(&written);
                if decimals {
                    rest.to_owned()
                } else {
                    whole.to_owned()
                }
            }
            None if decimals => String::new(),
            None => "—".to_owned(),
        }
    };
    view()
        .flex_row()
        .items_baseline()
        .min_w(px(0.0))
        .child(
            text(part(false))
                .typo(scale.number())
                .tabular_nums()
                .number_of_lines(1)
                .text_color(move || {
                    if value().is_some() {
                        color::INK
                    } else {
                        color::FAINT
                    }
                }),
        )
        .child(
            text(part(true))
                .typo(scale.number())
                .tabular_nums()
                .number_of_lines(1)
                .text_color(color::MUTED),
        )
        .child(
            text(move || match value() {
                Some(_) => unit(),
                None => String::new(),
            })
            .typo(scale.unit())
            .text_color(color::MUTED)
            .number_of_lines(1)
            .ml(px(4.0)),
        )
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
