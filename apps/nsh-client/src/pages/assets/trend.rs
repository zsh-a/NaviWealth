mod snapshots;

use crate::data::valuation as observations;
use crate::ui::trend::{self, Unit, Window};
use crate::{
    domain::meal::Day,
    i18n::s,
    ui::{Type, Typo, color},
};
use jiff::civil::Date;
use navi_finance::{
    currency::{Currency, FxRate},
    holdings::Book,
    journal::Transaction,
    valuation,
};
use nsh_core::{element::Rows, prelude::*};
use std::collections::BTreeMap;

pub fn history_page() -> nsh_core::element::Screen {
    use crate::nav;
    let recorded = signal(false);
    let basis = signal(false);
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
                                    crate::ui::segmented::Segment::new(false, || {
                                        copy("Historical estimates", "历史估算").into()
                                    }),
                                    crate::ui::segmented::Segment::new(true, || {
                                        copy("Net worth snapshots", "净值快照").into()
                                    }),
                                ],
                                move || recorded.get(),
                                move |v| recorded.set(v),
                            ))
                            .pb_safe_area_plus(px(24.0))
                            .child(dynamic(move || {
                                if recorded.get() {
                                    snapshots::recorded_panel(snapshots_window)
                                } else {
                                    estimate_panel(estimates_window, basis)
                                }
                            })),
                    ),
                ),
        )
}

const TREND_DAYS: i32 = 30;

/// Both charts use the same available dates, complete valuations and missing-rate gaps.
pub(super) struct NetWorthHistory {
    pub points: Vec<(jiff::civil::Date, Option<i64>)>,
    missing: BTreeMap<Currency, Vec<Date>>,
    errors: Vec<Date>,
}

impl NetWorthHistory {
    pub fn load(entries: &[Transaction], book: &Book, rates: &[FxRate], today: Day) -> Self {
        Self::between(
            entries,
            book,
            rates,
            today.plus_days(-TREND_DAYS).0,
            today.0,
        )
    }

    fn between(
        entries: &[Transaction],
        book: &Book,
        rates: &[FxRate],
        from: Date,
        to: Date,
    ) -> Self {
        let mut history = Self {
            points: Vec::new(),
            missing: BTreeMap::new(),
            errors: Vec::new(),
        };
        for (day, valuation) in book.valuation_range(entries, rates, from, to) {
            let value = match valuation {
                Ok(v) if v.missing.is_empty() => Some(v.snapshot.net),
                Ok(v) => {
                    for currency in v.missing {
                        history.missing.entry(currency).or_default().push(day);
                    }
                    None
                }
                Err(_) => {
                    history.errors.push(day);
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

fn estimate_panel(window: Signal<Window>, basis: Signal<bool>) -> AnyElement {
    use crate::data::{clock, finance};
    let entries = finance::transactions_snapshot();
    let book = finance::holdings_snapshot();
    let rates = finance::rates_snapshot();
    let today = clock::today().0;
    let has_holdings = !book.securities.is_empty();
    // Each confirmed trade has a journal entry on its effective date.
    let earliest = entries
        .iter()
        .map(|entry| entry.at.date())
        .min()
        .unwrap_or(today)
        .min(today);
    view()
        .gap_3()
        .child(dynamic(move || {
            let from = window.get().start(today, earliest);
            let history = NetWorthHistory::between(&entries, &book, &rates, from, today);
            untracked(move || {
                let title = if has_holdings {
                    copy("Net worth", "净资产")
                } else {
                    copy("Book value", "账面净资产")
                };
                view()
                    .gap_2()
                    .child(trend::chart_from(
                        title.into(),
                        history.points,
                        Unit::Money,
                        window,
                        today,
                        earliest,
                    ))
                    .children(history.missing.into_iter().map(|(currency, days)| {
                        gap_note(&days, &s().missing_rate(currency.code()), color::MUTED)
                    }))
                    .child((!history.errors.is_empty()).then(|| {
                        gap_note(
                            &history.errors,
                            copy("Valuation unavailable", "无法估值"),
                            color::DANGER,
                        )
                    }))
                    .into_element()
            })
        }))
        .child(crate::ui::surface::disclosure(basis, || {
            copy("Valuation basis", "估值依据").into()
        }))
        .child(when(
            move || basis.get(),
            move || {
                let calculation = copy(
                    "History recalculated from current records and dated prices. Edits can change these values.",
                    "按当前账本和当日行情估算，补录后会重新计算。",
                );
                let basis = if has_holdings { s().portfolio_basis } else { s().assets_basis };
                view().gap_2().children(
                    [calculation, basis, s().asset_history_note]
                        .map(|line| text(line).typo(Type::Subhead).text_color(color::MUTED)),
                )
            },
        ))
        .into_element()
}

/// Group adjacent dates without implying that intermediate, unaffected days had a gap.
fn gap_note(days: &[Date], reason: &str, tint: AdaptiveColor) -> AnyElement {
    let ranges = days
        .chunk_by(|a, b| a.tomorrow().ok().as_ref() == Some(b))
        .map(|run| {
            let first = run[0];
            let last = run[run.len() - 1];
            if first == last {
                first.to_string()
            } else {
                format!("{first} – {last}")
            }
        })
        .collect::<Vec<_>>();
    let detail = ranges.join(", ");
    if ranges.len() <= 2 {
        return text(format!("{reason} · {detail}"))
            .typo(Type::Subhead)
            .tabular_nums()
            .text_color(tint)
            .into_element();
    }
    let label = format!("{reason} · {} {}", days.len(), copy("days", "天"));
    let open = signal(false);
    view()
        .child(crate::ui::surface::disclosure(open, move || {
            label.clone().into()
        }))
        .child(when(
            move || open.get(),
            move || {
                text(detail.clone())
                    .typo(Type::Subhead)
                    .tabular_nums()
                    .text_color(tint)
            },
        ))
        .into_element()
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
