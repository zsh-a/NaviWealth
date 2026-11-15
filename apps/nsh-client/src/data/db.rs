//! The app's SQLite database, `naviwealth.sqlite` in its data directory.
//! The file sits in the app's private storage, which Android encrypts at
//! rest; the database itself is not encrypted (ADR 0002). Hosts that keep
//! no files for the app (headless tests without a data directory) get an
//! in-memory database instead.
//!
//! Schema changes are appended to [`MIGRATIONS`]; `PRAGMA user_version`
//! records how many have run, and each runs in its own transaction.

use std::{path::Path, rc::Rc};

use nsh_core::prelude::*;
use rusqlite::Connection;

const FILE: &str = "naviwealth.sqlite";

/// Every schema change, in order. Never edit one that has shipped.
const MIGRATIONS: &[&str] = &[
    // 1: confirmed meals, one JSON body per meal (`domain::meal`).
    "CREATE TABLE meals (
        id TEXT PRIMARY KEY NOT NULL,
        day TEXT NOT NULL,
        logged_at_ms INTEGER NOT NULL,
        body TEXT NOT NULL
    );
    CREATE INDEX meals_by_day ON meals (day, logged_at_ms);",
    // 2: body weight, one entry per day (`domain::weight`).
    "CREATE TABLE weights (
        day TEXT PRIMARY KEY NOT NULL,
        kg REAL NOT NULL,
        logged_at_ms INTEGER NOT NULL
    );",
    // 3: Garmin daily summaries, one JSON body per day (`health_core::garmin`).
    "CREATE TABLE garmin_days (
        day TEXT PRIMARY KEY NOT NULL,
        body TEXT NOT NULL,
        fetched_at_ms INTEGER NOT NULL
    );",
    // 4: favorites, one JSON body each (`domain::favorite`).
    "CREATE TABLE saved_meals (
        id TEXT PRIMARY KEY NOT NULL,
        saved_at_ms INTEGER NOT NULL,
        used_at_ms INTEGER NOT NULL,
        body TEXT NOT NULL
    );",
    // 5: recognition drafts (`domain::pending`); not in backups.
    "CREATE TABLE meal_drafts (
        id TEXT PRIMARY KEY NOT NULL,
        created_at_ms INTEGER NOT NULL,
        body TEXT NOT NULL
    );",
    // 6: the owner's review notes, one line per day (`data::notes`).
    "CREATE TABLE review_notes (
        day TEXT PRIMARY KEY NOT NULL,
        text TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
    );",
    // 7: the confirmed double-entry ledger and remembered import rules.
    finance_core::repository::SCHEMA,
    // 8: text/image recognition drafts, consumed atomically on confirmation.
    "CREATE TABLE capture_drafts (id TEXT PRIMARY KEY NOT NULL, created_at_ms INTEGER NOT NULL, body TEXT NOT NULL);",
    // 9: confirmed balance observations, including zero-difference checks.
    finance_core::repository::BALANCE_SCHEMA,
    // 10: securities, exact trades and dated manual prices.
    finance_core::holdings::store::SCHEMA,
    // 11: resumable statement review.
    finance_core::import::store::SCHEMA,
    // 12: explicit security bindings and verified catalog cache.
    finance_core::catalog::SCHEMA,
    // 13: dated public quotes, separate from manual prices.
    finance_core::market::SCHEMA,
    // 14: dated currency conversion rates, with explicit provenance.
    finance_core::currency::SCHEMA,
    // 15: immutable daily bars and price revisions.
    finance_core::history::SCHEMA,
    // 16: immutable observed valuations.
    finance_core::valuation::SCHEMA,
];

#[derive(Clone, Default)]
struct Db(Option<Rc<Connection>>);

impl PartialEq for Db {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (Some(a), Some(b)) => Rc::ptr_eq(a, b),
            (None, None) => true,
            _ => false,
        }
    }
}

fn db() -> Signal<Db> {
    global::<Db>()
}

/// Opens the database once per app; the root calls it before loading.
pub fn open() -> Result<(), String> {
    if db().with_untracked(|db| db.0.is_some()) {
        return Ok(());
    }
    let connection = match data_dir() {
        Some(dir) => open_file(&dir),
        None => lifeos_core::memory(MIGRATIONS),
    }
    .map_err(|error| {
        log::error!("db: cannot open {FILE}: {error}");
        error.to_string()
    })?;
    db().set(Db(Some(Rc::new(connection))));
    Ok(())
}

fn open_file(dir: &Path) -> Result<Connection, lifeos_core::Error> {
    lifeos_core::open(&dir.join(FILE), MIGRATIONS)
}

fn migrate(connection: &mut Connection) -> Result<(), lifeos_core::Error> {
    lifeos_core::migrate(connection, MIGRATIONS)
}

/// The schema version this app writes: how many migrations exist.
pub const SCHEMA: u32 = MIGRATIONS.len() as u32;

/// What a backup carries and a restore replaces: each table and its columns.
const HEALTH_TABLES: &[(&str, &str)] = &[
    ("meals", "id, day, logged_at_ms, body"),
    ("weights", "day, kg, logged_at_ms"),
    ("garmin_days", "day, body, fetched_at_ms"),
    ("saved_meals", "id, saved_at_ms, used_at_ms, body"),
    ("review_notes", "day, text, updated_at_ms"),
];

/// Why a restore was refused; nothing changed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RestoreError {
    /// The file is not a readable database of this app.
    Unreadable,
    /// It was written by a newer version of the app.
    Newer,
    /// The device could not write.
    Storage,
}

/// A scratch file in the app's data directory (the temp directory without one).
fn scratch(name: &str) -> std::path::PathBuf {
    let dir = data_dir().unwrap_or_else(std::env::temp_dir);
    let _ = std::fs::create_dir_all(&dir);
    dir.join(format!("{name}-{}.sqlite", std::process::id()))
}

fn remove_scratch(path: &Path) {
    for suffix in ["", "-wal", "-shm", "-journal"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", path.display()));
    }
}

/// A consistent copy of the whole database, as file bytes.
pub fn snapshot() -> Result<Vec<u8>, String> {
    let path = scratch("snapshot");
    remove_scratch(&path);
    let result = with(|c| lifeos_core::snapshot(c, &path))
        .ok_or("the database is not open")?
        .map_err(|error| error.to_string());
    remove_scratch(&path);
    result
}

/// Health-only backups (schema 1–6) replace Health records and preserve the
/// current ledger. Backups from schema 7 onward replace both domains. The
/// whole replacement is atomic and validated before touching current rows.
pub fn replace_with(file: &[u8]) -> Result<(), RestoreError> {
    let path = scratch("restore");
    remove_scratch(&path);
    std::fs::write(&path, file).map_err(|_| RestoreError::Storage)?;
    let result = with(|c| restore_file(c, &path)).unwrap_or(Err(RestoreError::Storage));
    remove_scratch(&path);
    result
}

fn restore_file(connection: &Connection, path: &Path) -> Result<(), RestoreError> {
    let mut restored = Connection::open(path).map_err(|_| RestoreError::Unreadable)?;
    restored
        .pragma_update(None, "trusted_schema", false)
        .map_err(|_| RestoreError::Unreadable)?;
    let ok: String = restored
        .query_row("PRAGMA integrity_check", [], |r| r.get(0))
        .map_err(|_| RestoreError::Unreadable)?;
    let version: u32 = restored
        .pragma_query_value(None, "user_version", |r| r.get(0))
        .map_err(|_| RestoreError::Unreadable)?;
    if ok != "ok" || version == 0 {
        return Err(RestoreError::Unreadable);
    }
    if version > SCHEMA {
        return Err(RestoreError::Newer);
    }
    migrate(&mut restored).map_err(|_| RestoreError::Unreadable)?;
    validate_restored(&restored).map_err(|_| RestoreError::Unreadable)?;
    drop(restored);
    let mut tables = HEALTH_TABLES.to_vec();
    if version >= 7 {
        tables.extend_from_slice(finance_core::repository::TABLES);
    }
    lifeos_core::replace_tables(connection, path, &tables).map_err(|error| {
        log::error!("db: restore failed: {error}");
        match error {
            lifeos_core::Error::Sql(rusqlite::Error::SqliteFailure(error, _))
                if error.code == rusqlite::ErrorCode::ConstraintViolation =>
            {
                RestoreError::Unreadable
            }
            _ => RestoreError::Storage,
        }
    })
}

/// Reject malformed records before replacing anything. Ordinary loading
/// skips bad rows; doing that during restore would silently lose data.
fn validate_restored(connection: &Connection) -> Result<(), String> {
    use crate::domain::{meal::Meal, weight::valid_kg};
    for (table, _) in HEALTH_TABLES.iter().chain(finance_core::repository::TABLES) {
        let kind: String = connection
            .query_row(
                "SELECT type FROM sqlite_schema WHERE name = ?1",
                [table],
                |row| row.get(0),
            )
            .map_err(|e| e.to_string())?;
        if kind != "table" {
            return Err("expected a table".into());
        }
    }
    let read = || -> rusqlite::Result<()> {
        let mut statement = connection.prepare("SELECT id, day, logged_at_ms, body FROM meals")?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, String>(3)?,
            ))
        })?;
        for row in rows {
            let (id, day, at, body) = row?;
            let meal: Meal =
                serde_json::from_str(&body).map_err(|_| rusqlite::Error::InvalidQuery)?;
            if !meal.is_valid()
                || meal.id != id
                || meal.day.to_string() != day
                || meal.logged_at_ms != at
            {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement = connection.prepare("SELECT day, kg, logged_at_ms FROM weights")?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, f64>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })?;
        for row in rows {
            let (day, kg, _) = row?;
            if day.parse::<crate::domain::meal::Day>().is_err() || !valid_kg(kg) {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement =
            connection.prepare("SELECT day, body, fetched_at_ms FROM garmin_days")?;
        let rows = statement.query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })?;
        for row in rows {
            let (day, body, _) = row?;
            let value: health_core::garmin::GarminDay =
                serde_json::from_str(&body).map_err(|_| rusqlite::Error::InvalidQuery)?;
            if day.parse::<crate::domain::meal::Day>().is_err() || value.day != day {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement = connection.prepare("SELECT id, body FROM saved_meals")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (id, body) = row?;
            let value: crate::domain::favorite::Favorite =
                serde_json::from_str(&body).map_err(|_| rusqlite::Error::InvalidQuery)?;
            if !value.is_valid() || value.id != id {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        let mut statement = connection.prepare("SELECT day, text FROM review_notes")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        for row in rows {
            let (day, text) = row?;
            if day.parse::<crate::domain::meal::Day>().is_err() || !crate::data::notes::valid(&text)
            {
                return Err(rusqlite::Error::InvalidQuery);
            }
        }
        Ok(())
    };
    read().map_err(|e| e.to_string())?;
    finance_core::repository::validate(connection).map_err(|e| e.to_string())
}

/// Runs `f` on the open database; `None` before [`open`].
pub fn with<R>(f: impl FnOnce(&Connection) -> R) -> Option<R> {
    let connection = db().with_untracked(|db| db.0.clone())?;
    Some(f(&connection))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spending(id: &str, amount: i64) -> finance_core::journal::Transaction {
        use finance_core::{
            account::{Account, defaults},
            journal::{self, Entry, Source},
        };
        journal::spend(
            Entry {
                id: id.into(),
                at: jiff::civil::date(2026, 11, 14).at(12, 0, 0, 0),
                payee: "Lunch".into(),
                note: String::new(),
                source: Source::Manual,
            },
            &Account::parse("资产:现金").unwrap(),
            &defaults::expense("餐饮"),
            amount,
        )
        .unwrap()
    }

    #[test]
    fn health_only_restore_preserves_the_current_ledger() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("health.sqlite");
        let old = lifeos_core::open(&source, &MIGRATIONS[..6]).unwrap();
        old.execute("INSERT INTO weights VALUES ('2026-11-14', 70.0, 1)", [])
            .unwrap();
        drop(old);
        let current = lifeos_core::memory(MIGRATIONS).unwrap();
        finance_core::repository::save(&current, &spending("current", 3150)).unwrap();
        current
            .execute("INSERT INTO weights VALUES ('2026-11-14', 80.0, 1)", [])
            .unwrap();
        restore_file(&current, &source).unwrap();
        assert_eq!(
            finance_core::repository::transactions(&current).unwrap(),
            [spending("current", 3150)]
        );
        assert_eq!(
            current
                .query_row("SELECT kg FROM weights", [], |r| r.get::<_, f64>(0))
                .unwrap(),
            70.0
        );
    }

    #[test]
    fn financial_restore_replaces_both_domains_and_rejects_unbalanced_backup() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("both.sqlite");
        let backup = lifeos_core::open(&source, MIGRATIONS).unwrap();
        finance_core::repository::save(&backup, &spending("backup", 4150)).unwrap();
        let check = finance_core::repository::BalanceCheck {
            id: "verified".into(),
            account: spending("backup", 4150)
                .own_postings()
                .next()
                .unwrap()
                .account
                .clone(),
            day: jiff::civil::date(2026, 11, 14),
            actual: -4150,
            checked_at: jiff::civil::date(2026, 11, 14).at(16, 0, 0, 0),
        };
        finance_core::repository::confirm_balance(&backup, &check, -4150).unwrap();
        backup
            .execute("INSERT INTO weights VALUES ('2026-11-14', 70.0, 1)", [])
            .unwrap();
        let current = lifeos_core::memory(MIGRATIONS).unwrap();
        finance_core::repository::save(&current, &spending("current", 3150)).unwrap();
        current
            .execute("INSERT INTO weights VALUES ('2026-11-14', 80.0, 1)", [])
            .unwrap();
        backup
            .execute("UPDATE finance_postings SET amount=1 WHERE position=0", [])
            .unwrap();
        assert_eq!(
            restore_file(&current, &source),
            Err(RestoreError::Unreadable)
        );
        assert_eq!(
            finance_core::repository::transactions(&current).unwrap(),
            [spending("current", 3150)]
        );
        assert_eq!(
            current
                .query_row("SELECT kg FROM weights", [], |r| r.get::<_, f64>(0))
                .unwrap(),
            80.0
        );
        finance_core::repository::save(&backup, &spending("backup", 4150)).unwrap();
        drop(backup);
        restore_file(&current, &source).unwrap();
        assert_eq!(
            finance_core::repository::balance_checks(&current).unwrap(),
            vec![check]
        );
        assert_eq!(
            finance_core::repository::transactions(&current).unwrap(),
            [spending("backup", 4150)]
        );
        assert_eq!(
            current
                .query_row("SELECT kg FROM weights", [], |r| r.get::<_, f64>(0))
                .unwrap(),
            70.0
        );
    }

    #[test]
    fn holdings_restore_keeps_prices_and_rejects_trade_ledger_mismatch() {
        use finance_core::{
            holdings::{Kind, Quote, Security, Trade, store},
            repository,
        };
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("holdings.sqlite");
        let backup = lifeos_core::open(&source, MIGRATIONS).unwrap();
        let day = jiff::civil::date(2026, 11, 15);
        let security = Security::new("etf", "ETF").unwrap();
        store::add_trade(
            &backup,
            Some(&security),
            &Trade {
                id: "opening".into(),
                security: security.id.clone(),
                at: day.at(12, 0, 0, 0),
                kind: Kind::Opening,
                quantity: 100_000_000,
                price: 4_000_000,
                amount: 0,
                fee: 0,
                cash: None,
            },
            day,
        )
        .unwrap();
        let expected = store::set_quote(
            &backup,
            &Quote {
                security: security.id.clone(),
                day,
                price: 5_000_000,
            },
            day,
        )
        .unwrap();
        let binding = finance_core::catalog::SecurityBinding {
            security: security.id.clone(),
            market: "cn_a".into(),
            symbol: "510300".into(),
            currency: "CNY".into(),
        };
        finance_core::catalog::bind(&backup, &binding).unwrap();
        let quote = finance_core::market::MarketQuote {
            security: security.id.clone(),
            symbol: "510300.SH".into(),
            currency: "CNY".into(),
            provider: "tencent".into(),
            price: 6_000_000,
            observed_at: "2026-11-13T07:00:00Z".parse().unwrap(),
            fetched_at: "2026-11-13T07:01:00Z".parse().unwrap(),
            previous_close_only: false,
        };
        finance_core::market::save(&backup, &quote, jiff::Timestamp::now()).unwrap();
        let rate = finance_core::currency::FxRate {
            currency: finance_core::currency::Currency::USD,
            day,
            rate: 7_000_000,
            source: "manual".into(),
        };
        finance_core::currency::save_rate(&backup, &rate).unwrap();
        let import = finance_core::import::store::create(
            &backup,
            "card.txt",
            "招商银行信用卡对账单 2026年07月\n交易明细\n07/02 07/03 晚餐 68.00 1234 68.00\n"
                .as_bytes(),
        )
        .unwrap();
        let current = lifeos_core::memory(MIGRATIONS).unwrap();
        restore_file(&current, &source).unwrap();
        assert_eq!(
            finance_core::currency::rates(&current).unwrap().as_slice(),
            std::slice::from_ref(&rate)
        );
        assert_eq!(
            finance_core::catalog::bindings(&current).unwrap(),
            [binding]
        );
        assert_eq!(
            finance_core::market::load(&current).unwrap().as_slice(),
            std::slice::from_ref(&quote)
        );
        assert_eq!(
            finance_core::import::store::active(&current).unwrap(),
            Some(import)
        );
        assert_eq!(store::load(&current).unwrap(), expected.book);
        assert_eq!(
            repository::transactions(&current).unwrap(),
            expected.entries
        );
        assert_eq!(
            expected.book.overview(&expected.entries, day).unwrap().net,
            50000
        );
        backup
            .execute("UPDATE finance_fx_rates SET currency='EUR'", [])
            .unwrap();
        assert_eq!(
            restore_file(&current, &source),
            Err(RestoreError::Unreadable)
        );
        assert_eq!(finance_core::currency::rates(&current).unwrap(), [rate]);
        backup
            .execute("UPDATE finance_fx_rates SET currency='USD'", [])
            .unwrap();
        backup
            .execute("UPDATE finance_market_quotes SET currency='USD'", [])
            .unwrap();
        assert_eq!(
            restore_file(&current, &source),
            Err(RestoreError::Unreadable)
        );
        assert_eq!(finance_core::market::load(&current).unwrap(), [quote]);
        backup
            .execute("UPDATE finance_market_quotes SET currency='CNY'", [])
            .unwrap();
        backup
            .execute("UPDATE finance_trades SET quantity=200000000", [])
            .unwrap();
        assert_eq!(
            restore_file(&current, &source),
            Err(RestoreError::Unreadable)
        );
        assert_eq!(store::load(&current).unwrap(), expected.book);
        assert_eq!(
            repository::transactions(&current).unwrap(),
            expected.entries
        );
    }

    fn seed_legacy_prices(c: &Connection) -> finance_core::catalog::SecurityBinding {
        use finance_core::{
            catalog, currency,
            holdings::{Kind, Quote, Security, Trade, store},
            market,
        };
        let day = jiff::civil::date(2026, 11, 1);
        let security = Security::new("history-etf", "History ETF").unwrap();
        store::add_trade(
            c,
            Some(&security),
            &Trade {
                id: "history-opening".into(),
                security: security.id.clone(),
                at: day.at(12, 0, 0, 0),
                kind: Kind::Opening,
                quantity: 100_000_000,
                price: 4_000_000,
                amount: 0,
                fee: 0,
                cash: None,
            },
            day,
        )
        .unwrap();
        let binding = catalog::SecurityBinding {
            security: security.id.clone(),
            market: "cn_a".into(),
            symbol: "510300".into(),
            currency: "CNY".into(),
        };
        catalog::bind(c, &binding).unwrap();
        store::set_quote(
            c,
            &Quote {
                security: security.id.clone(),
                day,
                price: 4_500_000,
            },
            day,
        )
        .unwrap();
        currency::save_rate(
            c,
            &currency::FxRate {
                currency: currency::Currency::USD,
                day,
                rate: 7_100_000,
                source: "manual".into(),
            },
        )
        .unwrap();
        market::save(
            c,
            &market::MarketQuote {
                security: security.id,
                symbol: "510300.SH".into(),
                currency: "CNY".into(),
                provider: "tencent".into(),
                price: 5_000_000,
                observed_at: "2026-11-02T07:00:00Z".parse().unwrap(),
                fetched_at: "2026-11-02T07:01:00Z".parse().unwrap(),
                previous_close_only: false,
            },
            jiff::Timestamp::now(),
        )
        .unwrap();
        binding
    }

    /// Exact persisted rows catch accidental audit generation, ID changes and body rewriting.
    fn finance_rows(c: &Connection) -> Vec<(&'static str, Vec<Vec<rusqlite::types::Value>>)> {
        finance_core::repository::TABLES
            .iter()
            .map(|&(table, columns)| {
                let mut q = c
                    .prepare(&format!("SELECT {columns} FROM {table} ORDER BY {columns}"))
                    .unwrap();
                let width = q.column_count();
                let rows = q
                    .query_map([], |r| (0..width).map(|i| r.get(i)).collect())
                    .unwrap()
                    .collect::<Result<Vec<_>, _>>()
                    .unwrap();
                (table, rows)
            })
            .collect()
    }

    #[test]
    fn schema14_price_baselines_migrate_once_and_history_restores_exactly() {
        use finance_core::{history, valuation};
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("legacy14.sqlite");
        let mut old = lifeos_core::open(&path, &MIGRATIONS[..14]).unwrap();
        let binding = seed_legacy_prices(&old);
        migrate(&mut old).unwrap();
        let baseline = history::audit(&old).unwrap();
        assert_eq!(baseline.len(), 3);
        for kind in ["manual_quote", "fx_rate", "market_quote"] {
            let row = baseline.iter().find(|r| r.kind == kind).unwrap();
            let body: serde_json::Value = serde_json::from_str(&row.body).unwrap();
            assert_eq!(body["baseline"], true);
        }
        let after_migration = finance_rows(&old);
        migrate(&mut old).unwrap();
        assert_eq!(finance_rows(&old), after_migration);
        let now = jiff::Timestamp::now();
        let mut bar = history::DailyBar {
            market: binding.market.clone(),
            symbol: "510300.SH".into(),
            currency: binding.currency.clone(),
            provider: "tencent_raw".into(),
            day: jiff::civil::date(2026, 11, 3),
            open: 4_900_000,
            high: 5_200_000,
            low: 4_800_000,
            close: 5_100_000,
            volume: Some(12345),
            fetched_at: "2026-11-04T01:00:00Z".parse().unwrap(),
        };
        history::save_bars(&old, &binding, &[bar.clone()], now).unwrap();
        bar.close = 5_200_000;
        bar.fetched_at = "2026-11-05T01:00:00Z".parse().unwrap();
        history::save_bars(&old, &binding, &[bar], now).unwrap();
        let today = now.to_zoned(jiff::tz::TimeZone::UTC).date();
        valuation::record_current(&old, today, now).unwrap();
        let expected = finance_rows(&old);
        let source = dir.path().join("snapshot16.sqlite");
        std::fs::write(
            &source,
            lifeos_core::snapshot(&old, &dir.path().join("copy.sqlite")).unwrap(),
        )
        .unwrap();
        let current = lifeos_core::memory(MIGRATIONS).unwrap();
        finance_core::repository::save(&current, &spending("replaced", 3150)).unwrap();
        restore_file(&current, &source).unwrap();
        assert_eq!(finance_rows(&current), expected);
        // Corrupt each immutable record family independently. Failed restore keeps every
        // existing ledger, price revision and observation unchanged.
        for (i, sql) in [
            "UPDATE finance_price_audit SET item_key='wrong' WHERE kind='manual_quote'",
            "UPDATE finance_daily_bars SET received_at='2020-01-01T00:00:00Z'",
            "UPDATE finance_valuation_snapshots SET body=json_set(body,'$.net',123)",
        ]
        .into_iter()
        .enumerate()
        {
            let corrupt = dir.path().join(format!("corrupt-{i}.sqlite"));
            std::fs::copy(&source, &corrupt).unwrap();
            let bad = Connection::open(&corrupt).unwrap();
            bad.execute_batch(sql).unwrap();
            drop(bad);
            assert_eq!(
                restore_file(&current, &corrupt),
                Err(RestoreError::Unreadable)
            );
            assert_eq!(finance_rows(&current), expected);
        }
    }

    #[test]
    fn migrations_run_once_and_record_the_version() {
        let mut connection = Connection::open_in_memory().unwrap();
        migrate(&mut connection).unwrap();
        migrate(&mut connection).unwrap();
        let version: usize = connection
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version, MIGRATIONS.len());
        connection
            .execute(
                "INSERT INTO meals (id, day, logged_at_ms, body) VALUES ('a', '2026-11-13', 1, '{}')",
                [],
            )
            .unwrap();
    }

    #[test]
    fn a_file_database_keeps_rows_across_opens() {
        let dir = tempfile::tempdir().unwrap();
        open_file(dir.path())
            .unwrap()
            .execute(
                "INSERT INTO meals (id, day, logged_at_ms, body) VALUES ('a', '2026-11-13', 1, '{}')",
                [],
            )
            .unwrap();
        let count: i64 = open_file(dir.path())
            .unwrap()
            .query_row("SELECT COUNT(*) FROM meals", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn a_restore_checks_favorites_too() {
        let mut connection = Connection::open_in_memory().unwrap();
        migrate(&mut connection).unwrap();
        let food = r#"{"id":1,"name":"Oats","grams":50.0,"per_100g":{"kcal":380.0,"protein":13.0,"carbs":67.0,"fat":7.0},"source":{"kind":"manual"}}"#;
        let body = format!(r#"{{"id":"f1","foods":[{food}],"saved_at_ms":1,"used_at_ms":1}}"#);
        connection
            .execute(
                "INSERT INTO saved_meals (id, saved_at_ms, used_at_ms, body) VALUES ('f1', 1, 1, ?1)",
                [&body],
            )
            .unwrap();
        assert_eq!(validate_restored(&connection), Ok(()));
        connection
            .execute(
                "UPDATE saved_meals SET body = '{\"id\":\"f1\",\"foods\":[],\"saved_at_ms\":1,\"used_at_ms\":1}'",
                [],
            )
            .unwrap();
        assert!(
            validate_restored(&connection).is_err(),
            "a favorite without foods"
        );
    }
}
