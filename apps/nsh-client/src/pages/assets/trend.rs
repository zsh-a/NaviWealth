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
    let explain = signal(false);
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
                                    estimate_panel(estimates_window, basis, explain, selected, edit)
                                }
                            })),
                    ),
                )
                .child(super::super::finance::finance_editor(edit)),
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

    /// The change from the earliest complete valuation to today's, when the
    /// history is too short for [`Self::change`] and both ends are known.
    pub fn since_first_dated(&self) -> Option<(Day, i64)> {
        let &(last, end) = self.points.last()?;
        let &(first, start) = self.points.iter().find(|p| p.1.is_some())?;
        if first == last {
            return None;
        }
        Some((Day(first), end?.checked_sub(start?)?))
    }
}

fn estimate_panel(
    window: Signal<Window>,
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
    view()
        .gap_3()
        .child(dynamic(move || {
            let from = window.get().available(today, earliest).start(today, earliest);
            let history = NetWorthHistory::between(&entries, &book, &rates, from, today);
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
                        today,
                        earliest,
                        Some(selected),
                    ))
                    .child(breakdown)
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
                                "A complete change is unavailable for these dates.",
                                "所选日期缺少完整估值，暂时无法拆解变化。",
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
