mod snapshots;

use crate::data::valuation as observations;
use crate::ui::trend::{self, Unit, Window};
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
use nsh_core::{element::Rows, prelude::*};
use std::collections::BTreeMap;

pub fn history_page() -> nsh_core::element::Screen {
    use crate::{
        data::{clock, finance},
        nav,
    };
    let recorded = signal(false);
    let estimates_window = signal(Window::Month);
    let snapshots_window = signal(Window::Month);
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
                                if recorded.get() { return snapshots::recorded_panel(snapshots_window); }
                                let entries = finance::transactions_snapshot();
                                let portfolio = finance::holdings_snapshot();
                                let today = clock::today();
                                let rates = finance::rates_snapshot();
                                untracked(move || {
                                    view()
                                        .gap_5()
                                        .child(chart(&entries, &portfolio, &rates, today, estimates_window))
                                        .child(text(copy("History recalculated from current records and dated prices. Edits can change these values.", "按当前账本与对应日期行情重新计算；修改记录后，历史数值会变化。")).typo(Type::Subhead).text_color(color::MUTED))
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
    window: Signal<Window>,
) -> AnyElement {
    let has_holdings = !portfolio.securities.is_empty();
    let NetWorthHistory {
        points,
        missing,
        errors,
    } = NetWorthHistory::load(entries, portfolio, rates, today);
    let mut panel = view().gap_2();
    panel = panel.child(trend::chart(
        if has_holdings {
            copy("Net worth", "净资产")
        } else {
            copy("Book value", "账面净资产")
        }
        .into(),
        points,
        Unit::Money,
        window,
    ));
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
    panel.into_element()
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

fn copy(en: &'static str, zh: &'static str) -> &'static str {
    crate::i18n::statement_import::copy(en, zh)
}
