//! The double-entry journal: every transaction is two or more postings in
//! currency minor units that sum to zero within each currency. Balances, spending and net worth are
//! derived from the postings, never stored, so they always agree.

use std::collections::BTreeMap;

use jiff::civil::{Date, DateTime};
use serde::{Deserialize, Serialize};

use crate::{
    account::{Account, AccountKind, defaults},
    currency::Currency,
    money::{self, Minor},
};

/// One side of a transaction: `amount` into `account` (negative is out).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Posting {
    pub account: Account,
    pub amount: Minor,
}

/// Where a transaction came from.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Source {
    Manual,
    /// A statement row; `id` identifies it within its `provider`.
    Statement {
        provider: String,
        id: String,
    },
    /// Text or an image interpreted by the owner's model.
    Recognition {
        model: String,
        prompt_version: String,
    },
    /// A confirmed balance-check difference.
    BalanceCheck,
    /// Cash and cost postings generated only from a confirmed investment trade.
    Investment {
        trade_id: String,
    },
}

/// A balanced entry in the journal.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Transaction {
    pub id: String,
    /// When it happened, as the statement or the owner wrote it.
    pub at: DateTime,
    pub payee: String,
    pub note: String,
    pub source: Source,
    pub postings: Vec<Posting>,
}

/// Why a transaction cannot be kept.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum JournalError {
    #[error("a transaction needs at least two postings")]
    TooFewPostings,
    #[error("postings must sum to zero, not {0}")]
    Unbalanced(Minor),
    #[error("a posting has no amount")]
    ZeroPosting,
    #[error("an amount must be positive")]
    NotPositive,
    #[error("the account is of the wrong type for this transaction")]
    WrongKind,
    #[error("money moves between two different accounts")]
    SameAccount,
    #[error("account currencies do not match")]
    CurrencyMismatch,
}

impl Transaction {
    /// Checks the invariants: two or more non-zero postings summing to zero.
    pub fn validate(&self) -> Result<(), JournalError> {
        if self.postings.len() < 2 {
            return Err(JournalError::TooFewPostings);
        }
        if self.postings.iter().any(|p| p.amount == 0) {
            return Err(JournalError::ZeroPosting);
        }
        for currency in Currency::ALL {
            let total: i128 = self
                .postings
                .iter()
                .filter(|p| p.account.currency() == currency)
                .map(|p| i128::from(p.amount))
                .sum();
            if total != 0 {
                return Err(JournalError::Unbalanced(money::saturate(total)));
            }
        }
        Ok(())
    }

    /// The amount it moves into or out of `account` (zero when untouched).
    pub fn amount_in(&self, account: &Account) -> Minor {
        money::sum(
            self.postings
                .iter()
                .filter(|p| &p.account == account)
                .map(|p| p.amount),
        )
    }

    /// Whether any posting is to an own (asset or liability) account.
    pub fn own_postings(&self) -> impl Iterator<Item = &Posting> {
        self.postings.iter().filter(|p| p.account.kind().is_own())
    }
}

/// The parts every transaction shares.
#[derive(Debug, Clone)]
pub struct Entry {
    pub id: String,
    pub at: DateTime,
    pub payee: String,
    pub note: String,
    pub source: Source,
}

impl Entry {
    fn with(self, postings: Vec<Posting>) -> Transaction {
        Transaction {
            id: self.id,
            at: self.at,
            payee: self.payee,
            note: self.note,
            source: self.source,
            postings,
        }
    }
}

fn two(
    entry: Entry,
    into: &Account,
    from: &Account,
    amount: Minor,
) -> Result<Transaction, JournalError> {
    if amount <= 0 {
        return Err(JournalError::NotPositive);
    }
    if into.currency() != from.currency() {
        return Err(JournalError::CurrencyMismatch);
    }
    if into == from {
        return Err(JournalError::SameAccount);
    }
    Ok(entry.with(vec![
        Posting {
            account: into.clone(),
            amount,
        },
        Posting {
            account: from.clone(),
            amount: -amount,
        },
    ]))
}

/// Spending `amount` (positive) from the own account `from` on the expense
/// account `category`.
pub fn spend(
    entry: Entry,
    from: &Account,
    category: &Account,
    amount: Minor,
) -> Result<Transaction, JournalError> {
    if !from.kind().is_own() || category.kind() != AccountKind::Expenses {
        return Err(JournalError::WrongKind);
    }
    two(entry, category, from, amount)
}

/// Receiving `amount` into the own account `into` from the income account
/// `category`.
pub fn receive(
    entry: Entry,
    into: &Account,
    category: &Account,
    amount: Minor,
) -> Result<Transaction, JournalError> {
    if !into.kind().is_own() || category.kind() != AccountKind::Income {
        return Err(JournalError::WrongKind);
    }
    two(entry, into, category, amount)
}

/// Moving `amount` between two own accounts (a top-up, a repayment).
pub fn transfer(
    entry: Entry,
    from: &Account,
    into: &Account,
    amount: Minor,
) -> Result<Transaction, JournalError> {
    if !from.kind().is_own() || !into.kind().is_own() {
        return Err(JournalError::WrongKind);
    }
    two(entry, into, from, amount)
}

/// Exchange explicitly stated amounts, balancing each currency against equity.
pub fn exchange(
    entry: Entry,
    from: &Account,
    into: &Account,
    from_amount: Minor,
    to_amount: Minor,
) -> Result<Transaction, JournalError> {
    if !from.is_cash() || !into.is_cash() {
        return Err(JournalError::WrongKind);
    }
    if from.currency() == into.currency() {
        return Err(JournalError::CurrencyMismatch);
    }
    if from_amount <= 0 || to_amount <= 0 {
        return Err(JournalError::NotPositive);
    }
    let bridge = Account::new(AccountKind::Equity, "换汇").expect("fixed account");
    let t = entry.with(vec![
        Posting {
            account: from.clone(),
            amount: -from_amount,
        },
        Posting {
            account: bridge.in_currency(from.currency()),
            amount: from_amount,
        },
        Posting {
            account: into.clone(),
            amount: to_amount,
        },
        Posting {
            account: bridge.in_currency(into.currency()),
            amount: -to_amount,
        },
    ]);
    t.validate()?;
    Ok(t)
}

/// An own account's opening balance (`balance` may be negative: a debt).
pub fn opening(
    entry: Entry,
    account: &Account,
    balance: Minor,
) -> Result<Transaction, JournalError> {
    if !account.kind().is_own() {
        return Err(JournalError::WrongKind);
    }
    balance_against(
        entry,
        account,
        &defaults::opening().in_currency(account.currency()),
        balance,
    )
}

fn balance_against(
    entry: Entry,
    account: &Account,
    equity: &Account,
    amount: Minor,
) -> Result<Transaction, JournalError> {
    match amount {
        0 => Err(JournalError::ZeroPosting),
        a if a > 0 => two(entry, account, equity, a),
        a => two(
            entry,
            equity,
            account,
            a.checked_neg().ok_or(JournalError::NotPositive)?,
        ),
    }
}

/// Every account's balance over `transactions`.
pub fn balances<'a>(
    transactions: impl IntoIterator<Item = &'a Transaction>,
) -> BTreeMap<Account, Minor> {
    let mut totals: BTreeMap<Account, i128> = BTreeMap::new();
    for posting in transactions.into_iter().flat_map(|t| &t.postings) {
        *totals.entry(posting.account.clone()).or_default() += i128::from(posting.amount);
    }
    totals
        .into_iter()
        .map(|(account, total)| (account, money::saturate(total)))
        .collect()
}

/// `account`'s balance at the end of `day`.
pub fn balance_on<'a>(
    transactions: impl IntoIterator<Item = &'a Transaction>,
    account: &Account,
    day: Date,
) -> Minor {
    money::sum(
        transactions
            .into_iter()
            .filter(|t| t.at.date() <= day)
            .map(|t| t.amount_in(account)),
    )
}

/// Net worth: assets plus liabilities (liabilities are negative).
pub fn net_worth(balances: &BTreeMap<Account, Minor>) -> Minor {
    money::sum(
        balances
            .iter()
            .filter(|(account, _)| account.kind().is_own() && account.currency() == Currency::CNY)
            .map(|(_, amount)| *amount),
    )
}

/// What each expense account took from `first` to `last` (inclusive);
/// refunds lower it.
pub fn spending<'a>(
    transactions: impl IntoIterator<Item = &'a Transaction>,
    first: Date,
    last: Date,
) -> BTreeMap<Account, Minor> {
    let within = transactions
        .into_iter()
        .filter(|t| (first..=last).contains(&t.at.date()));
    balances(within)
        .into_iter()
        .filter(|(account, _)| account.kind() == AccountKind::Expenses)
        .collect()
}

/// The difference between a stated real balance and the book balance at
/// the end of `day` (positive: more money than the books say).
pub fn balance_difference<'a>(
    transactions: impl IntoIterator<Item = &'a Transaction>,
    account: &Account,
    day: Date,
    actual: Minor,
) -> Minor {
    money::saturate(i128::from(actual) - i128::from(balance_on(transactions, account, day)))
}

/// The adjustment that brings `account` to a stated balance, `difference`
/// away from the books, against `权益:调整`.
pub fn adjustment(
    entry: Entry,
    account: &Account,
    difference: Minor,
) -> Result<Transaction, JournalError> {
    if !account.kind().is_own() {
        return Err(JournalError::WrongKind);
    }
    balance_against(
        entry,
        account,
        &defaults::adjustment().in_currency(account.currency()),
        difference,
    )
}

#[cfg(test)]
mod tests {
    use jiff::civil::date;

    use super::*;

    fn entry(id: &str, day: Date) -> Entry {
        Entry {
            id: id.into(),
            at: day.at(12, 0, 0, 0),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        }
    }

    fn acct(full: &str) -> Account {
        Account::parse(full).unwrap()
    }

    #[test]
    fn transactions_balance_and_refuse_wrong_kinds() {
        let alipay = acct("资产:支付宝余额");
        let dining = defaults::expense("餐饮");
        let t = spend(entry("t1", date(2026, 7, 10)), &alipay, &dining, 3150).unwrap();
        assert_eq!(t.validate(), Ok(()));
        assert_eq!(t.amount_in(&dining), 3150);
        assert_eq!(t.amount_in(&alipay), -3150);
        assert_eq!(
            spend(entry("x", date(2026, 7, 10)), &dining, &alipay, 1),
            Err(JournalError::WrongKind)
        );
        assert_eq!(
            spend(entry("x", date(2026, 7, 10)), &alipay, &dining, 0),
            Err(JournalError::NotPositive)
        );
        assert_eq!(
            transfer(entry("x", date(2026, 7, 10)), &alipay, &alipay, 1),
            Err(JournalError::SameAccount)
        );
        let mut broken = t.clone();
        broken.postings[0].amount = 3000;
        assert_eq!(broken.validate(), Err(JournalError::Unbalanced(-150)));
        broken.postings.truncate(1);
        assert_eq!(broken.validate(), Err(JournalError::TooFewPostings));
        let mut zero = t;
        zero.postings.push(Posting {
            account: defaults::other_expense(),
            amount: 0,
        });
        assert_eq!(zero.validate(), Err(JournalError::ZeroPosting));
    }

    #[test]
    fn balances_spending_net_worth_and_balance_checks_derive_from_postings() {
        let bank = acct("资产:招行储蓄卡");
        let card = acct("负债:招行信用卡");
        let dining = defaults::expense("餐饮");
        let journal = vec![
            opening(entry("o1", date(2026, 7, 1)), &bank, 500_000).unwrap(),
            opening(entry("o2", date(2026, 7, 1)), &card, -20_000).unwrap(),
            spend(entry("t1", date(2026, 7, 2)), &card, &dining, 6800).unwrap(),
            receive(
                entry("t2", date(2026, 7, 5)),
                &bank,
                &defaults::income("工资"),
                1_000_000,
            )
            .unwrap(),
            transfer(entry("t3", date(2026, 7, 9)), &bank, &card, 26_800).unwrap(),
        ];
        let all = balances(&journal);
        assert_eq!(all[&bank], 1_473_200);
        assert_eq!(all[&card], 0, "repaid in full");
        assert_eq!(net_worth(&all), 1_473_200);
        assert_eq!(all.values().copied().sum::<i64>(), 0);
        assert_eq!(balance_on(&journal, &card, date(2026, 7, 2)), -26_800);
        let july = spending(&journal, date(2026, 7, 1), date(2026, 7, 31));
        assert_eq!(july.get(&dining), Some(&6800));
        assert_eq!(july.len(), 1);
        assert!(spending(&journal, date(2026, 7, 3), date(2026, 7, 31)).is_empty());

        // The bank really holds 2.00 less: a confirmed adjustment fixes it.
        let difference = balance_difference(&journal, &bank, date(2026, 7, 31), 1_473_000);
        assert_eq!(difference, -200);
        let fix = adjustment(entry("a1", date(2026, 7, 31)), &bank, difference).unwrap();
        assert_eq!(fix.amount_in(&bank), -200);
        assert_eq!(fix.amount_in(&defaults::adjustment()), 200);
        assert_eq!(
            adjustment(entry("a2", date(2026, 7, 31)), &bank, 0),
            Err(JournalError::ZeroPosting)
        );
    }

    #[test]
    fn any_mix_of_valid_transactions_sums_to_zero_and_net_worth_mirrors_the_rest() {
        // A deterministic pseudo-random walk (no external generator).
        let own = [
            acct("资产:现金"),
            acct("资产:支付宝余额"),
            acct("负债:花呗"),
        ];
        let mut seed: u64 = 0x5eed;
        let mut next = |n: u64| {
            seed = seed
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1_442_695_040_888_963_407);
            (seed >> 33) % n
        };
        let mut journal = Vec::new();
        for i in 0..2000 {
            let day = date(2026, 1, 1) + jiff::Span::new().days(next(365) as i64);
            let amount = 1 + next(500_000) as i64;
            let a = &own[next(3) as usize];
            let b = &own[next(3) as usize];
            let e = entry(&format!("t{i}"), day);
            let t = match next(4) {
                0 => spend(
                    e,
                    a,
                    &defaults::expense(defaults::EXPENSES[next(9) as usize]),
                    amount,
                ),
                1 => receive(e, a, &defaults::other_income(), amount),
                2 => transfer(e, a, b, amount),
                _ => opening(e, a, amount - 250_000),
            };
            if let Ok(t) = t {
                assert_eq!(t.validate(), Ok(()));
                journal.push(t);
            }
        }
        let all = balances(&journal);
        assert_eq!(all.values().map(|v| i128::from(*v)).sum::<i128>(), 0);
        let rest: i64 = all
            .iter()
            .filter(|(a, _)| !a.kind().is_own())
            .map(|(_, v)| *v)
            .sum();
        assert_eq!(net_worth(&all), -rest);
    }
}
