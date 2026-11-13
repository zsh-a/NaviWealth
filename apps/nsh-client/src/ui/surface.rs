//! Surfaces: cards lifted off the canvas by soft light, their rows and
//! hairlines, and section headers.

use nsh_base::{ButtonElement, button};
use nsh_core::prelude::*;

use super::{
    Lift, Typo,
    icons::{Icon, icon},
    theme::{Type, color, motion, radius, shadow, space},
};

/// A hairline's thickness.
pub const HAIRLINE: f32 = 0.75;

/// A card: a white surface lifted by soft light (a hairline edge in dark).
pub fn card() -> View {
    view()
        .bg(color::SURFACE)
        .rounded(px(radius::CARD))
        .lift(&shadow::CARD)
        .dark(|s| s.border_1().border_color(color::LINE))
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
        .min_h(px(36.0))
        .px(px(2.0))
        .child(
            text(title)
                .typo(Type::Title)
                .text_color(color::INK)
                .role(AccessibilityRole::Header),
        )
        .child(trailing)
}

/// A pressable row inside a card: it fills the card's width and darkens
/// while pressed.
pub fn row_button(press: impl Fn() + 'static) -> ButtonElement {
    button()
        .on_press(press)
        .flex_row()
        .items_center()
        .gap_3()
        .min_h(px(68.0))
        .px(px(space::CARD))
        .py_3()
        .transition_colors()
        .duration(motion::INSTANT)
        .hover(|s| s.bg(color::SURFACE_2))
        .active(|s| s.bg(color::SUNKEN))
        .focus_visible(|s| s.bg(color::SURFACE_2))
}

/// A pressable card: it sinks a little under the finger.
pub fn card_button(press: impl Fn() + 'static) -> ButtonElement {
    let scale = animated_value(1.0);
    button()
        .on_press_down(move || {
            if !reduce_motion() {
                scale.spring(motion::PRESS_SCALE_CARD, motion::PRESS);
            }
        })
        .on_press_up(move || {
            scale.spring(1.0, motion::PRESS);
        })
        .on_press(press)
        .bind_scale(&scale)
        .bg(color::SURFACE)
        .rounded(px(radius::CARD))
        .lift(&shadow::CARD)
        .dark(|s| s.border_1().border_color(color::LINE))
        .transition_colors()
        .duration(motion::INSTANT)
        .active(|s| s.bg(color::SURFACE_2))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
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
        .rounded(px(radius::BADGE))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
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
                .child(icon(Icon::ChevronRight, 18.0, color::MUTED)),
        )
}

/// A quiet label above a group of settings.
pub fn group_label(title: impl IntoReactive<SharedString>) -> impl IntoElement {
    text(title)
        .typo(Type::Subhead)
        .font_weight(FontWeight::SEMIBOLD)
        .text_color(color::MUTED)
        .px(px(6.0))
        .role(AccessibilityRole::Header)
}
