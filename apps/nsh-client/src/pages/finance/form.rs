//! The manual entry draft: its fields, the remembered values that decide
//! whether closing needs a confirmation, and its translation to and from the
//! supported two-posting (or exchange) transactions.

use jiff::civil::{Date, Time};
use navi_finance::{
    account::{Account, AccountKind},
    currency::Currency,
    journal::{self, Entry, Source, Transaction},
    money,
};
use nsh_core::prelude::*;

use crate::i18n::{Strings, s};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Kind {
    Expense,
    Income,
    Transfer,
}

impl Kind {
    pub(super) fn label(self, strings: &Strings) -> &'static str {
        match self {
            Self::Expense => strings.spending,
            Self::Income => strings.income,
            Self::Transfer => strings.transfer,
        }
    }
}

#[derive(Clone, Copy)]
pub(super) struct Own {
    pub(super) selected: Signal<String>,
    pub(super) creating: Signal<bool>,
    pub(super) kind: Signal<AccountKind>,
    pub(super) name: Signal<String>,
    pub(super) currency: Signal<Currency>,
}

impl Own {
    pub(super) fn new(account: Option<Account>) -> Self {
        let currency = account.as_ref().map_or(Currency::CNY, Account::currency);
        Self {
            currency: signal(currency),
            selected: signal(account.map(|a| a.to_string()).unwrap_or_default()),
            creating: signal(false),
            kind: signal(AccountKind::Assets),
            name: signal(String::new()),
        }
    }

    pub(super) fn account(self) -> Option<Account> {
        if self.creating.get() {
            Account::new_in(self.kind.get(), &self.name.get(), self.currency.get()).ok()
        } else {
            Account::parse(&self.selected.get())
                .ok()
                .filter(|a| a.is_cash())
        }
    }

    fn snapshot(self) -> (String, bool, AccountKind, String, Currency) {
        (
            self.selected.get(),
            self.creating.get(),
            self.kind.get(),
            self.name.get(),
            self.currency.get(),
        )
    }
}

#[derive(Clone, Copy)]
pub(super) struct Form {
    pub(super) kind: Signal<Kind>,
    pub(super) amount: Signal<String>,
    pub(super) received: Signal<String>,
    pub(super) day: Signal<String>,
    pub(super) time: Signal<String>,
    pub(super) own: Own,
    pub(super) other: Own,
    pub(super) category: Signal<String>,
    pub(super) payee: Signal<String>,
    pub(super) memo: Signal<String>,
}

#[derive(PartialEq)]
pub(super) struct Values {
    kind: Kind,
    amount: String,
    received: String,
    day: String,
    time: String,
    own: (String, bool, AccountKind, String, Currency),
    other: (String, bool, AccountKind, String, Currency),
    category: String,
    payee: String,
    memo: String,
}

impl Form {
    pub(super) fn values(self) -> Values {
        Values {
            kind: self.kind.get(),
            amount: self.amount.get(),
            received: self.received.get(),
            day: self.day.get(),
            time: self.time.get(),
            own: self.own.snapshot(),
            other: self.other.snapshot(),
            category: self.category.get(),
            payee: self.payee.get(),
            memo: self.memo.get(),
        }
    }

    pub(super) fn build(self, id: String, source: Source) -> Result<Transaction, &'static str> {
        let amount = money::parse(&self.amount.get(), false)
            .filter(|n| *n > 0)
            .ok_or(s().error_money)?;
        let day: Date = self
            .day
            .get()
            .trim()
            .parse()
            .map_err(|_| s().error_transaction_date)?;
        let time: Time = self
            .time
            .get()
            .trim()
            .parse()
            .map_err(|_| s().error_transaction_date)?;
        let own = self.own.account().ok_or(s().error_account)?;
        let entry = Entry {
            id,
            at: day.to_datetime(time),
            payee: self.payee.get().trim().to_owned(),
            note: self.memo.get().trim().to_owned(),
            source,
        };
        match self.kind.get() {
            Kind::Expense => {
                let category =
                    Account::parse(&self.category.get()).map_err(|_| s().error_account)?;
                journal::spend(entry, &own, &category.in_currency(own.currency()), amount)
                    .map_err(|_| s().error_account)
            }
            Kind::Income => {
                let category =
                    Account::parse(&self.category.get()).map_err(|_| s().error_account)?;
                journal::receive(entry, &own, &category.in_currency(own.currency()), amount)
                    .map_err(|_| s().error_account)
            }
            Kind::Transfer => {
                let other = self.other.account().ok_or(s().error_account)?;
                if own.currency() == other.currency() {
                    journal::transfer(entry, &own, &other, amount)
                } else {
                    let received = money::parse(&self.received.get(), false)
                        .filter(|v| *v > 0)
                        .ok_or(s().error_money)?;
                    journal::exchange(entry, &own, &other, amount, received)
                }
                .map_err(|_| s().error_transfer)
            }
        }
    }
}

/// The supported two-posting forms. Split postings and equity entries are never
/// flattened into a two-posting transaction by merely opening the editor.
pub(super) fn parts(t: &Transaction) -> Option<(Kind, Account, Account, i64)> {
    if t.validate().is_ok() && t.postings.len() == 4 {
        let from = t.own_postings().find(|p| p.amount < 0)?;
        let to = t.own_postings().find(|p| p.amount > 0)?;
        let amount = from.amount.checked_neg()?;
        let expected = journal::exchange(
            Entry {
                id: t.id.clone(),
                at: t.at,
                payee: t.payee.clone(),
                note: t.note.clone(),
                source: t.source.clone(),
            },
            &from.account,
            &to.account,
            amount,
            to.amount,
        )
        .ok()?;
        let sorted = |postings: &[journal::Posting]| {
            let mut values: Vec<_> = postings
                .iter()
                .map(|p| (p.account.clone(), p.amount))
                .collect();
            values.sort();
            values
        };
        if sorted(&expected.postings) == sorted(&t.postings) {
            return Some((
                Kind::Transfer,
                from.account.clone(),
                to.account.clone(),
                amount,
            ));
        }
    }
    if t.postings.len() != 2 || t.validate().is_err() {
        return None;
    }
    let positive = t.postings.iter().find(|p| p.amount > 0)?;
    let negative = t.postings.iter().find(|p| p.amount < 0)?;
    match (positive.account.kind(), negative.account.kind()) {
        (AccountKind::Expenses, own) if own.is_own() => Some((
            Kind::Expense,
            negative.account.clone(),
            positive.account.clone(),
            positive.amount,
        )),
        (own, AccountKind::Income) if own.is_own() => Some((
            Kind::Income,
            positive.account.clone(),
            negative.account.clone(),
            positive.amount,
        )),
        (a, b) if a.is_own() && b.is_own() => Some((
            Kind::Transfer,
            negative.account.clone(),
            positive.account.clone(),
            positive.amount,
        )),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use navi_finance::account::defaults;

    use super::*;

    #[test]
    fn simple_editor_round_trips_all_three_posting_directions() {
        let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
        let card = Account::new(AccountKind::Liabilities, "Card").unwrap();
        let entry = || Entry {
            id: "t".into(),
            at: "2026-11-14T12:30:00".parse().unwrap(),
            payee: "Shop".into(),
            note: String::new(),
            source: Source::Manual,
        };
        let expense = journal::spend(entry(), &card, &defaults::expense("餐饮"), 3150).unwrap();
        assert_eq!(
            parts(&expense),
            Some((Kind::Expense, card.clone(), defaults::expense("餐饮"), 3150))
        );
        let income = journal::receive(entry(), &cash, &defaults::income("工资"), 10000).unwrap();
        assert_eq!(
            parts(&income),
            Some((Kind::Income, cash.clone(), defaults::income("工资"), 10000))
        );
        let repayment = journal::transfer(entry(), &cash, &card, 3150).unwrap();
        assert_eq!(parts(&repayment), Some((Kind::Transfer, cash, card, 3150)));
    }

    #[test]
    fn opening_balance_is_not_silently_rewritten_as_spending() {
        let cash = Account::new(AccountKind::Assets, "Cash").unwrap();
        let entry = Entry {
            id: "t".into(),
            at: "2026-11-14T12:30:00".parse().unwrap(),
            payee: String::new(),
            note: String::new(),
            source: Source::Manual,
        };
        assert!(parts(&journal::opening(entry, &cash, 10000).unwrap()).is_none());
    }
}
