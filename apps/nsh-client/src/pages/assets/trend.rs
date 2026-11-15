use crate::{
    domain::meal::Day,
    i18n::s,
    ui::{Type, Typo, color},
};
use finance_core::{assets, journal::Transaction, money};
use nsh_base::plot::{Curve, Scale, line, plot};
use nsh_core::{
    element::{RowAccessor, Rows},
    prelude::*,
};

pub fn history_page() -> nsh_core::element::Screen {
    use crate::{
        data::{clock, finance},
        nav,
    };
    nsh_base::nav_page()
        .title(|| s().asset_history)
        .header_visible(false)
        .status_bar(super::super::parts::status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(super::super::parts::top_bar(
                    || s().asset_history.into(),
                    nav::pop,
                    None,
                ))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(crate::ui::space::GUTTER))
                            .pt_4()
                            .pb_safe_area_plus(px(24.0))
                            .child(dynamic(move || {
                                let entries = finance::transactions();
                                let portfolio = finance::holdings();
                                let today = clock::today();
                                untracked(move || {
                                    view()
                                        .gap_5()
                                        .child(chart(&entries, &portfolio, today))
                                        .child(
                                            text(if portfolio.securities.is_empty() {
                                                s().assets_basis
                                            } else {
                                                s().portfolio_basis
                                            })
                                            .typo(Type::Subhead)
                                            .text_color(color::MUTED),
                                        )
                                        .child(
                                            text(|| s().asset_history_note)
                                                .typo(Type::Subhead)
                                                .text_color(color::MUTED),
                                        )
                                })
                            })),
                    ),
                ),
        )
}

pub fn chart(
    entries: &[Transaction],
    portfolio: &finance_core::holdings::Book,
    today: Day,
) -> AnyElement {
    let has_holdings = !portfolio.securities.is_empty();
    let points: Vec<_> = assets::trend(entries, today.plus_days(-29).0, today.0)
        .into_iter()
        .map(|(day, _)| {
            (
                day,
                portfolio
                    .overview(entries, day)
                    .expect("validated portfolio history")
                    .net,
            )
        })
        .collect();
    if points.len() < 2 {
        return text(|| s().assets_trend_empty)
            .typo(Type::Subhead)
            .text_color(color::MUTED)
            .into_element();
    }
    let first = Day(points[0].0);
    let last = points.last().unwrap().1;
    let first_value = points[0].1;
    let days: Vec<f64> = points
        .iter()
        .map(|(d, _)| f64::from(Day(*d).days_since(first)))
        .collect();
    let values: Vec<f64> = points.iter().map(|(_, v)| *v as f64 / 100.0).collect();
    let low = values.iter().copied().fold(f64::INFINITY, f64::min);
    let high = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let pad = ((high - low) * 0.1).max(1.0);
    let label = format!(
        "{}: {} ¥{} → {} ¥{}",
        if has_holdings {
            s().portfolio_trend
        } else {
            s().assets_trend
        },
        s().long_date(first),
        money::format(first_value),
        s().long_date(today),
        money::format(last)
    );
    view()
        .gap_2()
        .child(
            text(move || {
                if has_holdings {
                    s().portfolio_trend
                } else {
                    s().assets_trend
                }
            })
            .typo(Type::Headline)
            .text_color(color::BODY),
        )
        .child(
            text(format!(
                "{} ¥{} – ¥{}",
                s().value_range,
                super::display_money(points.iter().map(|p| p.1).min().unwrap()),
                super::display_money(points.iter().map(|p| p.1).max().unwrap())
            ))
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(
            plot()
                .h(px(180.0))
                .data(Rows::from_columns(
                    points.len(),
                    [("day".into(), days), ("value".into(), values)],
                ))
                .x(Some(RowAccessor::from("day")))
                .y(Some(RowAccessor::from("value")))
                .x_scale(Scale::Linear {
                    domain: Some([0.0, f64::from(today.days_since(first)).max(1.0)]),
                    reverse: false,
                })
                .y_scale(Scale::Linear {
                    domain: Some([low - pad, high + pad]),
                    reverse: false,
                })
                .interactive(false)
                .accessibility_label(move || Some(label.clone().into()))
                .child(
                    line()
                        .curve(Curve::Linear)
                        .text_color(color::INK)
                        .stroke_width(px(2.0)),
                ),
        )
        .child(
            view()
                .flex_row()
                .child(
                    text(s().long_date(first))
                        .typo(Type::Caption)
                        .text_color(color::MUTED)
                        .flex_1(),
                )
                .child(text(s().today).typo(Type::Caption).text_color(color::MUTED)),
        )
        .into_element()
}
