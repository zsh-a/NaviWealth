//! Asset catalog (what the user holds) and its price-observation history.
//! The ledger keeps posting units as opaque unit strings; an asset row is
//! what gives a unit a display name, a class and valuations.

use rust_decimal::Decimal;

use lifeos::sync::SyncMeta;

/// Class of the held thing. Wire names are `snake_case` and match the
/// column literal; a rename needs a migration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AssetKind {
    Stock,
    Etf,
    MutualFund,
    Bond,
    Crypto,
    Cash,
    RealEstate,
    Vehicle,
    Other,
}

impl AssetKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Stock => "stock",
            Self::Etf => "etf",
            Self::MutualFund => "mutual_fund",
            Self::Bond => "bond",
            Self::Crypto => "crypto",
            Self::Cash => "cash",
            Self::RealEstate => "real_estate",
            Self::Vehicle => "vehicle",
            Self::Other => "other",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "stock" => Self::Stock,
            "etf" => Self::Etf,
            "mutual_fund" => Self::MutualFund,
            "bond" => Self::Bond,
            "crypto" => Self::Crypto,
            "cash" => Self::Cash,
            "real_estate" => Self::RealEstate,
            "vehicle" => Self::Vehicle,
            "other" => Self::Other,
            _ => return None,
        })
    }

    /// Cash-class assets are valued as one lump (the ledger books them in
    /// currency units); physical/securities carry a per-unit quantity.
    pub fn is_cash_class(self) -> bool {
        matches!(self, Self::Cash)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Asset {
    pub id: String,
    pub kind: AssetKind,
    pub name: String,
    pub note: Option<String>,
    pub sync: SyncMeta,
}

#[derive(Debug, Clone)]
pub struct NewAsset {
    pub kind: AssetKind,
    pub name: String,
    pub note: Option<String>,
}

impl NewAsset {
    pub fn new(kind: AssetKind, name: impl Into<String>) -> Self {
        Self {
            kind,
            name: name.into(),
            note: None,
        }
    }
}

/// One observed price for a ledger unit: "1 `unit` was worth `per_unit`
/// `quote_currency` on `observed_on` (epoch secs)". Append-only history;
/// valuation reads take the newest observation at or before a date.
#[derive(Debug, Clone, PartialEq)]
pub struct AssetPrice {
    pub id: String,
    /// ISO 4217 code or an asset id — the same unit space as postings.
    pub unit: String,
    pub quote_currency: String,
    pub observed_on: i64,
    pub per_unit: Decimal,
    /// Where the quote came from (`manual`, a feed name, …).
    pub source: Option<String>,
    pub sync: SyncMeta,
}

#[derive(Debug, Clone)]
pub struct NewAssetPrice {
    pub unit: String,
    pub quote_currency: String,
    pub observed_on: i64,
    pub per_unit: Decimal,
    pub source: Option<String>,
}
