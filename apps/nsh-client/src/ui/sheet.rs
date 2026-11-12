//! The app's bottom sheet: `nsh_base`'s sheet (slide, backdrop, Escape,
//! back, swipe down) in the app's surface, with a grabber, the safe area
//! and the keyboard taken into account.

use nsh_base::{SheetEvent, sheet};
use nsh_core::prelude::*;

use super::theme::{color, radius, space};

/// A sheet shown while `open` reads true; `close` is asked to set it false
/// when the user dismisses it. `content` is made on each opening (use a
/// `#[component]` for state that should start fresh).
pub fn bottom_sheet(
    open: impl Fn() -> bool + 'static,
    close: impl Fn() + 'static,
    content: impl IntoElement,
) -> impl IntoElement {
    sheet()
        .open(move || Some(open()))
        .on_open_change(move |event: &SheetEvent| {
            if let SheetEvent::OpenChange(false, _) = event {
                close();
            }
        })
        .close_on_swipe(true)
        .backdrop_style(|s| s.bg(color::SCRIM.opacity(0.42)))
        .popup_style(|s| {
            s.rounded_t(px(radius::SHEET))
                .bg(color::SURFACE)
                .shadow_xl()
        })
        .child(
            view()
                .max_h(move || px(window().height.0 * 0.92))
                .mb_keyboard()
                .child(
                    view()
                        .w(px(36.0))
                        .h(px(5.0))
                        .mt_2()
                        .mb_1()
                        .self_center()
                        .rounded_full()
                        .bg(color::LINE_STRONG)
                        .accessibility_elements_hidden(true),
                )
                .child(
                    scroll().flex_shrink(1.0).child(
                        view()
                            .px(px(space::GUTTER))
                            .pt_2()
                            .pb_safe_area_plus(px(16.0))
                            .gap_4()
                            .child(content),
                    ),
                ),
        )
}
