//! From statement rows to balanced transactions for the owner to confirm.
//! A row's payment method names one of the owner's accounts (asked once,
//! then remembered per provider); its payee or the statement's category
//! picks the expense or income account. Each candidate is new, a duplicate
//! (its provider id is already in the journal or earlier in the statement)
//! or a possible duplicate (the same amount on the same own account within
//! a day, as when an Alipay purchase paid by card is also on the card's
//! statement). Nothing is kept here; the client keeps what is confirmed.

use std::collections::{BTreeMap, HashMap, HashSet};

use jiff::civil::DateTime;
use serde::{Deserialize, Serialize};

use crate::{
    account::{Account, AccountKind, defaults},
    journal::{self, Entry, Source, Transaction},
    statement::{Kind, Provider, Report, Row},
};

/// What the owner taught the import.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Rules {
    /// `provider key → payment method → own account`.
    pub methods: BTreeMap<String, BTreeMap<String, Account>>,
    /// `payee → expense or income account`, across providers.
    pub payees: BTreeMap<String, Account>,
}

impl Rules {
    /// Remembers that `method` on `provider`'s statements is `account`.
    pub fn remember_method(&mut self, provider: Provider, method: &str, account: Account) {
        if account.kind().is_own() {
            self.methods
                .entry(provider.key().to_owned())
                .or_default()
                .insert(method.to_owned(), account);
        }
    }

    /// Remembers `payee`'s category.
    pub fn remember_payee(&mut self, payee: &str, account: Account) {
        if matches!(account.kind(), AccountKind::Expenses | AccountKind::Income) {
            self.payees.insert(payee.to_owned(), account);
        }
    }

    fn own(&self, provider: Provider, method: &str) -> Option<Account> {
        self.methods.get(provider.key())?.get(method).cloned()
    }
}

/// The payment method a row is matched by: what the statement says, or
/// the provider's name when it says nothing.
pub fn method_of(provider: Provider, row: &Row) -> String {
    row.payment_method
        .clone()
        .unwrap_or_else(|| provider.key().to_owned())
}

/// The category of `row`: the payee's remembered one, else the statement's
/// hint, else `支出:其他` / `收入:其他`.
pub fn category_of(rules: &Rules, row: &Row) -> Account {
    let remembered = row
        .payee
        .as_ref()
        .and_then(|payee| rules.payees.get(payee))
        .filter(|a| {
            a.kind()
                == match row.kind {
                    Kind::Expense => AccountKind::Expenses,
                    Kind::Income => AccountKind::Income,
                }
        });
    if let Some(account) = remembered {
        return account.clone();
    }
    match (row.kind, row.category_hint) {
        (Kind::Income, Some("salary")) => defaults::income("工资"),
        (Kind::Income, _) => defaults::other_income(),
        (Kind::Expense, Some(hint)) => defaults::expense(match hint {
            "dining" | "coffee" => "餐饮",
            "groceries" => "买菜日用",
            "housing" | "utilities" => "居住",
            "shopping" => "购物",
            "entertainment" => "娱乐",
            "transport" => "交通",
            _ => "其他",
        }),
        (Kind::Expense, None) => defaults::other_expense(),
    }
}

/// Where a candidate stands.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    New,
    /// Its provider id is already kept, or appeared earlier in the file.
    Duplicate,
    /// Something like it is kept: shown, but not selected.
    PossibleDuplicate,
    /// Its payment method is not mapped to an account yet.
    NeedsAccount,
}

/// One row, ready for review.
#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
    pub row: Row,
    /// The id it is kept under, stable across imports of the same file.
    pub id: String,
    pub method: String,
    pub status: Status,
    pub category: Account,
    /// The balanced transaction, once its own account is known.
    pub transaction: Option<Transaction>,
}

impl Candidate {
    /// Whether the review page selects it at first.
    pub fn selected(&self) -> bool {
        self.status == Status::New
    }
}

/// A statement id for rows without one: their day, amount, method and
/// description, numbered when a statement repeats them.
fn fingerprint(row: &Row, method: &str, seen: &mut HashMap<String, usize>) -> String {
    let base = format!("{}|{}|{}|{}", row.at, row.amount, method, row.description);
    let n = seen.entry(base.clone()).or_insert(0);
    *n += 1;
    format!("fp:{base}#{n}")
}

/// The candidates of `report` against the kept `journal`.
pub fn prepare(report: &Report, rules: &Rules, journal: &[Transaction]) -> Vec<Candidate> {
    let provider = report.provider;
    let kept: HashSet<&str> = journal
        .iter()
        .filter_map(|t| match &t.source {
            Source::Statement { provider: p, id } if p == provider.key() => Some(id.as_str()),
            _ => None,
        })
        .collect();
    let mut in_file = HashSet::new();
    let mut seen = HashMap::new();
    report
        .rows
        .iter()
        .map(|row| {
            let method = method_of(provider, row);
            let id = row
                .reference
                .clone()
                .unwrap_or_else(|| fingerprint(row, &method, &mut seen));
            let category = category_of(rules, row);
            let own = rules.own(provider, &method);
            let transaction = own
                .as_ref()
                .and_then(|own| transaction(provider, row, &id, own, &category));
            let duplicate = kept.contains(id.as_str()) || !in_file.insert(id.clone());
            let status = if duplicate {
                Status::Duplicate
            } else if own.is_none() {
                Status::NeedsAccount
            } else if transaction.as_ref().is_some_and(|t| looks_kept(t, journal)) {
                Status::PossibleDuplicate
            } else {
                Status::New
            };
            Candidate {
                row: row.clone(),
                id,
                method,
                status,
                category,
                transaction,
            }
        })
        .collect()
}

/// The balanced transaction of `row` paid through `own`.
pub fn transaction(
    provider: Provider,
    row: &Row,
    id: &str,
    own: &Account,
    category: &Account,
) -> Option<Transaction> {
    let entry = Entry {
        id: format!("{}:{id}", provider.key()),
        at: row.at,
        payee: row.payee.clone().unwrap_or_default(),
        note: row.item.clone().unwrap_or_default(),
        source: Source::Statement {
            provider: provider.key().to_owned(),
            id: id.to_owned(),
        },
    };
    let amount = row.amount.checked_abs()?;
    match row.kind {
        Kind::Expense => journal::spend(entry, own, category, amount).ok(),
        Kind::Income => journal::receive(entry, own, category, amount).ok(),
    }
}

/// Whether a kept transaction moves the same amount through the same own
/// account within a day of `candidate`.
fn looks_kept(candidate: &Transaction, journal: &[Transaction]) -> bool {
    candidate.own_postings().any(|posting| {
        journal.iter().any(|kept| {
            within_a_day(kept.at, candidate.at)
                && kept
                    .own_postings()
                    .any(|p| p.account == posting.account && p.amount == posting.amount)
        })
    })
}

fn within_a_day(a: DateTime, b: DateTime) -> bool {
    let (a, b) = (a.date(), b.date());
    let (early, late) = if a <= b { (a, b) } else { (b, a) };
    early.tomorrow().is_ok_and(|next| late <= next)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::statement;

    const ALIPAY: &str = include_str!("../tests/fixtures/alipay_representative.csv");
    const CMB: &str = include_str!("../tests/fixtures/cmb_credit_card_representative.txt");

    fn acct(full: &str) -> Account {
        Account::parse(full).unwrap()
    }

    #[test]
    fn methods_are_asked_once_and_categories_follow_rules_then_hints() {
        let report = statement::parse(ALIPAY, "CNY");
        let mut rules = Rules::default();
        let first = prepare(&report, &rules, &[]);
        assert!(
            first
                .iter()
                .all(|c| c.status == Status::NeedsAccount && c.transaction.is_none())
        );
        assert_eq!(first[0].method, "余额");
        assert_eq!(first[0].category, defaults::expense("餐饮"));
        assert_eq!(first[1].category, defaults::expense("买菜日用"));

        rules.remember_method(Provider::Alipay, "余额", acct("资产:支付宝余额"));
        rules.remember_method(Provider::Alipay, "银行卡", acct("资产:招行储蓄卡"));
        rules.remember_method(Provider::Alipay, "无效", defaults::other_expense());
        rules.remember_payee("示例超市", defaults::expense("购物"));
        let ready = prepare(&report, &rules, &[]);
        assert!(
            ready
                .iter()
                .all(|c| c.status == Status::New && c.selected())
        );
        let t = ready[0].transaction.as_ref().unwrap();
        assert_eq!(t.validate(), Ok(()));
        assert_eq!(t.amount_in(&acct("资产:支付宝余额")), -3150);
        assert_eq!(t.amount_in(&defaults::expense("餐饮")), 3150);
        assert_eq!(t.payee, "示例餐厅");
        assert_eq!(t.id, "alipay:trade-1");
        assert_eq!(ready[1].category, defaults::expense("购物"));
        assert!(
            !rules.methods["alipay"].contains_key("无效"),
            "only own accounts"
        );
    }

    #[test]
    fn importing_the_same_statement_twice_adds_nothing() {
        let mut rules = Rules::default();
        rules.remember_method(
            Provider::CmbCreditCard,
            "招商银行信用卡(1234)",
            acct("负债:招行信用卡"),
        );
        let report = statement::parse(CMB, "CNY");
        let first = prepare(&report, &rules, &[]);
        assert_eq!(first.len(), 5);
        assert!(first.iter().all(|c| c.status == Status::New));
        let kept: Vec<Transaction> = first.into_iter().filter_map(|c| c.transaction).collect();
        let again = prepare(&report, &rules, &kept);
        assert!(
            again
                .iter()
                .all(|c| c.status == Status::Duplicate && !c.selected())
        );
    }

    #[test]
    fn a_card_purchase_on_two_statements_is_a_possible_duplicate() {
        // Alipay paid 68.00 by the CMB card on 07-02; the card's statement
        // has the same purchase dated the same day.
        let alipay = "支付宝交易记录明细\n交易时间,交易分类,交易对方,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号\n2026-07-02 19:30:00,餐饮美食,示例餐厅,晚餐,支出,68.00,招商银行信用卡(1234),交易成功,trade-9,order-9\n";
        let card = acct("负债:招行信用卡");
        let mut rules = Rules::default();
        rules.remember_method(Provider::Alipay, "招商银行信用卡(1234)", card.clone());
        rules.remember_method(Provider::CmbCreditCard, "招商银行信用卡(1234)", card);
        let kept: Vec<Transaction> = prepare(&statement::parse(alipay, "CNY"), &rules, &[])
            .into_iter()
            .filter_map(|c| c.transaction)
            .collect();
        assert_eq!(kept.len(), 1);
        let from_card = prepare(&statement::parse(CMB, "CNY"), &rules, &kept);
        let dinner = from_card
            .iter()
            .find(|c| c.row.description == "示例餐厅")
            .unwrap();
        assert_eq!(dinner.status, Status::PossibleDuplicate);
        assert!(!dinner.selected());
        assert_eq!(
            from_card.iter().filter(|c| c.status == Status::New).count(),
            4
        );
    }

    #[test]
    fn repeated_lines_without_ids_stay_distinct_and_dates_compare_by_day() {
        let text = "招商银行信用卡对账单 2026年07月\n交易明细\n07/02 07/03 示例餐厅 68.00 1234 68.00\n07/02 07/03 示例餐厅 68.00 1234 68.00\n";
        let mut rules = Rules::default();
        rules.remember_method(
            Provider::CmbCreditCard,
            "招商银行信用卡(1234)",
            acct("负债:招行信用卡"),
        );
        let candidates = prepare(&statement::parse(text, "CNY"), &rules, &[]);
        assert_eq!(candidates.len(), 2);
        assert_ne!(candidates[0].id, candidates[1].id);
        assert!(candidates.iter().all(|c| c.status == Status::New));
        let at = |d: i8| jiff::civil::date(2026, 7, d).at(23, 0, 0, 0);
        assert!(within_a_day(at(1), at(2)) && within_a_day(at(2), at(1)));
        assert!(!within_a_day(at(1), at(3)));
    }
}
