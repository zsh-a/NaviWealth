//! Two-state controls: a checkbox for a choice inside a decision, a switch
//! for a setting that applies at once. Both are rows whose whole width is
//! the target, the label included.

use nsh_base::{checkbox, switch};
use nsh_core::{Haptic, prelude::*};

use super::{
    Typo,
    icons::{Icon, icon},
    theme::{Type, color, motion, radius, size},
};

/// A checkbox row bound to `checked`.
pub fn checkbox_row(
    checked: Signal<bool>,
    label: impl Fn() -> SharedString + 'static,
) -> impl IntoElement {
    checkbox()
        .checked(checked)
        .on_change(move |next: &bool| {
            haptic(Haptic::Selection);
            checked.set(*next);
        })
        .flex_row()
        .items_center()
        .gap_3()
        .min_h(px(size::TOUCH))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::ACCENT))
        .indicator_style(|s| {
            s.size(px(22.0))
                .items_center()
                .justify_center()
                .rounded(px(radius::BADGE))
                .border_2()
                .border_color(color::LINE_STRONG)
                .transition_colors()
                .duration(motion::INSTANT)
                .checked(|s| s.bg(color::ACCENT_FILL).border_color(color::ACCENT_FILL))
        })
        .indicator(when(checked, || icon(Icon::Check, 16.0, color::ON_ACCENT)))
        .child(
            text(label)
                .typo(Type::Callout)
                .text_color(color::BODY)
                .flex_shrink(1.0),
        )
}

/// A switch row bound to `on`, with its label leading and the switch at the
/// trailing edge.
pub fn switch_row(
    on: Signal<bool>,
    label: impl Fn() -> SharedString + 'static,
) -> impl IntoElement {
    let travel = 20.0;
    switch()
        .checked(on)
        .on_change(move |next: &bool| {
            haptic(Haptic::Selection);
            on.set(*next);
        })
        .flex_row()
        .items_center()
        .justify_between()
        .gap_4()
        .min_h(px(size::TOUCH))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::ACCENT))
        .track_style(|s| {
            s.w(px(48.0))
                .h(px(28.0))
                .p(px(2.0))
                .rounded_full()
                .bg(color::LINE_STRONG)
                .transition_colors()
                .duration(motion::FAST)
                .checked(|s| s.bg(color::ACCENT_FILL))
        })
        .thumb_style(move |s| {
            s.size(px(24.0))
                .rounded_full()
                .bg(color::KNOB)
                .shadow_sm()
                .transition_transform()
                .duration(motion::FAST)
                .checked(move |s| s.translate_x(px(travel)))
        })
        .child(
            text(label)
                .typo(Type::Body)
                .text_color(color::INK)
                .flex_shrink(1.0),
        )
}
