//! A quiet overview of the same dated valuations used by Asset changes.
use crate::{domain::meal::Day, ui::color};
use nsh_base::plot::{Curve, Scale, line, plot};
use nsh_core::{element::RowAccessor, prelude::*};

pub(super) fn sparkline(history: &super::trend::NetWorthHistory) -> Option<AnyElement> {
    let points = &history.points;
    let first = Day(points.first()?.0);
    let span = Day(points.last()?.0).days_since(first);
    let known: Vec<_> = points.iter().filter_map(|p| p.1).collect();
    if span == 0 || known.is_empty() {
        return None;
    }
    let low = *known.iter().min().unwrap() as f64 / 100.0;
    let high = *known.iter().max().unwrap() as f64 / 100.0;
    let pad = ((high - low) * 0.1).max(1.0);
    Some(
        plot()
            .h(px(40.0))
            .interactive(false)
            .x_scale(Scale::Linear {
                domain: Some([0.0, f64::from(span)]),
                reverse: false,
            })
            .y_scale(Scale::Linear {
                domain: Some([low - pad, high + pad]),
                reverse: false,
            })
            .children(
                points
                    .split(|p| p.1.is_none())
                    .filter(|run| !run.is_empty())
                    .map(|run| {
                        let rows = super::trend::segment_rows(run, first);
                        line()
                            .data(Some(rows))
                            .x(Some(RowAccessor::from("day")))
                            .y(Some(RowAccessor::from("value")))
                            .curve(Curve::Linear)
                            .dot(run.len() == 1)
                            .stroke_width(px(1.5))
                            .text_color(color::INK.opacity(0.6))
                    }),
            )
            .into_element(),
    )
}
