mod snapshots;

use crate::data::valuation as observations;
use crate::ui::trend::{self, ChartDates, Unit, Window};
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

pub fn history_page(comparison: Option<(Day, Day)>) -> nsh_core::element::Screen {
    use crate::nav;
    let recorded = signal(false);
    let basis = signal(false);
    let comparison = comparison.map(|(from, to)| (from.0, to.0));
    let estimates_window =
        signal(comparison.map_or(Window::Month, |(from, to)| Window::Comparison { from, to }));
    let snapshots_window = signal(Window::Month);
    let explain = signal(comparison.is_some());
    let selected = signal(None::<Date>);
    let edit = signal(None::<String>);
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
                                    estimate_panel(
                                        estimates_window,
                                        comparison,
                                        basis,
                                        explain,
                                        selected,
                                        edit,
                                    )
                                }
                            })),
                    ),
                )
                .child(super::super::finance::finance_editor(edit)),
        )
}

pub(super) const TREND_DAYS: i32 = 30;

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

    /// Keep the exact endpoints used by the headline for its detail link.
    pub fn comparison(&self) -> Option<(Day, Day, i64)> {
        let &(last, end) = self.points.last()?;
        let &(first, start) = self.points.iter().find(|p| p.1.is_some())?;
        let delta = end?.checked_sub(start?)?;
        let (from, to) = (Day(first), Day(last));
        (first != last && (to.days_since(from) == TREND_DAYS || delta != 0))
            .then_some((from, to, delta))
    }
}

fn estimate_panel(
    window: Signal<Window>,
    comparison: Option<(Date, Date)>,
    basis: Signal<bool>,
    explain: Signal<bool>,
    selected: Signal<Option<Date>>,
    edit: Signal<Option<String>>,
) -> AnyElement {
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
    let dates = ChartDates {
        today,
        earliest,
        comparison,
    };
    view()
        .gap_3()
        .child(dynamic(move || {
            let (from, to) = dates.bounds(window.get());
            let history = NetWorthHistory::between(&entries, &book, &rates, from, to);
            untracked(move || {
                let title = if has_holdings {
                    copy("Net worth", "净资产")
                } else {
                    copy("Book value", "账面净资产")
                };
                let breakdown = change_explanation(&history.points, selected, explain, edit);
                view()
                    .gap_2()
                    .child(trend::chart_from(
                        title.into(),
                        history.points,
                        Unit::Money,
                        window,
                        dates,
                        Some(selected),
                    ))
                    .child(breakdown)
                    .children(
                        history
                            .missing
                            .into_iter()
                            .map(|(currency, days)| missing_rates(currency, &days)),
                    )
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
                let line = |value| text(value).typo(Type::Subhead).text_color(color::MUTED);
                view()
                    .gap_2()
                    .child(line(s().assets_basis))
                    .child(has_holdings.then(|| line(s().portfolio_basis)))
            },
        ))
        .into_element()
}

/// The chart reads changes from its first visible sample, even when history
/// began inside the selected window. Never move the baseline past a gap.
fn change_explanation(
    points: &[trend::Point],
    selected: Signal<Option<Date>>,
    open: Signal<bool>,
    edit: Signal<Option<String>>,
) -> AnyElement {
    use navi_finance::attribution::{self, Outcome};
    let [first, .., last] = points else {
        return view().into_element();
    };
    let (first, last) = (*first, *last);
    let points = stored(points.to_vec());
    view()
        .gap_2()
        .child(crate::ui::surface::disclosure(open, || {
            copy("Change breakdown", "变化来源").into()
        }))
        .child(when(
            move || open.get(),
            move || {
                dynamic(move || {
                    let selected = selected.get();
                    let last = points.with(|p| {
                        selected
                            .and_then(|day| p.binary_search_by_key(&day, |p| p.0).ok())
                            .map(|i| p[i])
                            .unwrap_or(last)
                    });
                    let date_span = format!(
                        "{} – {}",
                        s().axis_date(Day(first.0), first.0.year() != last.0.year()),
                        s().axis_date(Day(last.0), first.0.year() != last.0.year())
                    );
                    if first.0 == last.0 && first.1.is_some() {
                        return text(format!(
                            "{date_span} · {}",
                            copy("Opening observation", "起始估值")
                        ))
                        .typo(Type::Caption)
                        .tabular_nums()
                        .text_color(color::MUTED)
                        .into_element();
                    }
                    let outcome = attribution::attribute(
                        &crate::data::finance::holdings_snapshot(),
                        &crate::data::finance::transactions_snapshot(),
                        &crate::data::finance::rates_snapshot(),
                        first.0,
                        last.0,
                    );
                    let mut body = view().gap_2().child(
                        text(date_span)
                            .typo(Type::Caption)
                            .text_color(color::MUTED)
                            .tabular_nums(),
                    );
                    body = match outcome {
                        Ok(Outcome::Complete(a))
                            if Some(a.start) == first.1 && Some(a.end) == last.1 =>
                        {
                            body.child(
                                text(crate::ui::currency::signed(a.change(), Currency::CNY))
                                    .typo(Type::Figure)
                                    .text_color(color::INK)
                                    .tabular_nums(),
                            )
                            .child(super::super::net_worth_review::breakdown(&a, edit))
                        }
                        Ok(Outcome::Missing(missing)) => body.child(
                            text(s().net_worth_missing(&missing))
                                .typo(Type::Subhead)
                                .text_color(color::MUTED),
                        ),
                        _ => body.child(
                            text(copy(
                                "Incomplete valuation for this period",
                                "区间估值不完整",
                            ))
                            .typo(Type::Subhead)
                            .text_color(color::MUTED),
                        ),
                    };
                    body.into_element()
                })
            },
        ))
        .into_element()
}

/// Keep each recovery link scoped to one contiguous gap.
fn date_ranges(days: &[Date]) -> impl Iterator<Item = (Date, Date)> + '_ {
    days.chunk_by(|a, b| a.tomorrow().ok().as_ref() == Some(b))
        .map(|run| (run[0], run[run.len() - 1]))
}

fn range_label(first: Date, last: Date) -> String {
    if first == last {
        first.to_string()
    } else {
        format!("{first} – {last}")
    }
}

fn missing_rates(currency: Currency, days: &[Date]) -> AnyElement {
    let reason = s().missing_rate(currency.code());
    let ranges: Vec<_> = date_ranges(days).collect();
    let count = ranges.len();
    let label = gap_count(&reason, days.len());
    gap_details(count, label, move || {
        view()
            .children(ranges.iter().map(|&(first, last)| {
                let label = format!("{reason} · {}", range_label(first, last));
                crate::ui::surface::row_button(move || {
                    crate::nav::push(crate::nav::Route::HistoricalRate {
                        currency,
                        from: Day(first),
                        to: Day(last),
                    })
                })
                .px_0()
                .min_h(px(48.0))
                .gap_2()
                .child(
                    text(label)
                        .flex_1()
                        .min_w(px(0.0))
                        .typo(Type::Subhead)
                        .tabular_nums()
                        .text_color(color::BODY),
                )
                .child(crate::ui::icon(
                    crate::ui::Icon::ChevronRight,
                    16.0,
                    color::MUTED,
                ))
            }))
            .into_element()
    })
}

fn gap_note(days: &[Date], reason: &str, tint: AdaptiveColor) -> AnyElement {
    let ranges: Vec<_> = date_ranges(days)
        .map(|(first, last)| range_label(first, last))
        .collect();
    let count = ranges.len();
    let detail = ranges.join(", ");
    let detail = if count <= 2 {
        format!("{reason} · {detail}")
    } else {
        detail
    };
    gap_details(count, gap_count(reason, days.len()), move || {
        text(detail.clone())
            .typo(Type::Subhead)
            .tabular_nums()
            .text_color(tint)
            .into_element()
    })
}

fn gap_count(reason: &str, days: usize) -> String {
    format!("{reason} · {days}{}", copy(" days", "天"))
}

fn gap_details(
    count: usize,
    label: String,
    content: impl Fn() -> AnyElement + 'static,
) -> AnyElement {
    if count <= 2 {
        return content();
    }
    let open = signal(false);
    view()
        .child(crate::ui::surface::disclosure(open, move || {
            label.clone().into()
        }))
        .child(when(move || open.get(), content))
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
