//! The last four weeks as a strip of days, today at its trailing end: one
//! ink selection slides to the chosen day (natively), and a dot marks the
//! days that have meals. Arrow keys move between days.

use std::time::Duration;

use nsh_base::{tab, tabs};
use nsh_core::{Haptic, prelude::*};

use crate::{
    data::{clock, meals},
    i18n::s,
    ui::{Type, Typo, color, space},
};

/// How many days the strip offers.
const DAYS: i32 = 28;
/// A day's width.
const CELL: f32 = 46.0;

/// The strip; `offset` is the chosen day, in days from today (0 or less).
pub fn day_strip(offset: Signal<i32>) -> impl IntoElement {
    let strip = element_ref();
    // Open on today, at the strip's end, once it is laid out.
    set_timeout(Duration::from_millis(40), move || {
        strip.scroll_to_end(false)
    });
    scroll()
        .horizontal()
        .scrollbar(false)
        .element_ref(&strip)
        .mx(px(-space::GUTTER))
        .child(
            tabs()
                .flex_row()
                .gap(px(6.0))
                .px(px(space::GUTTER))
                .indicator_style(|s| s.top_0().bottom_0().rounded_full().bg(color::ACTION))
                .children((0..DAYS).map(move |index| day(DAYS - 1 - index, offset))),
        )
}

fn day(back: i32, offset: Signal<i32>) -> impl IntoElement {
    let date = move || clock::today().plus_days(-back);
    let chosen = move || offset.get() == -back;
    let logged = move || meals::summary(date()).meals > 0;
    tab()
        .selected(chosen)
        .on_press(move |_: &()| {
            if !chosen() {
                haptic(Haptic::Selection);
                offset.set(-back);
            }
        })
        .accessibility_label(move || Some(s().long_date(date()).into()))
        .w(px(CELL))
        .min_h(px(68.0))
        .items_center()
        .justify_center()
        .gap(px(3.0))
        .rounded_full()
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
        .child(
            text(move || s().weekday_short(date()))
                .typo(Type::Caption)
                .text_color(move || {
                    if chosen() {
                        color::ON_ACTION.opacity(0.7)
                    } else {
                        color::MUTED
                    }
                }),
        )
        .child(
            text(move || date().0.day().to_string())
                .typo(Type::Headline)
                .tabular_nums()
                .text_color(move || {
                    if chosen() {
                        color::ON_ACTION
                    } else {
                        color::INK
                    }
                }),
        )
        .child(
            view()
                .size(px(5.0))
                .rounded_full()
                .bg(move || match (logged(), chosen()) {
                    (false, _) => AdaptiveColor::TRANSPARENT,
                    (true, true) => color::ON_ACTION,
                    (true, false) => color::INK,
                }),
        )
}
