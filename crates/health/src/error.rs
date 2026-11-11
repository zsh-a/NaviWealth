//! Health-domain errors.

#[derive(Debug, thiserror::Error)]
pub enum HealthError {
    #[error(transparent)]
    Lifeos(#[from] lifeos::LifeosError),
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("invalid data: {0}")]
    InvalidData(String),
    #[error("metric not found: {0}")]
    MetricNotFound(String),
}

pub type Result<T> = std::result::Result<T, HealthError>;

/// Domain errors crossing the `Db::call` boundary convert into
/// `LifeosError`, so closures can `?` health failures directly.
impl From<HealthError> for lifeos::LifeosError {
    fn from(error: HealthError) -> Self {
        match error {
            HealthError::Lifeos(inner) => inner,
            HealthError::Db(inner) => inner.into(),
            HealthError::InvalidData(message) => lifeos::LifeosError::InvalidData(message),
            HealthError::MetricNotFound(id) => {
                lifeos::LifeosError::NotFound(format!("metric {id}"))
            }
        }
    }
}
