//! Currency identities and exact dated exchange rates. One foreign unit is quoted in CNY millionths.
use crate::money::Minor;
use jiff::civil::Date;
use navi_storage::sqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};
use std::fmt;
#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize,
)]
pub enum Currency {
    #[default]
    CNY,
    HKD,
    USD,
}
impl Currency {
    pub const ALL: [Self; 3] = [Self::CNY, Self::HKD, Self::USD];
    pub fn as_str(self) -> &'static str {
        self.code()
    }
    pub fn code(self) -> &'static str {
        match self {
            Self::CNY => "CNY",
            Self::HKD => "HKD",
            Self::USD => "USD",
        }
    }
    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|c| c.code() == s)
    }
}
impl fmt::Display for Currency {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.code())
    }
}
pub const RATE_SCALE: i64 = 1_000_000;
pub const SCHEMA: &str = "CREATE TABLE finance_fx_rates(currency TEXT NOT NULL, day TEXT NOT NULL, rate INTEGER NOT NULL CHECK(rate > 0), source TEXT NOT NULL, PRIMARY KEY(currency,day));";
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FxRate {
    pub currency: Currency,
    pub day: Date,
    pub rate: i64,
    pub source: String,
}
#[derive(Debug, thiserror::Error)]
pub enum FxError {
    #[error("invalid exchange rate")]
    Invalid,
    #[error("converted amount overflows")]
    Overflow,
    #[error(transparent)]
    Sql(#[from] navi_storage::sqlite::Error),
}
pub fn convert_to_cny(amount: Minor, rate: i64) -> Result<Minor, FxError> {
    if rate <= 0 {
        return Err(FxError::Invalid);
    }
    let n = i128::from(amount) * i128::from(rate);
    let rounded = (n.abs() + i128::from(RATE_SCALE) / 2) / i128::from(RATE_SCALE) * n.signum();
    i64::try_from(rounded).map_err(|_| FxError::Overflow)
}
pub fn save_rate(conn: &Connection, r: &FxRate) -> Result<(), FxError> {
    save_rates(conn, std::slice::from_ref(r)).map(|_| ())
}
/// Atomically persist a dated provider batch, preserving manual date ties.
pub fn save_rates(conn: &Connection, rows: &[FxRate]) -> Result<usize, FxError> {
    let tx = conn.unchecked_transaction()?;
    let mut updated = 0;
    for r in rows {
        if r.rate <= 0
            || r.source.trim().is_empty()
            || (r.currency == Currency::CNY && r.rate != RATE_SCALE)
        {
            return Err(FxError::Invalid);
        }
        let changed=tx.execute("INSERT INTO finance_fx_rates(currency,day,rate,source) VALUES(?1,?2,?3,?4) ON CONFLICT(currency,day) DO UPDATE SET rate=excluded.rate,source=excluded.source WHERE (finance_fx_rates.source != 'manual' OR excluded.source = 'manual') AND (finance_fx_rates.rate != excluded.rate OR finance_fx_rates.source != excluded.source)",params![r.currency.code(),r.day.to_string(),r.rate,r.source])?;
        updated += changed;
        if changed > 0 {
            crate::history::record(
                &tx,
                "fx_rate",
                r.currency.code(),
                &r.day.to_string(),
                &serde_json::json!({"currency":r.currency.code(),"day":r.day.to_string(),"rate":r.rate,"source":r.source}),
            )?;
        }
    }
    tx.commit()?;
    Ok(updated)
}
pub fn rate_on(
    conn: &Connection,
    currency: Currency,
    day: Date,
) -> Result<Option<FxRate>, FxError> {
    if currency == Currency::CNY {
        return Ok(Some(FxRate {
            currency,
            day,
            rate: RATE_SCALE,
            source: "base".into(),
        }));
    }
    let row:Option<(String,i64,String)>=conn.query_row("SELECT day,rate,source FROM finance_fx_rates WHERE currency=?1 AND day<=?2 ORDER BY day DESC LIMIT 1",params![currency.code(),day.to_string()],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional()?;
    row.map(|(d, rate, source)| {
        let day = d.parse().map_err(|_| FxError::Invalid)?;
        if rate <= 0 || source.trim().is_empty() {
            return Err(FxError::Invalid);
        }
        Ok(FxRate {
            currency,
            day,
            rate,
            source,
        })
    })
    .transpose()
}
pub fn validate(conn: &Connection) -> Result<(), FxError> {
    let mut q = conn.prepare("SELECT currency,day,rate,source FROM finance_fx_rates")?;
    let mut rows = q.query([])?;
    while let Some(r) = rows.next()? {
        let c: String = r.get(0)?;
        let d: String = r.get(1)?;
        let rate: i64 = r.get(2)?;
        let source: String = r.get(3)?;
        let c = Currency::parse(&c).ok_or(FxError::Invalid)?;
        let parsed: Date = d.parse().map_err(|_| FxError::Invalid)?;
        if parsed.to_string() != d {
            return Err(FxError::Invalid);
        }
        if rate <= 0 || source.trim().is_empty() || (c == Currency::CNY && rate != RATE_SCALE) {
            return Err(FxError::Invalid);
        }
    }
    Ok(())
}

pub fn rates(conn: &Connection) -> Result<Vec<FxRate>, FxError> {
    validate(conn)?;
    let mut q = conn
        .prepare("SELECT currency,day,rate,source FROM finance_fx_rates ORDER BY day,currency")?;
    let mut rows = q.query([])?;
    let mut out = Vec::new();
    while let Some(r) = rows.next()? {
        let c: String = r.get(0)?;
        let d: String = r.get(1)?;
        out.push(FxRate {
            currency: Currency::parse(&c).ok_or(FxError::Invalid)?,
            day: d.parse().map_err(|_| FxError::Invalid)?,
            rate: r.get(2)?,
            source: r.get(3)?,
        });
    }
    Ok(out)
}
pub fn rate_in(rates: &[FxRate], currency: Currency, day: Date) -> Option<FxRate> {
    if currency == Currency::CNY {
        return Some(FxRate {
            currency,
            day,
            rate: RATE_SCALE,
            source: "base".into(),
        });
    }
    rates
        .iter()
        .filter(|r| r.currency == currency && r.day <= day && r.rate > 0)
        .max_by_key(|r| r.day)
        .cloned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use jiff::civil::date;
    #[test]
    fn dated_rates_missing_future_and_rounding_are_explicit() {
        let db = navi_storage::memory(&[SCHEMA]).unwrap();
        let day = date(2026, 7, 1);
        assert!(rate_on(&db, Currency::USD, day).unwrap().is_none());
        save_rate(
            &db,
            &FxRate {
                currency: Currency::USD,
                day: day.tomorrow().unwrap(),
                rate: 7_123_456,
                source: "manual".into(),
            },
        )
        .unwrap();
        assert!(rate_on(&db, Currency::USD, day).unwrap().is_none());
        assert_eq!(
            rate_on(&db, Currency::USD, day.tomorrow().unwrap())
                .unwrap()
                .unwrap()
                .rate,
            7_123_456
        );
        assert_eq!(convert_to_cny(1, 1_500_000).unwrap(), 2);
        assert_eq!(convert_to_cny(-1, 1_500_000).unwrap(), -2);
        assert!(convert_to_cny(i64::MAX, i64::MAX).is_err());
        assert_eq!(
            rate_on(&db, Currency::CNY, day).unwrap().unwrap().rate,
            RATE_SCALE
        );
    }
    #[test]
    fn account_identity_and_ledger_balance_are_currency_specific() {
        use crate::{
            account::{Account, AccountKind, defaults},
            journal::{self, Entry, Posting, Source},
        };
        let usd = Account::new_in(AccountKind::Assets, "Bank", Currency::USD).unwrap();
        assert_eq!(usd.as_str(), "资产/USD:Bank");
        assert_eq!(usd.name(), "Bank");
        assert_eq!(Account::parse(usd.as_str()).unwrap(), usd);
        let cny = Account::new(AccountKind::Assets, "Bank").unwrap();
        let entry = || Entry {
            id: "fx".into(),
            at: date(2026, 7, 1).at(0, 0, 0, 0),
            payee: "".into(),
            note: "".into(),
            source: Source::Manual,
        };
        assert!(journal::transfer(entry(), &usd, &cny, 100).is_err());
        let fx = journal::exchange(entry(), &usd, &cny, 100, 700).unwrap();
        assert!(fx.validate().is_ok());
        let mut bad = fx;
        bad.postings = vec![
            Posting {
                account: usd.clone(),
                amount: -100,
            },
            Posting {
                account: cny,
                amount: 100,
            },
        ];
        assert!(bad.validate().is_err());
        assert!(
            journal::opening(entry(), &usd, 100)
                .unwrap()
                .validate()
                .is_ok()
        );
        assert!(journal::spend(entry(), &usd, &defaults::other_expense(), 100).is_err());
    }
}
