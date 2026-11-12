//! Exact financial labels with official plot geometry. Missing intervals are separate marks.
use super::*;
use nsh_base::plot::{
    self, AppearKey, BandScale, ColorScale, Curve, OrdinalScale, PlotMotion, Scale,
};
use nsh_core::element::{RowAccessor, RowText, Rows, Timing};
use rust_decimal::{Decimal, prelude::ToPrimitive};
use std::sync::Arc;

pub fn plot_motion() -> PlotMotion {
    if reduce_motion() {
        return PlotMotion::default();
    }
    PlotMotion {
        pointer: Some(settle_spring()),
        enter: Some(Timing::new(120.0, Easing::EaseOut)),
        exit: Some(Timing::new(100.0, Easing::EaseOut)),
        appear: Some(Timing::new(220.0, Easing::EaseOut)),
        update: None,
    }
}
fn rows(xs: Vec<f64>, ys: Vec<f64>) -> Rows {
    Rows::from_columns(xs.len(), [("x".into(), xs), ("y".into(), ys)])
}
/// Normalize before floating conversion so cents on a large balance remain visible.
fn position(value: Decimal, low: Decimal, high: Decimal) -> f64 {
    if low == high {
        return 0.5;
    }
    value
        .checked_sub(low)
        .and_then(|v| v.checked_div(high.checked_sub(low)?))
        .and_then(|v| v.to_f64())
        .unwrap_or_else(|| {
            let (v, l, h) = (
                value.to_f64().unwrap_or_default(),
                low.to_f64().unwrap_or_default(),
                high.to_f64().unwrap_or(1.0),
            );
            (v - l) / (h - l)
        })
}
pub(super) struct TrendGeometry {
    pub all: Rows,
    pub segments: Vec<Rows>,
    pub last: usize,
}
pub(super) fn trend_geometry(points: &[(String, Option<Decimal>)]) -> TrendGeometry {
    let known = points.iter().filter_map(|(_, v)| *v).collect::<Vec<_>>();
    let low = known.iter().copied().min().unwrap_or_default();
    let high = known.iter().copied().max().unwrap_or_default();
    let values = points
        .iter()
        .map(|(_, v)| v.map(|v| position(v, low, high)).unwrap_or(f64::NAN))
        .collect::<Vec<_>>();
    let all = rows(
        (0..points.len()).map(|i| i as f64).collect(),
        values.clone(),
    );
    let mut segments = vec![];
    let mut xs = vec![];
    let mut ys = vec![];
    let mut last = 0;
    for (i, v) in values.into_iter().enumerate() {
        if v.is_finite() {
            xs.push(i as f64);
            ys.push(v);
            last = i;
        } else if !xs.is_empty() {
            segments.push(rows(std::mem::take(&mut xs), std::mem::take(&mut ys)));
        }
    }
    if !xs.is_empty() {
        segments.push(rows(xs, ys));
    }
    TrendGeometry {
        all,
        segments,
        last,
    }
}
pub fn trend_plot(
    points: Vec<(String, Option<Decimal>)>,
    currency: String,
    cash: bool,
) -> impl Element {
    let model = trend_geometry(&points);
    let last = model.last;
    let count = points.len();
    let hovered = signal(None::<u32>);
    let points = Arc::new(points);
    let tooltip_points = points.clone();
    let tooltip = move || {
        hovered
            .get()
            .and_then(|i| tooltip_points.get(i as usize))
            .map(|(date, value)| {
                format!(
                    "{date} · {}",
                    value
                        .map(|v| format!("{} {currency}", money_for(v, &currency)))
                        .unwrap_or_else(|| "估值缺失".into())
                )
            })
            .unwrap_or_default()
    };
    let dot_rows = model.all.clone();
    let mut graph = plot::plot()
        .data(model.all)
        .x(RowAccessor::key("x"))
        .y(RowAccessor::key("y"))
        .x_scale(Scale::Linear {
            domain: Some([0.0, count.saturating_sub(1).max(1) as f64]),
            reverse: false,
        })
        .y_scale(Scale::Linear {
            domain: Some([0.0, 1.0]),
            reverse: false,
        })
        .motion(plot_motion())
        .appear_generation(AppearKey::Text(
            format!("trend-{count}-{}", points[0].0).into(),
        ))
        .accessibility_label("净资产趋势，滑动或使用方向键查看时点")
        .on_hover_change(move |i: &Option<u32>| hovered.set(*i))
        .h(px(144.0))
        .w_full()
        .cross_line_class("w-px bg-muted-foreground/40")
        .dot_class("hidden")
        .tooltip_content(
            view()
                .rounded_md()
                .bg(move || theme().popover)
                .border_1()
                .border_color(move || theme().border)
                .shadow_sm()
                .p_2()
                .child(text(tooltip).text_xs().tabular_nums()),
        )
        .child(
            plot::grid()
                .y(vec![0.0, 0.5, 1.0])
                .stroke_color(move || theme().border)
                .stroke_width(px(1.0)),
        );
    for segment in model.segments {
        if segment.len() > 1 {
            graph = graph
                .child(
                    plot::area()
                        .data(segment.clone())
                        .x(RowAccessor::key("x"))
                        .y1(RowAccessor::key("y"))
                        .y0(plot::AreaY0::Value(0.0))
                        .curve(Curve::Linear)
                        .background_class("bg-linear-to-b from-primary/20 to-primary/0")
                        .hover_dot_class("hidden"),
                )
                .child(
                    plot::line()
                        .data(segment)
                        .x(RowAccessor::key("x"))
                        .y(RowAccessor::key("y"))
                        .curve(Curve::Linear)
                        .stroke_width(px(2.0))
                        .stroke_color(move || {
                            if cash {
                                crate::finance_ui::data_cash()
                            } else {
                                theme().primary
                            }
                        })
                        .hover_dot_class("hidden"),
                );
        }
    }
    let markers = NativeControl(
        plot::plot()
            .data(dot_rows)
            .x(RowAccessor::key("x"))
            .y(RowAccessor::key("y"))
            .x_scale(Scale::Linear {
                domain: Some([0.0, count.saturating_sub(1).max(1) as f64]),
                reverse: false,
            })
            .y_scale(Scale::Linear {
                domain: Some([0.0, 1.0]),
                reverse: false,
            })
            .interactive(false)
            .absolute()
            .inset_0()
            .child(
                plot::dot()
                    .r(move || {
                        let active = hovered.get();
                        RowAccessor::from_fn(move |i| {
                            if i == last || active == Some(i as u32) {
                                3.5
                            } else {
                                0.0
                            }
                        })
                    })
                    .fill_color(move || theme().primary),
            ),
    )
    .pointer_events(PointerEvents::None);
    NativeControl(graph.child(markers)).test_id("finance-trend-plot")
}

pub fn spending_chart(values: &[Decimal], currency: &str) -> impl Element + use<> {
    let values = Arc::new(values.to_vec());
    let peak = spending_peak(&values);
    let high = peak.map(|(_, v)| v).unwrap_or(Decimal::ONE);
    let peak_index = peak.map(|(i, _)| i);
    let hovered = signal(None::<u32>);
    let data = Rows::from_columns(
        values.len(),
        [(
            "amount".into(),
            values
                .iter()
                .map(|v| position(*v, Decimal::ZERO, high))
                .collect(),
        )],
    );
    let tooltip_values = values.clone();
    let currency = currency.to_owned();
    NativeControl(
        plot::plot()
            .data(data)
            .y(RowAccessor::key("amount"))
            .x_scale(Scale::Band({
                let mut bands = BandScale::default();
                bands.padding_inner = percentage(0.32);
                bands
            }))
            .y_scale(Scale::Linear {
                domain: Some([0.0, 1.0]),
                reverse: false,
            })
            .color_scale(move || {
                ColorScale::Ordinal(OrdinalScale::new(
                    ["peak", "day"],
                    [
                        color(theme().primary),
                        color(crate::finance_ui::data_cash()),
                    ],
                ))
            })
            .motion(plot_motion())
            .appear_generation(AppearKey::Text(format!("spending-{}", values.len()).into()))
            .accessibility_label("本月每日支出，滑动查看金额")
            .on_hover_change(move |i: &Option<u32>| hovered.set(*i))
            .tooltip_content(
                view()
                    .bg(move || theme().popover)
                    .rounded_md()
                    .p_1()
                    .shadow_sm()
                    .child(
                        text(move || {
                            hovered
                                .get()
                                .and_then(|i| {
                                    tooltip_values.get(i as usize).map(|v| {
                                        format!(
                                            "{} 日 · {} {currency}",
                                            i + 1,
                                            money_for(*v, &currency)
                                        )
                                    })
                                })
                                .unwrap_or_default()
                        })
                        .text_xs(),
                    ),
            )
            .child(
                plot::bar()
                    .color(RowText::from_fn(move |i| {
                        if Some(i) == peak_index {
                            "peak".into()
                        } else {
                            "day".into()
                        }
                    }))
                    .corner_radii(px(2.0)),
            )
            .min_h(px(44.0))
            .w_full(),
    )
    .test_id("today-spending-plot")
}
pub fn allocation_plot(investment: Decimal, cash: Decimal, currency: &str) -> impl Element + use<> {
    let total = investment.checked_add(cash).unwrap_or(Decimal::ONE);
    let data = Rows::from_columns(
        2,
        [(
            "share".into(),
            vec![ratio(investment, total) as f64, ratio(cash, total) as f64],
        )],
    );
    NativeControl(
        plot::plot()
            .data(data)
            .size(px(96.0))
            .motion(plot_motion())
            .appear_generation(AppearKey::Text(format!("allocation-{currency}").into()))
            .accessibility_label(format!("{currency} 已知投资与现金构成"))
            .child(
                plot::pie()
                    .value(RowAccessor::key("share"))
                    .inner_radius(relative(0.72))
                    .slice_class(plot::SliceClass::from_fn(|i| {
                        if i == 0 {
                            "fill-chart-1".into()
                        } else {
                            "fill-chart-2".into()
                        }
                    })),
            ),
    )
    .test_id("wealth-allocation-plot")
}
/// Static category summary; official horizontal stacked Bar owns the geometry.
pub fn category_composition_plot(parts: &[Decimal], total: Decimal) -> impl Element + use<> {
    let columns = parts
        .iter()
        .enumerate()
        .map(|(i, value)| {
            (
                SharedString::from(format!("part-{i}")),
                vec![ratio(*value, total) as f64],
            )
        })
        .collect::<Vec<_>>();
    let mut bands = BandScale::default();
    bands.padding_inner = percentage(0.0);
    bands.padding_outer = percentage(0.0);
    let mut graph = plot::plot()
        .data(Rows::from_columns(1, columns))
        .x_scale(Scale::Linear {
            domain: Some([0.0, 1.0]),
            reverse: false,
        })
        .y_scale(Scale::Band(bands))
        .interactive(false)
        .motion(plot_motion())
        .appear_generation(AppearKey::Text("category-summary".into()))
        .accessibility_label("本月支出分类构成")
        .h(px(7.0))
        .w_full();
    for i in 0..parts.len() {
        graph = graph.child(
            plot::bar()
                .value(RowAccessor::key(format!("part-{i}")))
                .stack("categories")
                .fill_color(move || match i {
                    0 => theme().primary,
                    1 => crate::finance_ui::data_cash(),
                    2 => theme().muted_foreground,
                    _ => theme().border,
                }),
        );
    }
    NativeControl(graph).test_id("ledger-category-plot")
}
#[cfg(test)]
#[path = "plots_tests.rs"]
mod tests;
