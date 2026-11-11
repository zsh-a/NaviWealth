//! Execution-domain errors.

#[derive(Debug, thiserror::Error)]
pub enum ExecutionError {
    #[error(transparent)]
    Lifeos(#[from] lifeos::LifeosError),
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("invalid data: {0}")]
    InvalidData(String),
    #[error("plan not found: {0}")]
    PlanNotFound(String),
    #[error("action not found: {0}")]
    ActionNotFound(String),
}

pub type Result<T> = std::result::Result<T, ExecutionError>;

/// Domain errors crossing the `Db::call` boundary convert into
/// `LifeosError`, so closures can `?` execution failures directly.
impl From<ExecutionError> for lifeos::LifeosError {
    fn from(error: ExecutionError) -> Self {
        match error {
            ExecutionError::Lifeos(inner) => inner,
            ExecutionError::Db(inner) => inner.into(),
            ExecutionError::InvalidData(message) => lifeos::LifeosError::InvalidData(message),
            ExecutionError::PlanNotFound(id) => lifeos::LifeosError::NotFound(format!("plan {id}")),
            ExecutionError::ActionNotFound(id) => {
                lifeos::LifeosError::NotFound(format!("action {id}"))
            }
        }
    }
}
