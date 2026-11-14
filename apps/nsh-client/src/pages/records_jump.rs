//! Go to a day in Records: a month calendar in a sheet, stepping back
//! through earlier months. Days with records are pressable; choosing one
//! closes the sheet and scrolls Records to that day.

use std::rc::Rc;

use nsh_core::prelude::*;

use super::{
    home::Sheets,
    review_calendar::{calendar, month_days},
};
use crate::{
    data::{clock, meals, settings, weights},
    domain::review::{self, Period},
    i18n::s,
    ui::{Icon, IconBtn, Type, Typo, color},
};

/// The sheet's content; `sheets.jump` opens it.
pub fn jump_sheet(sheets: Sheets) -> impl IntoElement {
    // Months back from the current one.
    let back = signal(0_i32);
    let days = computed(move || {
        review::period_days_starting(Period::Month, clock::today(), back.get(), s().week_start())
    });
    view()
        .gap_4()
        .child(
            text(|| s().go_to_day)
                .typo(Type::Title)
                .text_color(color::INK)
                .role(AccessibilityRole::Header),
        )
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    IconBtn::new(Icon::ChevronLeft, || s().previous_month.into())
                        .on_press(move || back.update(|b| *b += 1)),
                )
                .child(
                    text(move || days.with(|d| s().month_name(d[0])))
                        .flex_1()
                        .text_center()
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(
                    IconBtn::new(Icon::ChevronRight, || s().next_month.into())
                        .on_press(move || back.update(|b| *b = (*b - 1).max(0)))
                        .disabled(move || back.get() == 0),
                ),
        )
        .child(dynamic(move || {
            let days = days.get();
            let kcal: Vec<Option<f64>> = days
                .iter()
                .map(|&d| {
                    let summary = meals::summary(d);
                    (summary.meals > 0).then_some(summary.total.kcal)
                })
                .collect();
            let weighed: Vec<bool> = days.iter().map(|&d| weights::on(d).is_some()).collect();
            let (goal, start) = (settings::goal(), s().week_start());
            untracked(move || {
                let pick = Rc::new(move |day| {
                    sheets.jump.set(false);
                    sheets.jump_to.set(Some(day));
                });
                calendar(month_days(&days, &kcal, &weighed), goal, start, Some(pick))
            })
        }))
}
