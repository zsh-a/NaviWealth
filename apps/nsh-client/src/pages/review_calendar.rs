//! A month in review as a calendar: one cell per day, shaded by how much of
//! the goal was eaten (amber past it), empty for a day without meals, a dot
//! under a day with a weight, today outlined. It replaces the month's bars,
//! where 31 thin columns were hard to read.

use std::{collections::BTreeMap, rc::Rc};

use nsh_base::{CalendarEntry, CalendarItemKind, Date, Matcher};
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
    pub has_transactions: bool,
}

/// How strongly a logged day is shaded: its share of the goal, kept above a
/// floor so a light day still reads as logged; a full shade without a goal.
pub fn shade(kcal: f64, goal: Option<f64>) -> f32 {
    match goal {
        Some(goal) if goal > 0.0 => (0.3 + 0.7 * (kcal / goal).clamp(0.0, 1.0)) as f32,
        _ => 1.0,
    }
}

/// The month's days through its last day: the reviewed `days` with their
/// records, then the days still to come (no records, never shaded).
pub fn month_days(days: &[Day], kcal: &[Option<f64>], weighed: &[bool]) -> Vec<CalendarDay> {
    let mut out: Vec<CalendarDay> = days
        .iter()
        .zip(kcal)
        .zip(weighed)
        .map(|((&day, &kcal), &weighed)| CalendarDay {
            day,
            kcal,
            weighed,
            has_transactions: false,
        })
        .collect();
    if let Some(last) = out.last().map(|d| d.day) {
        let mut next = last.plus_days(1);
        while next.0.month() == last.0.month() {
            out.push(CalendarDay {
                day: next,
                kcal: None,
                weighed: false,
                has_transactions: false,
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
) -> AnyElement {
    let Some(first) = days.first() else {
        return view().into_element();
    };
    let anchor = Date::Single(first.day.to_string().parse().ok());
    let today = untracked(clock::today);
    let cells: Rc<BTreeMap<String, CalendarDay>> = Rc::new(
        days.into_iter()
            .map(|cell| (cell.day.to_string(), cell))
            .collect(),
    );
    let enabled = cells.clone();
    let can_pick = pick.is_some();
    nsh_base::calendar()
        // The surrounding Review / Records task owns month navigation.
        .value(anchor)
        .header_style(|s| s.hidden())
        .first_day_of_week(match start {
            WeekStart::Sunday => 0u32,
            WeekStart::Monday => 1u32,
        })
        .disabled_matcher(Matcher::custom(move |date| {
            !can_pick
                || enabled.get(&date.to_string()).is_none_or(|cell| {
                    cell.day > today
                        || (cell.kcal.is_none() && !cell.weighed && !cell.has_transactions)
                })
        }))
        .month_style(|s| s.gap(px(6.0)))
        .row_style(|s| s.gap(px(4.0)))
        .item_class("data-outside:invisible active:opacity-60 focus-visible:outline-2 focus-visible:outline-foreground")
        .item_style(|s| s.rounded(px(radius::BADGE + 4.0)))
        .render_item(move |item: &CalendarEntry| match item.kind {
            CalendarItemKind::Weekday => {
                text(s().weekday_short(Day(jiff::civil::date(2026, 11, 1)).plus_days(item.value)))
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .text_center()
                    .number_of_lines(1)
                    .into_element()
            }
            CalendarItemKind::Day => item
                .date
                .as_ref()
                .and_then(|date| cells.get(date.as_str()))
                .filter(|_| !item.outside)
                .map(|cell| day_face(*cell, goal, today, can_pick))
                .unwrap_or_else(|| view().h(px(CELL)).into_element()),
            _ => view().into_element(),
        })
        .on_change(move |date: &Date| {
            if let Some(pick) = &pick
                && let Some(day) = date.start().and_then(|date| date.to_string().parse().ok())
            {
                pick(day);
            }
        })
        .into_element()
}

fn day_face(cell: CalendarDay, goal: Option<f64>, today: Day, can_pick: bool) -> AnyElement {
    let over = matches!((cell.kcal, goal), (Some(k), Some(g)) if g > 0.0 && k > g);
    let future = cell.day > today;
    let (fill, ink) = match cell.kcal {
        Some(_) if over => (Some(color::CAUTION_SOFT), color::CAUTION),
        Some(kcal) => (Some(color::HEAT.opacity(shade(kcal, goal))), color::INK),
        None if future => (None, color::FAINT.opacity(0.5)),
        // A weight alone makes a day a place to go when picking.
        None if (cell.weighed || cell.has_transactions) && can_pick => (None, color::BODY),
        None => (None, color::MUTED),
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
    view()
        .w_full()
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
        .child(
            view()
                .size(px(4.0))
                .rounded_full()
                .bg(if cell.weighed || cell.has_transactions {
                    color::MUTED
                } else {
                    AdaptiveColor::TRANSPARENT
                }),
        )
        .accessible(true)
        .label(SharedString::from(label))
        .into_element()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(text: &str) -> Day {
        Day(text.parse().unwrap())
    }

    #[test]
    fn the_month_keeps_records_and_pads_future_days_without_inventing_them() {
        let days = month_days(
            &[day("2026-11-01"), day("2026-11-02")],
            &[None, Some(1800.0)],
            &[false, true],
        );
        assert_eq!(days.len(), 30);
        assert_eq!(days[0].day, day("2026-11-01"));
        assert!(days[1].weighed && days[1].kcal == Some(1800.0));
        assert!(
            days[2..]
                .iter()
                .all(|day| day.kcal.is_none() && !day.weighed && !day.has_transactions)
        );
    }

    #[component]
    fn CalendarFixture() -> impl IntoElement {
        let monday = signal(false);
        let december = signal(false);
        let picked = signal(String::new());
        view()
            .w(px(350.0))
            .child(
                nsh_base::button()
                    .child(text("Monday first"))
                    .on_press(move || monday.set(true)),
            )
            .child(
                nsh_base::button()
                    .child(text("December"))
                    .on_press(move || december.set(true)),
            )
            .child(dynamic(move || {
                let first = day(if december.get() {
                    "2020-12-01"
                } else {
                    "2020-11-01"
                });
                let mut cells = month_days(
                    &(0..4).map(|n| first.plus_days(n)).collect::<Vec<_>>(),
                    &[None, Some(1800.0), None, None],
                    &[false, false, true, false],
                );
                cells[3].has_transactions = true;
                calendar(
                    cells,
                    Some(2000.0),
                    if monday.get() {
                        WeekStart::Monday
                    } else {
                        WeekStart::Sunday
                    },
                    Some(Rc::new(move |day| picked.set(day.to_string()))),
                )
            }))
            .child(text(move || format!("Picked {}", picked.get())))
    }

    #[test]
    fn official_calendar_keeps_local_week_alignment_and_record_only_picking() -> Result<(), String>
    {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        let mut app = Headless::start(EngineConfig::new(Root::of::<CalendarFixture>())).unwrap();
        app.wait_for("label:2020-11-01")?;
        let first = app.screen().layout("label:2020-11-01")?.unwrap().bounds;
        let second = app.screen().layout("label:2020-11-02")?.unwrap().bounds;
        assert!(first.origin.x < second.origin.x);
        assert_eq!(first.origin.y, second.origin.y);
        assert!(!app.screen().enabled("label:2020-11-01")?);
        assert!(app.screen().enabled("label:2020-11-02")?);
        assert!(app.screen().enabled("label:2020-11-03")?);
        assert!(app.screen().enabled("label:2020-11-04")?);
        assert!(!app.screen().enabled("label:2020-11-05")?);
        app.press("label:2020-11-03")?;
        app.wait_for("Picked 2020-11-03")?;
        app.press("Monday first")?;
        let first = app.screen().layout("label:2020-11-01")?.unwrap().bounds;
        let second = app.screen().layout("label:2020-11-02")?.unwrap().bounds;
        assert!(first.origin.x > second.origin.x);
        assert!(first.origin.y < second.origin.y);
        app.press("December")?;
        app.wait_for("label:2020-12-02")?;
        assert!(!app.shows("label:2020-11-02"));
        app.press("label:2020-12-04")?;
        app.wait_for("Picked 2020-12-04")?;
        Ok(())
    }

    #[test]
    fn future_dates_stay_disabled_even_if_a_source_contains_a_future_record() -> Result<(), String>
    {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        let mut config = EngineConfig::new(Root::of::<CalendarFixture>());
        config.environment.locale_settings.time_zone =
            nsh_core::platform::TimeZone::parse("UTC").unwrap();
        let now: jiff::Timestamp = "2020-11-03T12:00:00Z".parse().unwrap();
        config.clock = nsh_core::time::Clock::manual(
            std::time::UNIX_EPOCH + std::time::Duration::from_millis(now.as_millisecond() as u64),
        );
        let mut app = Headless::start(config).unwrap();
        app.wait_for("label:2020-11-03")?;
        assert!(app.screen().enabled("label:2020-11-03")?);
        assert!(!app.screen().enabled("label:2020-11-04")?);
        Ok(())
    }

    #[test]
    fn shade_follows_the_goal_with_a_floor() {
        assert_eq!(shade(0.0, Some(2000.0)), 0.3);
        assert_eq!(shade(2000.0, Some(2000.0)), 1.0);
        assert_eq!(shade(3000.0, Some(2000.0)), 1.0);
        assert_eq!(shade(500.0, None), 1.0);
    }
}
