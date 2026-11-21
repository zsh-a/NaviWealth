//! Inspect dated observations without changing their stored precision.
use super::{Type, Typo, chip, color, currency, surface::card};
use crate::{
    domain::meal::Day,
    i18n::{s, statement_import::copy},
};
use jiff::civil::Date;
use navi_finance::{currency::Currency, holdings};
use nsh_base::plot::{Curve, PlotAccessibilityValue, Scale, area, grid, line, plot};
use nsh_core::{
    TouchEvent, TouchPhase,
    element::{RowAccessor, Rows},
    prelude::*,
};

pub type Point = (Date, Option<i64>);

#[derive(Clone, Copy)]
pub enum Unit {
    Money,
    Price(Currency),
    Rate,
}

impl Unit {
    fn format(self, n: i64) -> String {
        match self {
            Self::Money => currency::format(n, Currency::CNY),
            Self::Price(c) => currency::unit_price(n, c),
            Self::Rate => holdings::format_units(n),
        }
    }
}

#[derive(Clone, Copy, PartialEq, Default)]
pub enum Window {
    Week,
    #[default]
    Month,
    All,
}

impl Window {
    fn label(self) -> &'static str {
        match self {
            Self::Week => copy("7D", "7天"),
            Self::Month => copy("30D", "30天"),
            Self::All => copy("All", "全部"),
        }
    }
}

/// Inputs are in ascending date order. An explicit missing valuation breaks its line.
pub fn chart(title: String, points: Vec<Point>, unit: Unit, window: Signal<Window>) -> AnyElement {
    let (Some(&(start, _)), Some(&(end, _))) = (points.first(), points.last()) else {
        return card()
            .p_5()
            .gap_2()
            .child(text(title).typo(Type::Headline).text_color(color::INK))
            .child(
                text(copy("No observations yet", "暂无历史记录"))
                    .typo(Type::Subhead)
                    .text_color(color::MUTED),
            )
            .into_element();
    };
    let span = Day(end).days_since(Day(start));
    let active = move || match window.get() {
        Window::All if span <= 30 => Window::Month,
        other => other,
    };
    let options = [Window::Week, Window::Month, Window::All]
        .into_iter()
        .filter(move |w| span > 7 && (*w != Window::All || span > 30));
    let title = stored(title);
    let data = stored(points);
    card()
        .p_4()
        .gap_2()
        .child(
            view()
                .flex_row()
                .items_center()
                .flex_wrap()
                .gap_2()
                .child(
                    text(move || title.get())
                        .typo(Type::Headline)
                        .text_color(color::BODY)
                        .flex_1(),
                )
                .children(options.map(move |w| {
                    chip(
                        move || w.label().into(),
                        move || active() == w,
                        move || window.set(w),
                    )
                    .min_w(px(42.0))
                    .px_2()
                })),
        )
        .child(dynamic(move || {
            let period = active();
            let days = match period {
                Window::Week => 7,
                Window::Month => 30,
                Window::All => span,
            };
            let from = Day(end).plus_days(-days).0.max(start);
            data.with(|points| {
                let visible = &points[points.partition_point(|p| p.0 < from)..];
                untracked(|| series(title.get(), visible, unit, from, end))
            })
        }))
        .into_element()
}

fn series(title: String, points: &[Point], unit: Unit, from: Date, end: Date) -> AnyElement {
    let height = if points.len() == 1 { 64.0 } else { 152.0 };
    let Some(low) = points.iter().filter_map(|p| p.1).min() else {
        return text(copy(
            "No complete observations in this period",
            "此时段暂无完整数据",
        ))
        .typo(Type::Subhead)
        .text_color(color::MUTED)
        .py_4()
        .into_element();
    };
    let high = points.iter().filter_map(|p| p.1).max().unwrap();
    // Subtract in integer space before projecting to pixels (e.g. one cent near i64::MAX).
    let y = |v| (i128::from(v) - i128::from(low)) as f64;
    let extent = y(high);
    let pad = (extent * 0.13).max(1.0);
    let domain = [-pad, extent + pad];
    let span = f64::from(Day(end).days_since(Day(from)));
    let x = |d| f64::from(Day(d).days_since(Day(from)));
    let x_domain = if span == 0.0 {
        [-1.0, 1.0]
    } else {
        [0.0, span]
    };
    let mut marks = Vec::new();
    for run in points.split(|p| p.1.is_none()).filter(|r| !r.is_empty()) {
        let rows = Rows::from_columns(
            run.len(),
            [
                ("day".into(), run.iter().map(|p| x(p.0)).collect()),
                ("v".into(), run.iter().map(|p| y(p.1.unwrap())).collect()),
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
                    .fill_color(color::INK.opacity(0.055))
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
                .dot_style(|s| s.size(px(5.0)).rounded_full().bg(color::INK))
                .text_color(color::INK)
                .stroke_width(px(2.25))
                .into_element(),
        );
    }
    // Include incomplete days in the inspection index so touching a gap reads as missing.
    let baseline = points.first().and_then(|p| p.1);
    let labels = stored(
        points
            .iter()
            .map(|&(day, value)| {
                let date = if from.year() == end.year() {
                    s().long_date(Day(day))
                } else {
                    day.to_string()
                };
                let value_label = value.map(|v| unit.format(v)).unwrap_or_else(|| "—".into());
                let change = value
                    .zip(baseline)
                    .and_then(|(current, start)| current.checked_sub(start));
                let detail = match change {
                    Some(delta) if delta != 0 => format!(
                        "{date}  ·  {} {}{}",
                        copy("From start", "较期初"),
                        if delta > 0 { "+" } else { "" },
                        unit.format(delta)
                    ),
                    _ => date.clone(),
                };
                (detail, value_label)
            })
            .collect::<Vec<_>>(),
    );
    let last = points.len() - 1;
    let inspected = signal(None::<usize>);
    let current = move || inspected.get().unwrap_or(last);
    let width = signal(0.0_f32);
    let positions = stored(
        points
            .iter()
            .map(|p| {
                (
                    ((x(p.0) - x_domain[0]) / (x_domain[1] - x_domain[0])) as f32,
                    p.1.map(|v| (1.0 - (y(v) - domain[0]) / (domain[1] - domain[0])) as f32),
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
        points.len(),
        [("day".into(), points.iter().map(|p| x(p.0)).collect())],
    );
    let summary = format!(
        "{} {} – {}",
        s().value_range,
        unit.format(low),
        unit.format(high)
    );
    view()
        .gap_1()
        .child(
            text(move || labels.with(|v| v[current()].1.clone()))
                .test_id("trend-value")
                .typo(Type::LargeTitle)
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
                .h(px(height))
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
                                .y(Some(vec![domain[0], extent / 2.0, domain[1]]))
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
                            .top(px(v * height - 4.0))
                            .size(px(8.0))
                            .rounded_full()
                            .bg(color::INK)
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
                    text(from.to_string())
                        .typo(Type::Caption)
                        .tabular_nums()
                        .text_color(color::MUTED),
                )
                .child({
                    text(end.to_string())
                        .typo(Type::Caption)
                        .tabular_nums()
                        .text_color(color::MUTED)
                })
        }))
        .child((low != high).then(|| {
            text(summary)
                .pt_1()
                .typo(Type::Caption)
                .tabular_nums()
                .text_color(color::MUTED)
        }))
        .into_element()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    #[component]
    fn TrendProbe() -> impl IntoElement {
        let day = Day(jiff::civil::date(2026, 11, 20));
        chart(
            "Net worth".into(),
            vec![
                (day.plus_days(-2).0, Some(100)),
                (day.plus_days(-1).0, None),
                (day.0, Some(-200)),
            ],
            Unit::Money,
            signal(Window::Month),
        )
    }

    #[test]
    fn keyboard_and_touch_inspect_the_same_gap_without_inventing_a_value() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<TrendProbe>())).unwrap();
        app.wait_for("text:−¥2.00").unwrap();
        app.set_environment("desktop keyboard", |e| e.os = nsh_core::platform::Os::Linux)
            .unwrap();
        app.press_key("tab").unwrap();
        app.press_key("home").unwrap();
        app.wait_for("text:¥1.00").unwrap();
        app.press_key("right").unwrap();
        app.wait_for("text:—").unwrap();
        app.press_key("end").unwrap();
        app.wait_for("text:−¥2.00").unwrap();
        app.drag_and_hold(
            "id:trend-inspector",
            nsh_core::geometry::point(px(1.0), px(0.0)),
        )
        .unwrap();
        app.wait_for("text:—").unwrap();
        app.drop_held().unwrap();
    }
}
