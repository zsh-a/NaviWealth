use super::*;
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordKind {
    Expense,
    Income,
    Transfer,
    OpeningBalance,
    Investment,
    Other,
}
impl RecordKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Expense => "支出",
            Self::Income => "收入",
            Self::Transfer => "转账",
            Self::OpeningBalance => "期初余额",
            Self::Investment => "投资交易",
            Self::Other => "其他记录",
        }
    }
}

/// Owning workflow for corrections. Structured records must be changed through
/// their original use case so linked receipts and the ledger remain consistent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecordSource {
    Daily,
    Wealth,
    Planning,
    Reconciliation,
    Other,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecordDraft {
    pub kind: RecordKind,
    pub date: i64,
    /// Positive magnitude, except opening balances which retain account signs.
    pub amount: Decimal,
    pub account_id: String,
    pub category_id: Option<String>,
    pub destination_account_id: Option<String>,
    pub destination_amount: Option<Decimal>,
    pub payee: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FinanceRecord {
    pub source: RecordSource,
    /// Typed investment intent for display; account arrows and signs cannot infer it.
    pub investment_kind: Option<crate::wealth::OperationKind>,
    /// Only standard two-leg daily records can be rewritten by the simple form.
    pub editable: bool,
    pub id: String,
    pub kind: RecordKind,
    pub date: i64,
    pub amount: Decimal,
    pub currency: String,
    pub account_id: String,
    pub account_name: String,
    pub category_id: Option<String>,
    pub category_name: Option<String>,
    pub destination_account_id: Option<String>,
    pub destination_account_name: Option<String>,
    pub destination_amount: Option<Decimal>,
    pub destination_currency: Option<String>,
    pub payee: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct RecordFilter {
    pub query: String,
    pub kind: Option<RecordKind>,
    pub account_id: Option<String>,
    /// Category ledger-account identity, independent of its display name.
    pub category_id: Option<String>,
    pub from: Option<i64>,
    /// Exclusive upper date bound.
    pub until: Option<i64>,
}
