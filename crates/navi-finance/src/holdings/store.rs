//! Atomic portfolio mutations. Trade history and cash/cost journal entries
//! either change together or remain untouched.
use super::*;
use crate::repository;
use navi_storage::sqlite::{Connection, Transaction as SqlTransaction, params};

pub const SCHEMA:&str="
CREATE TABLE finance_securities(id TEXT PRIMARY KEY NOT NULL,name TEXT NOT NULL,name_key TEXT NOT NULL UNIQUE,account TEXT NOT NULL UNIQUE REFERENCES finance_accounts(name));
CREATE TABLE finance_trades(id TEXT PRIMARY KEY NOT NULL,security TEXT NOT NULL REFERENCES finance_securities(id),at TEXT NOT NULL,kind TEXT NOT NULL,
quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer'),price INTEGER NOT NULL CHECK(typeof(price)='integer'),amount INTEGER NOT NULL CHECK(typeof(amount)='integer'),fee INTEGER NOT NULL CHECK(typeof(fee)='integer'),cash TEXT REFERENCES finance_accounts(name));
CREATE INDEX finance_trades_by_security ON finance_trades(security,at,id);
CREATE TABLE finance_quotes(security TEXT NOT NULL REFERENCES finance_securities(id),day TEXT NOT NULL,price INTEGER NOT NULL CHECK(typeof(price)='integer'),PRIMARY KEY(security,day));";

/// The mirror is read before commit, so refresh cannot turn a committed
/// operation into an apparent failure that invites a duplicate retry.
pub struct Saved {
    pub book: Book,
    pub entries: Vec<Transaction>,
    pub accounts: Vec<Account>,
}
pub fn load(c: &Connection) -> Result<Book, Error> {
    let mut book = Book::default();
    let mut query =
        c.prepare("SELECT id,name,name_key,account FROM finance_securities ORDER BY name_key")?;
    for row in query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
        ))
    })? {
        let (id, name, key, account) = row?;
        let parsed = Account::parse(&account).map_err(|_| Error::Invalid)?;
        let security = Security::new_in(&id, &name, parsed.currency())?;
        if key != name.to_lowercase() || security.account.as_str() != account {
            return Err(Error::Invalid);
        }
        book.securities.push(security);
    }
    let mut query=c.prepare("SELECT id,security,at,kind,quantity,price,amount,fee,cash FROM finance_trades ORDER BY at,id")?;
    for row in query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
            r.get(4)?,
            r.get(5)?,
            r.get(6)?,
            r.get(7)?,
            r.get::<_, Option<String>>(8)?,
        ))
    })? {
        let (id, security, at, kind, quantity, price, amount, fee, cash) = row?;
        let kind = serde_json::from_str(&kind).map_err(|_| Error::Invalid)?;
        let at = at.parse().map_err(|_| Error::Invalid)?;
        let cash = cash
            .map(|s| Account::parse(&s).map_err(|_| Error::Invalid))
            .transpose()?;
        if !book.securities.iter().any(|s| s.id == security) {
            return Err(Error::Missing);
        }
        book.trades.push(Trade {
            id,
            security,
            at,
            kind,
            quantity,
            price,
            amount,
            fee,
            cash,
        });
    }
    book.quotes = manual_quotes(c, &book.securities)?;
    Ok(book)
}
pub fn manual_quotes(c: &Connection, securities: &[Security]) -> Result<Vec<Quote>, Error> {
    let mut quotes = Vec::new();
    let mut query = c.prepare("SELECT security,day,price FROM finance_quotes ORDER BY day")?;
    for row in query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, i64>(2)?,
        ))
    })? {
        let (security, day, price) = row?;
        if price < 0 || !securities.iter().any(|s| s.id == security) {
            return Err(Error::Invalid);
        }
        quotes.push(Quote {
            security,
            day: day.parse().map_err(|_| Error::Invalid)?,
            price,
        });
    }
    Ok(quotes)
}

pub fn validate(c: &Connection) -> Result<(), Error> {
    let book = load(c)?;
    let accounts = repository::accounts(c)?;
    let entries = repository::transactions(c)?;
    book.validate_values()?;
    if accounts
        .iter()
        .any(|a| a.is_holding() && !book.securities.iter().any(|s| s.account == *a))
    {
        return Err(Error::Invalid);
    }
    let mut generated = Vec::new();
    for s in &book.securities {
        if !accounts.contains(&s.account) {
            return Err(Error::Missing);
        }
        generated.extend(replay(s, &book.trades, Date::MAX)?.1);
        book.position(s, Date::MAX)?;
    }
    for t in &book.trades {
        if t.cash.as_ref().is_some_and(|a| !accounts.contains(a)) {
            return Err(Error::Cash);
        }
    }
    for entry in &entries {
        if matches!(entry.source, Source::Investment { .. }) {
            if !generated.contains(entry) {
                return Err(Error::Invalid);
            }
        } else if entry.postings.iter().any(|p| p.account.is_holding()) {
            return Err(Error::Invalid);
        }
    }
    if generated.iter().any(|g| !entries.contains(g)) {
        return Err(Error::Invalid);
    }
    Ok(())
}

fn saved(tx: &SqlTransaction<'_>) -> Result<Saved, Error> {
    let book = load(tx)?;
    book.validate_values()?;
    // Retained network marks participate in valuation after every trade,
    // including backdated changes. Reject overflow before committing either
    // the trade or its cash postings. Older standalone stores lack this table.
    let has_market: bool = tx.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='finance_market_quotes')",
        [], |r| r.get(0),
    )?;
    if has_market {
        crate::market::valued_book(tx, book.clone())
            .map_err(|_| Error::Invalid)?
            .validate_values()?;
    }
    Ok(Saved {
        book,
        entries: repository::transactions(tx)?,
        accounts: repository::accounts(tx)?,
    })
}
fn rebuild(tx: &SqlTransaction<'_>, security: &Security, book: &Book) -> Result<(), Error> {
    let (_, entries) = replay(security, &book.trades, Date::MAX)?;
    // Foreign sources are never overwritten by a generated trade id.
    for entry in &entries {
        let existing: Option<String> = tx
            .query_row(
                "SELECT source FROM finance_transactions WHERE id=?1",
                [&entry.id],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(source) = existing {
            let source: Source = serde_json::from_str(&source).map_err(|_| Error::Invalid)?;
            if source != entry.source {
                return Err(Error::Duplicate);
            }
        }
    }
    for entry in entries {
        repository::save_investment(tx, &entry)?;
    }
    Ok(())
}
use navi_storage::sqlite::OptionalExtension;

pub fn add_trade(
    c: &Connection,
    new: Option<&Security>,
    trade: &Trade,
    today: Date,
) -> Result<Saved, Error> {
    add_trade_bound(c, new, trade, today, None)
}

pub fn add_trade_bound(
    c: &Connection,
    new: Option<&Security>,
    trade: &Trade,
    today: Date,
    binding: Option<&crate::catalog::SecurityBinding>,
) -> Result<Saved, Error> {
    let tx = c.unchecked_transaction()?;
    let result = add_trade_in_transaction(&tx, new, trade, today, binding)?;
    tx.commit()?;
    Ok(result)
}

/// Joins a host-owned mixed-record confirmation transaction.
pub fn add_trade_in_transaction(
    tx: &SqlTransaction<'_>,
    new: Option<&Security>,
    trade: &Trade,
    today: Date,
    binding: Option<&crate::catalog::SecurityBinding>,
) -> Result<Saved, Error> {
    if trade.at.date() > today {
        return Err(Error::Invalid);
    }
    if let Some(s) = new {
        if Security::new_in(&s.id, &s.name, s.currency())? != *s || s.id != trade.security {
            return Err(Error::Invalid);
        }
        let book = load(tx)?;
        if book
            .securities
            .iter()
            .any(|old| old.id == s.id || old.name.to_lowercase() == s.name.to_lowercase())
        {
            return Err(Error::Duplicate);
        }
        if repository::accounts(tx)?.contains(&s.account) {
            return Err(Error::Duplicate);
        }
        tx.execute(
            "INSERT INTO finance_accounts(name) VALUES (?1)",
            [s.account.as_str()],
        )?;
        tx.execute(
            "INSERT INTO finance_securities(id,name,name_key,account) VALUES(?1,?2,?3,?4)",
            params![s.id, s.name, s.name.to_lowercase(), s.account.as_str()],
        )?;
    }
    if let Some(cash) = &trade.cash
        && (!repository::accounts(tx)?.contains(cash)
            || repository::archived_accounts(tx)?.contains(cash)
            || repository::account_purposes(tx)?
                .get(cash)
                .is_some_and(|p| !p.usable_for_settlement()))
    {
        return Err(Error::Cash);
    }
    tx.execute("INSERT INTO finance_trades(id,security,at,kind,quantity,price,amount,fee,cash) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)",params![trade.id,trade.security,trade.at.to_string(),serde_json::to_string(&trade.kind).map_err(|_|Error::Invalid)?,trade.quantity,trade.price,trade.amount,trade.fee,trade.cash.as_ref().map(Account::as_str)])?;
    let book = load(tx)?;
    let s = book
        .securities
        .iter()
        .find(|s| s.id == trade.security)
        .ok_or(Error::Missing)?;
    rebuild(tx, s, &book)?;
    if let Some(binding) = binding {
        if binding.security != trade.security {
            return Err(Error::Invalid);
        }
        crate::catalog::bind(tx, binding).map_err(|e| match e {
            crate::catalog::Error::Sql(e) => Error::Sql(e),
            _ => Error::Invalid,
        })?;
    }
    saved(tx)
}

pub fn remove_trade(c: &Connection, id: &str) -> Result<Saved, Error> {
    let tx = c.unchecked_transaction()?;
    let result = remove_trade_in_transaction(&tx, id)?;
    tx.commit()?;
    Ok(result)
}
pub fn remove_trade_in_transaction(tx: &SqlTransaction<'_>, id: &str) -> Result<Saved, Error> {
    let before = load(tx)?;
    let trade = before
        .trades
        .iter()
        .find(|t| t.id == id)
        .ok_or(Error::Missing)?;
    tx.execute("DELETE FROM finance_trades WHERE id=?1", [id])?;
    tx.execute(
        "DELETE FROM finance_transactions WHERE id=?1",
        [format!("trade:{id}")],
    )?;
    let book = load(tx)?;
    let s = book
        .securities
        .iter()
        .find(|s| s.id == trade.security)
        .ok_or(Error::Missing)?;
    rebuild(tx, s, &book)?;
    saved(tx)
}

pub fn set_quote(c: &Connection, quote: &Quote, today: Date) -> Result<Saved, Error> {
    let tx = c.unchecked_transaction()?;
    let result = set_quote_in_transaction(&tx, quote, today)?;
    tx.commit()?;
    Ok(result)
}

/// A manual mark and its audit revision share the host's confirmation transaction.
pub fn set_quote_in_transaction(
    tx: &SqlTransaction<'_>,
    quote: &Quote,
    today: Date,
) -> Result<Saved, Error> {
    if quote.price < 0 || quote.day > today {
        return Err(Error::Invalid);
    }
    if !load(tx)?.securities.iter().any(|s| s.id == quote.security) {
        return Err(Error::Missing);
    }
    tx.execute("INSERT INTO finance_quotes(security,day,price) VALUES(?1,?2,?3) ON CONFLICT(security,day) DO UPDATE SET price=excluded.price",params![quote.security,quote.day.to_string(),quote.price])?;
    crate::history::record(
        tx,
        "manual_quote",
        &quote.security,
        &quote.day.to_string(),
        &serde_json::json!({"security":quote.security,"day":quote.day.to_string(),"price":quote.price}),
    )?;
    let result = saved(tx)?;
    // Validate mark-to-market arithmetic before committing a price.
    result.book.overview(&result.entries, today)?;
    Ok(result)
}

/// Withdraw the confirmed manual observation, retaining an explicit price audit entry.
pub fn retract_quote(tx: &SqlTransaction<'_>, quote: &Quote) -> Result<(), Error> {
    if tx.execute(
        "DELETE FROM finance_quotes WHERE security=?1 AND day=?2 AND price=?3",
        params![quote.security, quote.day.to_string(), quote.price],
    )? != 1
    {
        return Err(Error::Missing);
    }
    crate::history::record(
        tx,
        "manual_quote",
        &quote.security,
        &quote.day.to_string(),
        &serde_json::json!({"security":quote.security,"day":quote.day.to_string(),"price":quote.price,"retracted":true}),
    )?;
    saved(tx)?;
    Ok(())
}
