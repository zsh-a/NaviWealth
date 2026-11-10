//! Base-currency and small finance-scoped settings (device KV; the
//! backend knows nothing about these).

use lifeos::db::settings;
use rusqlite::Connection;

use crate::error::Result;

pub const BASE_CURRENCY_KEY: &str = "finance.base_currency";

pub fn base_currency(conn: &Connection) -> Result<String> {
    Ok(settings::get_setting(conn, BASE_CURRENCY_KEY)?.unwrap_or_else(|| "CNY".to_owned()))
}

pub fn set_base_currency(conn: &Connection, currency: &str) -> Result<()> {
    lifeos::money::Currency::new(currency)
        .map_err(|e| crate::error::FinanceError::InvalidData(e.to_string()))?;
    settings::set_setting(conn, BASE_CURRENCY_KEY, currency)?;
    Ok(())
}
