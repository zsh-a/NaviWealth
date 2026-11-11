//! FX rates (device-local, not synced): `fx_rates` stores one row per
//! (base, quote, UTC day). Lookup returns the latest rate with
//! `as_of <=` the requested day — never a future rate. Missing rates are
//! returned as `None`; callers refuse the write rather than assume 1.

use rusqlite::{Connection, OptionalExtension, params};
use rust_decimal::Decimal;

use crate::error::{FinanceError, Result};

/// Start of the UTC day containing `as_of_secs` (epoch seconds).
fn day_start(as_of_secs: i64) -> i64 {
    as_of_secs.div_euclid(86_400) * 86_400
}

/// Latest direct or inverse rate at `as_of_secs`. The inverse is computed
/// at 20 significant digits (matching the Flutter converter).
pub fn rate_at(conn: &Connection, from: &str, to: &str, as_of_secs: i64) -> Option<Decimal> {
    if from == to {
        return Some(Decimal::ONE);
    }
    let day = day_start(as_of_secs);
    let direct = conn
        .query_row(
            "SELECT rate FROM fx_rates WHERE base = ?1 AND quote = ?2 AND as_of <= ?3
             ORDER BY as_of DESC LIMIT 1",
            params![from, to, day],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .ok()
        .flatten()
        .and_then(|s| Decimal::from_str_exact(&s).ok());
    if direct.is_some() {
        return direct;
    }
    let inverse = conn
        .query_row(
            "SELECT rate FROM fx_rates WHERE base = ?1 AND quote = ?2 AND as_of <= ?3
             ORDER BY as_of DESC LIMIT 1",
            params![to, from, day],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .ok()
        .flatten()
        .and_then(|s| Decimal::from_str_exact(&s).ok())?;
    Decimal::ONE.checked_div(inverse).map(|r| r.round_dp(20))
}

/// Record one observed rate (idempotent per day).
pub fn upsert_rate(
    conn: &Connection,
    base: &str,
    quote: &str,
    as_of_secs: i64,
    rate: Decimal,
    source: Option<&str>,
) -> Result<()> {
    if rate <= Decimal::ZERO {
        return Err(FinanceError::InvalidData("fx rate must be positive".into()));
    }
    conn.execute(
        "INSERT INTO fx_rates (base, quote, as_of, rate, source, fetched_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT(base, quote, as_of) DO UPDATE SET rate = excluded.rate, source = excluded.source, fetched_at = excluded.fetched_at
         WHERE fx_rates.source IS NOT 'manual_fx' OR excluded.source = 'manual_fx'",
        params![
            base,
            quote,
            day_start(as_of_secs),
            rate.to_string(),
            source,
            lifeos::ids::now_secs()
        ],
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tables::migration;
    use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations};
    use std::path::PathBuf;
    use std::str::FromStr;

    fn db() -> Db {
        Db::open(DbOpenOptions {
            path: PathBuf::from(":memory:"),
            encryption_key: None,
            migrations: core_migrations().push(migration()),
        })
        .unwrap()
    }

    #[tokio::test]
    async fn lookup_uses_latest_day_and_never_the_future() {
        let db = db();
        db.call_sync(|conn: &mut rusqlite::Connection| -> lifeos::Result<()> {
            let day0 = 86_400; // 1970-01-02
            upsert_rate(
                conn,
                "USD",
                "CNY",
                day0,
                Decimal::from_str("7.0").unwrap(),
                Some("test"),
            )?;
            // Later day.
            upsert_rate(
                conn,
                "USD",
                "CNY",
                day0 + 86_400,
                Decimal::from_str("7.1").unwrap(),
                Some("test"),
            )?;

            // At day1: latest <= day1 is 7.1.
            let r = rate_at(conn, "USD", "CNY", day0 + 86_400).unwrap();
            assert_eq!(r.to_string(), "7.1");
            // Mid day2 still sees day2's rate.
            let r = rate_at(conn, "USD", "CNY", day0 + 86_400 + 43200).unwrap();
            assert_eq!(r.to_string(), "7.1");
            // Before any observation: None.
            assert!(rate_at(conn, "USD", "CNY", 0).is_none());
            // Inverse lookup.
            let r = rate_at(conn, "CNY", "USD", day0 + 86_400).unwrap();
            assert_eq!(r.round_dp(4).to_string(), "0.1408");
            // Identity short-circuits.
            assert_eq!(rate_at(conn, "CNY", "CNY", 0), Some(Decimal::ONE));
            Ok(())
        })
        .unwrap();
    }
}
