//! Surfaces: cards and grouped lists on the canvas, their rows and
//! hairlines, and section headers.

use nsh_base::{ButtonElement, button};
use nsh_core::prelude::*;

use super::{
    Typo,
    theme::{Type, color, motion, radius, space},
};

/// A hairline's thickness.
pub const HAIRLINE: f32 = 0.75;

/// A grouped surface on the canvas.
pub fn card() -> View {
    view().bg(color::SURFACE).rounded(px(radius::CARD))
}

/// A hairline between rows, inset from the leading edge by `inset`.
pub fn hairline(inset: f32) -> View {
    view().h(px(HAIRLINE)).ml(px(inset)).bg(color::LINE)
}

/// A section's title, a header for screen readers, with an optional
/// trailing element on the same line.
pub fn section_header(
    title: impl IntoReactive<SharedString>,
    trailing: Option<AnyElement>,
) -> View {
    view()
        .flex_row()
        .items_center()
        .justify_between()
        .min_h(px(32.0))
        .px(px(4.0))
        .child(
            text(title)
                .typo(Type::Title)
                .text_color(color::INK)
                .role(AccessibilityRole::Header),
        )
        .child(trailing)
}

/// A pressable row of a grouped list: it fills the group's width, washes
/// on hover and darkens while pressed (rows do not scale).
pub fn row_button(press: impl Fn() + 'static) -> ButtonElement {
    button()
        .on_press(press)
        .flex_row()
        .items_center()
        .gap_3()
        .min_h(px(64.0))
        .px(px(space::CARD - 2.0))
        .py_3()
        .transition_colors()
        .duration(motion::INSTANT)
        .hover(|s| s.bg(color::SUNKEN.opacity(0.6)))
        .active(|s| s.bg(color::SUNKEN))
        .focus_visible(|s| s.bg(color::ACCENT_SOFT))
}

/// A row that shows or hides the content under it; its chevron turns as
/// it opens.
pub fn disclosure(open: Signal<bool>, label: impl Fn() -> SharedString + 'static) -> ButtonElement {
    button()
        .on_press(move || open.update(|open| *open = !*open))
        .flex_row()
        .items_center()
        .justify_between()
        .min_h(px(44.0))
        .rounded(px(radius::SMALL))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::ACCENT))
        .active(|s| s.opacity(0.7))
        .child(text(label).typo(Type::Headline).text_color(color::INK))
        .child(
            view()
                .transition_transform()
                .duration(motion::BASE)
                .rotate(move || {
                    Radians(if open.get() {
                        std::f32::consts::FRAC_PI_2
                    } else {
                        0.0
                    })
                })
                .child(super::icons::icon(
                    super::icons::Icon::ChevronRight,
                    18.0,
                    color::MUTED,
                )),
        )
}

/// A quiet label above a group of settings.
pub fn group_label(title: impl IntoReactive<SharedString>) -> impl IntoElement {
    text(title)
        .typo(Type::Subhead)
        .font_weight(FontWeight::SEMIBOLD)
        .text_color(color::MUTED)
        .px_1()
        .role(AccessibilityRole::Header)
}
