//! The double-entry balance invariant (port of the Flutter
//! `invariants.dart`): per posting, weight = `units × cost.per_unit`
//! (cost preferred) | `units × price.per_unit` | `units` if the unit
//! looks like fiat. Weights are summed per native currency (zero sums
//! skip FX entirely), folded to the base currency at the JE date — a
//! missing rate is a hard error, never treated as 1. `|Σ| ≤ tolerance`
//! with a default of 1e-6; `padding` entries skip the check.

use rusqlite::Connection;
use rust_decimal::Decimal;

use crate::models::{EntryFlag, JournalEntry, Posting};

/// Base-currency FX rate lookup used by the JE balance check. Deliberately
/// narrow: the validator wants the rate at the JE date and nothing else.
/// The connection is handed in so implementations (and the blanket closure
/// impl) can read `fx_rates` inside the caller's transaction. `None` means
/// "no rate known" — callers treat it as a hard error rather than silently
/// treating the missing rate as 1.
pub trait FxRateSource {
    fn rate(&self, conn: &Connection, from: &str, to: &str, as_of_secs: i64) -> Option<Decimal>;
}

/// Blanket impl so call sites can pass a closure.
impl<F> FxRateSource for F
where
    F: Fn(&Connection, &str, &str, i64) -> Option<Decimal>,
{
    fn rate(&self, conn: &Connection, from: &str, to: &str, as_of_secs: i64) -> Option<Decimal> {
        self(conn, from, to, as_of_secs)
    }
}

/// Single-currency source for tests; refuses non-identity conversions so
/// bugs surface as a missing-rate problem instead of a fake balance.
pub struct IdentityFxRateSource;

impl FxRateSource for IdentityFxRateSource {
    fn rate(&self, _conn: &Connection, from: &str, to: &str, _as_of_secs: i64) -> Option<Decimal> {
        (from == to).then_some(Decimal::ONE)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BalanceProblemKind {
    /// A non-fiat unit posting carries neither a cost nor a price
    /// annotation — its base-currency weight is uncomputable.
    RawCommodityWithoutCostOrPrice,
    /// No FX rate for the leg's currency at the JE date.
    MissingFxRate,
    /// The journal entry has zero postings.
    EmptyEntry,
    /// Σ(weight) is non-zero outside the tolerance.
    Unbalanced,
}

#[derive(Debug, Clone)]
pub struct BalanceProblem {
    pub kind: BalanceProblemKind,
    pub message: String,
    pub posting_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct BalanceReport {
    /// Σ(weight) folded to the base currency; always reported so callers
    /// can show "off by 0.43 USD" hints.
    pub total_base_weight: Decimal,
    pub tolerance: Decimal,
    pub problems: Vec<BalanceProblem>,
}

impl BalanceReport {
    pub fn is_balanced(&self) -> bool {
        self.problems.is_empty() && self.total_base_weight.abs() <= self.tolerance
    }
}

/// Default tolerance for the JE balance check: 1e-6 absorbs the rounding
/// noise from string-stored decimals while still catching genuine
/// off-by-one cents (which differ by 1e-2).
pub fn default_balance_tolerance() -> Decimal {
    Decimal::new(1, 6)
}

/// `Posting.unit` values treated as fiat for the balance rule. Anything
/// else is a commodity/security and must carry a cost or price annotation.
/// The rule stays structural — an exotic fiat pair missing from the FX
/// source must fail as [`BalanceProblemKind::MissingFxRate`], not be
/// downgraded to "this is a commodity".
fn looks_like_fiat_code(unit: &str) -> bool {
    let bytes = unit.as_bytes();
    (3..=8).contains(&bytes.len()) && bytes.iter().all(u8::is_ascii_uppercase)
}

/// Compute the balance status of a journal entry given its postings.
/// `is_balanced()` on the report is the canonical "is this writeable"
/// answer.
pub fn evaluate_entry_balance(
    conn: &Connection,
    entry: &JournalEntry,
    postings: &[Posting],
    fx: &dyn FxRateSource,
    base_currency: &str,
    tolerance: Option<Decimal>,
) -> BalanceReport {
    let tolerance = tolerance.unwrap_or_else(default_balance_tolerance);

    // Padding rows skip the balance check by design — they exist purely
    // to reconcile against an externally-known total.
    if entry.flag == EntryFlag::Padding {
        return BalanceReport {
            total_base_weight: Decimal::ZERO,
            tolerance,
            problems: Vec::new(),
        };
    }

    if postings.is_empty() {
        return BalanceReport {
            total_base_weight: Decimal::ZERO,
            tolerance,
            problems: vec![BalanceProblem {
                kind: BalanceProblemKind::EmptyEntry,
                message: "Journal entry has no postings.".into(),
                posting_id: None,
            }],
        };
    }

    // Sum weights in their native currency before folding into the user's
    // base currency. An entry that self-balances within USD (a USD security
    // bought from a USD cash account) must not need an FX quote merely
    // because the reporting currency is CNY — and zero-sum buckets skip
    // FX entirely.
    let mut weights_by_currency: Vec<(String, Decimal)> = Vec::new();
    let mut first_posting_by_currency: Vec<(String, String)> = Vec::new();
    let mut problems: Vec<BalanceProblem> = Vec::new();

    for posting in postings {
        let (weight, weight_ccy) = if let Some(cost) = &posting.cost {
            (posting.units * cost.per_unit, cost.currency.clone())
        } else if let Some(price) = &posting.price {
            (posting.units * price.per_unit, price.currency.clone())
        } else if looks_like_fiat_code(&posting.unit) {
            (posting.units, posting.unit.clone())
        } else {
            problems.push(BalanceProblem {
                kind: BalanceProblemKind::RawCommodityWithoutCostOrPrice,
                message: format!(
                    "Posting {} carries non-fiat unit {:?} but no cost or price annotation; cannot fold to base currency.",
                    posting.id, posting.unit
                ),
                posting_id: Some(posting.id.clone()),
            });
            continue;
        };

        match weights_by_currency
            .iter_mut()
            .find(|(c, _)| *c == weight_ccy)
        {
            Some((_, sum)) => *sum += weight,
            None => {
                weights_by_currency.push((weight_ccy.clone(), weight));
                first_posting_by_currency.push((weight_ccy, posting.id.clone()));
            }
        }
    }

    let mut total = Decimal::ZERO;
    for (weight_ccy, weight) in &weights_by_currency {
        // Exact native-currency cancellation is already balanced; do not
        // require a historical FX observation just to convert zero into
        // another zero.
        if *weight == Decimal::ZERO {
            continue;
        }
        if weight_ccy == base_currency {
            total += weight;
            continue;
        }
        match fx.rate(conn, weight_ccy, base_currency, entry.date) {
            Some(rate) => total += weight * rate,
            None => {
                let posting_id = first_posting_by_currency
                    .iter()
                    .find(|(c, _)| c == weight_ccy)
                    .map(|(_, p)| p.clone());
                problems.push(BalanceProblem {
                    kind: BalanceProblemKind::MissingFxRate,
                    message: format!(
                        "Missing FX rate {weight_ccy} → {base_currency} for currency bucket starting at posting {}.",
                        posting_id.as_deref().unwrap_or("?")
                    ),
                    posting_id,
                });
            }
        }
    }

    if problems.is_empty() && total.abs() > tolerance {
        problems.push(BalanceProblem {
            kind: BalanceProblemKind::Unbalanced,
            message: format!("Σ(weight) = {total} {base_currency} exceeds tolerance ±{tolerance}."),
            posting_id: None,
        });
    }

    BalanceReport {
        total_base_weight: total,
        tolerance,
        problems,
    }
}

/// Convenience wrapper for callers that only need the boolean answer.
pub fn entry_is_balanced(
    conn: &Connection,
    entry: &JournalEntry,
    postings: &[Posting],
    fx: &dyn FxRateSource,
    base_currency: &str,
    tolerance: Option<Decimal>,
) -> bool {
    evaluate_entry_balance(conn, entry, postings, fx, base_currency, tolerance).is_balanced()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{AccountCategory, AccountSide, Cost, Price};
    use lifeos::sync::SyncMeta;
    use std::str::FromStr;

    fn sync(hlc: &str) -> SyncMeta {
        SyncMeta {
            owner_user_id: "u".into(),
            updated_at: 0,
            updated_by_device: "d".into(),
            hlc: hlc.into(),
            deleted_at: None,
        }
    }

    fn entry(flag: EntryFlag) -> JournalEntry {
        JournalEntry {
            id: "j1".into(),
            date: 1_767_258_000,
            settled_on: None,
            narration: "test".into(),
            payee: None,
            flag,
            tag_ids: vec![],
            sync: sync("1.0000-d"),
        }
    }

    fn posting(position: i64, account: &str, units: &str, unit: &str) -> Posting {
        Posting {
            id: format!("p{position}"),
            journal_entry_id: "j1".into(),
            position,
            account_id: account.into(),
            units: Decimal::from_str(units).unwrap(),
            unit: unit.into(),
            cost: None,
            price: None,
            sync: sync("1.0000-d"),
        }
    }

    fn usd_to_cny(rate: &str) -> impl FxRateSource {
        let rate = Decimal::from_str(rate).unwrap();
        move |_conn: &rusqlite::Connection, from: &str, to: &str, _: i64| match (from, to) {
            ("USD", "CNY") => Some(rate),
            ("CNY", "CNY") | ("USD", "USD") => Some(Decimal::ONE),
            _ => None,
        }
    }

    #[test]
    fn simple_expense_balances() {
        let conn = Connection::open_in_memory().unwrap();
        let entry = entry(EntryFlag::Confirmed);
        let postings = vec![
            posting(0, "expense:dining", "12.50", "CNY"),
            posting(1, "cash", "-12.50", "CNY"),
        ];
        assert!(entry_is_balanced(
            &conn,
            &entry,
            &postings,
            &IdentityFxRateSource,
            "CNY",
            None
        ));
    }

    #[test]
    fn off_by_one_cent_is_caught() {
        let conn = Connection::open_in_memory().unwrap();
        let entry = entry(EntryFlag::Confirmed);
        let postings = vec![
            posting(0, "expense:dining", "12.50", "CNY"),
            posting(1, "cash", "-12.49", "CNY"),
        ];
        let report =
            evaluate_entry_balance(&conn, &entry, &postings, &IdentityFxRateSource, "CNY", None);
        assert!(!report.is_balanced());
        assert!(matches!(
            report.problems[0].kind,
            BalanceProblemKind::Unbalanced
        ));
        assert_eq!(report.total_base_weight.to_string(), "0.01");
    }

    #[test]
    fn multi_currency_needs_rates_and_missing_rate_is_a_hard_error() {
        let conn = Connection::open_in_memory().unwrap();
        let entry = entry(EntryFlag::Confirmed);
        let postings = vec![
            posting(0, "expense:dining", "10", "USD"),
            posting(1, "cash", "-10", "USD"),
        ];
        // USD cancels natively: no CNY rate needed even with a CNY base.
        assert!(entry_is_balanced(
            &conn,
            &entry,
            &postings,
            &usd_to_cny("7"),
            "CNY",
            None
        ));

        // Now a USD -> CNY split that does not cancel natively.
        let postings = vec![
            posting(0, "expense:dining", "10", "USD"),
            posting(1, "cash", "-70", "CNY"),
        ];
        assert!(entry_is_balanced(
            &conn,
            &entry,
            &postings,
            &usd_to_cny("7"),
            "CNY",
            None
        ));

        struct NoRates;
        impl FxRateSource for NoRates {
            fn rate(&self, _: &rusqlite::Connection, _: &str, _: &str, _: i64) -> Option<Decimal> {
                None
            }
        }
        let report = evaluate_entry_balance(&conn, &entry, &postings, &NoRates, "CNY", None);
        assert!(!report.is_balanced());
        assert!(matches!(
            report.problems[0].kind,
            BalanceProblemKind::MissingFxRate
        ));
    }

    #[test]
    fn price_annotation_provides_the_weight() {
        let conn = Connection::open_in_memory().unwrap();
        let entry = entry(EntryFlag::Confirmed);
        let mut asset = posting(0, "broker", "2", "us_stock:AAPL");
        asset.price = Some(Price {
            per_unit: Decimal::from(150),
            currency: "USD".into(),
        });
        let cash = posting(1, "cash", "-300", "USD");
        assert!(entry_is_balanced(
            &conn,
            &entry,
            &[asset, cash],
            &usd_to_cny("7"),
            "CNY",
            None
        ));
    }

    #[test]
    fn cost_is_preferred_over_price() {
        let conn = Connection::open_in_memory().unwrap();
        let entry = entry(EntryFlag::Confirmed);
        let mut asset = posting(0, "broker", "2", "us_stock:AAPL");
        asset.cost = Some(Cost {
            per_unit: Decimal::from(100),
            currency: "USD".into(),
            lot_id: None,
            acquired_on: None,
        });
        asset.price = Some(Price {
            per_unit: Decimal::from(150),
            currency: "USD".into(),
        });
        // Cost weight = 200 USD, so a -150 USD cash leg is unbalanced and
        // -200 balances.
        let cash_short = posting(1, "cash", "-150", "USD");
        assert!(!entry_is_balanced(
            &conn,
            &entry,
            &[asset.clone(), cash_short],
            &usd_to_cny("7"),
            "CNY",
            None
        ));
        let cash = posting(1, "cash", "-200", "USD");
        assert!(entry_is_balanced(
            &conn,
            &entry,
            &[asset, cash],
            &usd_to_cny("7"),
            "CNY",
            None
        ));
    }

    #[test]
    fn padding_skips_the_check() {
        let conn = Connection::open_in_memory().unwrap();
        let entry = entry(EntryFlag::Padding);
        let postings = vec![posting(0, "cash", "999", "CNY")];
        let report =
            evaluate_entry_balance(&conn, &entry, &postings, &IdentityFxRateSource, "CNY", None);
        assert!(report.is_balanced());
    }

    #[test]
    fn empty_entry_is_rejected() {
        let conn = Connection::open_in_memory().unwrap();
        let entry = entry(EntryFlag::Confirmed);
        let report = evaluate_entry_balance(&conn, &entry, &[], &IdentityFxRateSource, "CNY", None);
        assert!(!report.is_balanced());
        assert!(matches!(
            report.problems[0].kind,
            BalanceProblemKind::EmptyEntry
        ));
    }

    #[test]
    fn side_naming_matches_the_flutter_enums() {
        assert_eq!(AccountSide::Asset.as_str(), "asset");
        assert_eq!(AccountCategory::Crypto.as_str(), "crypto");
    }
}
