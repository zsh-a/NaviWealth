//! A quiet overview of the same dated valuations used by Asset changes.
use crate::{
    domain::meal::Day,
    i18n::s,
    ui::{Type, Typo, color},
};
use navi_finance::{
    currency::{Currency, FxRate},
    holdings::Book,
    journal::Transaction,
};
use nsh_base::plot::{Curve, Scale, line, plot};
use nsh_core::{
    element::{RowAccessor, Rows},
    prelude::*,
};

pub(super) fn sparkline(
    entries: &[Transaction],
    book: &Book,
    rates: &[FxRate],
    today: Day,
) -> AnyElement {
    let first = today.plus_days(-30);
    let earliest = entries.iter().map(|t| t.at.date()).min();
    let points: Vec<_> = book
        .valuation_range(entries, rates, first.0, today.0)
        .into_iter()
        .map(|(day, result)| {
            let net = result
                .ok()
                .filter(|v| v.missing.is_empty())
                .filter(|_| earliest.is_some_and(|start| day >= start))
                .map(|v| v.snapshot.net);
            (day, net)
        })
        .collect();
    let known: Vec<_> = points.iter().filter_map(|p| p.1).collect();
    if known.len() < 2 {
        return view().into_element();
    }
    let low = *known.iter().min().unwrap() as f64 / 100.0;
    let high = *known.iter().max().unwrap() as f64 / 100.0;
    let pad = ((high - low) * 0.1).max(1.0);
    let change = points
        .first()
        .and_then(|p| p.1)
        .zip(points.last().and_then(|p| p.1))
        .and_then(|(start, end)| end.checked_sub(start));
    view()
        .gap_1()
        .child(
            plot()
                .h(px(40.0))
                .interactive(false)
                .x_scale(Scale::Linear {
                    domain: Some([0.0, 30.0]),
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
                            let rows = Rows::from_columns(
                                run.len(),
                                [
                                    (
                                        "day".into(),
                                        run.iter()
                                            .map(|p| f64::from(Day(p.0).days_since(first)))
                                            .collect(),
                                    ),
                                    (
                                        "net".into(),
                                        run.iter().map(|p| p.1.unwrap() as f64 / 100.0).collect(),
                                    ),
                                ],
                            );
                            line()
                                .data(Some(rows))
                                .x(Some(RowAccessor::from("day")))
                                .y(Some(RowAccessor::from("net")))
                                .curve(Curve::Linear)
                                .dot(run.len() == 1)
                                .stroke_width(px(1.5))
                                .text_color(color::INK.opacity(0.6))
                        }),
                ),
        )
        .child(change.map(|v| {
            text(format!(
                "{} {}",
                s().net_change_30d,
                crate::ui::currency::signed(v, Currency::CNY)
            ))
            .typo(Type::Caption)
            .tabular_nums()
            .text_color(color::MUTED)
        }))
        .into_element()
}
