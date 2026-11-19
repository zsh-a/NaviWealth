//! Thin reactive adapter over finance's confirmed ledger repository.
//! SQLite commits before a signal changes. Failure never looks like a save.

use navi_finance::{account::Account, journal::Transaction, repository};
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
    holdings: Rc<navi_finance::holdings::Book>,
    rates: Rc<Vec<navi_finance::currency::FxRate>>,
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
slice!(Holdings, navi_finance::holdings::Book, holdings_snapshot);
slice!(Rates, Vec<navi_finance::currency::FxRate>, rates_snapshot);

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
            rates: navi_finance::currency::rates(c)
                .map_err(|_| repository::Error::Invalid("exchange rates"))?
                .into(),
            transactions: repository::transactions(c)?.into(),
            accounts: repository::accounts(c)?.into(),
            checks: repository::balance_checks(c)?.into(),
            holdings: navi_finance::market::valued_book(
                c,
                navi_finance::holdings::store::load(c)
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

/// Publish only the two ledger slices affected by prices and FX.
pub(super) fn publish_prices(
    book: navi_finance::holdings::Book,
    rates: Vec<navi_finance::currency::FxRate>,
) {
    update(|ledger| {
        ledger.holdings = book.into();
        ledger.rates = rates.into();
    });
}

pub fn transactions() -> Vec<Transaction> {
    (*transactions_snapshot()).clone()
}
pub fn accounts() -> Vec<Account> {
    (*accounts_snapshot()).clone()
}

pub fn holdings() -> navi_finance::holdings::Book {
    (*holdings_snapshot()).clone()
}
pub fn rates() -> Vec<navi_finance::currency::FxRate> {
    (*rates_snapshot()).clone()
}
pub fn save_rate(rate: navi_finance::currency::FxRate) -> Result<(), String> {
    db::with(|c| navi_finance::currency::save_rate(c, &rate))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    let rates = db::with(navi_finance::currency::rates)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    update(|s| s.rates = rates.into());
    Ok(())
}
fn reflect(saved: navi_finance::holdings::store::Saved) {
    let started = Instant::now();
    let book = db::with(|c| navi_finance::market::valued_book(c, saved.book.clone()))
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
    security: Option<&navi_finance::holdings::Security>,
    trade: &navi_finance::holdings::Trade,
) -> Result<(), navi_finance::holdings::Error> {
    add_trade_bound(security, trade, None)
}
pub fn add_trade_bound(
    security: Option<&navi_finance::holdings::Security>,
    trade: &navi_finance::holdings::Trade,
    binding: Option<&navi_finance::catalog::SecurityBinding>,
) -> Result<(), navi_finance::holdings::Error> {
    let saved = db::with(|c| {
        navi_finance::holdings::store::add_trade_bound(
            c,
            security,
            trade,
            super::clock::today().0,
            binding,
        )
    })
    .ok_or(navi_finance::holdings::Error::Invalid)??;
    reflect(saved);
    Ok(())
}
pub fn remove_trade(id: &str) -> Result<(), navi_finance::holdings::Error> {
    let saved = db::with(|c| navi_finance::holdings::store::remove_trade(c, id))
        .ok_or(navi_finance::holdings::Error::Invalid)??;
    reflect(saved);
    Ok(())
}
pub fn set_quote(
    quote: &navi_finance::holdings::Quote,
) -> Result<(), navi_finance::holdings::Error> {
    let saved =
        db::with(|c| navi_finance::holdings::store::set_quote(c, quote, super::clock::today().0))
            .ok_or(navi_finance::holdings::Error::Invalid)??;
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
        Rc::make_mut(&mut s.checks)
            .sort_by(|a, b| a.checked_at.cmp(&b.checked_at).then(a.id.cmp(&b.id)));
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

#[derive(Debug)]
pub enum RemovalError {
    Missing,
    Changed,
    Unavailable,
}

fn removal_result<T>(
    result: Option<Result<T, repository::Error>>,
    operation: &str,
) -> Result<T, RemovalError> {
    match result {
        Some(Ok(value)) => Ok(value),
        Some(Err(error)) => {
            log::error!("finance: {operation} failed: {error}");
            Err(match error {
                repository::Error::Missing => RemovalError::Missing,
                repository::Error::RecordChanged => RemovalError::Changed,
                _ => RemovalError::Unavailable,
            })
        }
        None => {
            log::error!("finance: {operation} failed: the database is not open");
            Err(RemovalError::Unavailable)
        }
    }
}

pub fn remove(expected: &Transaction) -> Result<repository::RemovedTransaction, RemovalError> {
    let removed = removal_result(
        db::with(|c| repository::remove_confirmed(c, expected)),
        "deletion",
    )?;
    update(|s| {
        Rc::make_mut(&mut s.transactions).retain(|t| t.id != removed.entry.id);
        Rc::make_mut(&mut s.checks).retain(|c| c.id != removed.entry.id);
    });
    Ok(removed)
}

pub fn restore_removed(removed: &repository::RemovedTransaction) -> Result<(), RemovalError> {
    removal_result(
        db::with(|c| repository::restore_removed(c, removed)),
        "Undo",
    )?;
    update(|s| {
        Rc::make_mut(&mut s.transactions).push(removed.entry.clone());
        Rc::make_mut(&mut s.transactions).sort_by(|a, b| a.at.cmp(&b.at).then(a.id.cmp(&b.id)));
        if let Some(check) = &removed.balance_check {
            Rc::make_mut(&mut s.checks).push(check.clone());
            Rc::make_mut(&mut s.checks)
                .sort_by(|a, b| a.checked_at.cmp(&b.checked_at).then(a.id.cmp(&b.id)));
        }
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    fn assert_mirrors_match_disk() {
        db::with(|c| {
            assert_eq!(transactions(), repository::transactions(c).unwrap());
            assert_eq!(checks(), repository::balance_checks(c).unwrap());
            assert_eq!(accounts(), repository::accounts(c).unwrap());
        })
        .unwrap();
    }

    #[test]
    fn removal_errors_preserve_missing_changed_and_unavailable_distinctions() {
        assert!(matches!(
            removal_result::<()>(Some(Err(repository::Error::Missing)), "test"),
            Err(RemovalError::Missing)
        ));
        assert!(matches!(
            removal_result::<()>(Some(Err(repository::Error::RecordChanged)), "test"),
            Err(RemovalError::Changed)
        ));
        assert!(matches!(
            removal_result::<()>(Some(Err(repository::Error::Invalid("test"))), "test"),
            Err(RemovalError::Unavailable)
        ));
        assert!(matches!(
            removal_result::<()>(None, "test"),
            Err(RemovalError::Unavailable)
        ));
    }

    #[component]
    fn RemovalProbe() -> impl IntoElement {
        let done = signal(false);
        view()
            .child(text(move || if done.get() { "done" } else { "ready" }))
            .child(text("exercise removal").on_press(move || {
                let day = jiff::civil::date(2026, 11, 14);
                let own = Account::parse("资产:Cash").unwrap();
                let ordinary = navi_finance::journal::spend(
                    navi_finance::journal::Entry {
                        id: "ordinary".into(),
                        at: day.at(12, 0, 0, 0),
                        payee: "Lunch".into(),
                        note: String::new(),
                        source: navi_finance::journal::Source::Manual,
                    },
                    &own,
                    &navi_finance::account::defaults::expense("餐饮"),
                    3151,
                )
                .unwrap();
                let unavailable = repository::RemovedTransaction {
                    entry: ordinary.clone(),
                    balance_check: None,
                };
                assert!(matches!(remove(&ordinary), Err(RemovalError::Unavailable)));
                assert!(matches!(
                    restore_removed(&unavailable),
                    Err(RemovalError::Unavailable)
                ));
                assert!(transactions().is_empty());
                assert!(checks().is_empty());

                db::open().unwrap();
                load().unwrap();
                create_account(own.clone()).unwrap();
                let check = repository::BalanceCheck {
                    id: "m".into(),
                    account: own,
                    day,
                    actual: 10_001,
                    checked_at: day.at(23, 59, 59, 0),
                };
                confirm_balance(check.clone(), 0).unwrap();
                // Ties sort by id, even when confirmations arrive out of order.
                for id in ["z", "a"] {
                    confirm_balance(
                        repository::BalanceCheck {
                            id: id.into(),
                            ..check.clone()
                        },
                        check.actual,
                    )
                    .unwrap();
                }
                save(ordinary.clone()).unwrap();
                assert_mirrors_match_disk();
                let original = snapshot();
                let opening = transactions().into_iter().find(|t| t.id == "m").unwrap();
                let mut stale = ordinary.clone();
                stale.note = "stale snapshot".into();
                assert!(matches!(remove(&stale), Err(RemovalError::Changed)));
                assert!(snapshot() == original);

                db::with(|c| c.execute_batch("CREATE TRIGGER fail_delete_check BEFORE DELETE ON finance_balance_checks BEGIN SELECT RAISE(ABORT,'full disk'); END;")).unwrap().unwrap();
                assert!(matches!(remove(&opening), Err(RemovalError::Unavailable)));
                assert!(snapshot() == original);
                assert_mirrors_match_disk();
                db::with(|c| c.execute_batch("DROP TRIGGER fail_delete_check")).unwrap().unwrap();
                let removed = remove(&opening).unwrap();
                assert_eq!(removed.balance_check, Some(check));
                assert_mirrors_match_disk();
                let deleted = snapshot();
                db::with(|c| c.execute_batch("CREATE TRIGGER fail_insert_check BEFORE INSERT ON finance_balance_checks BEGIN SELECT RAISE(ABORT,'full disk'); END;")).unwrap().unwrap();
                assert!(matches!(restore_removed(&removed), Err(RemovalError::Unavailable)));
                assert!(snapshot() == deleted);
                assert_mirrors_match_disk();
                db::with(|c| c.execute_batch("DROP TRIGGER fail_insert_check")).unwrap().unwrap();
                restore_removed(&removed).unwrap();
                assert!(snapshot() == original);
                assert_mirrors_match_disk();
                assert!(matches!(restore_removed(&removed), Err(RemovalError::Changed)));
                assert!(snapshot() == original);

                let removed = remove(&ordinary).unwrap();
                assert!(matches!(remove(&ordinary), Err(RemovalError::Missing)));
                assert_mirrors_match_disk();
                restore_removed(&removed).unwrap();
                assert!(snapshot() == original);
                assert_mirrors_match_disk();
                let removed = remove(&ordinary).unwrap();
                let mut newer = ordinary;
                newer.note = "newer record".into();
                save(newer).unwrap();
                let before_conflict = snapshot();
                assert!(matches!(restore_removed(&removed), Err(RemovalError::Changed)));
                assert!(snapshot() == before_conflict);
                assert_mirrors_match_disk();
                done.set(true);
            }))
    }

    #[test]
    fn removal_and_undo_publish_only_committed_sorted_transactions_and_checks() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<RemovalProbe>())).unwrap();
        app.wait_for("ready").unwrap();
        app.press("exercise removal").unwrap();
        app.wait_for("done").unwrap();
    }

    #[component]
    fn PriceReloadProbe() -> impl IntoElement {
        use navi_finance::holdings::{self, Kind, Quote, Security, Trade, store};
        let done = signal(false);
        view()
            .child(text(move || if done.get() { "done" } else { "ready" }))
            .child(text("check price reload").on_press(move || {
                db::open().unwrap();
                load().unwrap();
                let day = super::super::clock::today().0;
                let security = Security::new("fund", "Fund").unwrap();
                add_trade(
                    Some(&security),
                    &Trade {
                        id: "opening".into(),
                        security: security.id.clone(),
                        at: day.at(0, 0, 0, 0),
                        kind: Kind::Opening,
                        quantity: holdings::SCALE,
                        price: 2 * holdings::SCALE,
                        amount: 0,
                        fee: 0,
                        cash: None,
                    },
                )
                .unwrap();
                let original = snapshot();
                db::with(|c| {
                    store::set_quote(
                        c,
                        &Quote {
                            security: security.id,
                            day,
                            price: 5 * holdings::SCALE,
                        },
                        day,
                    )
                    .unwrap();
                    // A price-only read must not touch snapshot history or the journal.
                    c.execute_batch(
                        "ALTER TABLE finance_valuation_snapshots RENAME TO hidden_snapshots;
                                 ALTER TABLE finance_postings RENAME TO hidden_postings;
                                 ALTER TABLE finance_trades RENAME TO hidden_trades;",
                    )
                    .unwrap();
                })
                .unwrap();
                super::super::market::reload_prices().unwrap();
                let next = snapshot();
                assert!(Rc::ptr_eq(&original.transactions, &next.transactions));
                assert!(Rc::ptr_eq(&original.accounts, &next.accounts));
                assert!(Rc::ptr_eq(&original.checks, &next.checks));
                assert_eq!(
                    next.holdings
                        .overview_with_rates(&next.transactions, day, &next.rates)
                        .unwrap()
                        .snapshot
                        .net,
                    500
                );
                done.set(true);
            }))
    }
    #[test]
    fn price_only_reload_updates_net_without_reading_or_publishing_the_journal() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<PriceReloadProbe>())).unwrap();
        app.wait_for("ready").unwrap();
        app.press("check price reload").unwrap();
        app.wait_for("done").unwrap();
    }

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
                    s.rates = vec![navi_finance::currency::FxRate {
                        currency: navi_finance::currency::Currency::USD,
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
                    let entry = navi_finance::journal::opening(
                        navi_finance::journal::Entry {
                            id: "one".into(),
                            at: jiff::civil::date(2026, 11, 15).at(12, 0, 0, 0),
                            payee: String::new(),
                            note: String::new(),
                            source: navi_finance::journal::Source::Manual,
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
