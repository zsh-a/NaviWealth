//! Append-only observations, independent of subsequent ledger and market edits.
use crate::{
    account::Account,
    currency::{self, Currency, FxRate},
    holdings::{self, Book, Quote, Security, Trade},
    journal::{self, Transaction},
};
use jiff::{Timestamp, civil::Date};
use navi_storage::sqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const SCHEMA: &str = "CREATE TABLE finance_valuation_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,day TEXT NOT NULL,captured_at TEXT NOT NULL,body TEXT NOT NULL);";
// Timestamps are stored in canonical UTC. Removing Z makes a whole second
// sort before a fractional instant in the same second.
pub const HISTORY_INDEXES: &str = "
CREATE INDEX finance_snapshot_by_time ON finance_valuation_snapshots(rtrim(captured_at,'Z') DESC, id DESC, captured_at, json_extract(body,'$.net'),json_extract(body,'$.missing'));
CREATE INDEX finance_snapshot_by_day ON finance_valuation_snapshots(day,id DESC,
    CASE WHEN json_array_length(body,'$.missing')=0 THEN json_extract(body,'$.net') END);";
pub const TABLES: &[&str] = &["finance_valuation_snapshots"];
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid valuation snapshot")]
    Invalid,
    #[error(transparent)]
    Sql(#[from] navi_storage::sqlite::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Rate {
    pub currency: Currency,
    pub day: Date,
    pub rate: i64,
    pub source: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Balance {
    pub account: Account,
    pub native: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Holding {
    pub security: String,
    pub quantity: i64,
    pub cost: i64,
    pub value: i64,
    pub price: Option<i64>,
    pub price_day: Option<Date>,
    pub source: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Body {
    pub day: Date,
    pub captured_at: Timestamp,
    pub assets: i64,
    pub debt: i64,
    pub net: i64,
    pub missing: Vec<Currency>,
    pub balances: Vec<Balance>,
    pub holdings: Vec<Holding>,
    pub rates: Vec<Rate>,
    /// Full immutable calculation inputs, including the journal, permit restore validation.
    pub entries: Vec<Transaction>,
    pub securities: Vec<Security>,
    pub trades: Vec<Trade>,
    pub quotes: Vec<Quote>,
    pub ledger_fingerprint: String,
    /// Checksum covers provenance and all copied inputs as well as calculated totals.
    pub integrity: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    pub id: i64,
    pub body: Body,
}
fn fingerprint(entries: &[Transaction]) -> Result<String, Error> {
    Ok(crate::sha256_hex(&serde_json::to_vec(entries)?))
}
fn integrity(body: &Body) -> Result<String, Error> {
    let mut body = body.clone();
    body.integrity.clear();
    Ok(crate::sha256_hex(&serde_json::to_vec(&body)?))
}
type Derived = (i64, i64, i64, Vec<Currency>, Vec<Balance>, Vec<Holding>);
fn derive(body: &Body) -> Result<Derived, Error> {
    let book = Book {
        securities: body.securities.clone(),
        trades: body.trades.clone(),
        quotes: body.quotes.clone(),
    };
    let rates: Vec<_> = body
        .rates
        .iter()
        .map(|r| FxRate {
            currency: r.currency,
            day: r.day,
            rate: r.rate,
            source: r.source.clone(),
        })
        .collect();
    let valued = book
        .overview_with_rates(&body.entries, body.day, &rates)
        .map_err(|_| Error::Invalid)?;
    let balances = journal::balances(body.entries.iter())
        .into_iter()
        .map(|(account, native)| Balance { account, native })
        .collect();
    let mut positions = Vec::new();
    for security in &book.securities {
        let p = book
            .position(security, body.day)
            .map_err(|_| Error::Invalid)?;
        positions.push(Holding {
            security: security.id.clone(),
            quantity: p.quantity,
            cost: p.cost,
            value: p.value.unwrap_or(p.cost),
            price: p.quote.as_ref().map(|q| q.price),
            price_day: p.quote.as_ref().map(|q| q.day),
            source: if p.quote.is_none() {
                "cost".into()
            } else {
                body.holdings
                    .iter()
                    .find(|h| h.security == security.id)
                    .map(|h| h.source.clone())
                    .unwrap_or_default()
            },
        });
    }
    Ok((
        valued.snapshot.assets,
        valued.snapshot.debt,
        valued.snapshot.net,
        valued.missing,
        balances,
        positions,
    ))
}
fn validate_body(b: &Body) -> Result<(), Error> {
    if b.integrity != integrity(b)? {
        return Err(Error::Invalid);
    }
    let utc = b.captured_at.to_zoned_datetime(jiff::tz::TimeZone::UTC);
    let earliest = utc
        .checked_sub(jiff::Span::new().hours(14))
        .map_err(|_| Error::Invalid)?
        .date();
    let latest = utc
        .checked_add(jiff::Span::new().hours(14))
        .map_err(|_| Error::Invalid)?
        .date();
    if b.day < earliest || b.day > latest {
        return Err(Error::Invalid);
    }
    if b.entries
        .iter()
        .any(|t| t.at.date() > b.day || t.validate().is_err())
        || b.quotes.iter().any(|q| q.day > b.day || q.price < 0)
        || b.trades.iter().any(|t| t.at.date() > b.day)
        || b.rates.iter().any(|r| {
            r.day > b.day
                || r.rate <= 0
                || r.source.trim().is_empty()
                || (r.currency == Currency::CNY && r.rate != currency::RATE_SCALE)
        })
        || b.holdings.iter().any(|h| h.source.trim().is_empty())
        || fingerprint(&b.entries)? != b.ledger_fingerprint
    {
        return Err(Error::Invalid);
    }
    let (a, d, n, m, balances, holdings) = derive(b)?;
    if (a, d, n, m, balances, holdings)
        != (
            b.assets,
            b.debt,
            b.net,
            b.missing.clone(),
            b.balances.clone(),
            b.holdings.clone(),
        )
    {
        return Err(Error::Invalid);
    }
    Ok(())
}
/// `day` is the caller's actual local current day, never a historical target.
/// `captured_at` is an absolute observation instant, not an end-of-day assertion.
pub fn record_current(
    c: &Connection,
    day: Date,
    captured_at: Timestamp,
) -> Result<Snapshot, Error> {
    let tx = c.unchecked_transaction()?;
    let snapshot = record_in(&tx, day, captured_at)?;
    tx.commit()?;
    Ok(snapshot)
}

/// Serializes the daily check with insertion. Manual captures can still append
/// further revisions on the same day.
pub fn record_if_absent(c: &Connection, day: Date, captured_at: Timestamp) -> Result<bool, Error> {
    use navi_storage::sqlite::{Transaction as SqlTransaction, TransactionBehavior};
    let tx = SqlTransaction::new_unchecked(c, TransactionBehavior::Immediate)?;
    let exists: bool = tx.query_row(
        "SELECT EXISTS(SELECT 1 FROM finance_valuation_snapshots WHERE day=?1)",
        [day.to_string()],
        |r| r.get(0),
    )?;
    if !exists {
        record_in(&tx, day, captured_at)?;
    }
    tx.commit()?;
    Ok(!exists)
}

fn record_in(tx: &Connection, day: Date, captured_at: Timestamp) -> Result<Snapshot, Error> {
    let entries = crate::repository::transactions(tx)
        .map_err(|_| Error::Invalid)?
        .into_iter()
        .filter(|t| t.at.date() <= day)
        .collect::<Vec<_>>();
    let manual = holdings::store::load(tx).map_err(|_| Error::Invalid)?;
    let market = crate::market::load(tx).map_err(|_| Error::Invalid)?;
    let mut book = crate::market::valued_book_with_quotes(tx, manual.clone(), &market)
        .map_err(|_| Error::Invalid)?;
    book.trades.retain(|t| t.at.date() <= day);
    book.quotes.retain(|q| q.day <= day);
    let all_rates = currency::rates(tx).map_err(|_| Error::Invalid)?;
    let mut body = Body {
        day,
        captured_at,
        assets: 0,
        debt: 0,
        net: 0,
        missing: vec![],
        balances: vec![],
        holdings: vec![],
        rates: Currency::ALL
            .into_iter()
            .filter_map(|currency| currency::rate_in(&all_rates, currency, day))
            .map(|r| Rate {
                currency: r.currency,
                day: r.day,
                rate: r.rate,
                source: r.source,
            })
            .collect(),
        integrity: String::new(),
        ledger_fingerprint: fingerprint(&entries)?,
        entries,
        securities: book.securities.clone(),
        trades: book.trades.clone(),
        quotes: book.quotes.clone(),
    };
    let (a, d, n, m, b, h) = derive(&body)?;
    body.assets = a;
    body.debt = d;
    body.net = n;
    body.missing = m;
    body.balances = b;
    body.holdings = h;
    // Keep the exact conversion inputs that contributed to this observation.
    let mut native = journal::balances(body.entries.iter());
    for h in &body.holdings {
        let security = body
            .securities
            .iter()
            .find(|s| s.id == h.security)
            .ok_or(Error::Invalid)?;
        let value = native.entry(security.account.clone()).or_default();
        *value = value
            .checked_add(h.value.checked_sub(h.cost).ok_or(Error::Invalid)?)
            .ok_or(Error::Invalid)?;
    }
    let mut totals = BTreeMap::<Currency, (i128, i128)>::new();
    for (account, value) in native {
        let total = totals.entry(account.currency()).or_default();
        match account.kind() {
            crate::account::AccountKind::Assets => total.0 += i128::from(value),
            crate::account::AccountKind::Liabilities => total.1 -= i128::from(value),
            _ => {}
        }
    }
    body.rates.retain(|r| {
        totals
            .get(&r.currency)
            .is_some_and(|(a, d)| *a != 0 || *d != 0)
    });
    for h in &mut body.holdings {
        if let (Some(price), Some(d)) = (h.price, h.price_day) {
            let historical = crate::history::effective_bar(
                tx,
                &Quote {
                    security: h.security.clone(),
                    day: d,
                    price,
                },
            )
            .map_err(|_| Error::Invalid)?;
            h.source = if let Some(bar) = historical {
                bar.provider
            } else if manual
                .quotes
                .iter()
                .any(|q| q.security == h.security && q.day == d && q.price == price)
            {
                "manual".into()
            } else {
                market
                    .iter()
                    .find(|q| q.security == h.security && q.day() == d && q.price == price)
                    .map(|q| q.provider.clone())
                    .unwrap_or_else(|| "dated".into())
            };
        }
    }
    body.integrity = integrity(&body)?;
    validate_body(&body)?;
    tx.execute(
        "INSERT INTO finance_valuation_snapshots(day,captured_at,body) VALUES(?1,?2,?3)",
        params![
            day.to_string(),
            captured_at.to_string(),
            serde_json::to_string(&body)?
        ],
    )?;
    let id = tx.last_insert_rowid();
    Ok(Snapshot { id, body })
}
pub fn load(c: &Connection) -> Result<Vec<Snapshot>, Error> {
    let mut q =
        c.prepare("SELECT id,day,captured_at,body FROM finance_valuation_snapshots ORDER BY id")?;
    let mut rows = q.query([])?;
    let mut out = Vec::new();
    while let Some(r) = rows.next()? {
        out.push(decode_snapshot(r)?);
    }
    Ok(out)
}
fn decode_snapshot(r: &navi_storage::sqlite::Row<'_>) -> Result<Snapshot, Error> {
    let id: i64 = r.get(0)?;
    let day: String = r.get(1)?;
    let at: String = r.get(2)?;
    let b: String = r.get(3)?;
    let body: Body = serde_json::from_str(&b)?;
    validate_body(&body)?;
    if id <= 0 || body.day.to_string() != day || body.captured_at.to_string() != at {
        return Err(Error::Invalid);
    }
    Ok(Snapshot { id, body })
}
pub fn detail(c: &Connection, id: i64) -> Result<Snapshot, Error> {
    let mut q =
        c.prepare("SELECT id,day,captured_at,body FROM finance_valuation_snapshots WHERE id=?1")?;
    let mut rows = q.query([id])?;
    decode_snapshot(rows.next()?.ok_or(Error::Invalid)?)
}
#[derive(Clone, Debug)]
pub struct Summary {
    pub id: i64,
    pub captured_at: Timestamp,
    pub net: i64,
    pub missing: Vec<Currency>,
}
#[derive(Clone, Debug)]
pub struct Cursor {
    time: String,
    id: i64,
}
impl Summary {
    pub fn cursor(&self) -> Cursor {
        Cursor {
            time: self.captured_at.to_string().trim_end_matches('Z').into(),
            id: self.id,
        }
    }
}

/// Keyset pagination uses the same timestamp/id ordering for ties on every page.
pub fn summaries(
    c: &Connection,
    from: Date,
    to: Date,
    before: Option<&Cursor>,
    limit: u32,
) -> Result<Vec<Summary>, Error> {
    const SELECT: &str = "SELECT id,captured_at,json_extract(body,'$.net'),json_extract(body,'$.missing') FROM finance_valuation_snapshots WHERE day BETWEEN ?2 AND ?3";
    const ORDER: &str = " ORDER BY rtrim(captured_at,'Z') DESC,id DESC LIMIT ?1";
    let filter = if before.is_some() {
        " AND rtrim(captured_at,'Z') <= ?4 AND (rtrim(captured_at,'Z'),id) < (?4,?5)"
    } else {
        ""
    };
    let mut q = c.prepare(&format!("{SELECT}{filter}{ORDER}"))?;
    let (from, to) = (from.to_string(), to.to_string());
    let mut rows = match before {
        Some(cursor) => q.query(params![limit, from, to, cursor.time, cursor.id])?,
        None => q.query(params![limit, from, to])?,
    };
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        let at: String = row.get(1)?;
        result.push(Summary {
            id: row.get(0)?,
            captured_at: at.parse().map_err(|_| Error::Invalid)?,
            net: row.get(2)?,
            missing: serde_json::from_str(&row.get::<_, String>(3)?)?,
        });
    }
    Ok(result)
}

/// A later revision supersedes an earlier one even when the clock moved back.
pub fn recorded_trend(c: &Connection) -> Result<Vec<(Date, Option<i64>)>, Error> {
    let mut q = c.prepare("SELECT day,net FROM (
        SELECT day, CASE WHEN json_array_length(body,'$.missing')=0 THEN json_extract(body,'$.net') END AS net,
        row_number() OVER (PARTITION BY day ORDER BY id DESC) AS revision
        FROM finance_valuation_snapshots) WHERE revision=1 ORDER BY day")?;
    let mut rows = q.query([])?;
    let mut result = Vec::new();
    while let Some(row) = rows.next()? {
        result.push((
            row.get::<_, String>(0)?
                .parse()
                .map_err(|_| Error::Invalid)?,
            row.get(1)?,
        ));
    }
    Ok(result)
}
pub fn validate(c: &Connection) -> Result<(), Error> {
    let mut stmt = c.prepare("SELECT id,day,captured_at,body FROM finance_valuation_snapshots")?;
    let mut rows = stmt.query([])?;
    while let Some(row) = rows.next()? {
        decode_snapshot(row)?;
    }
    Ok(())
}
/// Latest observation per recorded day. Partial observations must not be charted as complete net worth.
pub fn daily_latest(snapshots: &[Snapshot]) -> Vec<Snapshot> {
    let mut days = BTreeMap::new();
    for s in snapshots {
        let entry = days.entry(s.body.day).or_insert_with(|| s.clone());
        if s.id > entry.id {
            *entry = s.clone();
        }
    }
    days.into_values().collect()
}
