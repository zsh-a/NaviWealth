//! Shared error type. Domain crates wrap their own errors on top; anything
//! crossing the `lifeos` boundary is reported as a [`LifeosError`].

/// The sync domain a table family belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Domain {
    Finance,
    Health,
    Knowledge,
    Execution,
}

impl Domain {
    pub fn as_str(self) -> &'static str {
        match self {
            Domain::Finance => "finance",
            Domain::Health => "health",
            Domain::Knowledge => "knowledge",
            Domain::Execution => "execution",
        }
    }

    /// The row-family prefix used at the sync boundary (`fin:accounts`).
    pub fn table_prefix(self) -> &'static str {
        match self {
            Domain::Finance => "fin:",
            Domain::Health => "health:",
            Domain::Knowledge => "know:",
            Domain::Execution => "exec:",
        }
    }

    pub fn from_table(table: &str) -> Option<Self> {
        if table.starts_with("fin:") {
            Some(Domain::Finance)
        } else if table.starts_with("health:") {
            Some(Domain::Health)
        } else if table.starts_with("know:") {
            Some(Domain::Knowledge)
        } else if table.starts_with("exec:") {
            Some(Domain::Execution)
        } else {
            None
        }
    }
}

impl std::fmt::Display for Domain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum LifeosError {
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("database closed")]
    DbClosed,
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid data: {0}")]
    InvalidData(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("money error: {0}")]
    Money(#[from] crate::money::MoneyError),
    #[error("hlc error: {0}")]
    Hlc(#[from] crate::hlc::HlcError),
    #[error("key store error: {0}")]
    KeyStore(String),
    #[error("sync error: {0}")]
    Sync(String),
    #[error("sync cursor did not advance; refusing to loop")]
    SyncCursorStalled,
    #[error("auth error: {0}")]
    Auth(String),
    #[error("backup error: {0}")]
    Backup(String),
    #[error("http error: {0}")]
    Http(String),
}

pub type Result<T> = std::result::Result<T, LifeosError>;
