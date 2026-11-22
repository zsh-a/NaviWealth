//! Validate a mixed draft, then commit every proposed record and consume the draft together.
use super::{clock, db, entry, finance, refresh_records, weights};
use crate::domain::{
    capture::{Draft, PROMPT_VERSION, Record},
    meal::{Day, Meal},
};
use navi_finance::{
    account::Account,
    catalog::{Catalog, SecurityBinding},
    currency::Currency,
    holdings::{self, Book, Quote, Security, Trade, store},
    journal, repository,
};
use rusqlite::{Connection, OptionalExtension, Transaction, params};
use std::collections::{HashMap, HashSet};

type BatchResult<T> = Result<T, Box<dyn std::error::Error>>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureIssue {
    UnknownSecurity,
    UnknownAccount,
    InvalidTrade,
    ExistingPrice,
    ExistingNote,
    InvalidDate,
    Overflow,
}

fn trade(draft: &Draft, index: usize) -> Option<Trade> {
    let Record::Trade {
        day,
        security,
        kind,
        quantity,
        price,
        amount,
        fee,
        cash,
        ..
    } = draft.records.get(index)?
    else {
        return None;
    };
    let entry = entry(draft, index, *day);
    Some(Trade {
        id: entry.id,
        security: security.clone(),
        at: entry.at,
        kind: *kind,
        quantity: *quantity,
        price: *price,
        amount: *amount,
        fee: *fee,
        cash: cash.clone(),
    })
}

/// An incoming ticker and the verified catalog can use different display
/// spellings for the same listing (e.g. 0700.HK and 00700).
fn canonical_ticker(currency: Currency, symbol: &str) -> Option<String> {
    use navi_finance::market::{canonical_symbol, hong_kong_code};
    match currency {
        Currency::HKD => hong_kong_code(symbol),
        Currency::CNY => {
            let short = symbol.split('.').next()?;
            let qualified = canonical_symbol(short)?;
            (symbol == qualified || symbol == short).then(|| short.to_owned())
        }
        Currency::USD => {
            let short = symbol.strip_suffix(".US").unwrap_or(symbol);
            (!short.is_empty()).then(|| short.to_owned())
        }
    }
}

/// Resolve the provider's field on device even if no owner inventory was
/// disclosed. A unique exact name, stable ID or bound ticker can refer to a
/// holding. Only a verified listing can propose a first purchase.
fn resolve_security(
    reference: &str,
    currency: Currency,
    book: &Book,
    catalog: Option<&Catalog>,
    bindings: &[SecurityBinding],
) -> Option<(Security, Option<SecurityBinding>)> {
    let reference = reference.trim();
    if let Some(id) = reference.strip_prefix("id:") {
        return book
            .securities
            .iter()
            .find(|s| s.id == id && s.currency() == currency)
            .cloned()
            .map(|s| (s, None));
    }
    let market = match currency {
        Currency::CNY => "cn_a",
        Currency::USD => "us_stock",
        Currency::HKD => "hk_stock",
    };
    let ticker = reference
        .strip_prefix(&format!("{market}:"))
        .unwrap_or(reference)
        .to_ascii_uppercase();
    let symbol = canonical_ticker(currency, &ticker);
    let mut matches = book.securities.iter().filter(|s| {
        s.currency() == currency
            && (s.id == reference
                || s.name.eq_ignore_ascii_case(reference)
                || bindings.iter().any(|b| {
                    b.security == s.id
                        && b.currency == currency.code()
                        && b.market == market
                        && symbol.is_some()
                        && canonical_ticker(currency, &b.symbol) == symbol
                }))
    });
    if let Some(s) = matches.next() {
        return matches.next().is_none().then(|| (s.clone(), None));
    }
    let symbol = symbol?;
    let rows = &catalog?.entries;
    let listing = |ticker: &str| {
        let pos = rows
            .binary_search_by(|e| (e.market.as_str(), e.symbol.as_str()).cmp(&(market, ticker)))
            .ok()?;
        rows.get(pos)
    };
    let row = listing(&ticker).or_else(|| listing(&symbol)).or_else(|| {
        if currency != Currency::HKD {
            return None;
        }
        let hk = symbol.strip_prefix('0').unwrap_or(&symbol);
        listing(&format!("{hk}.HK")).or_else(|| listing(&format!("{symbol}.HK")))
    })?;
    if row.currency != currency.code() || !row.supported() {
        return None;
    }
    // The market prefix plus escaped symbol is a stable, reversible identity
    // even for class shares such as BRK.B / BRK-B.
    let prefix = match currency {
        Currency::USD => "U",
        Currency::HKD => "H",
        Currency::CNY => "C",
    };
    let id = format!("{prefix}{}", symbol.replace('-', "-h").replace('.', "-p"));
    let sec = Security::new_in(&id, row.name(), currency).ok()?;
    if book
        .securities
        .iter()
        .any(|s| s.id == sec.id || s.name.to_lowercase() == sec.name.to_lowercase())
    {
        return None;
    }
    Some((sec, Some(row.binding(&id))))
}
fn local_security(
    reference: &str,
    currency: Currency,
    book: &Book,
) -> Option<(Security, Option<SecurityBinding>)> {
    resolve_security(
        reference,
        currency,
        book,
        crate::data::catalog::installed().as_deref(),
        &crate::data::catalog::bindings(),
    )
}
pub fn trade_security_name(reference: &str, currency: Currency) -> Option<String> {
    let (security, binding) = local_security(reference, currency, &finance::holdings_snapshot())?;
    Some(match binding {
        Some(listing) => format!("{} · {}", security.name, listing.symbol),
        None => security.name,
    })
}
pub(crate) fn saved_security_id(reference: &str, currency: Currency) -> Option<String> {
    resolve_security(
        reference,
        currency,
        &finance::holdings_snapshot(),
        None,
        &crate::data::catalog::bindings(),
    )
    .map(|(security, _)| security.id)
}

pub fn price_security_name(reference: &str, currency: Currency) -> Option<String> {
    resolve_security(
        reference,
        currency,
        &finance::holdings_snapshot(),
        None,
        &crate::data::catalog::bindings(),
    )
    .map(|(s, _)| s.name)
}
fn resolved_trade(draft: &Draft, i: usize, book: &Book) -> Option<(Security, Trade)> {
    let Record::Trade {
        security, currency, ..
    } = draft.records.get(i)?
    else {
        return None;
    };
    let (security, _) = local_security(security, *currency, book)?;
    let mut t = trade(draft, i)?;
    t.security.clone_from(&security.id);
    Some((security, t))
}

/// Money drafts may propose a new account; trades and balance checks refer to saved accounts.
pub(crate) fn accepts_account(record: &Record, destination: bool, account: &Account) -> bool {
    if !account.is_cash() || finance::archived_accounts().contains(account) {
        return false;
    }
    match record {
        Record::Money { draft, .. } => {
            let opposite = if destination {
                draft.account.as_ref()
            } else {
                draft.other_account.as_ref()
            };
            account.currency().code() == draft.currency && opposite != Some(account)
        }
        Record::Trade { currency, .. } => {
            !destination
                && account.can_settle(*currency, finance::account_purpose(account))
                && finance::accounts_snapshot().contains(account)
        }
        Record::Balance {
            account: target, ..
        } => {
            !destination
                && target.currency() == account.currency()
                && target.kind() == account.kind()
                && finance::accounts_snapshot().contains(account)
        }
        _ => false,
    }
}

pub fn record_issue(draft: &Draft, index: usize) -> Option<CaptureIssue> {
    use CaptureIssue::*;
    let record = draft.records.get(index)?;
    match record {
        Record::Money { draft, .. } => {
            let invalid = draft
                .account
                .as_ref()
                .is_some_and(|a| !accepts_account(record, false, a))
                || draft
                    .other_account
                    .as_ref()
                    .is_some_and(|a| !accepts_account(record, true, a));
            invalid.then_some(UnknownAccount)
        }
        Record::Trade {
            day,
            security,
            currency,
            kind,
            cash,
            ..
        } => {
            if *day > clock::today() {
                return Some(InvalidDate);
            }
            let book = finance::holdings_snapshot();
            let Some((s, _)) = local_security(security, *currency, &book) else {
                return Some(UnknownSecurity);
            };
            if *kind != holdings::Kind::Opening
                && !cash
                    .as_ref()
                    .is_some_and(|a| accepts_account(record, false, a))
            {
                return Some(UnknownAccount);
            }
            let mut trades = book.trades.clone();
            trades.extend(
                (0..draft.records.len())
                    .filter_map(|i| resolved_trade(draft, i, &book).map(|(_, t)| t))
                    .filter(|t| t.security == s.id),
            );
            holdings::replay(&s, &trades, jiff::civil::Date::MAX)
                .err()
                .map(|_| InvalidTrade)
        }
        Record::Balance {
            day,
            account,
            actual,
        } => {
            if *day > clock::today() {
                return Some(InvalidDate);
            }
            if !accepts_account(record, false, account) {
                return Some(UnknownAccount);
            }
            if book_balance(draft, index)
                .and_then(|b| actual.checked_sub(b))
                .is_none()
            {
                return Some(Overflow);
            }
            None
        }
        Record::Price {
            day,
            security,
            currency,
            ..
        } => {
            if *day > clock::today() {
                return Some(InvalidDate);
            }
            let Some((held, _)) = resolve_security(
                security,
                *currency,
                &finance::holdings_snapshot(),
                None,
                &crate::data::catalog::bindings(),
            ) else {
                return Some(UnknownSecurity);
            };
            db::with(|c| manual_price(c, &held.id, *day))
                .and_then(Result::ok)
                .flatten()
                .map(|_| ExistingPrice)
        }
        Record::Note { day, .. } => {
            (!crate::data::notes::between(*day, *day).is_empty()).then_some(ExistingNote)
        }
        _ => None,
    }
}

fn manual_price(c: &Connection, security: &str, day: Day) -> rusqlite::Result<Option<i64>> {
    c.query_row(
        "SELECT price FROM finance_quotes WHERE security=?1 AND day=?2",
        params![security, day.to_string()],
        |r| r.get(0),
    )
    .optional()
}

/// Uses the same journal constructors and holdings replay as confirmation. Apply
/// cash postings first, then reconcile observations in date order.
pub fn book_balance(draft: &Draft, index: usize) -> Option<i64> {
    let Record::Balance { day, account, .. } = draft.records.get(index)? else {
        return None;
    };
    let book = finance::holdings_snapshot();
    let mut entries = finance::transactions();
    let mut trades = book.trades.clone();
    let mut changed = HashMap::new();
    for (i, r) in draft.records.iter().enumerate() {
        match r {
            Record::Money { day, draft: money } => {
                entries.push(money.transaction(entry(draft, i, *day), day.0).ok()?)
            }
            Record::Trade { .. } => {
                let (s, t) = resolved_trade(draft, i, &book)?;
                changed.insert(s.id.clone(), s);
                trades.push(t);
            }
            _ => {}
        }
    }
    for s in changed.into_values() {
        let (_, replayed) = holdings::replay(&s, &trades, jiff::civil::Date::MAX).ok()?;
        let ids: HashSet<_> = replayed.iter().map(|t| t.id.as_str()).collect();
        entries.retain(|t| !ids.contains(t.id.as_str()));
        entries.extend(replayed);
    }
    let previous = draft
        .records
        .iter()
        .filter_map(|r| match r {
            Record::Balance {
                day: earlier,
                account: other,
                actual,
            } if other == account && earlier < day => Some((*earlier, *actual)),
            _ => None,
        })
        .max_by_key(|(day, _)| *day);
    let current = journal::balance_on(&entries, account, day.0);
    match previous {
        Some((earlier, actual)) => actual
            .checked_add(current.checked_sub(journal::balance_on(&entries, account, earlier.0))?),
        None => Some(current),
    }
}

#[derive(Clone)]
enum Written {
    Money(journal::Transaction),
    Meal(Meal),
    Weight {
        day: Day,
        previous: Option<weights::Removed>,
        revision: i64,
    },
    Trade(Trade),
    Balance(repository::BalanceCheck, Option<journal::Transaction>),
    Price(Quote, i64),
    Note {
        day: Day,
        text: String,
        updated: i64,
    },
}

/// The receipt holds only this batch's records. Undo expires with the UI action.
#[derive(Clone)]
pub struct CaptureUndo {
    written: Vec<Written>,
    created_accounts: Vec<Account>,
    created_securities: Vec<(Security, SecurityBinding)>,
    trade_history: HashMap<String, Vec<Trade>>,
    // A subsequent reconciliation depends on all earlier cash postings.
    balance_days: HashMap<Account, jiff::civil::Date>,
    balance_checks: Vec<repository::BalanceCheck>,
}

pub(super) fn commit(c: &Connection, draft: &Draft) -> Result<CaptureUndo, String> {
    let expected: HashMap<_, _> = draft
        .records
        .iter()
        .enumerate()
        .filter_map(|(i, r)| {
            matches!(r, Record::Balance { .. })
                .then(|| book_balance(draft, i).map(|v| (i, v)))
                .flatten()
        })
        .collect();
    commit_in(c, draft, &expected, clock::today()).map_err(|e| e.to_string())
}
fn commit_in(
    c: &Connection,
    draft: &Draft,
    expected: &HashMap<usize, i64>,
    today: Day,
) -> BatchResult<CaptureUndo> {
    let tx = c.unchecked_transaction()?;
    let prior_accounts = repository::accounts(&tx)?;
    let mut undo = CaptureUndo {
        written: Vec::new(),
        created_accounts: Vec::new(),
        created_securities: Vec::new(),
        trade_history: HashMap::new(),
        balance_days: HashMap::new(),
        balance_checks: Vec::new(),
    };
    let original = tx.query_row(
        "SELECT body FROM capture_drafts WHERE id=?1",
        [&draft.id],
        |r| r.get::<_, String>(0),
    )?;
    let mut persisted = serde_json::from_str::<Draft>(&original)?.migrated();
    // The composer can reopen with an unsent correction which the owner clears
    // before confirming. Only the validated result and evidence are consumed.
    if !persisted.transcript.is_empty() && draft.correction.trim().is_empty() {
        persisted.correction.clone_from(&draft.correction);
    }
    if persisted != *draft {
        return Err("draft changed; reopen it".into());
    }
    tx.execute("DELETE FROM capture_drafts WHERE id=?1", [&draft.id])?;
    // Baseline balances are compared against what was shown. Within the batch,
    // apply all cash-producing entries before dated balance reconciliations.
    let mut ordered: Vec<_> = draft.records.iter().enumerate().collect();
    ordered.sort_by_key(|(_, r)| match r {
        Record::Trade { day, .. } => (0, Some(*day)),
        Record::Balance { day, .. } => (2, Some(*day)),
        _ => (1, None),
    });
    for (i, record) in ordered {
        let id = super::record_id(&draft.id, i);
        match record {
            Record::Money { day, draft: money } => {
                let t = money.transaction(entry(draft, i, *day), day.0)?;
                vacant_id(&tx, &id)?;
                repository::save_in_transaction(&tx, &t)?;
                undo.written.push(Written::Money(t));
            }
            Record::Meal {
                day,
                slot,
                estimate,
                source_image,
            } => {
                let meal = Meal {
                    id,
                    day: *day,
                    logged_at_ms: draft.created_at_ms,
                    slot: *slot,
                    title: estimate.title.clone(),
                    foods: estimate.foods.clone(),
                    photo: draft.meal_photo(*source_image)?,
                    model: Some(draft.model.clone()),
                    prompt_version: Some(PROMPT_VERSION.into()),
                };
                navi_health::store::insert_meal(&tx, &meal)?;
                undo.written.push(Written::Meal(meal));
            }
            Record::Weight { day, kg } => {
                if !crate::domain::weight::valid_kg(*kg) {
                    return Err("invalid weight".into());
                }
                let previous = weights::snapshot_on(&tx, *day)?;
                let kg = crate::domain::weight::rounded(*kg);
                crate::data::scale::reconcile_weight_in_transaction(
                    &tx,
                    &day.to_string(),
                    Some(kg),
                )?;
                tx.execute("INSERT INTO weights(day,kg,logged_at_ms) VALUES(?1,?2,?3) ON CONFLICT(day) DO UPDATE SET kg=excluded.kg,logged_at_ms=excluded.logged_at_ms",params![day.to_string(),kg,draft.created_at_ms])?;
                undo.written.push(Written::Weight {
                    day: *day,
                    previous,
                    revision: weights::weight_revision(&tx, *day)?,
                });
            }
            Record::Trade {
                security, currency, ..
            } => {
                let book = store::load(&tx)?;
                let bindings = navi_finance::catalog::bindings(&tx)?;
                let (s, binding) = if let Some(existing) =
                    resolve_security(security, *currency, &book, None, &bindings)
                {
                    existing
                } else {
                    let installed =
                        crate::data::catalog::installed().ok_or("verified catalog unavailable")?;
                    let checksum: String = tx.query_row(
                        "SELECT checksum FROM securities_catalog WHERE singleton=1",
                        [],
                        |r| r.get(0),
                    )?;
                    if checksum != installed.header.checksum {
                        return Err("installed catalog changed".into());
                    }
                    resolve_security(security, *currency, &book, Some(&installed), &bindings)
                        .ok_or("unknown or ambiguous security")?
                };
                let mut t = trade(draft, i).ok_or("invalid trade")?;
                t.security.clone_from(&s.id);
                let saved = store::add_trade_in_transaction(
                    &tx,
                    binding.as_ref().map(|_| &s),
                    &t,
                    today.0,
                    binding.as_ref(),
                )?;
                if let Some(b) = binding {
                    undo.created_securities.push((s.clone(), b));
                }
                undo.trade_history.insert(
                    s.id.clone(),
                    saved
                        .book
                        .trades
                        .into_iter()
                        .filter(|t| t.security == s.id)
                        .collect(),
                );
                undo.written.push(Written::Trade(t));
            }
            Record::Balance {
                day,
                account,
                actual,
            } => {
                vacant_id(&tx, &id)?;
                let check = repository::BalanceCheck {
                    id,
                    account: account.clone(),
                    actual: *actual,
                    day: day.0,
                    checked_at: today.0.to_datetime(clock::zoned(clock::now_ms()).time()),
                };
                let adjustment = repository::confirm_balance_in_transaction(
                    &tx,
                    &check,
                    *expected.get(&i).ok_or("unknown book balance")?,
                )?;
                undo.written.push(Written::Balance(check, adjustment));
            }
            Record::Price {
                security,
                currency,
                price,
                day,
            } => {
                let (held, _) = resolve_security(
                    security,
                    *currency,
                    &store::load(&tx)?,
                    None,
                    &navi_finance::catalog::bindings(&tx)?,
                )
                .ok_or("unknown or ambiguous holding")?;
                if manual_price(&tx, &held.id, *day)?.is_some() {
                    return Err("existing manual price".into());
                }
                let q = Quote {
                    security: held.id.clone(),
                    day: day.0,
                    price: *price,
                };
                store::set_quote_in_transaction(&tx, &q, today.0)?;
                undo.written
                    .push(Written::Price(q, quote_revision(&tx, &held.id, *day)?));
            }
            Record::Note { day, text } => {
                if !crate::data::notes::valid(text) {
                    return Err("invalid review note".into());
                }
                tx.execute(
                    "INSERT INTO review_notes(day,text,updated_at_ms) VALUES(?1,?2,?3)",
                    params![day.to_string(), text, draft.created_at_ms],
                )?;
                undo.written.push(Written::Note {
                    day: *day,
                    text: text.clone(),
                    updated: draft.created_at_ms,
                });
            }
        }
    }
    let mut mark = |account: &Account, day: jiff::civil::Date| {
        undo.balance_days
            .entry(account.clone())
            .and_modify(|first| *first = (*first).min(day))
            .or_insert(day);
    };
    for item in &undo.written {
        match item {
            Written::Money(t) => {
                for p in &t.postings {
                    if p.account.is_cash() {
                        mark(&p.account, t.at.date())
                    }
                }
            }
            Written::Trade(t) => {
                if let Some(a) = &t.cash {
                    mark(a, t.at.date())
                }
            }
            Written::Balance(check, _) => mark(&check.account, check.day),
            _ => {}
        }
    }
    undo.balance_checks = dependent_checks(&tx, &undo.balance_days)?;
    undo.created_accounts = repository::accounts(&tx)?
        .into_iter()
        .filter(|a| !prior_accounts.contains(a))
        .collect();
    tx.commit()?;
    Ok(undo)
}

fn vacant_id(tx: &Transaction<'_>, id: &str) -> BatchResult<()> {
    let used:bool=tx.query_row("SELECT EXISTS(SELECT 1 FROM finance_transactions WHERE id=?1) OR EXISTS(SELECT 1 FROM finance_balance_checks WHERE id=?1)",[id],|r|r.get(0))?;
    if used {
        return Err("record identity already exists".into());
    }
    Ok(())
}
fn quote_revision(c: &Connection, security: &str, day: Day) -> rusqlite::Result<i64> {
    c.query_row("SELECT max(id) FROM finance_price_audit WHERE kind='manual_quote' AND item_key=?1 AND day=?2",params![security,day.to_string()],|r|r.get(0))
}
pub fn undo(receipt: &CaptureUndo) -> Result<(), String> {
    db::with(|c| undo_in(c, receipt))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    refresh_records();
    Ok(())
}
fn dependent_checks(
    c: &Connection,
    accounts: &HashMap<Account, jiff::civil::Date>,
) -> BatchResult<Vec<repository::BalanceCheck>> {
    if accounts.is_empty() {
        return Ok(Vec::new());
    }
    Ok(repository::balance_checks(c)?
        .into_iter()
        .filter(|b| accounts.get(&b.account).is_some_and(|d| b.day >= *d))
        .collect())
}
fn undo_in(c: &Connection, receipt: &CaptureUndo) -> BatchResult<()> {
    let tx = c.unchecked_transaction()?;
    if dependent_checks(&tx, &receipt.balance_days)? != receipt.balance_checks {
        return Err("a subsequent balance check depends on this batch".into());
    }
    if !receipt.trade_history.is_empty() {
        let book = store::load(&tx)?;
        for (id, trades) in &receipt.trade_history {
            if !book.trades.iter().filter(|t| &t.security == id).eq(trades) {
                return Err("trade history changed".into());
            }
        }
    }
    for written in receipt.written.iter().rev() {
        match written {
            Written::Money(t) => remove_entry(&tx, t)?,
            Written::Balance(check, adjustment) => {
                if !repository::balance_checks(&tx)?.contains(check) {
                    return Err("balance check changed".into());
                }
                if let Some(t) = adjustment {
                    remove_entry(&tx, t)?;
                }
                tx.execute(
                    "DELETE FROM finance_balance_checks WHERE id=?1",
                    [&check.id],
                )?;
            }
            Written::Trade(t) => {
                store::remove_trade_in_transaction(&tx, &t.id)?;
            }
            Written::Price(q, revision) => {
                if quote_revision(&tx, &q.security, Day(q.day))? != *revision {
                    return Err("price changed".into());
                }
                store::retract_quote(&tx, q)?;
            }
            Written::Note { day, text, updated } => {
                if tx.execute(
                    "DELETE FROM review_notes WHERE day=?1 AND text=?2 AND updated_at_ms=?3",
                    params![day.to_string(), text, updated],
                )? != 1
                {
                    return Err("review note changed".into());
                }
            }
            Written::Meal(meal) => {
                if tx.execute(
                    "DELETE FROM meals WHERE id=?1 AND day=?2 AND logged_at_ms=?3 AND body=?4",
                    params![
                        meal.id,
                        meal.day.to_string(),
                        meal.logged_at_ms,
                        serde_json::to_string(meal)?
                    ],
                )? != 1
                {
                    return Err("meal changed".into());
                }
            }
            Written::Weight {
                day,
                previous,
                revision,
            } => {
                if weights::weight_revision(&tx, *day)? != *revision {
                    return Err("weight changed".into());
                }
                crate::data::scale::reconcile_weight_in_transaction(&tx, &day.to_string(), None)?;
                if tx.execute("DELETE FROM weights WHERE day=?1", [day.to_string()])? != 1 {
                    return Err("weight changed".into());
                }
                if let Some(old) = previous {
                    weights::insert_snapshot(&tx, old)?;
                }
            }
        }
    }
    for (s, binding) in &receipt.created_securities {
        // Price revisions identify their instrument by this stable holding ID.
        // Even a subsequently retracted quote must keep its audit provenance.
        let has_price_audit:bool=tx.query_row("SELECT EXISTS(SELECT 1 FROM finance_price_audit WHERE kind!='fx_rate' AND item_key=?1)",[&s.id],|r|r.get(0))?;
        if has_price_audit
            || !store::load(&tx)?.securities.contains(s)
            || !navi_finance::catalog::bindings(&tx)?.contains(binding)
        {
            return Err("holding changed".into());
        }
        tx.execute(
            "DELETE FROM finance_security_bindings WHERE security=?1",
            [&s.id],
        )?;
        tx.execute("DELETE FROM finance_securities WHERE id=?1", [&s.id])?;
    }
    for account in &receipt.created_accounts {
        tx.execute(
            "DELETE FROM finance_accounts WHERE name=?1",
            [account.as_str()],
        )?;
    }
    tx.commit()?;
    Ok(())
}
fn remove_entry(tx: &Transaction<'_>, entry: &journal::Transaction) -> BatchResult<()> {
    if !repository::transactions(tx)?.contains(entry) {
        return Err("ledger entry changed".into());
    }
    tx.execute(
        "DELETE FROM finance_postings WHERE transaction_id=?1",
        [&entry.id],
    )?;
    tx.execute("DELETE FROM finance_transactions WHERE id=?1", [&entry.id])?;
    Ok(())
}

#[cfg(test)]
mod tests;
