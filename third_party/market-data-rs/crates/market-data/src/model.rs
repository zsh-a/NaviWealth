use crate::{Error, ErrorKind, Result};
use chrono::{DateTime, FixedOffset, NaiveDate, NaiveDateTime, TimeZone, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use std::{fmt, str::FromStr};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Exchange {
    SSE,
    SZSE,
    BSE,
}

/// Canonical wire form: 600519.SH. Bare 000001 is SZSE; sh000001 is SSE.
/// Exchange namespaces are preserved; symbol alone does not imply asset type.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct Symbol {
    pub(crate) code: String,
    pub(crate) exchange: Exchange,
}

impl Symbol {
    pub fn code(&self) -> &str {
        &self.code
    }
    pub fn exchange(&self) -> Exchange {
        self.exchange
    }
    pub fn wire_code(&self) -> String {
        let prefix = match self.exchange {
            Exchange::SSE => "sh",
            Exchange::SZSE => "sz",
            Exchange::BSE => "bj",
        };
        format!("{prefix}{}", self.code)
    }
    pub fn eastmoney_id(&self) -> String {
        format!(
            "{}.{}",
            if self.exchange == Exchange::SSE { 1 } else { 0 },
            self.code
        )
    }
}
impl FromStr for Symbol {
    type Err = Error;
    fn from_str(value: &str) -> Result<Self> {
        let s = value.trim().to_ascii_uppercase();
        let parse_exchange = |s: &str| match s {
            "SH" | "SS" => Some(Exchange::SSE),
            "SZ" => Some(Exchange::SZSE),
            "BJ" => Some(Exchange::BSE),
            _ => None,
        };
        let (code, exchange) = if let Some((code, suffix)) = s.split_once('.') {
            (code, parse_exchange(suffix))
        } else if s.len() == 8 && s.is_ascii() {
            (&s[2..], parse_exchange(&s[..2]))
        } else {
            let exchange = match s.as_bytes().first() {
                Some(b'5' | b'6') => Some(Exchange::SSE),
                Some(b'0' | b'1' | b'3') => Some(Exchange::SZSE),
                Some(b'4' | b'8') => Some(Exchange::BSE),
                Some(b'9') if s.starts_with("920") => Some(Exchange::BSE),
                _ => None,
            };
            (s.as_str(), exchange)
        };
        if code.len() != 6 || !code.bytes().all(|b| b.is_ascii_digit()) || exchange.is_none() {
            return Err(Error::new(
                ErrorKind::InvalidRequest,
                "expected an A-share code such as 600519, sh600519 or 600519.SH",
            ));
        }
        Ok(Self {
            code: code.into(),
            exchange: exchange.unwrap(),
        })
    }
}
impl fmt::Display for Symbol {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{}.{}",
            self.code,
            match self.exchange {
                Exchange::SSE => "SH",
                Exchange::SZSE => "SZ",
                Exchange::BSE => "BJ",
            }
        )
    }
}
impl TryFrom<String> for Symbol {
    type Error = Error;
    fn try_from(s: String) -> Result<Self> {
        s.parse()
    }
}
impl From<Symbol> for String {
    fn from(s: Symbol) -> Self {
        s.to_string()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum Adjustment {
    #[default]
    Raw,
    Forward,
    Backward,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryRequest {
    pub symbol: Symbol,
    pub from: NaiveDate,
    pub to: NaiveDate,
    #[serde(default)]
    pub adjustment: Adjustment,
    /// Partial windows require an explicit opt-in. No provider switch can change adjustment.
    #[serde(default)]
    pub allow_partial: bool,
}
impl HistoryRequest {
    pub fn validate(&self) -> Result<()> {
        if self.from > self.to || (self.to - self.from).num_days() > 365 * 100 {
            return Err(Error::new(
                ErrorKind::InvalidRequest,
                "invalid history range (maximum 100 years)",
            ));
        }
        let today = Utc::now()
            .with_timezone(&FixedOffset::east_opt(8 * 3600).unwrap())
            .date_naive();
        if self.to > today {
            return Err(Error::new(
                ErrorKind::InvalidRequest,
                "history end date is in the future",
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Quote {
    pub symbol: Symbol,
    pub name: String,
    pub currency: String,
    #[serde(with = "rust_decimal::serde::str")]
    pub price: Decimal,
    #[serde(with = "rust_decimal::serde::str_option")]
    pub previous_close: Option<Decimal>,
    pub observed_at: DateTime<Utc>,
    /// True when no current price was available and previous close was used.
    pub previous_close_only: bool,
}

/// A daily bar's date is a trading calendar label, never a UTC-converted midnight.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bar {
    pub date: NaiveDate,
    #[serde(with = "rust_decimal::serde::str")]
    pub open: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub high: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub low: Decimal,
    #[serde(with = "rust_decimal::serde::str")]
    pub close: Decimal,
    /// Shares, not lots. Decimal preserves sub-share rounding present upstream.
    #[serde(with = "rust_decimal::serde::str")]
    pub volume_shares: Decimal,
}
impl Bar {
    pub fn validate(&self) -> Result<()> {
        if [self.open, self.high, self.low, self.close]
            .iter()
            .any(|x| *x <= Decimal::ZERO)
            || self.volume_shares < Decimal::ZERO
            || self.low > self.open.min(self.close)
            || self.high < self.open.max(self.close)
            || self.high < self.low
        {
            return Err(Error::new(
                ErrorKind::Parse,
                "invalid OHLCV or non-positive adjusted price",
            ));
        }
        Ok(())
    }
}

impl Quote {
    pub fn validate(&self, symbol: &Symbol) -> Result<()> {
        if &self.symbol != symbol
            || self.currency != "CNY"
            || self.price <= Decimal::ZERO
            || self.previous_close.is_some_and(|p| p <= Decimal::ZERO)
            || self.observed_at > Utc::now() + chrono::Duration::minutes(5)
        {
            return Err(Error::new(
                ErrorKind::Parse,
                "invalid quote identity, price, currency or future timestamp",
            ));
        }
        Ok(())
    }
}

/// Providers must report the actual price basis, even if the upstream ignored it.
#[derive(Debug, Clone)]
pub struct HistoryPage {
    pub symbol: Symbol,
    pub adjustment: Adjustment,
    pub bars: Vec<Bar>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Coverage {
    pub requested_from: NaiveDate,
    pub requested_to: NaiveDate,
    pub first: NaiveDate,
    pub last: NaiveDate,
    /// Conservative calendar-gap screening only; no exchange-calendar certification.
    pub boundary_check_passed: bool,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct History {
    pub symbol: Symbol,
    pub adjustment: Adjustment,
    pub bars: Vec<Bar>,
    pub coverage: Coverage,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Freshness {
    Network,
    Cached,
    Stale,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Data<T> {
    pub data: T,
    pub source: String,
    pub fetched_at: DateTime<Utc>,
    /// Freshness describes the fetch/cache, not whether the exchange is open.
    pub freshness: Freshness,
    pub warnings: Vec<String>,
    pub attempts: Vec<Error>,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct FetchOptions {
    pub refresh: bool,
    pub allow_stale: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuoteOutcome {
    pub symbol: Symbol,
    pub result: Result<Data<Quote>>,
}

pub(crate) fn decimal(s: &str) -> Result<Decimal> {
    Decimal::from_str(s.trim()).map_err(|_| Error::new(ErrorKind::Parse, "invalid decimal field"))
}
pub(crate) fn china_time(s: &str, fmt: &str) -> Result<DateTime<Utc>> {
    let value = NaiveDateTime::parse_from_str(s, fmt)
        .map_err(|_| Error::new(ErrorKind::Parse, "invalid quote timestamp"))?;
    FixedOffset::east_opt(8 * 3600)
        .unwrap()
        .from_local_datetime(&value)
        .single()
        .map(|v| v.with_timezone(&Utc))
        .ok_or_else(|| Error::new(ErrorKind::Parse, "invalid China timestamp"))
}
