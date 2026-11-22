//! Shared pointer, keyboard and accessibility inspection for dated measurements.
use super::{Date, Day};
use crate::{
    i18n::s,
    ui::{Type, Typo, color},
};
use nsh_base::plot::{Curve, PlotAccessibilityValue, Scale, area, grid, line, plot};
use nsh_core::{
    TouchEvent, TouchPhase,
    element::{RowAccessor, Rows},
    prelude::*,
};

pub(crate) struct Sample {
    pub day: Date,
    pub y: Option<f64>,
    pub caption: String,
    pub value: String,
}

/// Coordinates are display-only. Callers supply labels at the metric's native precision.
pub(crate) struct InspectionPlot {
    pub title: String,
    pub from: Date,
    pub end: Date,
    pub domain: [f64; 2],
    pub samples: Vec<Sample>,
    pub color: AdaptiveColor,
    pub goal: Option<f64>,
}

impl InspectionPlot {
    pub fn draw(self, height: impl Fn() -> f32 + Copy + 'static) -> AnyElement {
        let Self {
            title,
            from,
            end,
            domain,
            samples,
            color: tint,
            goal,
        } = self;
        let span = f64::from(Day(end).days_since(Day(from)));
        let x = |d| f64::from(Day(d).days_since(Day(from)));
        let x_domain = if span == 0.0 {
            [-1.0, 1.0]
        } else {
            [0.0, span]
        };
        let mut marks = Vec::new();
        for run in samples.split(|p| p.y.is_none()).filter(|r| !r.is_empty()) {
            let rows = Rows::from_columns(
                run.len(),
                [
                    ("day".into(), run.iter().map(|p| x(p.day)).collect()),
                    ("v".into(), run.iter().map(|p| p.y.unwrap()).collect()),
                ],
            );
            if run.len() > 1 {
                marks.push(
                    area()
                        .data(Some(rows.clone()))
                        .x(Some("day".into()))
                        .y1(Some("v".into()))
                        .y0(Some(domain[0].into()))
                        .curve(Curve::Linear)
                        .fill_color(tint.opacity(0.1))
                        .into_element(),
                );
            }
            marks.push(
                line()
                    .data(Some(rows))
                    .x(Some("day".into()))
                    .y(Some("v".into()))
                    .curve(Curve::Linear)
                    .dot(run.len() == 1)
                    .dot_style(move |s| s.size(px(5.0)).rounded_full().bg(tint))
                    .text_color(tint)
                    .stroke_width(px(2.25))
                    .into_element(),
            );
        }
        if let Some(goal) = goal.filter(|y| (domain[0]..=domain[1]).contains(y)) {
            let rows = Rows::from_columns(
                2,
                [
                    ("day".into(), x_domain.to_vec()),
                    ("v".into(), vec![goal; 2]),
                ],
            );
            marks.push(
                line()
                    .data(Some(rows))
                    .x(Some("day".into()))
                    .y(Some("v".into()))
                    .text_color(color::CARBS)
                    .stroke_width(px(1.0))
                    .into_element(),
            );
        }
        let last = samples.len() - 1;
        let inspected = signal(None::<usize>);
        let current = move || inspected.get().unwrap_or(last);
        let width = signal(0.0_f32);
        let positions = stored(
            samples
                .iter()
                .map(|p| {
                    (
                        ((x(p.day) - x_domain[0]) / (x_domain[1] - x_domain[0])) as f32,
                        p.y.map(|v| (1.0 - (v - domain[0]) / (domain[1] - domain[0])) as f32),
                    )
                })
                .collect::<Vec<_>>(),
        );
        let inspect = move |offset: f32| {
            let w = width.get_untracked();
            if w <= 0.0 {
                return;
            }
            let fraction = (offset / w).clamp(0.0, 1.0);
            let i = positions.with(|p| {
                let right = p.partition_point(|v| v.0 < fraction).min(last);
                if right > 0 && (fraction - p[right - 1].0).abs() <= (p[right].0 - fraction).abs() {
                    right - 1
                } else {
                    right
                }
            });
            inspected.set(Some(i));
        };
        let cursor_x = move || positions.with(|p| p[current()].0) * width.get();
        let rows = Rows::from_columns(
            samples.len(),
            [("day".into(), samples.iter().map(|p| x(p.day)).collect())],
        );
        let labels = stored(
            samples
                .into_iter()
                .map(|p| (p.caption, p.value))
                .collect::<Vec<_>>(),
        );
        view()
            .gap_1()
            .child(
                text(move || labels.with(|v| v[current()].1.clone()))
                    .test_id("trend-value")
                    .typo(Type::Lead)
                    .tabular_nums()
                    .text_color(color::INK)
                    .number_of_lines(1)
                    .shrink_to_fit(0.55),
            )
            .child(
                text(move || labels.with(|v| v[current()].0.clone()))
                    .test_id("trend-date")
                    .typo(Type::Caption)
                    .text_color(color::MUTED),
            )
            .child(
                view()
                    .relative()
                    .h(move || px(height()))
                    .my_2()
                    .on_layout(move |b: &Bounds<Points>| width.set(b.size.width.0))
                    .child(
                        plot()
                            .h_full()
                            .data(rows)
                            .x(Some(RowAccessor::from("day")))
                            .x_scale(Scale::Linear {
                                domain: Some(x_domain),
                                reverse: false,
                            })
                            .y_scale(Scale::Linear {
                                domain: Some(domain),
                                reverse: false,
                            })
                            .interactive(true)
                            .on_hover_change(move |i: &Option<u32>| {
                                inspected.set(i.map(|v| v as usize))
                            })
                            .accessibility_label(move || Some(title.clone().into()))
                            .accessibility_value(move || {
                                Some(PlotAccessibilityValue {
                                    text: Some(
                                        labels
                                            .with(|v| {
                                                format!("{} · {}", v[current()].0, v[current()].1)
                                            })
                                            .into(),
                                    ),
                                    ..Default::default()
                                })
                            })
                            .child(
                                grid()
                                    .y(Some(vec![
                                        domain[0],
                                        (domain[0] + domain[1]) / 2.0,
                                        domain[1],
                                    ]))
                                    .stroke_width(px(0.75))
                                    .text_color(color::LINE),
                            )
                            .children(marks),
                    )
                    .child(when(
                        move || inspected.get().is_some(),
                        move || {
                            view()
                                .absolute()
                                .top_0()
                                .bottom_0()
                                .left(move || px(cursor_x()))
                                .w(px(1.0))
                                .bg(color::FAINT)
                                .pointer_events(PointerEvents::None)
                        },
                    ))
                    .child(dynamic(move || {
                        let cy = positions.with(|p| p[current()].1);
                        cy.map(|v| {
                            view()
                                .absolute()
                                .left(move || px(cursor_x() - 4.0))
                                .top(move || px(v * height() - 4.0))
                                .size(px(8.0))
                                .rounded_full()
                                .bg(tint)
                                .border_1()
                                .border_color(color::SURFACE)
                                .pointer_events(PointerEvents::None)
                        })
                        .unwrap_or_else(view)
                        .into_element()
                    }))
                    .child(
                        view()
                            .absolute()
                            .inset_0()
                            .test_id("trend-inspector")
                            .on_touch(move |e: &TouchEvent| {
                                if e.phase == TouchPhase::Cancel {
                                    inspected.set(None);
                                } else if let Some(p) = e.points.iter().find(|p| p.changed) {
                                    inspect(p.location.x.0);
                                }
                            })
                            .on_mouse_move(move |e: &MouseEvent| inspect(e.position.x.0))
                            .on_mouse_leave(move |_: &MouseEvent| inspected.set(None)),
                    ),
            )
            .child((from != end).then(|| {
                view()
                    .flex_row()
                    .justify_between()
                    .child(
                        text(s().axis_date(Day(from), from.year() != end.year()))
                            .typo(Type::Caption)
                            .tabular_nums()
                            .text_color(color::MUTED),
                    )
                    .child({
                        text(s().axis_date(Day(end), from.year() != end.year()))
                            .typo(Type::Caption)
                            .tabular_nums()
                            .text_color(color::MUTED)
                    })
            }))
            .into_element()
    }
}
