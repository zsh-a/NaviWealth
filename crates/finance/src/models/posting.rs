use rust_decimal::Decimal;

use lifeos::sync::SyncMeta;

/// Cost annotation on a commodity leg (lot identification).
#[derive(Debug, Clone, PartialEq)]
pub struct Cost {
    pub per_unit: Decimal,
    pub currency: String,
    pub lot_id: Option<String>,
    pub acquired_on: Option<i64>,
}

/// Price annotation: "1 unit of the leg's unit is worth `per_unit` of
/// `currency`". Records the user's chosen rate so entries balance at
/// submit time even when the fx_rates table lags.
#[derive(Debug, Clone, PartialEq)]
pub struct Price {
    pub per_unit: Decimal,
    pub currency: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Posting {
    pub id: String,
    pub journal_entry_id: String,
    /// 0-based order; reorder is a single-column LWW update.
    pub position: i64,
    pub account_id: String,
    /// Signed decimal delta (see the builder sign convention).
    pub units: Decimal,
    /// ISO 4217 code or an asset id (`us_stock:AAPL`).
    pub unit: String,
    pub cost: Option<Cost>,
    pub price: Option<Price>,
    pub sync: SyncMeta,
}
