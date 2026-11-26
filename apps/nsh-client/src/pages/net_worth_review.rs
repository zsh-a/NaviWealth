//! Review's net-worth change: the close before the period against the close
//! of its last day (today for the current period), split into recorded
//! income and spending, investments, opening balances, balance corrections
//! and exchange rates ([`navi_finance::attribution`]). Investments open per
//! holding; corrections list their entries, which open in the editor. A
//! missing rate says so instead of showing a partial split.

use navi_finance::{
    attribution::{self, Attribution, Outcome, Part},
    currency::Currency,
};
use nsh_core::prelude::*;

use crate::{
    data::{clock, finance},
    domain::meal::Day,
    i18n::s,
    ui::{
        Type, Typo, color,
        currency::{format, signed},
        figures::counted,
        surface::{disclosure_chevron, row_button, section},
    },
};

/// The attribution of `days` (a period up to today), or `None` without a
/// ledger. Reads the ledger, holdings and rates, so callers track them.
pub(super) fn period_outcome(days: &[Day]) -> Option<Outcome> {
    let entries = finance::transactions_snapshot();
    if entries.is_empty() {
        return None;
    }
    let start = days.first()?.plus_days(-1).0;
    let end = days.last()?.0.min(clock::today().0);
    let (book, rates) = (finance::holdings_snapshot(), finance::rates_snapshot());
    attribution::attribute(&book, &entries, &rates, start, end)
        .inspect_err(|error| log::warn!("review: no net worth attribution: {error}"))
        .ok()
}

/// The disclosure chevron's width (`disclosure_chevron`).
const CHEVRON: f32 = 18.0;

/// What one part is made of: a holding, or an entry that opens the editor.
struct Detail {
    title: String,
    amount: i64,
    transaction: Option<String>,
}

pub fn net_worth_section(days: Memo<Vec<Day>>) -> impl IntoElement {
    let edit = signal(None::<String>);
    // The change figure lives above the rebuild boundary so a confirmed
    // entry rolls the number instead of jumping it.
    let change = computed(move || {
        period_outcome(&days.get()).and_then(|outcome| match outcome {
            Outcome::Complete(a) => Some(a.change()),
            _ => None,
        })
    });
    let shown = counted(move || change.get().map(|v| v as f64).unwrap_or(0.0));
    view()
        .child(dynamic(move || {
            let days = days.get();
            let outcome = period_outcome(&days);
            let start_day = days[0].plus_days(-1);
            untracked(move || match outcome {
                None => view().into_element(),
                Some(Outcome::Missing(missing)) => frame()
                    .child(
                        text(s().net_worth_missing(&missing))
                            .typo(Type::Subhead)
                            .text_color(color::MUTED),
                    )
                    .into_element(),
                Some(Outcome::Complete(a)) => complete(a, start_day, edit, shown).into_element(),
            })
        }))
        .child(super::finance::finance_editor(edit))
}

fn frame() -> View {
    section().gap_3().child(
        text(|| s().net_worth_change())
            .typo(Type::Headline)
            .text_color(color::INK),
    )
}

fn complete(
    a: Attribution,
    start_day: Day,
    edit: Signal<Option<String>>,
    shown: Signal<f64>,
) -> View {
    let cny = |amount| format(amount, Currency::CNY);
    frame()
        .child(
            text(move || signed(shown.get().round() as i64, Currency::CNY))
                .typo(Type::Lead)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(
            text(s().net_worth_span(start_day, &cny(a.start), &cny(a.end)))
                .typo(Type::Caption)
                .tabular_nums()
                .text_color(color::MUTED),
        )
        .child(breakdown(&a, edit))
}

/// Both Review and the dated Assets chart present the same six journal parts.
pub(super) fn breakdown(a: &Attribution, edit: Signal<Option<String>>) -> View {
    let parts: Vec<_> = a
        .parts()
        .into_iter()
        .filter(|(_, amount)| *amount != 0)
        .map(|(part, amount)| (part, amount, details(a, part)))
        .collect();
    view()
        .gap_2()
        .child(if parts.is_empty() {
            text(|| s().net_worth_unchanged())
                .typo(Type::Subhead)
                .text_color(color::MUTED)
                .into_element()
        } else {
            view()
                .children(
                    parts
                        .into_iter()
                        .map(move |(part, amount, details)| part_row(part, amount, details, edit)),
                )
                .into_element()
        })
        .child(
            (a.exchange != 0 && (a.income != 0 || a.spending != 0)).then(|| {
                text(|| s().net_worth_basis())
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
            }),
        )
}

fn details(a: &Attribution, part: Part) -> Vec<Detail> {
    match part {
        Part::Investment => {
            let book = finance::holdings_snapshot();
            a.holdings
                .iter()
                .map(|(id, amount)| Detail {
                    title: book
                        .securities
                        .iter()
                        .find(|security| security.id == *id)
                        .map_or_else(
                            || s().net_worth_other_investments().to_owned(),
                            |security| security.name.clone(),
                        ),
                    amount: *amount,
                    transaction: None,
                })
                .collect()
        }
        Part::Openings | Part::Adjustments => {
            let entries = finance::transactions_snapshot();
            a.corrections
                .iter()
                .filter(|c| c.part == part)
                .map(|c| {
                    let title = entries
                        .iter()
                        .find(|t| t.id == c.transaction)
                        .map(super::finance::transaction_title)
                        .unwrap_or_default();
                    Detail {
                        title: format!("{title} · {}", s().short_date(Day(c.day))),
                        amount: c.amount,
                        transaction: Some(c.transaction.clone()),
                    }
                })
                .collect()
        }
        Part::Income | Part::Spending | Part::Exchange => Vec::new(),
    }
}

fn line(label: String, amount: i64, style: Type, tint: AdaptiveColor) -> View {
    view()
        .flex_1()
        .min_w(px(0.0))
        .flex_row()
        .items_baseline()
        .gap_3()
        .child(
            text(label)
                .typo(style)
                .text_color(tint)
                .flex_1()
                .min_w(px(0.0)),
        )
        .child(
            text(signed(amount, Currency::CNY))
                .typo(Type::Subhead)
                .tabular_nums()
                .text_color(color::BODY),
        )
}

/// One part; a part with details is a visible disclosure.
fn part_row(
    part: Part,
    amount: i64,
    details: Vec<Detail>,
    edit: Signal<Option<String>>,
) -> AnyElement {
    let label = s().net_worth_part(part);
    if details.is_empty() {
        // The chevron's width keeps amounts in one column.
        return view()
            .min_h(px(48.0))
            .flex_row()
            .items_center()
            .gap_3()
            .child(line(label.to_owned(), amount, Type::Body, color::INK))
            .child(view().w(px(CHEVRON)))
            .into_element();
    }
    let open = signal(false);
    nsh_base::collapsible()
        .open(open)
        .child(
            row_button(move || open.update(|o| *o = !*o))
                .min_h(px(48.0))
                .px(px(0.0))
                .py(px(4.0))
                .accessibility_label(move || {
                    Some(
                        format!(
                            "{label}, {}, {}",
                            signed(amount, Currency::CNY),
                            s().net_worth_details(open.get())
                        )
                        .into(),
                    )
                })
                .child(line(label.to_owned(), amount, Type::Body, color::INK))
                .child(disclosure_chevron(open)),
        )
        .content(dynamic(move || {
            view().pl(px(12.0)).children(details.iter().map(|d| {
                let row = line(d.title.clone(), d.amount, Type::Subhead, color::BODY);
                match d.transaction.clone() {
                    Some(id) => row_button(move || edit.set(Some(id.clone())))
                        .min_h(px(48.0))
                        .px(px(0.0))
                        .py(px(4.0))
                        .child(row)
                        .into_element(),
                    None => view()
                        .min_h(px(44.0))
                        .flex_row()
                        .items_center()
                        .child(row)
                        .into_element(),
                }
            }))
        }))
        .into_element()
}
