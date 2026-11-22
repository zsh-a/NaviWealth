//! Surfaces: cards as objects on the one plane (a white face and a
//! hairline edge, no lift), their rows and hairlines, and section headers.

use nsh_base::{ButtonElement, button};
use nsh_core::prelude::*;

use super::{
    Typo,
    icons::{Icon, icon},
    theme::{Type, color, motion, radius, space},
};

/// A hairline's thickness.
pub const HAIRLINE: f32 = 0.5;

/// A card: an object on the page, a surface with a hairline edge. Groups of figures do not take one; they lie on the
/// canvas, divided by space and hairlines.
pub fn card() -> View {
    view()
        .bg(color::SURFACE)
        .rounded(px(radius::CARD))
        .border_curve(BorderCurve::Continuous)
        .border(px(HAIRLINE))
        .border_color(color::LINE)
}

/// A flat section of a page: a hairline above, then its title and figures
/// at the page gutter. Groups of figures take one instead of a card.
pub fn section() -> View {
    view()
        .pt(px(20.0))
        .pb(px(4.0))
        .border_t(px(HAIRLINE))
        .border_color(color::LINE)
}

/// A hairline between rows, with the same inset at both edges.
pub fn hairline(inset: f32) -> View {
    // Subpixel layout can round every other separator down to zero at 1×.
    view()
        .h(|| px(HAIRLINE.max(pixel_ratio().recip())))
        .flex_shrink_0()
        .mx(px(inset))
        .bg(color::LINE)
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
        .gap_3()
        .child(
            text(title)
                .typo(Type::Headline)
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

/// A row that shows or hides the content under it; its chevron turns as
/// it opens.
pub fn disclosure(open: Signal<bool>, label: impl Fn() -> SharedString + 'static) -> ButtonElement {
    button()
        .on_press(move || open.update(|open| *open = !*open))
        .flex_row()
        .items_center()
        .justify_between()
        .min_h(px(48.0))
        .rounded(px(radius::BADGE))
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
        .active(|s| s.opacity(0.7))
        .child(text(label).typo(Type::Headline).text_color(color::INK))
        .child(disclosure_chevron(open))
}

pub fn disclosure_chevron(open: Signal<bool>) -> impl IntoElement {
    view()
        .rotate(move || {
            Radians(if open.get() {
                std::f32::consts::PI
            } else {
                0.0
            })
        })
        .child(icon(Icon::ChevronDown, 18.0, color::MUTED))
}

/// A quiet label above a group of settings.
pub fn group_label(title: impl IntoReactive<SharedString>) -> impl IntoElement {
    text(title)
        .typo(Type::Subhead)
        .font_weight(FontWeight::SEMIBOLD)
        .text_color(color::MUTED)
        // Aligned with the card row titles it names, not the card edge.
        .px(px(space::CARD))
        .role(AccessibilityRole::Header)
}
