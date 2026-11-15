//! The Review tab's charts: a bar per day against the goal, the average
//! macros, and the weight's line.

use nsh_base::plot::{Scale, line, plot};
use nsh_core::{
    element::{RowAccessor, Rows},
    prelude::*,
};

use crate::{
    data::clock,
    domain::{format, meal::Day, review::Intake, weight::Weight},
    i18n::s,
    ui::{Type, Typo, color},
};

/// The chart's height.
const CHART: f32 = 120.0;

/// A bar per day against the goal's line; amber past it, ink for today,
/// nothing for a day without meals (never a zero bar). Weekdays under a
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
            _ => color::LINE_STRONG,
        };
        view().flex_1().h_full().justify_end().child(kcal.map(|k| {
            view()
                .h(px((k / top) as f32 * CHART))
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
                        .h(px(1.0))
                        .bg(color::MUTED.opacity(0.5))
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

/// The period's weights as a line, each at its day, with the goal weight as
/// a second line when it sits inside the drawn range; nothing with fewer
/// than two points.
pub fn trend(first: Day, span: f64, points: Vec<Weight>, goal: Option<f64>) -> AnyElement {
    if points.len() < 2 {
        return view().into_element();
    }
    let (days, kgs): (Vec<f64>, Vec<f64>) = points
        .iter()
        .map(|w| (f64::from(w.day.days_since(first)), w.kg))
        .unzip();
    let low = kgs.iter().copied().fold(f64::INFINITY, f64::min);
    let high = kgs.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    // At least 1 kg of range, so a flat week stays flat.
    let pad = ((1.0 - (high - low)) / 2.0).max(0.0) + 0.2;
    let rows = Rows::from_columns(days.len(), [("day".into(), days), ("kg".into(), kgs)]);
    let line = plot()
        .h(px(64.0))
        .data(rows)
        .x(Some(RowAccessor::from("day")))
        .y(Some(RowAccessor::from("kg")))
        .x_scale(Scale::Linear {
            domain: Some([0.0, (span - 1.0).max(1.0)]),
            reverse: false,
        })
        .y_scale(Scale::Linear {
            domain: Some([low - pad, high + pad]),
            reverse: false,
        })
        .interactive(false)
        .child(line().text_color(color::INK).stroke_width(px(2.0)))
        .child(match goal {
            // The goal rides the drawn range only; outside it the tiles
            // carry the distance instead.
            Some(goal) if (low - pad..=high + pad).contains(&goal) => {
                let goal_rows = Rows::from_columns(
                    2,
                    [
                        ("day".into(), vec![0.0, (span - 1.0).max(1.0)]),
                        ("goal".into(), vec![goal, goal]),
                    ],
                );
                line()
                    .data(goal_rows)
                    .x(Some(RowAccessor::from("day")))
                    .y(Some(RowAccessor::from("goal")))
                    .text_color(color::CAUTION)
                    .stroke_width(px(1.0))
                    .into_element()
            }
            _ => view().into_element(),
        });
    let caption = |kg| {
        text(format!("{} kg", s().kg(kg)))
            .typo(Type::Caption)
            .tabular_nums()
            .text_color(color::MUTED)
    };
    view()
        .gap_1()
        .child(
            text(|| s().trend_average)
                .typo(Type::Caption)
                .text_color(color::MUTED),
        )
        .child(caption(high))
        .child(line)
        .child(caption(low))
        .into_element()
}

/// The period's estimated body-fat shares as a line, each at its day;
/// nothing with fewer than two.
pub fn trend_percent(first: Day, span: f64, points: Vec<(Day, f64)>) -> AnyElement {
    if points.len() < 2 {
        return view().into_element();
    }
    let (days, shares): (Vec<f64>, Vec<f64>) = points
        .iter()
        .map(|(day, fat)| (f64::from(day.days_since(first)), *fat))
        .unzip();
    let low = shares.iter().copied().fold(f64::INFINITY, f64::min);
    let high = shares.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let pad = ((1.0 - (high - low)) / 2.0).max(0.0) + 0.2;
    let rows = Rows::from_columns(days.len(), [("day".into(), days), ("fat".into(), shares)]);
    let line = plot()
        .h(px(64.0))
        .data(rows)
        .x(Some(RowAccessor::from("day")))
        .y(Some(RowAccessor::from("fat")))
        .x_scale(Scale::Linear {
            domain: Some([0.0, (span - 1.0).max(1.0)]),
            reverse: false,
        })
        .y_scale(Scale::Linear {
            domain: Some([low - pad, high + pad]),
            reverse: false,
        })
        .interactive(false)
        .child(line().text_color(color::CAUTION).stroke_width(px(2.0)));
    let caption = |share| {
        text(format!("{share:.1}%"))
            .typo(Type::Caption)
            .tabular_nums()
            .text_color(color::MUTED)
    };
    view()
        .gap_1()
        .child(caption(high))
        .child(line)
        .child(caption(low))
        .into_element()
}
