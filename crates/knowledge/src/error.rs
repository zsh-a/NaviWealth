//! Knowledge-domain errors.

#[derive(Debug, thiserror::Error)]
pub enum KnowledgeError {
    #[error(transparent)]
    Lifeos(#[from] lifeos::LifeosError),
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("invalid data: {0}")]
    InvalidData(String),
    #[error("note not found: {0}")]
    NoteNotFound(String),
    #[error("decision not found: {0}")]
    DecisionNotFound(String),
}

pub type Result<T> = std::result::Result<T, KnowledgeError>;

/// Domain errors crossing the `Db::call` boundary convert into
/// `LifeosError`, so closures can `?` knowledge failures directly.
impl From<KnowledgeError> for lifeos::LifeosError {
    fn from(error: KnowledgeError) -> Self {
        match error {
            KnowledgeError::Lifeos(inner) => inner,
            KnowledgeError::Db(inner) => inner.into(),
            KnowledgeError::InvalidData(message) => lifeos::LifeosError::InvalidData(message),
            KnowledgeError::NoteNotFound(id) => lifeos::LifeosError::NotFound(format!("note {id}")),
            KnowledgeError::DecisionNotFound(id) => {
                lifeos::LifeosError::NotFound(format!("decision {id}"))
            }
        }
    }
}
