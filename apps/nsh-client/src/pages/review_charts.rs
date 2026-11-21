//! The Review tab's charts: a bar per day against the goal, the average
//! macros, and the weight's line.

use nsh_core::prelude::*;

use crate::{
    data::clock,
    domain::{format, meal::Day, review::Intake},
    i18n::s,
    ui::{
        Btn, Type, Typo, color,
        trend::{InspectionPlot, Sample, date_caption},
    },
};

/// The chart's height.
const CHART: f32 = 120.0;

/// A bar per day against the goal's line; amber past it, ink for today,
/// a blank column for a day without meals (never a zero bar). Weekdays under a
/// week; every seventh day's date under a month.
pub fn chart(days: Vec<Day>, kcal: Vec<Option<f64>>, goal: Option<f64>) -> impl IntoElement {
    let today = untracked(clock::today);
    let top = kcal
        .iter()
        .flatten()
        .copied()
        .chain(goal)
        .fold(1.0_f64, f64::max)
        * 1.08;
    let month = days.len() > 7;
    let gap = if month { 3.0 } else { 10.0 };
    let bars = days.iter().zip(&kcal).map(|(day, kcal)| {
        let color = match (kcal, goal) {
            _ if *day == today => color::INK,
            (Some(k), Some(g)) if *k > g => color::CAUTION,
            // Ordinary days sit one ink step below today's full bar; a
            // deeper fill would read as emphasis the number does not carry.
            _ => color::INK.opacity(0.42),
        };
        let reading = kcal.map_or_else(
            || s().no_records.to_owned(),
            |k| format!("{} {}", format::kcal(k), s().kcal),
        );
        // Every day keeps a faint track so a sparse week still reads as a
        // week; only logged days get a filled bar (no meals is never zero).
        view()
            .flex_1()
            .h_full()
            .justify_end()
            .bg(color::TRACK.opacity(0.7))
            .rounded(px(if month { 3.0 } else { 7.0 }))
            .overflow_hidden()
            .label(format!("{}, {reading}", s().short_date(*day)))
            .child(kcal.map(|k| {
                view()
                    .h(px(((k / top) as f32 * CHART).max(1.0)))
                    .rounded(px(if month { 3.0 } else { 7.0 }))
                    .bg(color)
            }))
    });
    let labels = days.iter().enumerate().map(move |(i, day)| {
        let shown = !month || i % 7 == 0;
        text(if shown {
            if month {
                day.0.day().to_string()
            } else {
                s().weekday_short(*day).to_owned()
            }
        } else {
            String::new()
        })
        .typo(Type::Caption)
        .tabular_nums()
        .text_color(color::MUTED)
        .text_center()
        .number_of_lines(1)
        .flex_1()
    });
    view()
        .gap(px(8.0))
        .child(goal.map(|g| {
            text(format!("{} {}", s().chart_goal, format::kcal(g)))
                .typo(Type::Caption)
                .text_color(color::MUTED)
                .text_right()
        }))
        .child(
            view()
                .h(px(CHART))
                .child(
                    view()
                        .absolute()
                        .inset_0()
                        .flex_row()
                        .items_end()
                        .gap(px(gap))
                        .children(bars),
                )
                .child(goal.map(|g| {
                    view()
                        .absolute()
                        .left_0()
                        .right_0()
                        .bottom(px((g / top) as f32 * CHART))
                        .flex_row()
                        .gap_1()
                        .children(
                            (0..30)
                                .map(|_| view().flex_1().h(px(1.5)).bg(color::MUTED.opacity(0.5))),
                        )
                        .pointer_events(PointerEvents::None)
                })),
        )
        .child(view().flex_row().gap(px(gap)).children(labels))
}

pub fn macros(intake: Memo<Intake>) -> impl IntoElement {
    let mark = |tint: AdaptiveColor,
                name: fn() -> &'static str,
                unit: fn() -> &'static str,
                grams: Box<dyn Fn() -> f64>| {
        view()
            .flex_row()
            .items_center()
            .gap(px(6.0))
            .child(view().size(px(6.0)).rounded_full().bg(tint))
            .child(
                text(move || format!("{} {}{}", name(), format::grams(grams()), unit()))
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_color(color::MUTED),
            )
    };
    let avg = move || intake.with(|i| i.average.unwrap_or_default());
    view()
        .flex_col()
        .gap(px(8.0))
        .child(
            view()
                .flex_row()
                .gap_4()
                .child(mark(
                    color::PROTEIN,
                    || s().protein,
                    || "g",
                    Box::new(move || avg().protein),
                ))
                .child(mark(
                    color::CARBS,
                    || s().carbs,
                    || "g",
                    Box::new(move || avg().carbs),
                ))
                .child(mark(
                    color::FAT,
                    || s().fat,
                    || "g",
                    Box::new(move || avg().fat),
                )),
        )
        .child(when(
            move || avg().extra.is_some(),
            move || {
                let extra = avg().extra.unwrap_or_default();
                view()
                    .flex_row()
                    .gap_4()
                    .child(mark(
                        color::MUTED,
                        || s().fiber,
                        || "g",
                        Box::new(move || extra.fiber),
                    ))
                    .child(mark(
                        color::MUTED,
                        || s().sugars,
                        || "g",
                        Box::new(move || extra.sugars),
                    ))
                    .child(mark(
                        color::MUTED,
                        || s().sodium,
                        || s().mg_unit,
                        Box::new(move || extra.sodium * 1000.0),
                    ))
                    .child(mark(
                        color::MUTED,
                        || s().sat_fat,
                        || "g",
                        Box::new(move || extra.sat_fat),
                    ))
            },
        ))
}

/// Health keeps its selected review period and original measured precision.
pub fn health_trend(
    title: String,
    first: Day,
    last: Day,
    points: Vec<(Day, Option<f64>)>,
    goal: Option<f64>,
    tint: AdaptiveColor,
    format: fn(f64) -> String,
) -> AnyElement {
    let mut values = points.iter().filter_map(|p| p.1);
    let Some(initial) = values.next() else {
        return view().into_element();
    };
    let (low, high) = values.fold((initial, initial), |(l, h), v| (l.min(v), h.max(v)));
    let pad = ((1.0 - (high - low)) / 2.0).max(0.0) + 0.2;
    let samples = points
        .into_iter()
        .map(|(day, y)| Sample {
            day: day.0,
            y,
            caption: date_caption(day.0, first.0, last.0),
            value: y.map(format).unwrap_or_else(|| "—".into()),
        })
        .collect();
    let expanded = signal(false);
    view()
        .gap_1()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    text(title.clone())
                        .typo(Type::Headline)
                        .text_color(color::BODY)
                        .flex_1(),
                )
                .child(
                    Btn::ghost()
                        .label(move || {
                            if expanded.get() {
                                crate::i18n::catalog::copy("Collapse", "收起")
                            } else {
                                crate::i18n::catalog::copy("Expand chart", "展开图表")
                            }
                            .into()
                        })
                        .on_press(move || expanded.update(|v| *v = !*v)),
                ),
        )
        .child(
            InspectionPlot {
                title,
                from: first.0,
                end: last.0,
                domain: [low - pad, high + pad],
                samples,
                color: tint,
                goal,
            }
            .draw(move || if expanded.get() { 180.0 } else { 88.0 }),
        )
        .into_element()
}
