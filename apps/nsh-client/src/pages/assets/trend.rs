mod snapshots;

use crate::data::valuation as observations;
use crate::{
    domain::meal::Day,
    i18n::s,
    ui::{Type, Typo, color},
};
use navi_finance::{
    currency::{Currency, FxRate},
    holdings::Book,
    journal::Transaction,
    valuation,
};
use nsh_base::plot::{Curve, Scale, area, line, plot};
use nsh_core::{
    element::{RowAccessor, Rows},
    prelude::*,
};
use std::collections::BTreeMap;

pub fn history_page() -> nsh_core::element::Screen {
    use crate::{
        data::{clock, finance},
        nav,
    };
    let recorded = signal(false);
    let notice = signal(String::new());
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
                            .gap_4()
                            .child(crate::ui::segmented::segmented(
                                vec![
                                    crate::ui::segmented::Segment::new(false, || copy("Historical estimates", "历史估算").into()),
                                    crate::ui::segmented::Segment::new(true, || copy("Net worth snapshots", "净值快照").into()),
                                ], move || recorded.get(), move |v| recorded.set(v),
                            ))
                            .pb_safe_area_plus(px(24.0))
                            .child(dynamic(move || {
                                if recorded.get() { return snapshots::recorded_panel(notice); }
                                let entries = finance::transactions_snapshot();
                                let portfolio = finance::holdings_snapshot();
                                let today = clock::today();
                                let rates = finance::rates_snapshot();
                                untracked(move || {
                                    view()
                                        .gap_5()
                                        .child(text(copy("History recalculated from current records and dated prices. Edits can change these values.", "按当前账本与对应日期行情重新计算；修改记录后，历史数值会变化。")).typo(Type::Subhead).text_color(color::MUTED))
                                        .child(chart(&entries, &portfolio, &rates, today))
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
                                        ).into_element()
                                })
                            })),
                    ),
                ),
        )
}

const TREND_DAYS: i32 = 30;

/// Both charts use the same available dates, complete valuations and missing-rate gaps.
pub(super) struct NetWorthHistory {
    pub points: Vec<(jiff::civil::Date, Option<i64>)>,
    missing: BTreeMap<Currency, usize>,
    errors: usize,
}

impl NetWorthHistory {
    pub fn load(entries: &[Transaction], book: &Book, rates: &[FxRate], today: Day) -> Self {
        let mut history = Self {
            points: Vec::new(),
            missing: BTreeMap::new(),
            errors: 0,
        };
        for (day, valuation) in
            book.valuation_range(entries, rates, today.plus_days(-TREND_DAYS).0, today.0)
        {
            let value = match valuation {
                Ok(v) if v.missing.is_empty() => Some(v.snapshot.net),
                Ok(v) => {
                    for currency in v.missing {
                        *history.missing.entry(currency).or_default() += 1;
                    }
                    None
                }
                Err(_) => {
                    history.errors += 1;
                    None
                }
            };
            history.points.push((day, value));
        }
        history
    }

    pub fn change(&self) -> Option<i64> {
        let &(first, start) = self.points.first()?;
        let &(last, end) = self.points.last()?;
        if Day(last).days_since(Day(first)) != TREND_DAYS {
            return None;
        }
        end?.checked_sub(start?)
    }
}

pub fn chart(
    entries: &[Transaction],
    portfolio: &Book,
    rates: &[FxRate],
    today: Day,
) -> AnyElement {
    let has_holdings = !portfolio.securities.is_empty();
    let NetWorthHistory {
        points,
        missing,
        errors,
    } = NetWorthHistory::load(entries, portfolio, rates, today);
    let mut panel = view().gap_2();
    if points.len() < 2 {
        panel = panel.child(
            text(|| s().assets_trend_empty)
                .typo(Type::Subhead)
                .text_color(color::MUTED),
        );
    } else if points.iter().any(|p| p.1.is_some()) {
        panel = panel.child(plot_points(
            points,
            if has_holdings {
                s().portfolio_trend
            } else {
                s().assets_trend
            },
        ));
    }
    let can_backfill = errors == 0 || !missing.is_empty();
    for (currency, count) in missing {
        panel = panel.child(
            text(s().missing_rate_days(currency.code(), count))
                .typo(Type::Subhead)
                .text_color(color::MUTED),
        );
    }
    if errors > 0 {
        panel = panel.child(
            text(copy(
                "Some dates could not be valued.",
                "部分日期估值失败。",
            ))
            .typo(Type::Subhead)
            .text_color(color::DANGER),
        );
    }
    if can_backfill {
        panel = panel.child(history_refresh(today));
    }
    panel.into_element()
}

fn history_refresh(today: Day) -> impl IntoElement {
    use crate::data::{history, tasks};
    view()
        .gap_2()
        .child(
            crate::ui::Btn::tonal()
                .label(|| copy("Fill 30-day price & FX history", "补全近30天价格与汇率").into())
                .busy(|| history::status().running)
                .on_press(move || {
                    tasks::spawn_app(async move {
                        history::backfill(today.plus_days(-TREND_DAYS).0, today.0, true).await;
                    })
                }),
        )
        .child(dynamic(|| {
            let status = history::status();
            let message = if status.running {
                copy("Fetching historical data…", "正在获取历史数据…").to_owned()
            } else if status.updated > 0 || status.failed > 0 {
                format!(
                    "{} {} · {} {}",
                    copy("Updated", "已更新"),
                    status.updated,
                    copy("Failed", "失败"),
                    status.failed
                )
            } else {
                return view().into_element();
            };
            text(message)
                .typo(Type::Caption)
                .text_color(color::MUTED)
                .into_element()
        }))
}

/// A contiguous run of complete daily valuations for either plot.
pub(super) fn segment_rows(run: &[(jiff::civil::Date, Option<i64>)], first: Day) -> Rows {
    let days = run
        .iter()
        .map(|(d, _)| f64::from(Day(*d).days_since(first)))
        .collect();
    let values = run.iter().map(|(_, v)| v.unwrap() as f64 / 100.0).collect();
    Rows::from_columns(run.len(), [("day".into(), days), ("value".into(), values)])
}

fn plot_points(points: Vec<(jiff::civil::Date, Option<i64>)>, title: &'static str) -> AnyElement {
    let first = Day(points[0].0);
    let today = Day(points.last().unwrap().0);
    let known: Vec<_> = points
        .iter()
        .filter_map(|(d, v)| v.map(|v| (*d, v)))
        .collect();
    let (start, first_value) = known[0];
    let (end, last) = *known.last().unwrap();
    let values: Vec<f64> = known.iter().map(|(_, v)| *v as f64 / 100.0).collect();
    let mut segments = Vec::new();
    for run in points
        .split(|p| p.1.is_none())
        .filter(|run| !run.is_empty())
    {
        let rows = segment_rows(run, first);
        segments.push(
            area()
                .data(Some(rows.clone()))
                .x(Some(RowAccessor::from("day")))
                .y1(Some(RowAccessor::from("value")))
                .curve(Curve::Linear)
                .fill_color(color::INK.opacity(0.06))
                .into_element(),
        );
        segments.push(
            line()
                .data(Some(rows))
                .x(Some(RowAccessor::from("day")))
                .y(Some(RowAccessor::from("value")))
                .dot(run.len() == 1)
                .curve(Curve::Linear)
                .text_color(color::INK)
                .stroke_width(px(2.0))
                .into_element(),
        );
    }
    let low = values.iter().copied().fold(f64::INFINITY, f64::min);
    let high = values.iter().copied().fold(f64::NEG_INFINITY, f64::max);
    let pad = ((high - low) * 0.1).max(1.0);
    let label = format!(
        "{}: {} {} → {} {}",
        title,
        s().long_date(Day(start)),
        crate::ui::currency::format(first_value, navi_finance::currency::Currency::CNY),
        s().long_date(Day(end)),
        crate::ui::currency::format(last, navi_finance::currency::Currency::CNY)
    );
    let hovered = signal(None::<u32>);
    let hover_labels = stored(
        known
            .iter()
            .map(|(d, v)| {
                format!(
                    "{} · {}",
                    s().short_date(Day(*d)),
                    crate::ui::currency::format(*v, navi_finance::currency::Currency::CNY)
                )
            })
            .collect::<Vec<_>>(),
    );
    let rows = Rows::from_columns(
        known.len(),
        [
            (
                "day".into(),
                known
                    .iter()
                    .map(|(d, _)| f64::from(Day(*d).days_since(first)))
                    .collect(),
            ),
            ("value".into(), values),
        ],
    );
    view()
        .gap_2()
        .child(text(title).typo(Type::Headline).text_color(color::BODY))
        .child(
            text(format!(
                "{} {} – {}",
                s().value_range,
                crate::ui::currency::format(
                    known.iter().map(|p| p.1).min().unwrap(),
                    navi_finance::currency::Currency::CNY
                ),
                crate::ui::currency::format(
                    known.iter().map(|p| p.1).max().unwrap(),
                    navi_finance::currency::Currency::CNY
                )
            ))
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(
            plot()
                .h(px(180.0))
                .x_scale(Scale::Linear {
                    domain: Some([0.0, f64::from(today.days_since(first)).max(1.0)]),
                    reverse: false,
                })
                .y_scale(Scale::Linear {
                    domain: Some([low - pad, high + pad]),
                    reverse: false,
                })
                .data(rows)
                .x(Some(RowAccessor::from("day")))
                .y(Some(RowAccessor::from("value")))
                .interactive(true)
                .on_hover_change(move |index: &Option<u32>| hovered.set(*index))
                .tooltip_content(
                    view()
                        .bg(color::SURFACE)
                        .px_2()
                        .py_1()
                        .rounded(px(8.0))
                        .child(
                            text(move || {
                                hover_labels.with(|labels| {
                                    hovered
                                        .get()
                                        .and_then(|i| labels.get(i as usize))
                                        .cloned()
                                        .unwrap_or_default()
                                })
                            })
                            .typo(Type::Caption)
                            .text_color(color::INK),
                        ),
                )
                .cross_line_style(|s| s.w(px(1.0)).bg(color::MUTED))
                .dot_style(|s| s.size(px(6.0)).rounded_full().bg(color::INK))
                .accessibility_label(move || Some(label.clone().into()))
                .children(segments),
        )
        .child(
            view()
                .flex_row()
                .child(
                    text(format!(
                        "{}\n{}",
                        s().long_date(Day(start)),
                        crate::ui::currency::format(
                            first_value,
                            navi_finance::currency::Currency::CNY
                        )
                    ))
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .flex_1(),
                )
                .child(
                    text(format!(
                        "{}\n{}",
                        s().long_date(Day(end)),
                        crate::ui::currency::format(last, navi_finance::currency::Currency::CNY)
                    ))
                    .text_right()
                    .typo(Type::Caption)
                    .text_color(color::MUTED),
                ),
        )
        .into_element()
}

fn copy(en: &'static str, zh: &'static str) -> &'static str {
    crate::i18n::statement_import::copy(en, zh)
}
