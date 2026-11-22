//! A first observed balance belongs before the account's recorded activity.
use super::{BalanceCheck, Error, balance_checks, confirm_balance_against, transactions};
use crate::{
    account::{Account, defaults},
    journal::Transaction,
};
use jiff::civil::Date;
use navi_storage::sqlite;

pub fn latest_day(
    account: &Account,
    entries: &[Transaction],
    checks: &[BalanceCheck],
    today: Date,
) -> Option<Date> {
    if checks.iter().any(|c| &c.account == account) {
        return None;
    }
    let equity = defaults::opening().in_currency(account.currency());
    let mut latest = today;
    for entry in entries
        .iter()
        .filter(|t| t.postings.iter().any(|p| &p.account == account))
    {
        if entry.postings.iter().any(|p| p.account == equity) {
            return None;
        }
        latest = latest.min(entry.at.date().yesterday().ok()?);
    }
    Some(latest)
}

/// Recheck eligibility in the write transaction: a later confirmation or a
/// newly imported earlier payment must not turn this intent into an adjustment.
pub fn confirm(
    tx: &sqlite::Transaction<'_>,
    check: &BalanceCheck,
) -> Result<Option<Transaction>, Error> {
    let entries = transactions(tx)?;
    let latest = latest_day(
        &check.account,
        &entries,
        &balance_checks(tx)?,
        check.checked_at.date(),
    );
    if latest.is_none_or(|day| check.day > day) {
        return Err(Error::BalanceChanged);
    }
    confirm_balance_against(tx, check, 0, &entries)
}
