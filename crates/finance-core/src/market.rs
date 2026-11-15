//! Dated public marks; these never mutate trades, costs or the cash journal.
use crate::{
    catalog,
    holdings::{Book, Quote},
};
use jiff::{Timestamp, civil::Date};
use lifeos_core::sqlite::{Connection, params};
use serde::{Deserialize, Serialize};

pub const SCHEMA: &str = "CREATE TABLE finance_market_quotes(security TEXT NOT NULL REFERENCES finance_securities(id),symbol TEXT NOT NULL,currency TEXT NOT NULL,provider TEXT NOT NULL,price INTEGER NOT NULL CHECK(typeof(price)='integer' AND price>0),observed_at TEXT NOT NULL,fetched_at TEXT NOT NULL,previous_close_only INTEGER NOT NULL,day TEXT NOT NULL,PRIMARY KEY(security,day));";
pub const TABLES: &[&str] = &["finance_market_quotes"];
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid or mismatched market quote")]
    Invalid,
    #[error(transparent)]
    Sql(#[from] lifeos_core::sqlite::Error),
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MarketQuote {
    pub security: String,
    pub symbol: String,
    pub currency: String,
    pub provider: String,
    /// Millionths of the binding currency per share, without floating point conversion.
    pub price: i64,
    pub observed_at: Timestamp,
    pub fetched_at: Timestamp,
    pub previous_close_only: bool,
}
impl MarketQuote {
    pub fn day(&self) -> Date {
        self.observed_at
            .to_zoned(if self.currency == "USD" {
                jiff::tz::TimeZone::get("America/New_York").expect("bundled US timezone")
            } else {
                jiff::tz::TimeZone::fixed(jiff::tz::Offset::from_hours(8).expect("fixed offset"))
            })
            .date()
    }
    pub fn validate(
        &self,
        binding: &catalog::SecurityBinding,
        now: Timestamp,
    ) -> Result<(), Error> {
        let expected = canonical_binding(binding).ok_or(Error::Invalid)?;
        if binding.validate().is_err()
            || self.security != binding.security
            || self.symbol != expected
            || self.currency != binding.currency
            || self.provider != "tencent"
            || self.price <= 0
            || self.observed_at
                > now
                    .checked_add(jiff::Span::new().minutes(5))
                    .map_err(|_| Error::Invalid)?
            || self.fetched_at
                > now
                    .checked_add(jiff::Span::new().minutes(5))
                    .map_err(|_| Error::Invalid)?
            || self.observed_at
                > self
                    .fetched_at
                    .checked_add(jiff::Span::new().minutes(5))
                    .map_err(|_| Error::Invalid)?
        {
            return Err(Error::Invalid);
        }
        Ok(())
    }
}
/// Same exchange inference as the A-share SDK; unsupported prefixes stay unsupported.
pub fn canonical_symbol(code: &str) -> Option<String> {
    if code.len() != 6 || !code.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let exchange = match code.as_bytes()[0] {
        b'5' | b'6' => "SH",
        b'0' | b'1' | b'3' => "SZ",
        b'4' | b'8' => "BJ",
        b'9' if code.starts_with("920") => "BJ",
        _ => return None,
    };
    Some(format!("{code}.{exchange}"))
}
/// The catalog uses Yahoo-style 0700.HK; Tencent requests require 00700.
pub fn hong_kong_code(symbol: &str) -> Option<String> {
    let code = symbol.strip_suffix(".HK").unwrap_or(symbol);
    if !(4..=5).contains(&code.len())
        || !code.bytes().all(|b| b.is_ascii_digit())
        || code.bytes().all(|b| b == b'0')
    {
        return None;
    }
    Some(format!("{code:0>5}"))
}
/// Market-qualified provider identity; numeric HK symbols never use A-share inference.
pub fn canonical_binding(binding: &catalog::SecurityBinding) -> Option<String> {
    binding.validate().ok()?;
    match binding.market.as_str() {
        "cn_a" => canonical_symbol(&binding.symbol),
        "hk_stock" => Some(format!("{}.HK", hong_kong_code(&binding.symbol)?)),
        "us_stock" => Some(format!("{}.US", binding.symbol)),
        _ => None,
    }
}
/// Strict Tencent HK/US boundary. Display names are deliberately ignored (GBK).
pub fn parse_tencent(
    binding: &catalog::SecurityBinding,
    raw: &str,
    fetched_at: Timestamp,
) -> Result<MarketQuote, Error> {
    binding.validate().map_err(|_| Error::Invalid)?;
    let request = match binding.market.as_str() {
        "hk_stock" => format!(
            "hk{}",
            hong_kong_code(&binding.symbol).ok_or(Error::Invalid)?
        ),
        "us_stock" => format!("us{}", binding.symbol),
        _ => return Err(Error::Invalid),
    };
    let prefix = format!("v_{request}=\"");
    let data = raw
        .trim()
        .strip_prefix(&prefix)
        .and_then(|s| s.strip_suffix("\";"))
        .ok_or(Error::Invalid)?;
    let fields: Vec<_> = data.split('~').collect();
    let field = |i| fields.get(i).copied().ok_or(Error::Invalid);
    let (currency, zone) = if binding.market == "hk_stock" {
        if field(0)? != "100"
            || field(2)? != hong_kong_code(&binding.symbol).ok_or(Error::Invalid)?
        {
            return Err(Error::Invalid);
        }
        (field(75)?, "Asia/Hong_Kong")
    } else {
        let id = field(2)?;
        if field(0)? != "200"
            || !(id == binding.symbol
                || id
                    .strip_prefix(&binding.symbol)
                    .is_some_and(|s| matches!(s, ".OQ" | ".N" | ".A" | ".P")))
        {
            return Err(Error::Invalid);
        }
        (field(35)?, "America/New_York")
    };
    if currency != binding.currency {
        return Err(Error::Invalid);
    }
    let local: jiff::civil::DateTime = field(30)?
        .replace('/', "-")
        .replace(' ', "T")
        .parse()
        .map_err(|_| Error::Invalid)?;
    let observed_at = local
        .to_zoned(jiff::tz::TimeZone::get(zone).map_err(|_| Error::Invalid)?)
        .map_err(|_| Error::Invalid)?
        .timestamp();
    let quote = MarketQuote {
        security: binding.security.clone(),
        symbol: canonical_binding(binding).ok_or(Error::Invalid)?,
        currency: currency.into(),
        provider: "tencent".into(),
        price: crate::holdings::parse_units(field(3)?)
            .filter(|p| *p > 0)
            .ok_or(Error::Invalid)?,
        observed_at,
        fetched_at,
        previous_close_only: false,
    };
    quote.validate(binding, fetched_at)?;
    Ok(quote)
}
/// ECB daily reference rates supplied through Frankfurter; never invent a parity rate.
pub fn parse_fx(
    raw: &str,
    currency: crate::currency::Currency,
    today: Date,
) -> Result<crate::currency::FxRate, Error> {
    use crate::currency::{Currency, FxRate};
    if currency == Currency::CNY || raw.len() > 16384 {
        return Err(Error::Invalid);
    }
    let rows: serde_json::Value = serde_json::from_str(raw).map_err(|_| Error::Invalid)?;
    let rows = rows
        .as_array()
        .filter(|r| r.len() == 1)
        .ok_or(Error::Invalid)?;
    let row = &rows[0];
    if row["base"].as_str() != Some(currency.code()) || row["quote"].as_str() != Some("CNY") {
        return Err(Error::Invalid);
    }
    let day: Date = row["date"]
        .as_str()
        .ok_or(Error::Invalid)?
        .parse()
        .map_err(|_| Error::Invalid)?;
    if day > today {
        return Err(Error::Invalid);
    }
    let text = row["rate"].as_number().ok_or(Error::Invalid)?.to_string();
    let (whole, fraction) = text.split_once('.').unwrap_or((&text, ""));
    if whole.is_empty()
        || !whole
            .bytes()
            .chain(fraction.bytes())
            .all(|b| b.is_ascii_digit())
    {
        return Err(Error::Invalid);
    }
    let mut decimals = fraction.chars().take(6).collect::<String>();
    while decimals.len() < 6 {
        decimals.push('0');
    }
    let rate = whole
        .parse::<i64>()
        .ok()
        .and_then(|v| v.checked_mul(1_000_000))
        .and_then(|v| v.checked_add(decimals.parse::<i64>().ok()?))
        .and_then(|v| {
            v.checked_add(i64::from(
                fraction.as_bytes().get(6).is_some_and(|b| *b >= b'5'),
            ))
        })
        .filter(|v| *v > 0)
        .ok_or(Error::Invalid)?;
    Ok(FxRate {
        currency,
        day,
        rate,
        source: "frankfurter:ecb".into(),
    })
}
pub fn load(c: &Connection) -> Result<Vec<MarketQuote>, Error> {
    let mut stmt=c.prepare("SELECT security,symbol,currency,provider,price,observed_at,fetched_at,previous_close_only,day FROM finance_market_quotes ORDER BY day,security")?;
    let rows = stmt.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, i64>(4)?,
            r.get::<_, String>(5)?,
            r.get::<_, String>(6)?,
            r.get::<_, i64>(7)?,
            r.get::<_, String>(8)?,
        ))
    })?;
    let bindings = catalog::bindings(c).map_err(|_| Error::Invalid)?;
    let mut out = Vec::new();
    for row in rows {
        let (
            security,
            symbol,
            currency,
            provider,
            price,
            observed,
            fetched,
            previous_close_only,
            day,
        ) = row?;
        if !matches!(previous_close_only, 0 | 1) {
            return Err(Error::Invalid);
        }
        let q = MarketQuote {
            security,
            symbol,
            currency,
            provider,
            price,
            observed_at: observed.parse().map_err(|_| Error::Invalid)?,
            fetched_at: fetched.parse().map_err(|_| Error::Invalid)?,
            previous_close_only: previous_close_only == 1,
        };
        let binding = bindings
            .iter()
            .find(|b| b.security == q.security)
            .ok_or(Error::Invalid)?;
        q.validate(binding, Timestamp::now())?;
        if q.day().to_string() != day {
            return Err(Error::Invalid);
        }
        out.push(q);
    }
    Ok(out)
}
/// False means an older asynchronous result was ignored, preserving the newer mark.
pub fn save(c: &Connection, q: &MarketQuote, now: Timestamp) -> Result<bool, Error> {
    let tx = c.unchecked_transaction()?;
    let binding = catalog::bindings(&tx)
        .map_err(|_| Error::Invalid)?
        .into_iter()
        .find(|b| b.security == q.security)
        .ok_or(Error::Invalid)?;
    q.validate(&binding, now)?;
    if load(&tx)?
        .iter()
        .filter(|old| old.security == q.security)
        .any(|old| {
            old.observed_at > q.observed_at
                || (old.observed_at == q.observed_at && old.fetched_at >= q.fetched_at)
        })
    {
        return Ok(false);
    }
    tx.execute("INSERT INTO finance_market_quotes(security,symbol,currency,provider,price,observed_at,fetched_at,previous_close_only,day) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9) ON CONFLICT(security,day) DO UPDATE SET symbol=excluded.symbol,currency=excluded.currency,provider=excluded.provider,price=excluded.price,observed_at=excluded.observed_at,fetched_at=excluded.fetched_at,previous_close_only=excluded.previous_close_only", params![q.security,q.symbol,q.currency,q.provider,q.price,q.observed_at.to_string(),q.fetched_at.to_string(),q.previous_close_only,q.day().to_string()])?;
    crate::history::record(
        &tx,
        "market_quote",
        &q.security,
        &q.day().to_string(),
        &serde_json::to_value(q).map_err(|_| Error::Invalid)?,
    )?;
    let book = crate::holdings::store::load(&tx).map_err(|_| Error::Invalid)?;
    valued_book(&tx, book)?
        .validate_values()
        .map_err(|_| Error::Invalid)?;
    tx.commit()?;
    Ok(true)
}
/// Keep all dated marks. Manual marks win a date tie; historical valuations
/// can only see quotes whose trading day has already occurred.
pub fn valued_book(c: &Connection, mut book: Book) -> Result<Book, Error> {
    let mut quotes = load(c)?
        .into_iter()
        .map(|q| {
            let day = q.day();
            Quote {
                security: q.security,
                day,
                price: q.price,
            }
        })
        .collect::<Vec<_>>();
    // Final raw daily closes supersede a sampled intraday mark on the same date.
    for binding in catalog::bindings(c).map_err(|_| Error::Invalid)? {
        for bar in
            crate::history::bars(c, &binding, Date::MIN, Date::MAX).map_err(|_| Error::Invalid)?
        {
            quotes.retain(|q| q.security != binding.security || q.day != bar.day);
            quotes.push(Quote {
                security: binding.security.clone(),
                day: bar.day,
                price: bar.close,
            });
        }
    }
    quotes.extend(book.quotes);
    book.quotes = quotes;
    Ok(book)
}

/// Validate backup/restore rows without rewriting them.
pub fn validate(c: &Connection) -> Result<(), Error> {
    let book = crate::holdings::store::load(c).map_err(|_| Error::Invalid)?;
    valued_book(c, book)?
        .validate_values()
        .map_err(|_| Error::Invalid)
}
