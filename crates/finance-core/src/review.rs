//! Recorded spending, derived exclusively from expense postings.
use crate::currency::Currency;
use crate::{
    account::AccountKind,
    journal::Transaction,
    money::{self, Minor},
};
use jiff::civil::Date;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Spending {
    pub total: Minor,
    /// Expense records, including refunds; absence is distinct from zero.
    pub records: usize,
    /// Largest net categories first, with stable alphabetical ties.
    pub categories: Vec<(String, Minor)>,
}

pub fn spending(entries: &[Transaction], from: Date, to: Date) -> Spending {
    spending_in(entries, from, to, Currency::CNY)
}

pub fn spending_in(entries: &[Transaction], from: Date, to: Date, currency: Currency) -> Spending {
    let rows = transactions_in(entries, from, to, None, currency);
    let mut categories = BTreeMap::<String, i128>::new();
    for t in &rows {
        for p in &t.postings {
            if p.account.kind() == AccountKind::Expenses && p.account.currency() == currency {
                *categories.entry(p.account.to_string()).or_default() += i128::from(p.amount);
            }
        }
    }
    let total = money::saturate(categories.values().copied().sum());
    let mut categories: Vec<_> = categories
        .into_iter()
        .map(|(a, v)| (a, money::saturate(v)))
        .collect();
    categories.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    Spending {
        total,
        records: rows.len(),
        categories,
    }
}

/// The exact rows behind a total/category. Newest first, including refunds.
pub fn transactions(
    entries: &[Transaction],
    from: Date,
    to: Date,
    category: Option<&str>,
) -> Vec<Transaction> {
    transactions_in(entries, from, to, category, Currency::CNY)
}

pub fn transactions_in(
    entries: &[Transaction],
    from: Date,
    to: Date,
    category: Option<&str>,
    currency: Currency,
) -> Vec<Transaction> {
    let mut rows: Vec<_> = entries
        .iter()
        .filter(|t| {
            t.at.date() >= from
                && t.at.date() <= to
                && t.postings.iter().any(|p| {
                    p.account.kind() == AccountKind::Expenses
                        && p.account.currency() == currency
                        && category.is_none_or(|c| p.account.as_str() == c)
                })
        })
        .cloned()
        .collect();
    rows.sort_by(|a, b| b.at.cmp(&a.at).then(a.id.cmp(&b.id)));
    rows
}

/// Current periods compare the same number of elapsed calendar days;
/// completed periods compare their full predecessor (including short months).
pub fn comparison_end(
    from: Date,
    to: Date,
    previous_from: Date,
    previous_to: Date,
    today: Date,
) -> Date {
    if today >= to {
        return previous_to;
    }
    let elapsed = (today - from).get_days().max(0);
    previous_from
        .checked_add(jiff::Span::new().days(elapsed))
        .unwrap_or(previous_to)
        .min(previous_to)
}
