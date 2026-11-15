//! Account views and balance reconciliation derived from the journal.
use crate::currency::Currency;
use crate::{
    account::{Account, AccountKind},
    journal::{self, Transaction},
    money::{self, Minor},
};
use jiff::civil::Date;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    pub assets: Minor,
    /// Positive is debt; a credit balance may make this negative.
    pub debt: Minor,
    pub net: Minor,
}

pub fn snapshot(entries: &[Transaction], day: Date) -> Snapshot {
    snapshot_in(entries, day, Currency::CNY)
}

pub fn snapshot_in(entries: &[Transaction], day: Date, currency: Currency) -> Snapshot {
    let balances = journal::balances(entries.iter().filter(|t| t.at.date() <= day))
        .into_iter()
        .filter(|(a, _)| a.currency() == currency)
        .collect::<std::collections::BTreeMap<_, _>>();
    let assets = money::sum(
        balances
            .iter()
            .filter(|(a, _)| a.kind() == AccountKind::Assets)
            .map(|(_, v)| *v),
    );
    let debt = money::saturate(
        -balances
            .iter()
            .filter(|(a, _)| a.kind() == AccountKind::Liabilities)
            .map(|(_, v)| i128::from(*v))
            .sum::<i128>(),
    );
    Snapshot {
        assets,
        debt,
        net: money::sum(
            balances
                .iter()
                .filter(|(a, _)| a.kind().is_own())
                .map(|(_, v)| *v),
        ),
    }
}

/// A liability's displayed balance is the amount owed, including credit
/// balances as negatives. Exact conversion rejects the unrepresentable edge.
pub fn book_value(account: &Account, displayed: Minor) -> Option<Minor> {
    if account.kind() == AccountKind::Liabilities {
        displayed.checked_neg()
    } else {
        Some(displayed)
    }
}
pub fn displayed(account: &Account, book: Minor) -> Minor {
    if account.kind() == AccountKind::Liabilities {
        money::saturate(-i128::from(book))
    } else {
        book
    }
}

/// Daily end-of-day net worth, never inventing history before the first entry.
pub fn trend(entries: &[Transaction], first: Date, last: Date) -> Vec<(Date, Minor)> {
    let Some(start) = entries
        .iter()
        .map(|t| t.at.date())
        .min()
        .map(|d| d.max(first))
    else {
        return vec![];
    };
    let mut points = Vec::new();
    let mut day = start;
    while day <= last {
        points.push((day, snapshot(entries, day).net));
        let Ok(next) = day.tomorrow() else {
            break;
        };
        day = next;
    }
    points
}
