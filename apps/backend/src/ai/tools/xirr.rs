//! Newton-Raphson XIRR core.
//!
//! Pure utility — no D1, no async. Lives in its own module so the
//! `tools/mod.rs` dispatch file shrinks and the algorithm has a stable
//! home as we eventually fold time-windowed XIRR variants into
//! `xirr_snapshot`.
//!
//! Matches Excel's XIRR for the simple two-flow case; returns `None`
//! when the series is single-sign / under-determined / non-convergent.

use chrono::{DateTime, Utc};

#[derive(Clone, Copy)]
pub(super) struct CashFlow {
    pub when: DateTime<Utc>,
    pub amount: f64,
}

pub(super) fn xirr(flows: &[CashFlow]) -> Option<f64> {
    if flows.len() < 2 {
        return None;
    }
    // All same sign → XIRR is undefined (no break-even rate).
    let any_pos = flows.iter().any(|f| f.amount > 0.0);
    let any_neg = flows.iter().any(|f| f.amount < 0.0);
    if !(any_pos && any_neg) {
        return None;
    }
    let t0 = flows.iter().map(|f| f.when).min()?;
    let years: Vec<f64> = flows
        .iter()
        .map(|f| (f.when - t0).num_seconds() as f64 / (365.25 * 86400.0))
        .collect();

    let f = |r: f64| -> f64 {
        flows
            .iter()
            .zip(&years)
            .map(|(cf, &t)| cf.amount / (1.0 + r).powf(t))
            .sum()
    };
    let df = |r: f64| -> f64 {
        flows
            .iter()
            .zip(&years)
            .map(|(cf, &t)| -t * cf.amount / (1.0 + r).powf(t + 1.0))
            .sum()
    };
    let mut r = 0.1_f64;
    for _ in 0..64 {
        let val = f(r);
        if val.abs() < 1e-9 {
            return Some(r);
        }
        let d = df(r);
        if d.abs() < 1e-12 {
            return None;
        }
        let next = r - val / d;
        if !next.is_finite() || next <= -0.999_999 {
            return None;
        }
        if (next - r).abs() < 1e-9 {
            return Some(next);
        }
        r = next;
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xirr_matches_excel_simple_case() {
        // -1000 today, +1100 in one year ≈ 10%.
        let t0 = DateTime::parse_from_rfc3339("2025-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let t1 = DateTime::parse_from_rfc3339("2026-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let rate = xirr(&[
            CashFlow {
                when: t0,
                amount: -1000.0,
            },
            CashFlow {
                when: t1,
                amount: 1100.0,
            },
        ])
        .unwrap();
        assert!((rate - 0.10).abs() < 1e-3, "rate = {rate}");
    }

    #[test]
    fn xirr_returns_none_for_single_sign() {
        let t0 = DateTime::parse_from_rfc3339("2025-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let t1 = DateTime::parse_from_rfc3339("2026-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let rate = xirr(&[
            CashFlow {
                when: t0,
                amount: -1000.0,
            },
            CashFlow {
                when: t1,
                amount: -1000.0,
            },
        ]);
        assert!(rate.is_none());
    }
}
