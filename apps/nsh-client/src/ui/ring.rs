//! Progress toward a daily energy goal, drawn clockwise from twelve o'clock.
use super::theme::{color, motion};
use nsh_core::{canvas::LineCap, prelude::*};
use std::f32::consts::{FRAC_PI_2, TAU};

pub fn goal_ring(
    size: f32,
    stroke: f32,
    fraction: impl Fn() -> f32 + Copy + 'static,
) -> impl IntoElement {
    let angle = move || TAU * fraction().clamp(0.0, 1.0) - FRAC_PI_2;
    let end = animated_value(untracked(angle));
    effect(move || {
        if reduce_motion() {
            end.set(angle());
        } else {
            end.timing(angle(), motion::FAST, motion::SETTLE);
        }
    });
    let center = size / 2.0;
    let radius = (size - stroke) / 2.0;
    canvas(move || {
        let track = Painter::new()
            .line_width(stroke)
            .line_cap(LineCap::Round)
            .stroke_color(nsh_core::prelude::color(color::TRACK))
            .begin_path()
            .arc(center, center, radius, 0.0, TAU)
            .stroke();
        if fraction() <= 0.0 {
            return track;
        }
        track
            .stroke_color(nsh_core::prelude::color(color::INK))
            .begin_path()
            .arc(center, center, radius, -FRAC_PI_2, &end)
            .stroke()
    })
    .size(px(size))
    .accessibility_elements_hidden(true)
}
