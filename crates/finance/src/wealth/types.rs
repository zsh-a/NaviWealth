use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};

/// Decimal fields in sync payloads remain strings, never binary floating point.
pub(super) mod decimal {
    use rust_decimal::Decimal;
    use serde::{Deserialize, Deserializer, Serializer, de::Error};
    pub fn serialize<S: Serializer>(v: &Decimal, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&v.to_string())
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Decimal, D::Error> {
        Decimal::from_str_exact(&String::deserialize(d)?).map_err(D::Error::custom)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AssetDraft {
    pub kind: String,
    pub name: String,
    pub market: Option<String>,
    pub symbol: Option<String>,
    pub currency: String,
    pub note: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WealthAsset {
    pub id: String,
    pub details: AssetDraft,
    pub archived: bool,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OperationKind {
    Opening,
    Buy,
    Sell,
    Dividend,
    Split,
}
impl OperationKind {
    pub fn label(self) -> &'static str {
        match self {
            Self::Opening => "期初持仓",
            Self::Buy => "买入",
            Self::Sell => "卖出",
            Self::Dividend => "分红",
            Self::Split => "拆股",
        }
    }
}
/// Opening/Buy/Sell use quantity + unit_price. Dividend uses amount, Split
/// uses quantity as the new/old share ratio. Fees are cash settlement costs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct OperationDraft {
    pub kind: OperationKind,
    pub asset_id: String,
    pub account_id: String,
    pub cash_account_id: Option<String>,
    pub date: i64,
    #[serde(with = "decimal")]
    pub quantity: Decimal,
    #[serde(with = "decimal")]
    pub unit_price: Decimal,
    #[serde(with = "decimal")]
    pub fees: Decimal,
    #[serde(with = "decimal")]
    pub amount: Decimal,
    pub note: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WealthOperation {
    /// Also the journal entry identity. Edits preserve it.
    pub id: String,
    pub details: OperationDraft,
    /// Stable insertion sequence breaks same-instant ties; edits preserve it.
    pub sequence: i64,
    pub currency: String,
    /// Signed economic cash effect; fees included, quantity never masquerades as money.
    #[serde(with = "decimal")]
    pub cash_amount: Decimal,
}
#[derive(Debug, Clone, PartialEq)]
pub struct Holding {
    pub asset_id: String,
    pub account_id: String,
    pub name: String,
    pub currency: String,
    pub quantity: Decimal,
    pub cost_basis: Decimal,
    pub market_price: Option<Decimal>,
    pub price_as_of: Option<i64>,
    pub market_value: Option<Decimal>,
    pub base_value: Option<Decimal>,
    pub unrealized_pnl: Option<Decimal>,
    pub realized_pnl: Decimal,
    pub dividends: Decimal,
}
#[derive(Debug, Clone, PartialEq)]
pub struct CashBalance {
    pub account_id: String,
    pub name: String,
    pub currency: String,
    pub amount: Decimal,
    pub liability: bool,
}
#[derive(Debug, Clone, PartialEq)]
pub struct CurrencyWealth {
    pub currency: String,
    pub assets: Decimal,
    pub liabilities: Decimal,
    pub net: Decimal,
}
#[derive(Debug, Clone, PartialEq)]
pub struct WealthSnapshot {
    /// An as-of boundary, including today's local civil-date label for a
    /// current read. Manual date labels are UTC midnight, not live quote times.
    pub as_of: i64,
    pub base_currency: String,
    pub holdings: Vec<Holding>,
    pub currencies: Vec<CurrencyWealth>,
    pub missing_prices: Vec<String>,
    pub missing_fx: Vec<String>,
    /// None whenever any nonzero holding or cash balance cannot be valued.
    pub net_worth: Option<Decimal>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct WealthHistoryPoint {
    pub as_of: i64,
    pub net_worth: Option<Decimal>,
    pub missing_prices: Vec<String>,
    pub missing_fx: Vec<String>,
}
