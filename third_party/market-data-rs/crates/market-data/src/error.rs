use serde::{Deserialize, Serialize};

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    InvalidRequest,
    Unsupported,
    Network,
    Timeout,
    RateLimited,
    CircuitOpen,
    Http,
    Parse,
    NoData,
    Incomplete,
    Cache,
    Unavailable,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Error {
    pub kind: ErrorKind,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub http_status: Option<u16>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub causes: Vec<Error>,
}

impl Error {
    pub fn new(kind: ErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
            provider: None,
            http_status: None,
            causes: vec![],
        }
    }
    pub fn at(mut self, provider: &str) -> Self {
        self.provider = Some(provider.into());
        self
    }
    pub fn with_http_status(mut self, status: u16) -> Self {
        self.http_status = Some(status);
        self
    }
    pub fn unavailable(causes: Vec<Error>) -> Self {
        Self {
            causes,
            ..Self::new(ErrorKind::Unavailable, "all eligible providers failed")
        }
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}: {}", self.kind, self.message)
    }
}
impl std::error::Error for Error {}
