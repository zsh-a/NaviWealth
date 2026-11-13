//! What the pages share: the bar at the top of a pushed page and the bar
//! pinned to the bottom of a page, over its scrolling content.

use nsh_core::prelude::*;

use crate::{
    i18n::s,
    ui::{Icon, IconBtn, Type, Typo, Variant, color, space, theme::size},
};

/// The height a [`bottom_bar`]'s controls take above the safe area.
pub const BOTTOM_BAR: f32 = 56.0 + 14.0;

/// The fade over the content just above a [`bottom_bar`]'s controls.
const FADE: f32 = 40.0;

/// A pushed page's top bar: a raised round Back, the title centered, and
/// an optional trailing action (or the room one takes, so the title stays
/// centered). The page's system header is hidden, so this is what every
/// platform shows; the system back gesture and button still pop the page.
pub fn top_bar(
    title: impl Fn() -> SharedString + 'static,
    back: impl Fn() + 'static,
    trailing: Option<AnyElement>,
) -> View {
    view()
        .flex_row()
        .items_center()
        .gap_2()
        .pt_safe_area_plus(px(6.0))
        .pb_2()
        .px_3()
        .bg(color::CANVAS)
        .child(
            IconBtn::new(Icon::ChevronLeft, || s().back.into())
                .variant(Variant::Secondary)
                .on_press(back),
        )
        .child(
            text(title)
                .typo(Type::Headline)
                .text_color(color::INK)
                .number_of_lines(1)
                .text_center()
                .flex_1()
                .role(AccessibilityRole::Header),
        )
        .child(trailing.unwrap_or_else(|| view().size(px(size::TOUCH)).into_element()))
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
        .pt(px(FADE))
        .px(px(space::GUTTER))
        .pb_safe_area_plus(px(14.0))
        .bg_linear_to_t()
        .gradient_from(color::CANVAS)
        .gradient_via(color::CANVAS.opacity(0.92))
        .gradient_to(color::CANVAS.opacity(0.0))
        .child(content)
}

/// The status bar's icons for the page under them: dark on the light canvas,
/// light on the dark one (the pages draw their own header under it).
pub fn status_bar() -> StatusBarSetting {
    StatusBarSetting::from(if dark() {
        StatusBarStyle::Light
    } else {
        StatusBarStyle::Dark
    })
}

/// The space a page's scrolling content leaves under its last item so it
/// clears the [`bottom_bar`].
pub fn bottom_clearance() -> f32 {
    BOTTOM_BAR + FADE + safe_area().bottom.0 + 4.0
}
