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
    shell(
        open,
        close,
        scroll().flex_shrink(1.0).child(
            view()
                .px(px(space::GUTTER))
                .pt_2()
                .pb_safe_area_plus(px(16.0))
                .gap_4()
                .child(content),
        ),
    )
}

/// A task sheet with a fixed header and actions; only its body scrolls.
/// The available height excludes the keyboard, including on small phones.
pub fn task_sheet(
    open: impl Fn() -> bool + 'static,
    close: impl Fn() + 'static,
    header: impl IntoElement,
    body: impl IntoElement,
    actions: impl IntoElement,
) -> impl IntoElement {
    shell(
        open,
        close,
        view()
            .h(move || {
                px((window().height.0 * 0.92 - keyboard_height().0 - 20.0).clamp(120.0, 540.0))
            })
            .child(
                view()
                    .flex_shrink(0.0)
                    .px(px(space::GUTTER))
                    .py_2()
                    .child(header),
            )
            .child(
                scroll()
                    .flex_1()
                    .min_h(px(0.0))
                    .child(view().px(px(space::GUTTER)).py_2().child(body)),
            )
            .child(
                view()
                    .flex_shrink(0.0)
                    .px(px(space::GUTTER))
                    .pt_3()
                    .pb_safe_area_plus(px(12.0))
                    .child(actions)
                    .child(super::toast::toast_view(|| 68.0)),
            ),
    )
}

fn shell(
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
                .max_h(move || px((window().height.0 * 0.92 - keyboard_height().0).max(140.0)))
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
                .child(content),
        )
}
