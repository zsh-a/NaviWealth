//! Finance-domain errors.

use crate::invariants::BalanceReport;

#[derive(Debug, thiserror::Error)]
pub enum FinanceError {
    #[error(transparent)]
    Lifeos(#[from] lifeos::LifeosError),
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("invalid data: {0}")]
    InvalidData(String),
    #[error("journal entry is unbalanced")]
    Unbalanced(BalanceReport),
    #[error("account not found: {0}")]
    AccountNotFound(String),
    #[error("category not found: {0}")]
    CategoryNotFound(String),
}

pub type Result<T> = std::result::Result<T, FinanceError>;

/// Domain errors crossing the `Db::call` boundary convert into
/// `LifeosError`, so closures can `?` finance failures directly.
impl From<FinanceError> for lifeos::LifeosError {
    fn from(error: FinanceError) -> Self {
        match error {
            FinanceError::Lifeos(inner) => inner,
            FinanceError::Db(inner) => inner.into(),
            FinanceError::InvalidData(message) => lifeos::LifeosError::InvalidData(message),
            FinanceError::AccountNotFound(id) => {
                lifeos::LifeosError::NotFound(format!("account {id}"))
            }
            FinanceError::CategoryNotFound(id) => {
                lifeos::LifeosError::NotFound(format!("category {id}"))
            }
            FinanceError::Unbalanced(report) => lifeos::LifeosError::InvalidData(format!(
                "journal entry unbalanced: {}",
                report
                    .problems
                    .iter()
                    .map(|p| p.message.as_str())
                    .collect::<Vec<_>>()
                    .join("; ")
            )),
        }
    }
}
