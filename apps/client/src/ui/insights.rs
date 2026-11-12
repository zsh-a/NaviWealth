//! Shared financial presentation; it never mutates domain values.
use super::*;
use naviwealth_finance::daily::DailySpending;
use naviwealth_finance::planning::BudgetProgress;
use rust_decimal::{Decimal, prelude::ToPrimitive};
use std::collections::BTreeMap;

pub fn progress_bar(ratio: f32) -> impl Element {
    progress_bar_state(ratio, false)
}
pub fn progress_bar_state(ratio: f32, exceeded: bool) -> impl Element {
    nsh_base::progress()
        .value(ratio.clamp(0.0, 1.0) * 100.0)
        .accessibility_label("预算与目标进度")
        .track_style(|s| s.h(px(4.0)).rounded_full().bg(move || theme().border))
        .indicator_style(move |s| {
            s.h_full().rounded_full().bg(move || {
                if exceeded {
                    theme().destructive
                } else {
                    theme().primary
                }
            })
        })
}
pub fn ratio(value: Decimal, total: Decimal) -> f32 {
    if total <= Decimal::ZERO {
        return 0.0;
    }
    value
        .checked_div(total)
        .and_then(|v| v.to_f32())
        .unwrap_or(0.0)
        .clamp(0.0, 1.0)
}
pub fn budget_totals(budgets: &[BudgetProgress]) -> Option<BTreeMap<String, (Decimal, Decimal)>> {
    let mut totals = BTreeMap::<String, (Decimal, Decimal)>::new();
    for b in budgets {
        let row = totals.entry(b.budget.currency.clone()).or_default();
        row.0 = row.0.checked_add(b.spent)?;
        row.1 = row.1.checked_add(b.budget.limit)?;
    }
    Some(totals)
}
/// Every day is included, including zero spending. Transfers and openings
/// never enter a spending chart. Currency families remain separate.
pub fn daily_spending(
    records: &[DailySpending],
    currency: &str,
    days: usize,
) -> Option<Vec<Decimal>> {
    let mut values = vec![Decimal::ZERO; days];
    for r in records.iter().filter(|r| r.currency == currency) {
        let date = ymd(r.date);
        let day = date.get(8..10)?.parse::<usize>().ok()?.checked_sub(1)?;
        if let Some(v) = values.get_mut(day) {
            *v = v.checked_add(r.amount)?;
        }
    }
    Some(values)
}
pub fn transaction_row(
    title: String,
    subtitle: String,
    category: &str,
    value: String,
    currency: RowCurrency,
    id: String,
    on_press: impl Fn() + 'static,
) -> NativeButton {
    transaction_amount_row(
        title,
        subtitle,
        category,
        RowAmount {
            value,
            currency: currency.code,
            inline_unit: currency.inline,
            secondary: None,
        },
        id,
        on_press,
    )
}
pub struct RowAmount {
    pub value: String,
    pub inline_unit: Option<String>,
    pub currency: String,
    pub secondary: Option<String>,
}
pub fn transaction_amount_row(
    title: String,
    subtitle: String,
    category: &str,
    amount: RowAmount,
    id: String,
    on_press: impl Fn() + 'static,
) -> NativeButton {
    let RowAmount {
        value,
        currency,
        secondary,
        inline_unit,
    } = amount;

    let tone = value.clone();
    press_target(on_press)
        .test_id(&id)
        .label(format!("{title}，{subtitle}，{value} {currency}"))
        .min_h(move || px(token("row-height")))
        .py(move || px(token("space-row")))
        .flex_row()
        .items_center()
        .gap(move || px(token("space-icon")))
        .child(category_icon(category))
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(
                    text(title)
                        .truncate()
                        .text_size(move || px(token("type-body")))
                        .font_weight(FontWeight::MEDIUM),
                )
                .child(quiet_text(subtitle).truncate()),
        )
        .child(
            view()
                .flex_shrink_0()
                .items_end()
                .gap_1()
                .child(
                    text(value)
                        .text_color(move || money_tone(&tone))
                        .tabular_nums()
                        .text_size(move || px(token("type-body")))
                        .font_weight(FontWeight::MEDIUM)
                        .child(inline_unit.map(|unit| {
                            text(format!(" {unit}"))
                                .text_size(move || px(token("type-caption")))
                                .font_weight(FontWeight::NORMAL)
                                .text_color(move || theme().muted_foreground)
                        })),
                )
                .child(secondary.map(|secondary| {
                    let tone = secondary.clone();
                    quiet_text(secondary).text_color(move || money_tone(&tone))
                })),
        )
}

#[cfg(test)]
#[path = "insights_tests.rs"]
mod tests;

/// Positive spending only; strict comparison keeps the earliest tied day.
pub fn spending_peak(values: &[Decimal]) -> Option<(usize, Decimal)> {
    values.iter().enumerate().fold(None, |peak, (i, v)| {
        if *v > Decimal::ZERO && peak.is_none_or(|(_, max)| *v > max) {
            Some((i, *v))
        } else {
            peak
        }
    })
}
