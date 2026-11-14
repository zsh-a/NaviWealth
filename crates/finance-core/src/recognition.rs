//! Untrusted recognition drafts. Missing information stays missing; only an
//! explicitly confirmed, complete draft can become balanced journal postings.

use crate::{
    account::{Account, AccountKind, defaults},
    journal::{self, Entry, Transaction},
    money,
};
use jiff::civil::{Date, Time};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Expense,
    Income,
    Transfer,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MoneyDraft {
    pub kind: Kind,
    /// Decimal CNY text, never a floating-point approximation.
    pub amount: Option<String>,
    pub currency: String,
    pub account: Option<Account>,
    pub other_account: Option<Account>,
    pub category: Option<Account>,
    pub time: Option<Time>,
    pub payee: String,
    pub note: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum Missing {
    #[error("invalid recognition values")]
    Invalid,
    #[error("amount")]
    Amount,
    #[error("account")]
    Account,
    #[error("category")]
    Category,
    #[error("destination account")]
    OtherAccount,
}

impl MoneyDraft {
    /// Reject invalid values; null is allowed so the UI can ask only for what
    /// is missing. A model cannot invent foreign currencies or equity entries.
    pub fn valid(&self) -> bool {
        self.currency == "CNY"
            && if self.kind == Kind::Transfer {
                self.category.is_none()
            } else {
                self.other_account.is_none()
            }
            && self
                .amount
                .as_ref()
                .is_none_or(|v| money::parse(v, false).is_some_and(|n| n > 0))
            && self.account.as_ref().is_none_or(|a| a.is_cash())
            && self.other_account.as_ref().is_none_or(|a| a.is_cash())
            && self.category.as_ref().is_none_or(|a| {
                a.kind()
                    == if self.kind == Kind::Income {
                        AccountKind::Income
                    } else {
                        AccountKind::Expenses
                    }
                    && defaults::all().contains(a)
            })
            && self.payee.chars().count() <= 120
            && self.note.chars().count() <= 500
    }

    pub fn transaction(&self, mut entry: Entry, day: Date) -> Result<Transaction, Missing> {
        if !self.valid() {
            return Err(Missing::Invalid);
        }
        let amount = self
            .amount
            .as_ref()
            .and_then(|v| money::parse(v, false))
            .filter(|n| *n > 0)
            .ok_or(Missing::Amount)?;
        let account = self
            .account
            .as_ref()
            .filter(|a| a.is_cash())
            .ok_or(Missing::Account)?;
        entry.at = day.to_datetime(self.time.unwrap_or(entry.at.time()));
        entry.payee.clone_from(&self.payee);
        entry.note.clone_from(&self.note);
        match self.kind {
            Kind::Transfer => {
                let other = self.other_account.as_ref().ok_or(Missing::OtherAccount)?;
                journal::transfer(entry, account, other, amount).map_err(|_| Missing::OtherAccount)
            }
            Kind::Expense | Kind::Income => {
                let category = self.category.as_ref().ok_or(Missing::Category)?;
                if self.kind == Kind::Expense {
                    journal::spend(entry, account, category, amount)
                } else {
                    journal::receive(entry, account, category, amount)
                }
                .map_err(|_| Missing::Category)
            }
        }
    }
}

pub const INSTRUCTIONS: &str = "For money, extract CNY expense, income or transfers only. Amounts are exact decimal STRINGS, never floats. Use the final paid amount, not an order subtotal, credit limit or account balance. Account names use the exact type:name format from known_accounts. If the input explicitly names a new payment account, propose 资产:name (cash/debit) or 负债:name (credit/debt); never guess an absent payment account or choose an alphabetical default. A payment app is NOT proof of its underlying funding account: Alipay/WeChat may use a card. Use null for missing amount/account/category/time. Classify categories only from known_categories. Repayments and top-ups are transfers, not spending. Unsupported refunds, trades, foreign currencies, account balances and ambiguous amounts require clarification, not a fabricated transaction. Do not create multiple copies of the same transaction visible in an image. If time is absent leave it null; the day is still required.";

pub fn schema() -> Value {
    let nullable = || json!({"type":["string","null"]});
    json!({"type":"object","additionalProperties":false,
    "required":["kind","amount","currency","account","other_account","category","time","payee","note"],
    "properties":{
        "kind":{"type":"string","enum":["expense","income","transfer"]},
        "amount":nullable(),"currency":{"type":"string","enum":["CNY"]},
        "account":nullable(),"other_account":nullable(),"category":nullable(),"time":nullable(),
        "payee":{"type":"string"},"note":{"type":"string"}
    }})
}
