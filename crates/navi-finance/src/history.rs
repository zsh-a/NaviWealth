//! Immutable raw daily OHLCV revisions and transactional price-change audit.
use crate::{
    catalog::{self, SecurityBinding},
    market,
};
use jiff::{Timestamp, civil::Date};
use navi_storage::sqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};

pub const SCHEMA: &str = r#"
CREATE TABLE finance_daily_bars(revision INTEGER PRIMARY KEY,market TEXT NOT NULL,symbol TEXT NOT NULL,currency TEXT NOT NULL,provider TEXT NOT NULL,day TEXT NOT NULL,open INTEGER NOT NULL CHECK(open>0),high INTEGER NOT NULL CHECK(high>=open AND high>=close),low INTEGER NOT NULL CHECK(low>0 AND low<=open AND low<=close),close INTEGER NOT NULL CHECK(close>0),volume INTEGER CHECK(volume>=0),fetched_at TEXT NOT NULL,received_at TEXT NOT NULL);
CREATE INDEX finance_daily_bars_identity ON finance_daily_bars(market,symbol,currency,provider,day,fetched_at,revision);
CREATE TABLE finance_price_audit(id INTEGER PRIMARY KEY,kind TEXT NOT NULL,item_key TEXT NOT NULL,day TEXT NOT NULL,body TEXT NOT NULL,received_at TEXT NOT NULL);
INSERT INTO finance_price_audit(kind,item_key,day,body,received_at) SELECT 'manual_quote',security,day,json_object('security',security,'day',day,'price',price,'baseline',json('true')),strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM finance_quotes;
INSERT INTO finance_price_audit(kind,item_key,day,body,received_at) SELECT 'fx_rate',currency,day,json_object('currency',currency,'day',day,'rate',rate,'source',source,'baseline',json('true')),strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM finance_fx_rates;
INSERT INTO finance_price_audit(kind,item_key,day,body,received_at) SELECT 'market_quote',security,day,json_object('security',security,'symbol',symbol,'currency',currency,'provider',provider,'price',price,'observed_at',observed_at,'fetched_at',fetched_at,'previous_close_only',json(CASE previous_close_only WHEN 1 THEN 'true' ELSE 'false' END),'baseline',json('true')),strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM finance_market_quotes;
"#;
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid daily price history or stale binding")]
    Invalid,
    #[error(transparent)]
    Sql(#[from] navi_storage::sqlite::Error),
    #[error(transparent)]
    Market(#[from] market::Error),
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DailyBar {
    pub market: String,
    pub symbol: String,
    pub currency: String,
    pub provider: String,
    pub day: Date,
    /// Raw, unadjusted prices in millionths of the listing currency.
    pub open: i64,
    pub high: i64,
    pub low: i64,
    pub close: i64,
    pub volume: Option<i64>,
    pub fetched_at: Timestamp,
}
impl DailyBar {
    pub fn validate(&self, b: &SecurityBinding, now: Timestamp) -> Result<(), Error> {
        let zone = if b.market == "us_stock" {
            "America/New_York"
        } else {
            "Asia/Shanghai"
        };
        let today = now
            .to_zoned(jiff::tz::TimeZone::get(zone).map_err(|_| Error::Invalid)?)
            .date();
        if b.validate().is_err()
            || market::canonical_binding(b).as_ref() != Some(&self.symbol)
            || self.market != b.market
            || self.currency != b.currency
            || self.provider.is_empty()
            || self.provider.len() > 80
            || !self
                .provider
                .bytes()
                .all(|v| v.is_ascii_alphanumeric() || b":_-".contains(&v))
            || self.day >= today
            || self.day
                >= self
                    .fetched_at
                    .to_zoned(jiff::tz::TimeZone::get(zone).map_err(|_| Error::Invalid)?)
                    .date()
            || self.open <= 0
            || self.close <= 0
            || self.low <= 0
            || self.high < self.open.max(self.close)
            || self.low > self.open.min(self.close)
            || self.volume.is_some_and(|v| v < 0)
            || self.fetched_at > now
        {
            return Err(Error::Invalid);
        }
        Ok(())
    }
}
fn exists(c: &Connection) -> Result<bool, Error> {
    Ok(c.query_row("SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='finance_daily_bars')", [], |r|r.get(0))?)
}
/// All immutable revisions, ordered by fetch time. Equal payload retries add no revision.
pub fn revisions(
    c: &Connection,
    b: &SecurityBinding,
    from: Date,
    to: Date,
) -> Result<Vec<DailyBar>, Error> {
    let symbol = market::canonical_binding(b).ok_or(Error::Invalid)?;
    if from > to {
        return Err(Error::Invalid);
    }
    if !exists(c)? {
        return Ok(vec![]);
    }
    let mut q=c.prepare("SELECT market,symbol,currency,provider,day,open,high,low,close,volume,fetched_at FROM finance_daily_bars WHERE market=?1 AND symbol=?2 AND currency=?3 AND day>=?4 AND day<=?5 ORDER BY day,revision")?;
    let rows = q.query_map(
        params![
            b.market,
            symbol,
            b.currency,
            from.to_string(),
            to.to_string()
        ],
        |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get(5)?,
                r.get(6)?,
                r.get(7)?,
                r.get(8)?,
                r.get(9)?,
                r.get::<_, String>(10)?,
            ))
        },
    )?;
    let mut out = vec![];
    for r in rows {
        let (market, symbol, currency, provider, day, open, high, low, close, volume, fetched_at) =
            r?;
        out.push(DailyBar {
            market,
            symbol,
            currency,
            provider,
            day: day.parse().map_err(|_| Error::Invalid)?,
            open,
            high,
            low,
            close,
            volume,
            fetched_at: fetched_at.parse().map_err(|_| Error::Invalid)?,
        });
    }
    out.sort_by_key(|row| (row.day, row.fetched_at));
    Ok(out)
}
/// Latest received revision at the newest fetch time for each trading date.
pub fn bars(
    c: &Connection,
    b: &SecurityBinding,
    from: Date,
    to: Date,
) -> Result<Vec<DailyBar>, Error> {
    let mut latest = std::collections::BTreeMap::new();
    for bar in revisions(c, b, from, to)? {
        latest.insert(bar.day, bar);
    }
    Ok(latest.into_values().collect())
}
pub fn save_bars(
    c: &Connection,
    b: &SecurityBinding,
    rows: &[DailyBar],
    now: Timestamp,
) -> Result<usize, Error> {
    let tx = c.unchecked_transaction()?;
    if !catalog::bindings(&tx)
        .map_err(|_| Error::Invalid)?
        .contains(b)
    {
        return Err(Error::Invalid);
    }
    let mut changed = 0;
    for row in rows {
        row.validate(b, now)?;
        let old = revisions(&tx, b, row.day, row.day)?
            .into_iter()
            .rfind(|v| v.provider == row.provider);
        if old.as_ref().is_some_and(|v| v.fetched_at > row.fetched_at) {
            continue;
        }
        if let Some(old) = old {
            let mut comparable = row.clone();
            comparable.fetched_at = old.fetched_at;
            if comparable == old {
                continue;
            }
            if old.fetched_at == row.fetched_at {
                return Err(Error::Invalid);
            }
        }
        tx.execute("INSERT INTO finance_daily_bars(market,symbol,currency,provider,day,open,high,low,close,volume,fetched_at,received_at) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)",params![row.market,row.symbol,row.currency,row.provider,row.day.to_string(),row.open,row.high,row.low,row.close,row.volume,row.fetched_at.to_string(),now.to_string()])?;
        changed += 1;
    }
    market::valued_book(
        &tx,
        crate::holdings::store::load(&tx).map_err(|_| Error::Invalid)?,
    )
    .map_err(|_| Error::Invalid)?
    .validate_values()
    .map_err(|_| Error::Invalid)?;
    tx.commit()?;
    Ok(changed)
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditRevision {
    pub id: i64,
    pub kind: String,
    pub item_key: String,
    pub day: String,
    pub body: String,
    pub received_at: String,
}
pub fn audit(c: &Connection) -> Result<Vec<AuditRevision>, Error> {
    let mut q = c.prepare(
        "SELECT id,kind,item_key,day,body,received_at FROM finance_price_audit ORDER BY id DESC",
    )?;
    Ok(q.query_map([], |r| {
        Ok(AuditRevision {
            id: r.get(0)?,
            kind: r.get(1)?,
            item_key: r.get(2)?,
            day: r.get(3)?,
            body: r.get(4)?,
            received_at: r.get(5)?,
        })
    })?
    .collect::<Result<Vec<_>, _>>()?)
}
pub fn validate(c: &Connection) -> Result<(), Error> {
    if !exists(c)? {
        return Ok(());
    }
    let mut q = c.prepare("SELECT DISTINCT market,symbol,currency FROM finance_daily_bars")?;
    let ids = q
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    for (market, symbol, currency) in ids {
        let raw = match market.as_str() {
            "cn_a" => symbol.split('.').next().unwrap_or("").to_string(),
            "hk_stock" => symbol.trim_end_matches(".HK").to_string(),
            "us_stock" => symbol.trim_end_matches(".US").to_string(),
            _ => return Err(Error::Invalid),
        };
        let b = SecurityBinding {
            security: "history".into(),
            market,
            symbol: raw,
            currency,
        };
        if b.validate().is_err() || market::canonical_binding(&b).as_ref() != Some(&symbol) {
            return Err(Error::Invalid);
        }
        for bar in revisions(c, &b, Date::MIN, Date::MAX)? {
            bar.validate(&b, Timestamp::now())?;
        }
    }
    let mut q = c.prepare("SELECT received_at,fetched_at FROM finance_daily_bars")?;
    for row in q.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (received, fetched) = row?;
        let received: Timestamp = received.parse().map_err(|_| Error::Invalid)?;
        let fetched: Timestamp = fetched.parse().map_err(|_| Error::Invalid)?;
        if received < fetched || received > Timestamp::now() {
            return Err(Error::Invalid);
        }
    }
    for row in audit(c)? {
        let received: Timestamp = row.received_at.parse().map_err(|_| Error::Invalid)?;
        let day: Date = row.day.parse().map_err(|_| Error::Invalid)?;
        let body: serde_json::Value =
            serde_json::from_str(&row.body).map_err(|_| Error::Invalid)?;
        if row.id <= 0 || day.to_string() != row.day || received > Timestamp::now() {
            return Err(Error::Invalid);
        }
        match row.kind.as_str() {
            "manual_quote" => {
                if body["security"].as_str() != Some(&row.item_key)
                    || body["day"].as_str() != Some(&row.day)
                    || body["price"].as_i64().is_none_or(|v| v < 0)
                {
                    return Err(Error::Invalid);
                }
            }
            "fx_rate" => {
                let currency =
                    crate::currency::Currency::parse(&row.item_key).ok_or(Error::Invalid)?;
                let rate = body["rate"].as_i64().ok_or(Error::Invalid)?;
                if body["currency"].as_str() != Some(&row.item_key)
                    || body["day"].as_str() != Some(&row.day)
                    || rate <= 0
                    || body["source"].as_str().is_none_or(|v| v.trim().is_empty())
                    || (currency == crate::currency::Currency::CNY
                        && rate != crate::currency::RATE_SCALE)
                {
                    return Err(Error::Invalid);
                }
            }
            "market_quote" | "market_quote_unbound" => {
                let quote: market::MarketQuote =
                    serde_json::from_value(if row.kind == "market_quote" {
                        body.clone()
                    } else {
                        body["quote"].clone()
                    })
                    .map_err(|_| Error::Invalid)?;
                let binding = if row.kind == "market_quote_unbound" {
                    serde_json::from_value(body["binding"].clone()).map_err(|_| Error::Invalid)?
                } else {
                    let (market, symbol) = if let Some(s) = quote.symbol.strip_suffix(".US") {
                        ("us_stock", s.to_string())
                    } else if let Some(s) = quote.symbol.strip_suffix(".HK") {
                        ("hk_stock", s.to_string())
                    } else {
                        (
                            "cn_a",
                            quote.symbol.split('.').next().unwrap_or("").to_string(),
                        )
                    };
                    SecurityBinding {
                        security: quote.security.clone(),
                        market: market.into(),
                        symbol,
                        currency: quote.currency.clone(),
                    }
                };
                quote
                    .validate(&binding, received)
                    .map_err(|_| Error::Invalid)?;
                if quote.security != row.item_key || quote.day() != day {
                    return Err(Error::Invalid);
                }
            }
            _ => return Err(Error::Invalid),
        }
    }
    Ok(())
}

/// Called inside the mutation transaction, so rejected writes leave no audit row.
pub(crate) fn record(
    c: &Connection,
    kind: &str,
    key: &str,
    day: &str,
    body: &serde_json::Value,
) -> Result<(), navi_storage::sqlite::Error> {
    let has:bool=c.query_row("SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='finance_price_audit')",[],|r|r.get(0))?;
    if has {
        let previous:Option<String>=c.query_row("SELECT body FROM finance_price_audit WHERE kind=?1 AND item_key=?2 AND day=?3 ORDER BY id DESC LIMIT 1",params![kind,key,day],|r|r.get(0)).optional()?;
        if let Some(previous) = previous
            && let Ok(mut previous) = serde_json::from_str::<serde_json::Value>(&previous)
        {
            if let Some(object) = previous.as_object_mut() {
                object.remove("baseline");
            }
            if previous == *body {
                return Ok(());
            }
        }
        c.execute("INSERT INTO finance_price_audit(kind,item_key,day,body,received_at) VALUES(?1,?2,?3,?4,?5)",params![kind,key,day,body.to_string(),Timestamp::now().to_string()])?;
    }
    Ok(())
}

/// Identify a final daily close used by the valued book. Manual ties remain explicit.
pub fn effective_bar(
    c: &Connection,
    q: &crate::holdings::Quote,
) -> Result<Option<DailyBar>, Error> {
    if has_manual_price(c, q)? {
        return Ok(None);
    }
    let binding = catalog::bindings(c)
        .map_err(|_| Error::Invalid)?
        .into_iter()
        .find(|b| b.security == q.security);
    let Some(binding) = binding else {
        return Ok(None);
    };
    Ok(bars(c, &binding, q.day, q.day)?
        .into_iter()
        .find(|b| b.close == q.price))
}

/// Full archive, including listings no longer bound to a holding.
pub fn all_daily_revisions(c: &Connection) -> Result<Vec<DailyBar>, Error> {
    if !exists(c)? {
        return Ok(vec![]);
    }
    let mut q = c.prepare("SELECT DISTINCT market,symbol,currency FROM finance_daily_bars")?;
    let ids = q
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let mut out = vec![];
    for (market, symbol, currency) in ids {
        let raw = if market == "us_stock" {
            symbol.trim_end_matches(".US").to_string()
        } else if market == "hk_stock" {
            symbol.trim_end_matches(".HK").to_string()
        } else {
            symbol.split('.').next().unwrap_or("").to_string()
        };
        let binding = SecurityBinding {
            security: "history".into(),
            market,
            symbol: raw,
            currency,
        };
        if binding.validate().is_err()
            || market::canonical_binding(&binding).as_ref() != Some(&symbol)
        {
            return Err(Error::Invalid);
        }
        out.extend(revisions(c, &binding, Date::MIN, Date::MAX)?);
    }
    out.sort_by(|a, b| b.day.cmp(&a.day).then(b.fetched_at.cmp(&a.fetched_at)));
    Ok(out)
}

/// Manual observations win ties with market marks and daily closes.
pub fn has_manual_price(c: &Connection, q: &crate::holdings::Quote) -> Result<bool, Error> {
    Ok(c.query_row(
        "SELECT EXISTS(SELECT 1 FROM finance_quotes WHERE security=?1 AND day=?2)",
        params![q.security, q.day.to_string()],
        |r| r.get(0),
    )?)
}
