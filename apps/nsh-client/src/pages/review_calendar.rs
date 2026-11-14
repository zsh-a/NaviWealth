//! A month in review as a calendar: one cell per day, shaded by how much of
//! the goal was eaten (amber past it), empty for a day without meals, a dot
//! under a day with a weight, today outlined. It replaces the month's bars,
//! where 31 thin columns were hard to read.

use std::rc::Rc;

use nsh_base::button;
use nsh_core::prelude::*;

use crate::{
    data::clock,
    domain::{meal::Day, review::WeekStart},
    i18n::s,
    ui::{Type, Typo, color, theme::radius},
};

/// A cell's height.
const CELL: f32 = 40.0;

/// What one day of the month shows.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CalendarDay {
    pub day: Day,
    /// The energy eaten, if anything was logged.
    pub kcal: Option<f64>,
    pub weighed: bool,
}

/// How strongly a logged day is shaded: its share of the goal, kept above a
/// floor so a light day still reads as logged; a full shade without a goal.
pub fn shade(kcal: f64, goal: Option<f64>) -> f32 {
    match goal {
        Some(goal) if goal > 0.0 => (0.3 + 0.7 * (kcal / goal).clamp(0.0, 1.0)) as f32,
        _ => 1.0,
    }
}

/// The month of `days` (its first day onward) as weeks of seven cells
/// starting on `start`; `None` pads before the first and after the last day.
pub fn weeks(days: &[CalendarDay], start: WeekStart) -> Vec<[Option<CalendarDay>; 7]> {
    let Some(first) = days.first() else {
        return Vec::new();
    };
    let monday_offset = i32::from(first.day.0.weekday().to_monday_zero_offset());
    let lead = match start {
        WeekStart::Monday => monday_offset,
        WeekStart::Sunday => (monday_offset + 1) % 7,
    } as usize;
    let cells: Vec<Option<CalendarDay>> = std::iter::repeat_n(None, lead)
        .chain(days.iter().copied().map(Some))
        .collect();
    cells
        .chunks(7)
        .map(|chunk| {
            let mut week = [None; 7];
            week[..chunk.len()].copy_from_slice(chunk);
            week
        })
        .collect()
}

/// The month's days through its last day: the reviewed `days` with their
/// records, then the days still to come (no records, never shaded).
pub fn month_days(days: &[Day], kcal: &[Option<f64>], weighed: &[bool]) -> Vec<CalendarDay> {
    let mut out: Vec<CalendarDay> = days
        .iter()
        .zip(kcal)
        .zip(weighed)
        .map(|((&day, &kcal), &weighed)| CalendarDay { day, kcal, weighed })
        .collect();
    if let Some(last) = out.last().map(|d| d.day) {
        let mut next = last.plus_days(1);
        while next.0.month() == last.0.month() {
            out.push(CalendarDay {
                day: next,
                kcal: None,
                weighed: false,
            });
            next = next.plus_days(1);
        }
    }
    out
}

/// What a pressed day does, for calendars that pick a day.
pub type Pick = Rc<dyn Fn(Day)>;

/// The calendar of one month; with `pick`, a day with records is pressable.
pub fn calendar(
    days: Vec<CalendarDay>,
    goal: Option<f64>,
    start: WeekStart,
    pick: Option<Pick>,
) -> impl IntoElement {
    let today = untracked(clock::today);
    let rows = weeks(&days, start);
    let heads = rows
        .first()
        .map(|_| {
            // Any seven consecutive days name the columns; take the week
            // that starts on `start` around the month's first day.
            let first = days[0].day;
            let lead = rows[0].iter().take_while(|c| c.is_none()).count() as i32;
            (0..7)
                .map(|i| s().weekday_short(first.plus_days(i - lead)))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    view()
        .gap(px(6.0))
        .child(
            view()
                .flex_row()
                .gap(px(4.0))
                .children(heads.into_iter().map(|head| {
                    text(head)
                        .typo(Type::Caption)
                        .text_color(color::MUTED)
                        .text_center()
                        .number_of_lines(1)
                        .flex_1()
                })),
        )
        .children(rows.into_iter().map(move |week| {
            let pick = pick.clone();
            view()
                .flex_row()
                .gap(px(4.0))
                .children(week.map(move |cell| day_cell(cell, goal, today, pick.clone())))
        }))
}

fn day_cell(
    cell: Option<CalendarDay>,
    goal: Option<f64>,
    today: Day,
    pick: Option<Pick>,
) -> AnyElement {
    let Some(cell) = cell else {
        return view().flex_1().h(px(CELL)).into_element();
    };
    let over = matches!((cell.kcal, goal), (Some(k), Some(g)) if g > 0.0 && k > g);
    let future = cell.day > today;
    let (fill, ink) = match cell.kcal {
        Some(_) if over => (Some(color::CAUTION_SOFT), color::CAUTION),
        Some(kcal) => (Some(color::HEAT.opacity(shade(kcal, goal))), color::INK),
        None if future => (None, color::FAINT.opacity(0.5)),
        // A weight alone makes a day a place to go when picking.
        None if cell.weighed && pick.is_some() => (None, color::BODY),
        None => (None, color::FAINT),
    };
    let label = match cell.kcal {
        Some(kcal) => format!(
            "{}, {} {}",
            s().long_date(cell.day),
            crate::domain::format::kcal(kcal),
            s().kcal
        ),
        None => s().long_date(cell.day),
    };
    let face = view()
        .flex_1()
        .h(px(CELL))
        .items_center()
        .justify_center()
        .gap(px(2.0))
        .rounded(px(radius::BADGE + 4.0))
        .style_when(
            move || fill.is_some(),
            move |s| s.bg(fill.unwrap_or(color::TRACK)),
        )
        .style_when(
            move || cell.day == today,
            |s| s.border(px(1.5)).border_color(color::INK),
        )
        .child(
            text(cell.day.0.day().to_string())
                .typo(Type::Caption)
                .tabular_nums()
                .text_color(ink),
        )
        .child(view().size(px(4.0)).rounded_full().bg(if cell.weighed {
            color::MUTED
        } else {
            AdaptiveColor::TRANSPARENT
        }));
    let recorded = cell.kcal.is_some() || cell.weighed;
    match pick.filter(|_| recorded) {
        Some(pick) => button()
            .on_press(move || pick(cell.day))
            .flex_1()
            .rounded(px(radius::BADGE + 4.0))
            .active(|s| s.opacity(0.6))
            .accessibility_label(move || Some(label.clone().into()))
            .child(face)
            .into_element(),
        None => view()
            .flex_1()
            .accessible(true)
            .label(SharedString::from(label))
            .child(face)
            .into_element(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(text: &str) -> Day {
        Day(text.parse().unwrap())
    }

    #[test]
    fn weeks_pad_to_the_chosen_first_weekday() {
        // November 2026 starts on a Sunday.
        let days = month_days(
            &[day("2026-11-01"), day("2026-11-02")],
            &[None, Some(1800.0)],
            &[false, true],
        );
        assert_eq!(days.len(), 30);
        let monday = weeks(&days, WeekStart::Monday);
        assert_eq!(monday[0].iter().filter(|c| c.is_none()).count(), 6);
        assert_eq!(monday[0][6].unwrap().day, day("2026-11-01"));
        assert_eq!(monday.len(), 6);
        let sunday = weeks(&days, WeekStart::Sunday);
        assert_eq!(sunday[0][0].unwrap().day, day("2026-11-01"));
        assert_eq!(sunday.len(), 5);
        assert!(days[1].weighed && days[1].kcal == Some(1800.0));
        assert!(days[29].kcal.is_none());
    }

    #[test]
    fn shade_follows_the_goal_with_a_floor() {
        assert_eq!(shade(0.0, Some(2000.0)), 0.3);
        assert_eq!(shade(2000.0, Some(2000.0)), 1.0);
        assert_eq!(shade(3000.0, Some(2000.0)), 1.0);
        assert_eq!(shade(500.0, None), 1.0);
    }
}
