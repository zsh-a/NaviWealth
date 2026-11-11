//! Pure construction layer: turns a high-level economic event into the
//! `(EntryDraft, Vec<PostingDraft>)` shape the journal repository
//! consumes. Forms, AI proposals and importers share the exact same leg
//! layout — there is exactly one place that knows what "an expense" looks
//! like.
//!
//! Sign convention (all builder parameters are **positive** magnitudes;
//! the builder applies the correct sign per leg):
//!
//! | Account side | `units` sign on a normal event |
//! |---|---|
//! | asset | `+` inflow, `-` outflow |
//! | expense | `+` when incurred |
//! | liability | `+` when paying down, `-` when accruing |
//! | income | `-` when earned |
//! | equity | `-` when contributed, `+` when withdrawn |

use rust_decimal::Decimal;

use crate::error::{FinanceError, Result};
use crate::models::{EntryFlag, Price};

/// Trade date (epoch seconds) plus narration metadata.
#[derive(Debug, Clone)]
pub struct EntryDraft {
    pub date: i64,
    pub settled_on: Option<i64>,
    pub narration: String,
    pub payee: Option<String>,
    pub flag: EntryFlag,
    pub tag_ids: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct PostingDraft {
    pub position: usize,
    pub account_id: String,
    pub units: Decimal,
    /// ISO 4217 code or asset id.
    pub unit: String,
    pub cost: Option<crate::models::Cost>,
    pub price: Option<Price>,
}

#[derive(Debug, Clone)]
pub struct EntryBuild {
    pub entry: EntryDraft,
    pub postings: Vec<PostingDraft>,
}

fn positive(amount: Decimal, label: &str) -> Result<()> {
    if amount <= Decimal::ZERO {
        return Err(FinanceError::InvalidData(format!(
            "{label} must be positive"
        )));
    }
    Ok(())
}

fn currency_code(currency: &str) -> Result<String> {
    lifeos::money::Currency::new(currency)
        .map(|c| c.as_str().to_owned())
        .map_err(|e| FinanceError::InvalidData(e.to_string()))
}

fn draft(
    date: i64,
    narration: &str,
    payee: Option<String>,
    settled_on: Option<i64>,
    tag_ids: Vec<String>,
) -> EntryDraft {
    EntryDraft {
        date,
        settled_on,
        narration: narration.to_owned(),
        payee,
        flag: EntryFlag::Confirmed,
        tag_ids,
    }
}

/// Categorised expense: amount flows from a cash account into a
/// `category=expense` ledger account.
#[allow(clippy::too_many_arguments)]
pub fn expense(
    date: i64,
    expense_account_id: impl Into<String>,
    from_account_id: impl Into<String>,
    amount: Decimal,
    currency: &str,
    payee: Option<String>,
    narration: Option<&str>,
    settled_on: Option<i64>,
    tag_ids: Vec<String>,
) -> Result<EntryBuild> {
    positive(amount, "amount")?;
    let currency = currency_code(currency)?;
    Ok(EntryBuild {
        entry: draft(
            date,
            narration.unwrap_or("Expense"),
            payee,
            settled_on,
            tag_ids,
        ),
        postings: vec![
            PostingDraft {
                position: 0,
                account_id: expense_account_id.into(),
                units: amount,
                unit: currency.clone(),
                cost: None,
                price: None,
            },
            PostingDraft {
                position: 1,
                account_id: from_account_id.into(),
                units: -amount,
                unit: currency,
                cost: None,
                price: None,
            },
        ],
    })
}

/// Cash income: the asset account increases, the seeded `income:*`
/// counter-account takes the balancing credit.
#[allow(clippy::too_many_arguments)]
pub fn income(
    date: i64,
    to_account_id: impl Into<String>,
    income_account_id: impl Into<String>,
    amount: Decimal,
    currency: &str,
    payee: Option<String>,
    narration: Option<&str>,
    settled_on: Option<i64>,
    tag_ids: Vec<String>,
) -> Result<EntryBuild> {
    positive(amount, "amount")?;
    let currency = currency_code(currency)?;
    Ok(EntryBuild {
        entry: draft(
            date,
            narration.unwrap_or("Income"),
            payee,
            settled_on,
            tag_ids,
        ),
        postings: vec![
            PostingDraft {
                position: 0,
                account_id: to_account_id.into(),
                units: amount,
                unit: currency.clone(),
                cost: None,
                price: None,
            },
            PostingDraft {
                position: 1,
                account_id: income_account_id.into(),
                units: -amount,
                unit: currency,
                cost: None,
                price: None,
            },
        ],
    })
}

/// Two-leg transfer. Same-currency transfers skip FX annotations.
/// Cross-currency transfers attach a `Price` annotation to the
/// destination leg equal to `amount / to_amount` in the source currency,
/// so the entry balances at the *user's chosen rate* rather than
/// whatever the fx table happens to know that day.
#[allow(clippy::too_many_arguments)]
pub fn transfer(
    date: i64,
    from_account_id: impl Into<String>,
    to_account_id: impl Into<String>,
    amount: Decimal,
    currency: &str,
    to_amount: Option<Decimal>,
    to_currency: Option<&str>,
    payee: Option<String>,
    narration: Option<&str>,
    settled_on: Option<i64>,
    tag_ids: Vec<String>,
) -> Result<EntryBuild> {
    positive(amount, "amount")?;
    let currency = currency_code(currency)?;
    if let Some(to_amount) = to_amount {
        positive(to_amount, "to_amount")?;
    }
    let dest_currency = match to_currency {
        Some(code) => currency_code(code)?,
        None => currency.clone(),
    };
    let dest_amount = to_amount.unwrap_or(amount);
    if to_currency.is_some() && to_amount.is_none() {
        return Err(FinanceError::InvalidData(
            "cross-currency transfer needs to_amount".into(),
        ));
    }
    if dest_currency == currency && to_amount.is_some() && to_amount != Some(amount) {
        return Err(FinanceError::InvalidData(
            "same-currency transfer must move the same amount".into(),
        ));
    }

    let dest_price = if dest_currency != currency {
        Some(Price {
            per_unit: (amount / dest_amount).round_dp(12),
            currency: currency.clone(),
        })
    } else {
        None
    };

    Ok(EntryBuild {
        entry: draft(
            date,
            narration.unwrap_or("Transfer"),
            payee,
            settled_on,
            tag_ids,
        ),
        postings: vec![
            PostingDraft {
                position: 0,
                account_id: from_account_id.into(),
                units: -amount,
                unit: currency,
                cost: None,
                price: None,
            },
            PostingDraft {
                position: 1,
                account_id: to_account_id.into(),
                units: dest_amount,
                unit: dest_currency,
                cost: None,
                price: dest_price,
            },
        ],
    })
}

/// Seeds an asset or liability with its starting balance against
/// `Equity:OpeningBalance`. `amount` is signed **as it should appear on
/// the target account** (positive for asset balances, negative for
/// liability balances).
#[allow(clippy::too_many_arguments)]
pub fn opening_balance(
    date: i64,
    account_id: impl Into<String>,
    opening_balance_account_id: impl Into<String>,
    amount: Decimal,
    currency: &str,
    narration: Option<&str>,
    settled_on: Option<i64>,
    tag_ids: Vec<String>,
) -> Result<EntryBuild> {
    if amount == Decimal::ZERO {
        return Err(FinanceError::InvalidData(
            "opening_balance must move a non-zero amount".into(),
        ));
    }
    let currency = currency_code(currency)?;
    Ok(EntryBuild {
        entry: draft(
            date,
            narration.unwrap_or("Opening balance"),
            None,
            settled_on,
            tag_ids,
        ),
        postings: vec![
            PostingDraft {
                position: 0,
                account_id: account_id.into(),
                units: amount,
                unit: currency.clone(),
                cost: None,
                price: None,
            },
            PostingDraft {
                position: 1,
                account_id: opening_balance_account_id.into(),
                units: -amount,
                unit: currency,
                cost: None,
                price: None,
            },
        ],
    })
}

/// Revalues a holding in place (no cash movement): the holding leg is
/// re-priced and the difference is booked against `Equity:Adjustments`
/// (the caller passes that seeded account).
///
/// Port of the Flutter `_buildValuationAdjustJournalEntry`:
///
/// - cash-class holdings (`quantity == 0`, valued as one lump) book
///   `units = 1` with `price = new_valuation` as the **absolute** value;
/// - physical/security holdings book `units = quantity` with
///   `price = new_valuation` **per unit**;
/// - the equity hedge carries `-leg_units × price` in `currency`;
/// - the entry is tagged `asset:<unit>` so valuation entries are
///   filterable per holding.
///
/// `asset_unit` is the ledger unit of the holding (an asset id or a
/// currency code); `new_valuation` must be positive.
#[allow(clippy::too_many_arguments)]
pub fn valuation_adjust(
    date: i64,
    account_id: impl Into<String>,
    equity_adjustments_account_id: impl Into<String>,
    asset_unit: impl Into<String>,
    quantity: Decimal,
    new_valuation: Decimal,
    currency: &str,
    narration: Option<&str>,
    settled_on: Option<i64>,
    tag_ids: Vec<String>,
) -> Result<EntryBuild> {
    if new_valuation <= Decimal::ZERO {
        return Err(FinanceError::InvalidData(
            "new_valuation must be positive".into(),
        ));
    }
    let currency = currency_code(currency)?;
    let asset_unit = asset_unit.into();
    // Cash-class: units=1 with price=new_valuation (absolute value).
    // Physical/security: units=quantity with price=new_valuation (per-unit).
    let leg_units = if quantity == Decimal::ZERO {
        Decimal::ONE
    } else {
        quantity
    };
    let total_value = leg_units * new_valuation;

    let mut tags = tag_ids;
    let asset_tag = format!("asset:{asset_unit}");
    if !tags.contains(&asset_tag) {
        tags.push(asset_tag);
    }

    Ok(EntryBuild {
        entry: draft(
            date,
            narration.unwrap_or("Valuation adjust"),
            None,
            settled_on,
            tags,
        ),
        postings: vec![
            PostingDraft {
                position: 0,
                account_id: account_id.into(),
                units: leg_units,
                unit: asset_unit,
                cost: None,
                price: Some(Price {
                    per_unit: new_valuation,
                    currency: currency.clone(),
                }),
            },
            PostingDraft {
                position: 1,
                account_id: equity_adjustments_account_id.into(),
                units: -total_value,
                unit: currency,
                cost: None,
                price: None,
            },
        ],
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::invariants::{FxRateSource, evaluate_entry_balance};
    use crate::models::{Cost, JournalEntry};
    use lifeos::sync::SyncMeta;
    use std::str::FromStr;

    struct MapFx;
    impl FxRateSource for MapFx {
        fn rate(
            &self,
            _conn: &rusqlite::Connection,
            from: &str,
            to: &str,
            _as_of_secs: i64,
        ) -> Option<Decimal> {
            match (from, to) {
                ("USD", "CNY") => Some(Decimal::from_str("7").unwrap()),
                _ => None,
            }
        }
    }

    fn entry_for(build: &EntryBuild) -> JournalEntry {
        JournalEntry {
            id: "j1".into(),
            date: build.entry.date,
            settled_on: None,
            narration: build.entry.narration.clone(),
            payee: None,
            flag: build.entry.flag,
            tag_ids: vec![],
            sync: SyncMeta {
                owner_user_id: "u".into(),
                updated_at: 0,
                updated_by_device: "d".into(),
                hlc: "1.0000-d".into(),
                deleted_at: None,
            },
        }
    }

    fn postings_for(entry_id: &str, build: &EntryBuild) -> Vec<crate::models::Posting> {
        build
            .postings
            .iter()
            .map(|d| crate::models::Posting {
                id: format!("p{}", d.position),
                journal_entry_id: entry_id.to_owned(),
                position: d.position as i64,
                account_id: d.account_id.clone(),
                units: d.units,
                unit: d.unit.clone(),
                cost: d.cost.clone(),
                price: d.price.clone(),
                sync: SyncMeta {
                    owner_user_id: "u".into(),
                    updated_at: 0,
                    updated_by_device: "d".into(),
                    hlc: "1.0000-d".into(),
                    deleted_at: None,
                },
            })
            .collect()
    }

    #[test]
    fn expense_is_balanced() {
        let build = expense(
            0,
            "expense:dining",
            "cash",
            Decimal::from_str("12.50").unwrap(),
            "CNY",
            None,
            None,
            None,
            vec![],
        )
        .unwrap();
        let entry = entry_for(&build);
        let postings = postings_for(&entry.id, &build);
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        let report = evaluate_entry_balance(&conn, &entry, &postings, &MapFx, "CNY", None);
        assert!(report.is_balanced(), "{:?}", report.problems);
    }

    #[test]
    fn cross_currency_transfer_carries_user_rate() {
        let build = transfer(
            0,
            "usd_cash",
            "cny_cash",
            Decimal::from(100),
            "USD",
            Some(Decimal::from(715)),
            Some("CNY"),
            None,
            None,
            None,
            vec![],
        )
        .unwrap();
        let entry = entry_for(&build);
        let postings = postings_for(&entry.id, &build);
        // Balanced at the user's rate without any fx source.
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        let report = evaluate_entry_balance(&conn, &entry, &postings, &MapFx, "CNY", None);
        assert!(report.is_balanced(), "{:?}", report.problems);
        // Beancount-style price: 1 unit of the destination currency is
        // worth `amount / dest_amount` of the source currency.
        let price = build.postings[1].price.as_ref().unwrap();
        assert_eq!(price.currency, "USD");
        assert_eq!(price.per_unit, Decimal::from_str("0.139860139860").unwrap());
    }

    #[test]
    fn non_positive_amounts_are_refused() {
        assert!(expense(0, "e", "c", Decimal::ZERO, "CNY", None, None, None, vec![]).is_err());
        assert!(
            income(
                0,
                "t",
                "i",
                Decimal::from_str("-1").unwrap(),
                "CNY",
                None,
                None,
                None,
                vec![]
            )
            .is_err()
        );
        assert!(opening_balance(0, "a", "eq", Decimal::ZERO, "CNY", None, None, vec![]).is_err());
    }

    #[test]
    fn opening_balance_signs_follow_the_target() {
        // Positive for an asset account.
        let asset = opening_balance(
            0,
            "cash",
            "eq:ob",
            Decimal::from(1000),
            "CNY",
            None,
            None,
            vec![],
        )
        .unwrap();
        assert_eq!(asset.postings[0].units, Decimal::from(1000));
        assert_eq!(asset.postings[1].units, Decimal::from(-1000));

        // Negative for a liability balance (what the user owes).
        let liability = opening_balance(
            0,
            "credit",
            "eq:ob",
            Decimal::from(-500),
            "CNY",
            None,
            None,
            vec![],
        )
        .unwrap();
        assert_eq!(liability.postings[0].units, Decimal::from(-500));
    }

    #[test]
    fn commodity_leg_without_annotation_fails_the_check() {
        // A manual buy layout: +10 AAPL {cost 150 USD} against -1500 USD.
        let cost = || Cost {
            per_unit: Decimal::from(150),
            currency: "USD".into(),
            lot_id: None,
            acquired_on: None,
        };
        let make = |cost: Option<Cost>| EntryBuild {
            entry: draft(0, "Buy", None, None, vec![]),
            postings: vec![
                PostingDraft {
                    position: 0,
                    account_id: "broker".into(),
                    units: Decimal::from(10),
                    unit: "us_stock:AAPL".into(),
                    cost: cost.clone(),
                    price: None,
                },
                PostingDraft {
                    position: 1,
                    account_id: "cash".into(),
                    units: Decimal::from(-1500),
                    unit: "USD".into(),
                    cost: None,
                    price: None,
                },
            ],
        };

        // Without the cost annotation the asset leg cannot fold to base.
        let bad = make(None);
        let entry = entry_for(&bad);
        let postings = postings_for(&entry.id, &bad);
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        let report = evaluate_entry_balance(&conn, &entry, &postings, &MapFx, "CNY", None);
        assert!(!report.is_balanced());
        assert!(matches!(
            report.problems[0].kind,
            crate::invariants::BalanceProblemKind::RawCommodityWithoutCostOrPrice
        ));

        // With the cost annotation it balances (cost is the preferred
        // weight) and needs no FX rate because USD cancels natively.
        let good = make(Some(cost()));
        let entry = entry_for(&good);
        let postings = postings_for(&entry.id, &good);
        let conn = rusqlite::Connection::open_in_memory().unwrap();
        let report = evaluate_entry_balance(&conn, &entry, &postings, &MapFx, "CNY", None);
        assert!(report.is_balanced(), "{:?}", report.problems);
    }
}
