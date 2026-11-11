//! Finance domain: ledger (Beancount-style double entry), accounts,
//! builders and repositories. Domain code never imports other domains and
//! reaches the database only through repositories over `&mut Connection`.

pub mod builders;
pub use repos::daily_repository as daily;
pub mod error;
pub mod fx;
pub mod invariants;
pub mod models;
pub mod repos;
pub mod system_accounts;
pub mod tables;

pub use error::{FinanceError, Result};
pub use tables::FINANCE_SCHEMA_VERSION;
