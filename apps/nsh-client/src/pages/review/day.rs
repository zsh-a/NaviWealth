//! The day a meal counts toward: a chip on the review page, and the last
//! four weeks in a sheet for logging late.

use nsh_base::button;
use nsh_core::prelude::*;

use super::draft::Draft;
use crate::{
    data::clock,
    i18n::s,
    pages::today::day_strip,
    ui::{Icon, Type, Typo, color, icon},
};

/// The day the meal counts toward, as a chip: Today unless the owner is
/// logging late, which opens the four-week strip.
pub fn day_chip(draft: Draft) -> impl IntoElement {
    view().flex_row().child(
        button()
            .on_press(move || draft.choosing_day.set(true))
            .flex_row()
            .items_center()
            .gap(px(6.0))
            .h(px(36.0))
            .pl(px(12.0))
            .pr(px(10.0))
            .rounded_full()
            .bg(color::SURFACE_2)
            .active(|s| s.bg(color::SUNKEN))
            .accessibility_label(move || {
                Some(format!("{}, {}", s().meal_day, s().long_date(draft.day.get())).into())
            })
            .child(icon(Icon::Calendar, 16.0, color::MUTED))
            .child(
                text(move || s().day_title(draft.day.get(), clock::today()))
                    .typo(Type::Subhead)
                    .font_weight(FontWeight::SEMIBOLD)
                    .tabular_nums()
                    .text_color(color::BODY),
            )
            .child(icon(Icon::ChevronDown, 16.0, color::MUTED)),
    )
}

/// The last four weeks; choosing a day moves the meal there.
pub fn day_sheet(draft: Draft) -> impl IntoElement {
    let offset = signal(untracked(|| draft.day.get().days_since(clock::today())));
    effect(move || {
        let day = clock::today().plus_days(offset.get());
        if untracked(|| draft.day.get()) != day {
            draft.day.set(day);
            draft.dirty.set(true);
            draft.choosing_day.set(false);
        }
    });
    view()
        .gap_4()
        .child(
            text(|| s().meal_day)
                .typo(Type::Title)
                .text_color(color::INK)
                .role(AccessibilityRole::Header),
        )
        .child(day_strip(offset))
}
