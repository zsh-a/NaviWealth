//! Thin reactive adapter over finance-core's confirmed ledger repository.
//! SQLite commits before a signal changes. Failure never looks like a save.

use finance_core::{account::Account, journal::Transaction, repository};
use nsh_core::prelude::*;

use super::db;

#[derive(Clone, Default, PartialEq)]
struct Ledger {
    transactions: Vec<Transaction>,
    accounts: Vec<Account>,
    checks: Vec<repository::BalanceCheck>,
    holdings: finance_core::holdings::Book,
    rates: Vec<finance_core::currency::FxRate>,
}

fn state() -> Signal<Ledger> {
    global::<Ledger>()
}

pub fn load() -> Result<(), String> {
    let loaded = db::with(|c| -> Result<Ledger, repository::Error> {
        // Validate first: opening a damaged journal must not mutate it.
        repository::validate(c)?;
        repository::ensure_defaults(c)?;
        Ok(Ledger {
            rates: finance_core::currency::rates(c)
                .map_err(|_| repository::Error::Invalid("exchange rates"))?,
            transactions: repository::transactions(c)?,
            accounts: repository::accounts(c)?,
            checks: repository::balance_checks(c)?,
            holdings: finance_core::market::valued_book(
                c,
                finance_core::holdings::store::load(c)
                    .map_err(|_| repository::Error::Invalid("holdings"))?,
            )
            .map_err(|_| repository::Error::Invalid("market quotes"))?,
        })
    })
    .ok_or("the database is not open")?
    .map_err(|error| {
        log::error!("finance: cannot load ledger: {error}");
        error.to_string()
    })?;
    state().set(loaded);
    Ok(())
}

pub fn transactions() -> Vec<Transaction> {
    state().with(|s| s.transactions.clone())
}
pub fn accounts() -> Vec<Account> {
    state().with(|s| s.accounts.clone())
}

pub fn holdings() -> finance_core::holdings::Book {
    state().with(|s| s.holdings.clone())
}
pub fn rates() -> Vec<finance_core::currency::FxRate> {
    state().with(|s| s.rates.clone())
}
pub fn save_rate(rate: finance_core::currency::FxRate) -> Result<(), String> {
    db::with(|c| finance_core::currency::save_rate(c, &rate))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    let rates = db::with(finance_core::currency::rates)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    state().update(|s| s.rates = rates);
    Ok(())
}
fn reflect(saved: finance_core::holdings::store::Saved) {
    let book = db::with(|c| finance_core::market::valued_book(c, saved.book.clone()))
        .and_then(Result::ok)
        .unwrap_or(saved.book);
    state().update(|s| {
        s.holdings = book;
        s.transactions = saved.entries;
        s.accounts = saved.accounts;
    });
}
pub fn add_trade(
    security: Option<&finance_core::holdings::Security>,
    trade: &finance_core::holdings::Trade,
) -> Result<(), finance_core::holdings::Error> {
    add_trade_bound(security, trade, None)
}
pub fn add_trade_bound(
    security: Option<&finance_core::holdings::Security>,
    trade: &finance_core::holdings::Trade,
    binding: Option<&finance_core::catalog::SecurityBinding>,
) -> Result<(), finance_core::holdings::Error> {
    let saved = db::with(|c| {
        finance_core::holdings::store::add_trade_bound(
            c,
            security,
            trade,
            super::clock::today().0,
            binding,
        )
    })
    .ok_or(finance_core::holdings::Error::Invalid)??;
    reflect(saved);
    Ok(())
}
pub fn remove_trade(id: &str) -> Result<(), finance_core::holdings::Error> {
    let saved = db::with(|c| finance_core::holdings::store::remove_trade(c, id))
        .ok_or(finance_core::holdings::Error::Invalid)??;
    reflect(saved);
    Ok(())
}
pub fn set_quote(
    quote: &finance_core::holdings::Quote,
) -> Result<(), finance_core::holdings::Error> {
    let saved =
        db::with(|c| finance_core::holdings::store::set_quote(c, quote, super::clock::today().0))
            .ok_or(finance_core::holdings::Error::Invalid)??;
    reflect(saved);
    Ok(())
}

pub fn checks() -> Vec<repository::BalanceCheck> {
    state().with(|s| s.checks.clone())
}

pub fn create_account(own: Account) -> Result<(), repository::Error> {
    db::with(|c| repository::create_account(c, &own))
        .ok_or(repository::Error::Invalid("database unavailable"))??;
    state().update(|s| {
        s.accounts.push(own);
        s.accounts.sort();
    });
    Ok(())
}

pub fn confirm_balance(
    check: repository::BalanceCheck,
    expected: i64,
) -> Result<(), repository::Error> {
    let entry = db::with(|c| repository::confirm_balance(c, &check, expected))
        .ok_or(repository::Error::Invalid("database unavailable"))??;
    state().update(|s| {
        s.checks.push(check);
        if let Some(entry) = entry {
            s.transactions.push(entry);
            s.transactions
                .sort_by(|a, b| a.at.cmp(&b.at).then(a.id.cmp(&b.id)));
        }
    });
    Ok(())
}

pub fn rename_account(old: &Account, new: &Account) -> Result<(), repository::Error> {
    use crate::domain::capture::{Record, Status};
    // A running response holds its own account context. Keep that context
    // stable until it finishes rather than reviving the old name afterward.
    if super::capture::all()
        .iter()
        .any(|d| d.status == Status::Analyzing)
    {
        return Err(repository::Error::Invalid("recognition running"));
    }
    let mut drafts = super::capture::all();
    for d in &mut drafts {
        for r in &mut d.records {
            if let Record::Money { draft, .. } = r {
                for a in [&mut draft.account, &mut draft.other_account] {
                    if a.as_ref() == Some(old) {
                        *a = Some(new.clone());
                    }
                }
            }
        }
    }
    db::with(|c| -> Result<(), repository::Error> {
        let tx = c.unchecked_transaction()?;
        repository::rename_account(&tx, old, new)?;
        for d in &drafts {
            tx.execute(
                "UPDATE capture_drafts SET body=?1 WHERE id=?2",
                rusqlite::params![serde_json::to_string(d)?, d.id],
            )?;
        }
        tx.commit()?;
        Ok(())
    })
    .ok_or(repository::Error::Invalid("database unavailable"))??;
    state().update(|s| {
        for a in &mut s.accounts {
            if a == old {
                *a = new.clone();
            }
        }
        s.accounts.sort();
        for t in &mut s.transactions {
            for p in &mut t.postings {
                if &p.account == old {
                    p.account = new.clone();
                }
            }
        }
        for check in &mut s.checks {
            if &check.account == old {
                check.account = new.clone();
            }
        }
        for trade in &mut s.holdings.trades {
            if trade.cash.as_ref() == Some(old) {
                trade.cash = Some(new.clone());
            }
        }
    });
    super::capture::replace_mirror(drafts);
    // The repository renames references inside an unfinished statement review.
    // The durable rename already succeeded; reload its UI mirror separately.
    if let Err(error) = super::statement_import::load() {
        log::error!("finance: cannot reload import after account rename: {error}");
    }
    let mut defaults = super::settings::current().ledger;
    for a in [&mut defaults.own, &mut defaults.other] {
        if a.as_deref() == Some(old.as_str()) {
            *a = Some(new.to_string());
        }
    }
    super::settings::save_ledger_defaults(defaults);
    Ok(())
}

pub fn save(entry: Transaction) -> Result<(), String> {
    db::with(|c| repository::save(c, &entry))
        .ok_or("the database is not open")?
        .map_err(|error| {
            log::error!("finance: save failed: {error}");
            error.to_string()
        })?;
    // Derive the mirror from the committed mutation; a second database read
    // cannot make a successful commit appear to have failed.
    state().update(|s| {
        for p in &entry.postings {
            if !s.accounts.contains(&p.account) {
                s.accounts.push(p.account.clone());
            }
        }
        s.accounts.sort();
        s.transactions.retain(|t| t.id != entry.id);
        s.transactions.push(entry);
        s.transactions
            .sort_by(|a, b| a.at.cmp(&b.at).then(a.id.cmp(&b.id)));
    });
    Ok(())
}

pub fn remove(id: &str) -> Result<Transaction, String> {
    let removed = db::with(|c| repository::remove(c, id))
        .ok_or("the database is not open")?
        .map_err(|error| {
            log::error!("finance: deletion failed: {error}");
            error.to_string()
        })?;
    state().update(|s| s.transactions.retain(|t| t.id != id));
    Ok(removed)
}
