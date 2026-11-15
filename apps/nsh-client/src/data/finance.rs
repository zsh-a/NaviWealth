//! Thin reactive adapter over finance-core's confirmed ledger repository.
//! SQLite commits before a signal changes. Failure never looks like a save.

use finance_core::{account::Account, journal::Transaction, repository};
use nsh_core::prelude::*;
use std::{rc::Rc, time::Instant};

use super::db;

// Each slice has its own dependency. Shared snapshots make repeated derived
// reads cheap; the Vec-returning API remains available to existing callers.
#[derive(Clone, Default, PartialEq)]
struct Ledger {
    transactions: Rc<Vec<Transaction>>,
    accounts: Rc<Vec<Account>>,
    checks: Rc<Vec<repository::BalanceCheck>>,
    holdings: Rc<finance_core::holdings::Book>,
    rates: Rc<Vec<finance_core::currency::FxRate>>,
}
macro_rules! slice {
    ($name:ident, $ty:ty, $snapshot:ident) => {
        #[derive(Clone, Default)]
        struct $name(Rc<$ty>);
        pub fn $snapshot() -> Rc<$ty> {
            global::<$name>().with(|s| s.0.clone())
        }
    };
}
slice!(Transactions, Vec<Transaction>, transactions_snapshot);
slice!(Accounts, Vec<Account>, accounts_snapshot);
slice!(Checks, Vec<repository::BalanceCheck>, checks_snapshot);
slice!(Holdings, finance_core::holdings::Book, holdings_snapshot);
slice!(Rates, Vec<finance_core::currency::FxRate>, rates_snapshot);

fn snapshot() -> Ledger {
    untracked(|| Ledger {
        transactions: transactions_snapshot(),
        accounts: accounts_snapshot(),
        checks: checks_snapshot(),
        holdings: holdings_snapshot(),
        rates: rates_snapshot(),
    })
}
fn publish(next: Ledger) {
    // global() deliberately notifies on every write. Compare before writing,
    // and batch so a trade/rename/restore is observed as one committed snapshot.
    macro_rules! write {
        ($slice:ident, $field:ident) => {
            let signal = global::<$slice>();
            if signal
                .with_untracked(|old| !Rc::ptr_eq(&old.0, &next.$field) && *old.0 != *next.$field)
            {
                signal.set($slice(next.$field));
            }
        };
    }
    batch(|| {
        write!(Transactions, transactions);
        write!(Accounts, accounts);
        write!(Checks, checks);
        write!(Holdings, holdings);
        write!(Rates, rates);
    });
}
fn update(f: impl FnOnce(&mut Ledger)) {
    let mut next = snapshot();
    f(&mut next);
    publish(next);
}

pub fn load() -> Result<(), String> {
    let started = Instant::now();
    let loaded = db::with(|c| -> Result<Ledger, repository::Error> {
        // Validate first: opening a damaged journal must not mutate it.
        repository::validate(c)?;
        repository::ensure_defaults(c)?;
        Ok(Ledger {
            rates: finance_core::currency::rates(c)
                .map_err(|_| repository::Error::Invalid("exchange rates"))?
                .into(),
            transactions: repository::transactions(c)?.into(),
            accounts: repository::accounts(c)?.into(),
            checks: repository::balance_checks(c)?.into(),
            holdings: finance_core::market::valued_book(
                c,
                finance_core::holdings::store::load(c)
                    .map_err(|_| repository::Error::Invalid("holdings"))?,
            )
            .map_err(|_| repository::Error::Invalid("market quotes"))?
            .into(),
        })
    })
    .ok_or("the database is not open")?
    .map_err(|error| {
        log::error!("finance: cannot load ledger: {error}");
        error.to_string()
    })?;
    publish(loaded);
    log::debug!(
        "finance load and publish: {:.2}ms",
        started.elapsed().as_secs_f64() * 1000.0
    );
    Ok(())
}

pub fn transactions() -> Vec<Transaction> {
    (*transactions_snapshot()).clone()
}
pub fn accounts() -> Vec<Account> {
    (*accounts_snapshot()).clone()
}

pub fn holdings() -> finance_core::holdings::Book {
    (*holdings_snapshot()).clone()
}
pub fn rates() -> Vec<finance_core::currency::FxRate> {
    (*rates_snapshot()).clone()
}
pub fn save_rate(rate: finance_core::currency::FxRate) -> Result<(), String> {
    db::with(|c| finance_core::currency::save_rate(c, &rate))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    let rates = db::with(finance_core::currency::rates)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    update(|s| s.rates = rates.into());
    Ok(())
}
fn reflect(saved: finance_core::holdings::store::Saved) {
    let started = Instant::now();
    let book = db::with(|c| finance_core::market::valued_book(c, saved.book.clone()))
        .and_then(Result::ok)
        .unwrap_or(saved.book);
    update(|s| {
        s.holdings = book.into();
        s.transactions = saved.entries.into();
        s.accounts = saved.accounts.into();
    });
    log::debug!(
        "finance reflect: {:.2}ms",
        started.elapsed().as_secs_f64() * 1000.0
    );
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
    (*checks_snapshot()).clone()
}

pub fn create_account(own: Account) -> Result<(), repository::Error> {
    db::with(|c| repository::create_account(c, &own))
        .ok_or(repository::Error::Invalid("database unavailable"))??;
    update(|s| {
        Rc::make_mut(&mut s.accounts).push(own);
        Rc::make_mut(&mut s.accounts).sort();
    });
    Ok(())
}

pub fn confirm_balance(
    check: repository::BalanceCheck,
    expected: i64,
) -> Result<(), repository::Error> {
    let entry = db::with(|c| repository::confirm_balance(c, &check, expected))
        .ok_or(repository::Error::Invalid("database unavailable"))??;
    update(|s| {
        Rc::make_mut(&mut s.checks).push(check);
        if let Some(entry) = entry {
            Rc::make_mut(&mut s.transactions).push(entry);
            Rc::make_mut(&mut s.transactions).sort_by(|a, b| a.at.cmp(&b.at).then(a.id.cmp(&b.id)));
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
    update(|s| {
        for a in Rc::make_mut(&mut s.accounts) {
            if a == old {
                *a = new.clone();
            }
        }
        Rc::make_mut(&mut s.accounts).sort();
        for t in Rc::make_mut(&mut s.transactions) {
            for p in &mut t.postings {
                if &p.account == old {
                    p.account = new.clone();
                }
            }
        }
        for check in Rc::make_mut(&mut s.checks) {
            if &check.account == old {
                check.account = new.clone();
            }
        }
        for trade in &mut Rc::make_mut(&mut s.holdings).trades {
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
    let started = Instant::now();
    db::with(|c| repository::save(c, &entry))
        .ok_or("the database is not open")?
        .map_err(|error| {
            log::error!("finance: save failed: {error}");
            error.to_string()
        })?;
    // Derive the mirror from the committed mutation; a second database read
    // cannot make a successful commit appear to have failed.
    update(|s| {
        let mut added = false;
        for p in &entry.postings {
            if !s.accounts.contains(&p.account) {
                Rc::make_mut(&mut s.accounts).push(p.account.clone());
                added = true;
            }
        }
        if added {
            Rc::make_mut(&mut s.accounts).sort();
        }
        Rc::make_mut(&mut s.transactions).retain(|t| t.id != entry.id);
        Rc::make_mut(&mut s.transactions).push(entry);
        Rc::make_mut(&mut s.transactions).sort_by(|a, b| a.at.cmp(&b.at).then(a.id.cmp(&b.id)));
    });
    log::debug!(
        "finance save and publish: {:.2}ms",
        started.elapsed().as_secs_f64() * 1000.0
    );
    Ok(())
}

pub fn remove(id: &str) -> Result<Transaction, String> {
    let removed = db::with(|c| repository::remove(c, id))
        .ok_or("the database is not open")?
        .map_err(|error| {
            log::error!("finance: deletion failed: {error}");
            error.to_string()
        })?;
    update(|s| Rc::make_mut(&mut s.transactions).retain(|t| t.id != id));
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    #[component]
    fn SliceProbe() -> impl IntoElement {
        let runs = signal([0usize; 6]);
        effect(move || {
            let _ = accounts_snapshot();
            runs.update(|r| r[0] += 1);
        });
        effect(move || {
            let _ = transactions_snapshot();
            runs.update(|r| r[1] += 1);
        });
        effect(move || {
            let _ = checks_snapshot();
            runs.update(|r| r[2] += 1);
        });
        effect(move || {
            let _ = holdings_snapshot();
            runs.update(|r| r[3] += 1);
        });
        effect(move || {
            let _ = rates_snapshot();
            runs.update(|r| r[4] += 1);
        });
        effect(move || {
            let accounts = accounts_snapshot();
            let entries = transactions_snapshot();
            assert_eq!(
                accounts.len(),
                entries.len(),
                "a subscriber observed a mixed snapshot"
            );
            runs.update(|r| r[5] += 1);
        });
        view()
            .child(text(move || format!("runs {:?}", runs.get())))
            .child(text("same").on_press(|| publish(snapshot())))
            .child(text("rate").on_press(|| {
                update(|s| {
                    s.rates = vec![finance_core::currency::FxRate {
                        currency: finance_core::currency::Currency::USD,
                        day: jiff::civil::date(2026, 11, 15),
                        rate: 7_000_000,
                        source: "manual".into(),
                    }]
                    .into();
                })
            }))
            .child(text("pair").on_press(|| {
                update(|s| {
                    let own = Account::parse("资产:Cash").unwrap();
                    let entry = finance_core::journal::opening(
                        finance_core::journal::Entry {
                            id: "one".into(),
                            at: jiff::civil::date(2026, 11, 15).at(12, 0, 0, 0),
                            payee: String::new(),
                            note: String::new(),
                            source: finance_core::journal::Source::Manual,
                        },
                        &own,
                        100,
                    )
                    .unwrap();
                    s.accounts = vec![own].into();
                    s.transactions = vec![entry].into();
                })
            }))
    }
    #[test]
    fn equal_and_unrelated_slices_do_not_notify_and_multi_slice_publish_is_atomic() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<SliceProbe>())).unwrap();
        app.wait_for("runs [1, 1, 1, 1, 1, 1]").unwrap();
        app.press("same").unwrap();
        app.wait_for("runs [1, 1, 1, 1, 1, 1]").unwrap();
        app.press("rate").unwrap();
        app.wait_for("runs [1, 1, 1, 1, 2, 1]").unwrap();
        // Equal values in a different allocation also do not notify.
        app.press("rate").unwrap();
        app.wait_for("runs [1, 1, 1, 1, 2, 1]").unwrap();
        app.press("pair").unwrap();
        app.wait_for("runs [2, 2, 1, 1, 2, 2]").unwrap();
    }
}
