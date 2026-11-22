//! Accounts of the five double-entry types, named `type:name`
//! (`资产:支付宝余额`, `支出:餐饮`). Assets and liabilities are the owner's
//! own accounts; expenses and income are the categories; equity holds
//! opening balances and balance-check adjustments.

use crate::currency::Currency;
use std::fmt;

use serde::{Deserialize, Serialize};

/// The five types. Balances follow the usual signs: assets and expenses
/// positive, liabilities, income and equity negative.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub enum AccountKind {
    Assets,
    Liabilities,
    Income,
    Expenses,
    Equity,
}

impl AccountKind {
    pub const ALL: [AccountKind; 5] = [
        AccountKind::Assets,
        AccountKind::Liabilities,
        AccountKind::Income,
        AccountKind::Expenses,
        AccountKind::Equity,
    ];

    /// The name's prefix (`资产`).
    pub fn prefix(self) -> &'static str {
        match self {
            AccountKind::Assets => "资产",
            AccountKind::Liabilities => "负债",
            AccountKind::Income => "收入",
            AccountKind::Expenses => "支出",
            AccountKind::Equity => "权益",
        }
    }

    fn of_prefix(prefix: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|kind| kind.prefix() == prefix)
    }

    /// Whether it is one of the owner's own accounts (money they hold or
    /// owe), as opposed to a category or equity.
    pub fn is_own(self) -> bool {
        matches!(self, AccountKind::Assets | AccountKind::Liabilities)
    }
}

/// The owner's use for a cash or liability account. Older accounts can stay
/// unclassified, including accounts referenced by historical trades.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AccountPurpose {
    Cash,
    Bank,
    Wallet,
    Brokerage,
    Credit,
    Loan,
}

impl AccountPurpose {
    pub const ALL: [Self; 6] = [
        Self::Cash,
        Self::Bank,
        Self::Wallet,
        Self::Brokerage,
        Self::Credit,
        Self::Loan,
    ];

    pub fn kind(self) -> AccountKind {
        match self {
            Self::Cash | Self::Bank | Self::Wallet | Self::Brokerage => AccountKind::Assets,
            Self::Credit | Self::Loan => AccountKind::Liabilities,
        }
    }

    pub fn usable_for_settlement(self) -> bool {
        matches!(self, Self::Bank | Self::Brokerage)
    }

    pub(crate) fn code(self) -> &'static str {
        match self {
            Self::Cash => "cash",
            Self::Bank => "bank",
            Self::Wallet => "wallet",
            Self::Brokerage => "brokerage",
            Self::Credit => "credit",
            Self::Loan => "loan",
        }
    }
}

/// Why a name is not an account.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AccountError {
    #[error("an account is named type:name")]
    Unnamed,
    #[error("unknown account type")]
    UnknownKind,
    #[error("an account name is 1 to {MAX_NAME} characters without ':' or control characters")]
    BadName,
}

/// The longest name after the type, in characters.
pub const MAX_NAME: usize = 40;

/// A validated account, `type:name`.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct Account(String);

impl Account {
    /// The account `name` of `kind` (the name trimmed).
    pub fn new(kind: AccountKind, name: &str) -> Result<Self, AccountError> {
        Self::new_in(kind, name, Currency::CNY)
    }

    pub fn new_in(kind: AccountKind, name: &str, currency: Currency) -> Result<Self, AccountError> {
        let name = name.trim();
        let valid = !name.is_empty()
            && name.chars().count() <= MAX_NAME
            && !name
                .chars()
                .any(|c| c == ':' || c == '：' || c.is_control());
        if !valid {
            return Err(AccountError::BadName);
        }
        Ok(Account(if currency == Currency::CNY {
            format!("{}:{name}", kind.prefix())
        } else {
            format!("{}/{currency}:{name}", kind.prefix())
        }))
    }

    /// The account written as `type:name`.
    pub fn parse(full: &str) -> Result<Self, AccountError> {
        let (prefix, name) = full.split_once(':').ok_or(AccountError::Unnamed)?;
        let (prefix, currency) = match prefix.trim().split_once('/') {
            Some((p, c)) => (p, Currency::parse(c).ok_or(AccountError::UnknownKind)?),
            None => (prefix.trim(), Currency::CNY),
        };
        let kind = AccountKind::of_prefix(prefix).ok_or(AccountError::UnknownKind)?;
        Self::new_in(kind, name, currency)
    }

    pub fn kind(&self) -> AccountKind {
        let prefix = self.0.split_once(':').map_or("", |(p, _)| p);
        AccountKind::of_prefix(prefix.split('/').next().unwrap_or(prefix))
            .unwrap_or(AccountKind::Equity)
    }

    /// The name after the type (`支付宝余额`).
    pub fn name(&self) -> &str {
        self.0.split_once(':').map_or("", |(_, n)| n)
    }

    pub fn currency(&self) -> Currency {
        self.0
            .split_once(':')
            .and_then(|(p, _)| p.split_once('/'))
            .and_then(|(_, c)| Currency::parse(c))
            .unwrap_or(Currency::CNY)
    }

    pub fn in_currency(&self, currency: Currency) -> Self {
        Self::new_in(self.kind(), self.name(), currency).expect("validated account")
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn is_holding(&self) -> bool {
        self.kind() == AccountKind::Assets
            && self.name().starts_with(crate::holdings::ACCOUNT_PREFIX)
    }
    /// Securities settle against an asset account in the instrument's currency.
    pub fn is_settlement_cash(&self, currency: Currency) -> bool {
        self.is_cash() && self.kind() == AccountKind::Assets && self.currency() == currency
    }

    /// New settlements honor current purpose. Replaying an existing trade
    /// only needs its original native asset account and currency.
    pub fn can_settle(&self, currency: Currency, purpose: Option<AccountPurpose>) -> bool {
        self.is_settlement_cash(currency)
            && purpose.is_none_or(AccountPurpose::usable_for_settlement)
    }

    /// Accounts that can be picked for cash entry or balance reconciliation.
    pub fn is_cash(&self) -> bool {
        self.kind().is_own() && !self.is_holding()
    }
}

impl fmt::Display for Account {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl TryFrom<String> for Account {
    type Error = AccountError;
    fn try_from(full: String) -> Result<Self, Self::Error> {
        Account::parse(&full)
    }
}

impl From<Account> for String {
    fn from(account: Account) -> Self {
        account.0
    }
}

/// The accounts every ledger starts with: the fixed categories and equity.
pub mod defaults {
    use super::{Account, AccountKind};

    /// Expense categories, in the order they are offered.
    pub const EXPENSES: [&str; 9] = [
        "餐饮",
        "买菜日用",
        "交通",
        "居住",
        "购物",
        "娱乐",
        "医疗",
        "人情",
        "其他",
    ];
    /// Income categories.
    pub const INCOME: [&str; 2] = ["工资", "其他"];

    fn fixed(kind: AccountKind, name: &str) -> Account {
        Account::new(kind, name).unwrap_or_else(|_| unreachable!("built-in names are valid"))
    }

    pub fn expense(name: &str) -> Account {
        fixed(AccountKind::Expenses, name)
    }

    pub fn income(name: &str) -> Account {
        fixed(AccountKind::Income, name)
    }

    /// `支出:其他`, where an expense lands until a better category is chosen.
    pub fn other_expense() -> Account {
        expense("其他")
    }

    /// `收入:其他`.
    pub fn other_income() -> Account {
        income("其他")
    }

    /// `权益:期初`, the other side of opening balances.
    pub fn opening() -> Account {
        fixed(AccountKind::Equity, "期初")
    }

    /// `权益:调整`, the other side of confirmed balance-check differences.
    pub fn adjustment() -> Account {
        fixed(AccountKind::Equity, "调整")
    }

    /// Every built-in account.
    pub fn all() -> Vec<Account> {
        EXPENSES
            .iter()
            .map(|n| expense(n))
            .chain(INCOME.iter().map(|n| income(n)))
            .chain([opening(), adjustment()])
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_carry_their_type_and_are_validated() {
        let card = Account::parse("负债:招行信用卡(1234)").unwrap();
        assert_eq!(card.kind(), AccountKind::Liabilities);
        assert_eq!(card.name(), "招行信用卡(1234)");
        assert!(card.kind().is_own());
        assert!(!defaults::expense("餐饮").kind().is_own());
        assert_eq!(
            Account::new(AccountKind::Assets, "  现金 ")
                .unwrap()
                .as_str(),
            "资产:现金"
        );
        assert_eq!(Account::parse("现金"), Err(AccountError::Unnamed));
        assert_eq!(Account::parse("钱包:现金"), Err(AccountError::UnknownKind));
        assert_eq!(Account::parse("资产: "), Err(AccountError::BadName));
        assert_eq!(Account::parse("资产:a:b"), Err(AccountError::BadName));
        assert_eq!(
            Account::new(AccountKind::Assets, &"长".repeat(41)),
            Err(AccountError::BadName)
        );
    }

    #[test]
    fn defaults_are_the_fixed_categories_and_equity() {
        let all = defaults::all();
        assert_eq!(all.len(), 13);
        assert!(all.contains(&defaults::other_expense()));
        assert_eq!(defaults::opening().as_str(), "权益:期初");
        let json = serde_json::to_string(&defaults::adjustment()).unwrap();
        assert_eq!(json, "\"权益:调整\"");
        assert!(serde_json::from_str::<Account>("\"x:y\"").is_err());
    }
}
