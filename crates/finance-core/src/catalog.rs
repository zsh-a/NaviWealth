//! Verified public listing data and explicit links to the owner's stable securities.
use lifeos_core::sqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{collections::BTreeSet, io::Read};

pub const SCHEMA: &str = "CREATE TABLE finance_security_bindings(security TEXT PRIMARY KEY NOT NULL REFERENCES finance_securities(id),market TEXT NOT NULL,symbol TEXT NOT NULL,currency TEXT NOT NULL); CREATE TABLE securities_catalog(singleton INTEGER PRIMARY KEY CHECK(singleton=1),version TEXT NOT NULL,checksum TEXT NOT NULL,body TEXT NOT NULL);";
pub const BINDING_TABLES: &[&str] = &["finance_security_bindings"];
pub const MAX_BYTES: usize = 32 * 1024 * 1024;
pub const MAX_DOWNLOAD: usize = 8 * 1024 * 1024;
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("invalid securities catalog or binding")]
    Invalid,
    #[error("unsupported market, currency or instrument")]
    Unsupported,
    #[error(transparent)]
    Sql(#[from] lifeos_core::sqlite::Error),
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SecurityBinding {
    pub security: String,
    pub market: String,
    pub symbol: String,
    pub currency: String,
}
impl SecurityBinding {
    pub fn validate(&self) -> Result<(), Error> {
        if self.security.is_empty()
            || self.security.len() > 30
            || !self
                .security
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-')
        {
            return Err(Error::Invalid);
        }
        let supported = match (self.market.as_str(), self.currency.as_str()) {
            ("cn_a", "CNY") => crate::market::canonical_symbol(&self.symbol).is_some(),
            ("hk_stock", "HKD") => crate::market::hong_kong_code(&self.symbol).is_some(),
            ("us_stock", "USD") => {
                self.symbol.len() <= 15
                    && self
                        .symbol
                        .bytes()
                        .next()
                        .is_some_and(|b| b.is_ascii_uppercase())
                    && self.symbol.bytes().all(|b| {
                        b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'.' || b == b'-'
                    })
            }
            _ => false,
        };
        if !supported {
            return Err(Error::Unsupported);
        }
        Ok(())
    }
}
pub fn bindings(c: &Connection) -> Result<Vec<SecurityBinding>, Error> {
    let mut q = c.prepare(
        "SELECT security,market,symbol,currency FROM finance_security_bindings ORDER BY security",
    )?;
    let rows = q.query_map([], |r| {
        Ok(SecurityBinding {
            security: r.get(0)?,
            market: r.get(1)?,
            symbol: r.get(2)?,
            currency: r.get(3)?,
        })
    })?;
    let mut out = Vec::new();
    for row in rows {
        let b = row?;
        b.validate()?;
        let account: String = c.query_row(
            "SELECT account FROM finance_securities WHERE id=?1",
            [&b.security],
            |r| r.get(0),
        )?;
        let account = crate::account::Account::parse(&account).map_err(|_| Error::Invalid)?;
        if account.currency().code() != b.currency {
            return Err(Error::Unsupported);
        }
        out.push(b)
    }
    Ok(out)
}
pub fn bind(c: &Connection, b: &SecurityBinding) -> Result<(), Error> {
    b.validate()?;
    let exists: bool = c.query_row(
        "SELECT EXISTS(SELECT 1 FROM finance_securities WHERE id=?1)",
        [&b.security],
        |r| r.get(0),
    )?;
    if !exists {
        return Err(Error::Invalid);
    }
    let book = crate::holdings::store::load(c).map_err(|_| Error::Invalid)?;
    let security = book
        .securities
        .iter()
        .find(|s| s.id == b.security)
        .ok_or(Error::Invalid)?;
    if security.currency().code() != b.currency {
        return Err(Error::Unsupported);
    }
    c.execute_batch("SAVEPOINT catalog_bind")?;
    let result = (|| -> Result<(), Error> {
        let old = bindings(c)?
            .into_iter()
            .find(|old| old.security == b.security);
        let has_quotes: bool = c.query_row("SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='finance_market_quotes')", [], |r| r.get(0))?;
        if old.as_ref() != Some(b) && has_quotes {
            for q in crate::market::load(c)
                .map_err(|_| Error::Invalid)?
                .into_iter()
                .filter(|q| q.security == b.security)
            {
                crate::history::record(
                    c,
                    "market_quote_unbound",
                    &b.security,
                    &q.day().to_string(),
                    &serde_json::json!({"binding":old,"quote":q}),
                )?;
            }
            c.execute(
                "DELETE FROM finance_market_quotes WHERE security=?1",
                [&b.security],
            )?;
        }
        c.execute("INSERT INTO finance_security_bindings(security,market,symbol,currency) VALUES(?1,?2,?3,?4) ON CONFLICT(security) DO UPDATE SET market=excluded.market,symbol=excluded.symbol,currency=excluded.currency",params![b.security,b.market,b.symbol,b.currency])?;
        Ok(())
    })();
    if let Err(error) = result {
        c.execute_batch("ROLLBACK TO catalog_bind; RELEASE catalog_bind")?;
        return Err(error);
    }
    c.execute_batch("RELEASE catalog_bind")?;
    Ok(())
}
pub fn validate(c: &Connection) -> Result<(), Error> {
    for b in bindings(c)? {
        let exists: bool = c.query_row(
            "SELECT EXISTS(SELECT 1 FROM finance_securities WHERE id=?1)",
            [b.security],
            |r| r.get(0),
        )?;
        if !exists {
            return Err(Error::Invalid);
        }
    }
    Ok(())
}
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Entry {
    #[serde(rename = "s")]
    pub symbol: String,
    #[serde(rename = "m")]
    pub market: String,
    #[serde(rename = "t")]
    pub kind: String,
    #[serde(rename = "c")]
    pub currency: String,
    #[serde(rename = "nc", default)]
    pub chinese: String,
    #[serde(rename = "ne", default)]
    pub english: String,
    #[serde(rename = "p", default)]
    pub pinyin: String,
    #[serde(rename = "pi", default)]
    pub initials: String,
    #[serde(rename = "a", default)]
    pub aliases: String,
}
impl Entry {
    pub fn name(&self) -> &str {
        if self.chinese.is_empty() {
            if self.english.is_empty() {
                &self.symbol
            } else {
                &self.english
            }
        } else {
            &self.chinese
        }
    }
    pub fn supported(&self) -> bool {
        matches!(self.kind.as_str(), "stock" | "etf")
            && self.binding("catalog-check").validate().is_ok()
    }
    pub fn binding(&self, security: &str) -> SecurityBinding {
        SecurityBinding {
            security: security.into(),
            market: self.market.clone(),
            symbol: self.symbol.clone(),
            currency: self.currency.clone(),
        }
    }
}
#[derive(Debug, Clone, Deserialize)]
pub struct Header {
    pub version: String,
    pub checksum: String,
    pub count: usize,
}
#[derive(Debug, Clone)]
pub struct Catalog {
    pub header: Header,
    pub entries: Vec<Entry>,
}
fn version(v: &str) -> Option<u32> {
    let date = v.strip_prefix("v1.")?;
    if date.len() != 8 || !date.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let year = date[..4].parse().ok()?;
    let month = date[4..6].parse().ok()?;
    let day = date[6..].parse().ok()?;
    jiff::civil::Date::new(year, month, day).ok()?;
    date.parse().ok()
}
fn valid_text(v: &str) -> bool {
    v.len() <= 512 && !v.chars().any(char::is_control)
}
pub fn parse(raw: &str) -> Result<Catalog, Error> {
    if raw.len() > MAX_BYTES {
        return Err(Error::Invalid);
    }
    let mut lines = raw.lines();
    let header: Header =
        serde_json::from_str(lines.next().ok_or(Error::Invalid)?).map_err(|_| Error::Invalid)?;
    if version(&header.version).is_none() || header.count == 0 || header.count > 100_000 {
        return Err(Error::Invalid);
    }
    let mut entries = Vec::new();
    let mut seen = BTreeSet::new();
    let mut previous = None;
    let mut hash = 0xcbf29ce484222325u64;
    for line in lines {
        if line.is_empty() {
            return Err(Error::Invalid);
        }
        let object: serde_json::Value = serde_json::from_str(line).map_err(|_| Error::Invalid)?;
        let entry: Entry = serde_json::from_value(object.clone()).map_err(|_| Error::Invalid)?;
        if !["cn_a", "hk_stock", "us_stock", "crypto", "fx", "unknown"]
            .contains(&entry.market.as_str())
            || !["stock", "etf", "mutualFund", "bond", "crypto"].contains(&entry.kind.as_str())
            || entry.symbol.is_empty()
            || entry.currency.is_empty()
            || !object
                .as_object()
                .ok_or(Error::Invalid)?
                .values()
                .all(|v| v.as_str().is_some_and(valid_text))
        {
            return Err(Error::Invalid);
        }
        let key = (entry.market.clone(), entry.symbol.clone());
        if previous.as_ref().is_some_and(|p| p >= &key)
            || !seen.insert((entry.market.clone(), entry.symbol.to_lowercase()))
        {
            return Err(Error::Invalid);
        }
        previous = Some(key);
        // Python's sorted JSON encoding uses a space after commas and colons.
        let map = object.as_object().ok_or(Error::Invalid)?;
        let mut fields = map.iter().collect::<Vec<_>>();
        fields.sort_by_key(|(k, _)| *k);
        let canonical = format!(
            "{{{}}}",
            fields
                .into_iter()
                .map(|(k, v)| format!(
                    "{}: {}",
                    serde_json::to_string(k).unwrap(),
                    serde_json::to_string(v).unwrap()
                ))
                .collect::<Vec<_>>()
                .join(", ")
        );
        if !entries.is_empty() {
            hash = (hash ^ 10).wrapping_mul(0x100000001b3)
        }
        for b in canonical.bytes() {
            hash = (hash ^ u64::from(b)).wrapping_mul(0x100000001b3)
        }
        entries.push(entry);
    }
    if entries.len() != header.count || format!("{hash:016x}") != header.checksum {
        return Err(Error::Invalid);
    }
    Ok(Catalog { header, entries })
}
impl Catalog {
    pub fn search(&self, query: &str, limit: usize) -> Vec<Entry> {
        let q = query.trim().to_lowercase();
        if q.is_empty() || q.len() > 128 {
            return Vec::new();
        }
        let mut found: Vec<_> = self
            .entries
            .iter()
            .filter(|e| {
                [
                    &e.symbol,
                    &e.chinese,
                    &e.english,
                    &e.pinyin,
                    &e.initials,
                    &e.aliases,
                ]
                .iter()
                .any(|v| v.to_lowercase().contains(&q))
            })
            .collect();
        found.sort_by_key(|e| {
            (
                e.symbol.to_lowercase() != q,
                !e.symbol.to_lowercase().starts_with(&q),
                e.market.clone(),
                e.symbol.clone(),
            )
        });
        found.into_iter().take(limit.min(50)).cloned().collect()
    }
}
pub fn install(c: &Connection, raw: &str) -> Result<Catalog, Error> {
    let catalog = parse(raw)?;
    let tx = c.unchecked_transaction()?;
    tx.execute("INSERT INTO securities_catalog VALUES(1,?1,?2,?3) ON CONFLICT(singleton) DO UPDATE SET version=excluded.version,checksum=excluded.checksum,body=excluded.body",params![catalog.header.version,catalog.header.checksum,raw])?;
    tx.commit()?;
    Ok(catalog)
}
pub fn current(c: &Connection) -> Result<Option<Catalog>, Error> {
    use lifeos_core::sqlite::OptionalExtension;
    let raw: Option<String> = c
        .query_row(
            "SELECT body FROM securities_catalog WHERE singleton=1",
            [],
            |r| r.get(0),
        )
        .optional()?;
    raw.map(|v| parse(&v)).transpose()
}
#[derive(Debug, Deserialize)]
pub struct Manifest {
    pub schema: u32,
    pub version: String,
    pub checksum: String,
    pub count: usize,
    pub sha256: String,
    pub asset: String,
    pub gzip_sha256: String,
    pub gzip_size: usize,
}
impl Manifest {
    pub fn parse(raw: &str) -> Result<Self, Error> {
        if raw.len() > 16384 {
            return Err(Error::Invalid);
        }
        let m: Self = serde_json::from_str(raw).map_err(|_| Error::Invalid)?;
        let sha = |v: &str| {
            v.len() == 64
                && v.bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        };
        if m.schema != 1
            || version(&m.version).is_none()
            || m.count == 0
            || m.count > 100_000
            || !sha(&m.sha256)
            || !sha(&m.gzip_sha256)
            || m.gzip_size == 0
            || m.gzip_size > MAX_DOWNLOAD
            || m.asset.is_empty()
            || m.asset == "."
            || m.asset == ".."
            || !m
                .asset
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
        {
            return Err(Error::Invalid);
        }
        Ok(m)
    }
    pub fn newer(&self, h: &Header) -> bool {
        version(&self.version) > version(&h.version)
            || (self.version == h.version && self.checksum != h.checksum)
    }
    pub fn verify(&self, gzip: &[u8]) -> Result<String, Error> {
        if gzip.len() != self.gzip_size || format!("{:x}", Sha256::digest(gzip)) != self.gzip_sha256
        {
            return Err(Error::Invalid);
        }
        let mut bytes = Vec::new();
        flate2::read::GzDecoder::new(gzip)
            .take((MAX_BYTES + 1) as u64)
            .read_to_end(&mut bytes)
            .map_err(|_| Error::Invalid)?;
        if bytes.len() > MAX_BYTES || format!("{:x}", Sha256::digest(&bytes)) != self.sha256 {
            return Err(Error::Invalid);
        }
        let raw = String::from_utf8(bytes).map_err(|_| Error::Invalid)?;
        let c = parse(&raw)?;
        if c.header.version != self.version
            || c.header.count != self.count
            || c.header.checksum != self.checksum
        {
            return Err(Error::Invalid);
        }
        Ok(raw)
    }
}
