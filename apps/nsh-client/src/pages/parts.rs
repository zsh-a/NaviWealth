//! What the pages share: the bar at the top of a pushed page and the bar
//! pinned to the bottom of a page, over its scrolling content.

use nsh_core::prelude::*;

use crate::{
    i18n::s,
    ui::{Icon, IconBtn, Type, Typo, color, space},
};

/// The height a [`bottom_bar`] takes above the safe area.
pub const BOTTOM_BAR: f32 = 56.0 + 4.0 + 12.0;

/// The fade over the content just above a [`bottom_bar`].
const FADE: f32 = 28.0;

/// A pushed page's top bar: Back, the title, and an optional trailing
/// action. The page's system header is hidden, so this is what every
/// platform shows; the system back gesture and button still pop the page.
pub fn top_bar(
    title: impl Fn() -> SharedString + 'static,
    back: impl Fn() + 'static,
    trailing: Option<AnyElement>,
) -> View {
    view()
        .flex_row()
        .items_center()
        .gap_1()
        .pt_safe_area_plus(px(4.0))
        .pb_1()
        .px_2()
        .bg(color::CANVAS)
        .child(IconBtn::new(Icon::ChevronLeft, || s().back.into()).on_press(back))
        .child(
            text(title)
                .typo(Type::Headline)
                .text_color(color::INK)
                .number_of_lines(1)
                .flex_1()
                .role(AccessibilityRole::Header),
        )
        .child(trailing)
}

/// A bar pinned to the bottom of a page, fading the content that scrolls
/// under it into the canvas.
pub fn bottom_bar(content: impl IntoElement) -> View {
    view()
        .absolute()
        .left_0()
        .right_0()
        .bottom_0()
        .pointer_events(PointerEvents::BoxNone)
        .child(
            view()
                .h(px(FADE))
                .bg_linear_to_t()
                .gradient_from(color::CANVAS)
                .gradient_to(color::CANVAS.opacity(0.0))
                .pointer_events(PointerEvents::None),
        )
        .child(
            view()
                .px(px(space::GUTTER))
                .pt_1()
                .pb_safe_area_plus(px(12.0))
                .bg(color::CANVAS)
                .child(content),
        )
}

/// The space a page's scrolling content leaves under its last item so it
/// clears the [`bottom_bar`].
pub fn bottom_clearance() -> f32 {
    BOTTOM_BAR + FADE + safe_area().bottom.0 + 4.0
}
