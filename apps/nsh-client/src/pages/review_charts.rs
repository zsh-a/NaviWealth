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
    let mark = |tint: AdaptiveColor, name: fn() -> &'static str, grams: Box<dyn Fn() -> f64>| {
        view()
            .flex_row()
            .items_center()
            .gap(px(6.0))
            .child(view().size(px(6.0)).rounded_full().bg(tint))
            .child(
                text(move || format!("{} {}g", name(), format::grams(grams())))
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_color(color::MUTED),
            )
    };
    let avg = move || intake.with(|i| i.average.unwrap_or_default());
    view()
        .flex_row()
        .gap_4()
        .child(mark(
            color::PROTEIN,
            || s().protein,
            Box::new(move || avg().protein),
        ))
        .child(mark(
            color::CARBS,
            || s().carbs,
            Box::new(move || avg().carbs),
        ))
        .child(mark(color::FAT, || s().fat, Box::new(move || avg().fat)))
}

/// The period's weights as a line, each at its day; nothing with fewer
/// than two.
pub fn trend(first: Day, span: f64, points: Vec<Weight>) -> AnyElement {
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
    plot()
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
        .into_element()
}
