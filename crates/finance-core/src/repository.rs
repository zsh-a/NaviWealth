//! Confirmed ledger writes. All postings, metadata and newly used accounts
//! commit together; reads reject malformed journals instead of dropping rows.

use std::collections::{BTreeMap, HashSet};

use lifeos_core::sqlite::{self, Connection, params};

use crate::{
    account::{Account, AccountKind, defaults},
    import::Rules,
    journal::{Posting, Source, Transaction},
};

/// Appended as one migration by the composition root. Account names are the
/// current domain identity (`type:name`); renames update references atomically.
pub const SCHEMA: &str = "
CREATE TABLE finance_accounts (name TEXT PRIMARY KEY NOT NULL);
CREATE TABLE finance_transactions (
    id TEXT PRIMARY KEY NOT NULL CHECK(length(trim(id)) > 0),
    at TEXT NOT NULL,
    payee TEXT NOT NULL,
    note TEXT NOT NULL,
    source TEXT NOT NULL,
    source_provider TEXT,
    source_id TEXT,
    CHECK ((source_provider IS NULL) = (source_id IS NULL)),
    UNIQUE (source_provider, source_id)
);
CREATE INDEX finance_transactions_by_at ON finance_transactions(at, id);
CREATE TABLE finance_postings (
    transaction_id TEXT NOT NULL REFERENCES finance_transactions(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK(position >= 0),
    account TEXT NOT NULL REFERENCES finance_accounts(name),
    amount INTEGER NOT NULL CHECK(typeof(amount) = 'integer' AND amount != 0),
    PRIMARY KEY (transaction_id, position)
);
CREATE INDEX finance_postings_by_account ON finance_postings(account);
CREATE TABLE finance_mapping_rules (
    kind TEXT NOT NULL CHECK(kind IN ('method', 'payee')),
    provider TEXT NOT NULL,
    pattern TEXT NOT NULL,
    account TEXT NOT NULL REFERENCES finance_accounts(name),
    PRIMARY KEY (kind, provider, pattern)
);";

/// Parents before children, for atomic backup replacement.
pub const TABLES: &[(&str, &str)] = &[
    ("finance_accounts", "name"),
    (
        "finance_transactions",
        "id, at, payee, note, source, source_provider, source_id",
    ),
    (
        "finance_postings",
        "transaction_id, position, account, amount",
    ),
    ("finance_mapping_rules", "kind, provider, pattern, account"),
    (
        "finance_balance_checks",
        "id, account, day, actual, checked_at",
    ),
    ("finance_securities", "id,name,name_key,account"),
    (
        "finance_trades",
        "id,security,at,kind,quantity,price,amount,fee,cash",
    ),
    ("finance_quotes", "security,day,price"),
];

pub const BALANCE_SCHEMA: &str = "CREATE TABLE finance_balance_checks (
    id TEXT PRIMARY KEY NOT NULL,
    account TEXT NOT NULL REFERENCES finance_accounts(name),
    day TEXT NOT NULL,
    actual INTEGER NOT NULL CHECK(typeof(actual) = 'integer'),
    checked_at TEXT NOT NULL
);";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BalanceCheck {
    pub id: String,
    pub account: Account,
    pub day: jiff::civil::Date,
    pub actual: i64,
    pub checked_at: jiff::civil::DateTime,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(transparent)]
    Sql(#[from] sqlite::Error),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Journal(#[from] crate::journal::JournalError),
    #[error("invalid ledger: {0}")]
    Invalid(&'static str),
    #[error("transaction no longer exists")]
    Missing,
    #[error("an account with this name already exists")]
    AccountExists,
    #[error("the account balance changed; review the new difference")]
    BalanceChanged,
}

pub fn create_account(connection: &Connection, own: &Account) -> Result<(), Error> {
    if !own.is_cash() {
        return Err(Error::Invalid("own account required"));
    }
    if accounts(connection)?.contains(own) {
        return Err(Error::AccountExists);
    }
    connection.execute(
        "INSERT INTO finance_accounts(name) VALUES (?1)",
        [own.as_str()],
    )?;
    Ok(())
}

pub fn balance_checks(connection: &Connection) -> Result<Vec<BalanceCheck>, Error> {
    let known = accounts(connection)?;
    let mut query = connection.prepare("SELECT id, account, day, actual, checked_at FROM finance_balance_checks ORDER BY checked_at, id")?;
    let rows = query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, i64>(3)?,
            r.get::<_, String>(4)?,
        ))
    })?;
    rows.map(|r| {
        let (id, name, day, actual, at) = r?;
        let own = account(&name)?;
        if id.trim().is_empty() || !own.is_cash() || !known.contains(&own) {
            return Err(Error::Invalid("balance check"));
        }
        Ok(BalanceCheck {
            id,
            account: own,
            day: day.parse().map_err(|_| Error::Invalid("balance date"))?,
            actual,
            checked_at: at.parse().map_err(|_| Error::Invalid("check time"))?,
        })
    })
    .collect()
}

/// The expected balance is the one the owner saw. A concurrent write requires
/// a new preview, never a different adjustment hidden behind the same button.
pub fn confirm_balance(
    connection: &Connection,
    check: &BalanceCheck,
    expected: i64,
) -> Result<Option<Transaction>, Error> {
    if check.id.trim().is_empty() || !check.account.is_cash() || check.day > check.checked_at.date()
    {
        return Err(Error::Invalid("balance check"));
    }
    let tx = connection.unchecked_transaction()?;
    if !accounts(&tx)?.contains(&check.account) {
        return Err(Error::Missing);
    }
    let entries = transactions(&tx)?;
    let book = crate::journal::balance_on(&entries, &check.account, check.day);
    if book != expected {
        return Err(Error::BalanceChanged);
    }
    let difference = check
        .actual
        .checked_sub(book)
        .ok_or(Error::Invalid("balance overflow"))?;
    let has_history = entries
        .iter()
        .any(|t| t.at.date() <= check.day && t.postings.iter().any(|p| p.account == check.account));
    let entry = crate::journal::Entry {
        id: check.id.clone(),
        at: check.day.at(23, 59, 59, 999_999_999),
        payee: String::new(),
        note: String::new(),
        source: Source::BalanceCheck,
    };
    let adjustment = if difference == 0 {
        None
    } else if has_history {
        Some(crate::journal::adjustment(
            entry,
            &check.account,
            difference,
        )?)
    } else {
        Some(crate::journal::opening(entry, &check.account, difference)?)
    };
    // Insert first: replaying a confirmation cannot overwrite its posting.
    tx.execute("INSERT INTO finance_balance_checks(id,account,day,actual,checked_at) VALUES(?1,?2,?3,?4,?5)", params![check.id,check.account.as_str(),check.day.to_string(),check.actual,check.checked_at.to_string()])?;
    if let Some(t) = &adjustment {
        save_in_transaction(&tx, t)?;
    }
    tx.commit()?;
    Ok(adjustment)
}

/// Called inside the app's transaction, which also renames its draft references.
pub fn rename_account(
    tx: &sqlite::Transaction<'_>,
    old: &Account,
    new: &Account,
) -> Result<(), Error> {
    if !old.is_cash() || !new.is_cash() || old.kind() != new.kind() {
        return Err(Error::Invalid("account type cannot change"));
    }
    if old == new {
        return Ok(());
    }
    let known = accounts(tx)?;
    if !known.contains(old) {
        return Err(Error::Missing);
    }
    if known.contains(new) {
        return Err(Error::AccountExists);
    }
    keep_account(tx, new)?;
    for (table, column) in [
        ("finance_postings", "account"),
        ("finance_mapping_rules", "account"),
        ("finance_balance_checks", "account"),
        ("finance_trades", "cash"),
    ] {
        tx.execute(
            &format!("UPDATE {table} SET {column}=?1 WHERE {column}=?2"),
            params![new.as_str(), old.as_str()],
        )?;
    }
    tx.execute("DELETE FROM finance_accounts WHERE name=?1", [old.as_str()])?;
    Ok(())
}

fn account(text: &str) -> Result<Account, Error> {
    let account = Account::parse(text).map_err(|_| Error::Invalid("account"))?;
    if account.as_str() != text {
        return Err(Error::Invalid("noncanonical account"));
    }
    Ok(account)
}

fn keep_account(connection: &Connection, account: &Account) -> Result<(), Error> {
    connection.execute(
        "INSERT INTO finance_accounts (name) VALUES (?1) ON CONFLICT(name) DO NOTHING",
        [account.as_str()],
    )?;
    Ok(())
}

pub fn ensure_defaults(connection: &Connection) -> Result<(), Error> {
    let tx = connection.unchecked_transaction()?;
    for account in defaults::all() {
        keep_account(&tx, &account)?;
    }
    tx.commit()?;
    Ok(())
}

pub fn accounts(connection: &Connection) -> Result<Vec<Account>, Error> {
    let mut query = connection.prepare("SELECT name FROM finance_accounts ORDER BY name")?;
    let mut seen = HashSet::new();
    let mut accounts = Vec::new();
    for row in query.query_map([], |r| r.get::<_, String>(0))? {
        let value = account(&row?)?;
        if !seen.insert(value.clone()) {
            return Err(Error::Invalid("duplicate account"));
        }
        accounts.push(value);
    }
    Ok(accounts)
}

fn validate_entry(entry: &Transaction) -> Result<(), Error> {
    entry.validate()?;
    if entry.id.trim().is_empty() || entry.id.chars().any(char::is_control) {
        return Err(Error::Invalid("transaction id"));
    }
    if let Source::Statement { provider, id } = &entry.source
        && (provider.trim().is_empty() || id.trim().is_empty())
    {
        return Err(Error::Invalid("statement identity"));
    }
    Ok(())
}

/// Validates before touching SQLite. Editing replaces the postings as one unit.
pub fn save(connection: &Connection, entry: &Transaction) -> Result<(), Error> {
    let tx = connection.unchecked_transaction()?;
    save_in_transaction(&tx, entry)?;
    tx.commit()?;
    Ok(())
}

/// Joins the host's draft-confirmation transaction so the ledger write and
/// removal of its draft either both happen or neither does.
pub fn save_in_transaction(tx: &sqlite::Transaction<'_>, entry: &Transaction) -> Result<(), Error> {
    if matches!(entry.source, Source::Investment { .. })
        || entry.id.starts_with("trade:")
        || entry.postings.iter().any(|p| p.account.is_holding())
    {
        return Err(Error::Invalid(
            "investment entries must be changed through trades",
        ));
    }
    write_entry(tx, entry)
}

pub(crate) fn save_investment(
    tx: &sqlite::Transaction<'_>,
    entry: &Transaction,
) -> Result<(), Error> {
    if !matches!(&entry.source,Source::Investment {trade_id} if entry.id == format!("trade:{trade_id}"))
    {
        return Err(Error::Invalid("investment identity"));
    }
    write_entry(tx, entry)
}

fn write_entry(tx: &sqlite::Transaction<'_>, entry: &Transaction) -> Result<(), Error> {
    validate_entry(entry)?;
    for posting in &entry.postings {
        keep_account(tx, &posting.account)?;
    }
    let (provider, source_id) = match &entry.source {
        Source::Statement { provider, id } => (Some(provider.as_str()), Some(id.as_str())),
        _ => (None, None),
    };
    tx.execute(
        "INSERT INTO finance_transactions (id, at, payee, note, source, source_provider, source_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
         ON CONFLICT(id) DO UPDATE SET at=excluded.at, payee=excluded.payee, note=excluded.note,
         source=excluded.source, source_provider=excluded.source_provider, source_id=excluded.source_id",
        params![entry.id, entry.at.to_string(), entry.payee, entry.note, serde_json::to_string(&entry.source)?, provider, source_id],
    )?;
    tx.execute(
        "DELETE FROM finance_postings WHERE transaction_id=?1",
        [&entry.id],
    )?;
    for (position, posting) in entry.postings.iter().enumerate() {
        tx.execute(
            "INSERT INTO finance_postings (transaction_id, position, account, amount) VALUES (?1, ?2, ?3, ?4)",
            params![entry.id, position as i64, posting.account.as_str(), posting.amount],
        )?;
    }
    Ok(())
}

/// Reads every entry, ordered by its civil date/time. No bad row is skipped.
pub fn transactions(connection: &Connection) -> Result<Vec<Transaction>, Error> {
    let known: HashSet<Account> = accounts(connection)?.into_iter().collect();
    let mut postings: BTreeMap<String, Vec<Posting>> = BTreeMap::new();
    let mut query = connection.prepare("SELECT transaction_id, position, account, amount FROM finance_postings ORDER BY transaction_id, position")?;
    let rows = query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, i64>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, i64>(3)?,
        ))
    })?;
    for row in rows {
        let (id, position, name, amount) = row?;
        let account = account(&name)?;
        if !known.contains(&account) {
            return Err(Error::Invalid("missing posting account"));
        }
        let list = postings.entry(id).or_default();
        if position != list.len() as i64 {
            return Err(Error::Invalid("posting order"));
        }
        list.push(Posting { account, amount });
    }
    let mut query = connection.prepare("SELECT id, at, payee, note, source, source_provider, source_id FROM finance_transactions ORDER BY at, id")?;
    let rows = query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
            r.get::<_, String>(4)?,
            r.get::<_, Option<String>>(5)?,
            r.get::<_, Option<String>>(6)?,
        ))
    })?;
    let mut result = Vec::new();
    let mut identities = HashSet::new();
    for row in rows {
        let (id, at, payee, note, source, provider, source_id) = row?;
        let source: Source = serde_json::from_str(&source)?;
        match &source {
            Source::Statement { provider: p, id: i } => {
                if provider.as_ref() != Some(p)
                    || source_id.as_ref() != Some(i)
                    || !identities.insert((p.clone(), i.clone()))
                {
                    return Err(Error::Invalid("statement identity mismatch or duplicate"));
                }
            }
            _ if provider.is_some() || source_id.is_some() => {
                return Err(Error::Invalid("unexpected statement identity"));
            }
            _ => {}
        }
        let entry = Transaction {
            postings: postings.remove(&id).unwrap_or_default(),
            id,
            at: at.parse().map_err(|_| Error::Invalid("transaction date"))?,
            payee,
            note,
            source,
        };
        validate_entry(&entry)?;
        result.push(entry);
    }
    if !postings.is_empty() {
        return Err(Error::Invalid("orphan postings"));
    }
    Ok(result)
}

pub fn remove(connection: &Connection, id: &str) -> Result<Transaction, Error> {
    let tx = connection.unchecked_transaction()?;
    let entry = transactions(&tx)?
        .into_iter()
        .find(|t| t.id == id)
        .ok_or(Error::Missing)?;
    if matches!(entry.source, Source::Investment { .. }) {
        return Err(Error::Invalid("delete the trade instead"));
    }
    // Explicit deletion also works for test/host connections without FK enforcement.
    tx.execute("DELETE FROM finance_postings WHERE transaction_id=?1", [id])?;
    tx.execute("DELETE FROM finance_transactions WHERE id=?1", [id])?;
    tx.commit()?;
    Ok(entry)
}

pub fn rules(connection: &Connection) -> Result<Rules, Error> {
    let known: HashSet<Account> = accounts(connection)?.into_iter().collect();
    let mut result = Rules::default();
    let mut seen = HashSet::new();
    let mut query =
        connection.prepare("SELECT kind, provider, pattern, account FROM finance_mapping_rules")?;
    let rows = query.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
            r.get::<_, String>(3)?,
        ))
    })?;
    for row in rows {
        let (kind, provider, pattern, name) = row?;
        let account = account(&name)?;
        if !known.contains(&account)
            || !seen.insert((kind.clone(), provider.clone(), pattern.clone()))
        {
            return Err(Error::Invalid("mapping account or duplicate"));
        }
        match kind.as_str() {
            "method" if account.is_cash() && !provider.is_empty() => {
                result
                    .methods
                    .entry(provider)
                    .or_default()
                    .insert(pattern, account);
            }
            "payee"
                if provider.is_empty()
                    && matches!(account.kind(), AccountKind::Expenses | AccountKind::Income) =>
            {
                result.payees.insert(pattern, account);
            }
            _ => return Err(Error::Invalid("mapping kind")),
        }
    }
    Ok(result)
}

/// Replaces the confirmed mapping rules in one transaction.
pub fn save_rules(connection: &Connection, rules: &Rules) -> Result<(), Error> {
    let tx = connection.unchecked_transaction()?;
    tx.execute("DELETE FROM finance_mapping_rules", [])?;
    for (provider, methods) in &rules.methods {
        for (pattern, account) in methods {
            if provider.is_empty() || !account.is_cash() {
                return Err(Error::Invalid("payment method account"));
            }
            keep_account(&tx, account)?;
            tx.execute(
                "INSERT INTO finance_mapping_rules VALUES ('method', ?1, ?2, ?3)",
                params![provider, pattern, account.as_str()],
            )?;
        }
    }
    for (payee, account) in &rules.payees {
        if !matches!(account.kind(), AccountKind::Expenses | AccountKind::Income) {
            return Err(Error::Invalid("payee category"));
        }
        keep_account(&tx, account)?;
        tx.execute(
            "INSERT INTO finance_mapping_rules VALUES ('payee', '', ?1, ?2)",
            params![payee, account.as_str()],
        )?;
    }
    tx.commit()?;
    Ok(())
}

/// Validates imported databases independently of their declared constraints.
pub fn validate(connection: &Connection) -> Result<(), Error> {
    transactions(connection)?;
    rules(connection)?;
    balance_checks(connection)?;
    crate::holdings::store::validate(connection)
        .map_err(|_| Error::Invalid("holdings do not match the journal"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::journal::{self, Entry};

    fn entry(id: &str, amount: i64) -> Transaction {
        journal::spend(
            Entry {
                id: id.into(),
                at: jiff::civil::date(2026, 11, 14).at(12, 30, 0, 0),
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
    fn saves_edits_and_deletes_survive_reopen_with_exact_minor_units() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("ledger.sqlite");
        let db = lifeos_core::open(
            &path,
            &[SCHEMA, BALANCE_SCHEMA, crate::holdings::store::SCHEMA],
        )
        .unwrap();
        ensure_defaults(&db).unwrap();
        save(&db, &entry("one", 3151)).unwrap();
        save(&db, &entry("two", 1)).unwrap();
        save(&db, &entry("one", 9999)).unwrap();
        drop(db);
        let db = lifeos_core::open(
            &path,
            &[SCHEMA, BALANCE_SCHEMA, crate::holdings::store::SCHEMA],
        )
        .unwrap();
        let rows = transactions(&db).unwrap();
        assert_eq!(rows, [entry("one", 9999), entry("two", 1)]);
        assert_eq!(journal::balances(&rows)[&defaults::expense("餐饮")], 10000);
        assert_eq!(remove(&db, "one").unwrap(), entry("one", 9999));
        assert_eq!(transactions(&db).unwrap(), [entry("two", 1)]);
        assert_eq!(
            db.query_row("SELECT count(*) FROM finance_postings", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            2
        );
    }

    #[test]
    fn invalid_or_failed_edits_leave_original_postings_and_accounts_intact() {
        let db =
            lifeos_core::memory(&[SCHEMA, BALANCE_SCHEMA, crate::holdings::store::SCHEMA]).unwrap();
        save(&db, &entry("one", 3150)).unwrap();
        let mut invalid = entry("one", 5000);
        invalid.postings[0].amount = 5001;
        assert!(save(&db, &invalid).is_err());
        db.execute_batch("CREATE TRIGGER fail_second BEFORE INSERT ON finance_postings WHEN NEW.position = 1 BEGIN SELECT RAISE(ABORT, 'simulated full disk'); END;").unwrap();
        let mut changed = entry("one", 5000);
        changed.postings[1].account = Account::parse("资产:新卡").unwrap();
        assert!(save(&db, &changed).is_err());
        assert_eq!(transactions(&db).unwrap(), [entry("one", 3150)]);
        assert!(!accounts(&db).unwrap().iter().any(|a| a.name() == "新卡"));
    }

    #[test]
    fn statement_identity_is_unique_across_transaction_ids_and_rules_round_trip() {
        let db =
            lifeos_core::memory(&[SCHEMA, BALANCE_SCHEMA, crate::holdings::store::SCHEMA]).unwrap();
        let mut one = entry("one", 3150);
        one.source = Source::Statement {
            provider: "alipay".into(),
            id: "ref1".into(),
        };
        save(&db, &one).unwrap();
        let mut duplicate = one.clone();
        duplicate.id = "two".into();
        assert!(save(&db, &duplicate).is_err());
        assert_eq!(transactions(&db).unwrap(), [one]);
        let mut mapping = Rules::default();
        mapping.remember_method(
            crate::statement::Provider::Alipay,
            "余额",
            Account::parse("资产:支付宝余额").unwrap(),
        );
        mapping.remember_payee("Lunch", defaults::expense("餐饮"));
        save_rules(&db, &mapping).unwrap();
        assert_eq!(rules(&db).unwrap(), mapping);
        let mut invalid = mapping.clone();
        invalid
            .payees
            .insert("Bad".into(), Account::parse("资产:现金").unwrap());
        assert!(save_rules(&db, &invalid).is_err());
        assert_eq!(rules(&db).unwrap(), mapping);
    }

    #[test]
    fn malformed_balances_references_and_source_metadata_are_rejected() {
        let db =
            lifeos_core::memory(&[SCHEMA, BALANCE_SCHEMA, crate::holdings::store::SCHEMA]).unwrap();
        save(&db, &entry("one", 3150)).unwrap();
        db.execute(
            "UPDATE finance_postings SET amount=3149 WHERE position=0",
            [],
        )
        .unwrap();
        assert!(validate(&db).is_err());
        save(&db, &entry("one", 3150)).unwrap();
        db.execute_batch(
            "PRAGMA foreign_keys=OFF; DELETE FROM finance_accounts WHERE name='资产:现金';",
        )
        .unwrap();
        assert!(validate(&db).is_err());
        save(&db, &entry("one", 3150)).unwrap();
        db.execute(
            "UPDATE finance_transactions SET source_provider='alipay', source_id='fake'",
            [],
        )
        .unwrap();
        assert!(validate(&db).is_err());
    }
}
