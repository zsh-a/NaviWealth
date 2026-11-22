use super::{Error, account};
use crate::account::{Account, AccountPurpose};
use navi_storage::sqlite::{Connection, Transaction, params};
use std::collections::BTreeMap;

pub const PURPOSE_SCHEMA: &str = "ALTER TABLE finance_accounts ADD COLUMN purpose TEXT
    CHECK (purpose IN ('cash','bank','wallet','brokerage','credit','loan'));";

fn validate(own: &Account, purpose: Option<AccountPurpose>) -> Result<(), Error> {
    if !own.is_cash() || purpose.is_some_and(|p| p.kind() != own.kind()) {
        return Err(Error::Invalid("account purpose"));
    }
    Ok(())
}

pub fn account_purposes(
    connection: &Connection,
) -> Result<BTreeMap<Account, AccountPurpose>, Error> {
    let mut purposes = BTreeMap::new();
    if !connection.column_exists(None, "finance_accounts", "purpose")? {
        return Ok(purposes);
    }
    let mut query = connection
        .prepare("SELECT name, purpose FROM finance_accounts WHERE purpose IS NOT NULL")?;
    let mut rows = query.query([])?;
    while let Some(row) = rows.next()? {
        let own = account(&row.get::<_, String>(0)?)?;
        let code: String = row.get(1)?;
        let purpose = AccountPurpose::ALL
            .into_iter()
            .find(|p| p.code() == code)
            .ok_or(Error::Invalid("account purpose"))?;
        validate(&own, Some(purpose))?;
        if purposes.insert(own, purpose).is_some() {
            return Err(Error::Invalid("duplicate account purpose"));
        }
    }
    Ok(purposes)
}

/// An inline editor or import draft may have proposed the same name that was
/// created while it was open. Only the creator assigns the initial purpose.
pub fn create_if_new_with_purpose(
    tx: &Transaction<'_>,
    own: &Account,
    purpose: AccountPurpose,
) -> Result<bool, Error> {
    validate(own, Some(purpose))?;
    let added = tx.execute(
        "INSERT INTO finance_accounts(name,purpose) VALUES(?1,?2) ON CONFLICT(name) DO NOTHING",
        params![own.as_str(), purpose.code()],
    )?;
    Ok(added == 1)
}

pub fn set_account_purpose(
    connection: &Connection,
    own: &Account,
    purpose: Option<AccountPurpose>,
) -> Result<(), Error> {
    validate(own, purpose)?;
    let changed = connection.execute(
        "UPDATE finance_accounts SET purpose=?2 WHERE name=?1",
        params![own.as_str(), purpose.map(AccountPurpose::code)],
    )?;
    if changed == 0 {
        return Err(Error::Missing);
    }
    Ok(())
}
