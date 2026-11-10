use lifeos::sync::SyncMeta;

/// Wealth-container category of an account (mirrors the Flutter
/// `AccountCategory`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccountCategory {
    Cash,
    Bank,
    Broker,
    Crypto,
    Credit,
    Loan,
    Asset,
    Liability,
}

impl AccountCategory {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Cash => "cash",
            Self::Bank => "bank",
            Self::Broker => "broker",
            Self::Crypto => "crypto",
            Self::Credit => "credit",
            Self::Loan => "loan",
            Self::Asset => "asset",
            Self::Liability => "liability",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "cash" => Self::Cash,
            "bank" => Self::Bank,
            "broker" => Self::Broker,
            "crypto" => Self::Crypto,
            "credit" => Self::Credit,
            "loan" => Self::Loan,
            "asset" => Self::Asset,
            "liability" => Self::Liability,
            _ => return None,
        })
    }
}

/// Side of the double-entry identity the account settles to.
/// Auto-derived from [`AccountCategory`]; never user-edited.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccountSide {
    Asset,
    Liability,
    Income,
    Expense,
    Equity,
}

impl AccountSide {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Asset => "asset",
            Self::Liability => "liability",
            Self::Income => "income",
            Self::Expense => "expense",
            Self::Equity => "equity",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "asset" => Self::Asset,
            "liability" => Self::Liability,
            "income" => Self::Income,
            "expense" => Self::Expense,
            "equity" => Self::Equity,
            _ => return None,
        })
    }
}

/// Auto-derive the accounting side from a wealth-container category
/// (port of `accountSideForCategory`).
pub fn side_for_category(category: AccountCategory) -> AccountSide {
    match category {
        AccountCategory::Cash
        | AccountCategory::Bank
        | AccountCategory::Broker
        | AccountCategory::Crypto
        | AccountCategory::Asset => AccountSide::Asset,
        AccountCategory::Credit | AccountCategory::Loan | AccountCategory::Liability => {
            AccountSide::Liability
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Account {
    pub id: String,
    pub kind: AccountCategory,
    pub name: String,
    pub currency: String,
    pub institution: Option<String>,
    pub account_number: Option<String>,
    pub note: Option<String>,
    pub archived: bool,
    pub side: AccountSide,
    /// Beancount-style tree parent; no FK so sync reorders always land.
    pub parent_id: Option<String>,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub sync: SyncMeta,
}

/// Draft for a user-visible account. System accounts (income/expense/
/// equity) are seeded, never created here.
#[derive(Debug, Clone)]
pub struct NewAccount {
    pub kind: AccountCategory,
    pub name: String,
    pub currency: String,
    pub institution: Option<String>,
    pub account_number: Option<String>,
    pub note: Option<String>,
    pub parent_id: Option<String>,
    pub icon: Option<String>,
    pub color: Option<String>,
}

impl NewAccount {
    pub fn custody(
        kind: AccountCategory,
        name: impl Into<String>,
        currency: impl Into<String>,
    ) -> Self {
        Self {
            kind,
            name: name.into(),
            currency: currency.into(),
            institution: None,
            account_number: None,
            note: None,
            parent_id: None,
            icon: None,
            color: None,
        }
    }
}
