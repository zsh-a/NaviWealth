//! The domain: plain Rust that knows nothing of NSH, tested without an
//! engine. Meals and their nutrients, the bundled catalog, the model
//! account, what is asked of a vision model and how its answer is read.

pub mod account;
pub mod backup;
pub mod favorite;
pub mod format;
pub mod meal;
pub mod pending;
pub mod review;
pub mod weight;
pub use health_core::{catalog, garmin, nutrition, recognition};

/// Why a provider gave no usable reply.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProviderError {
    /// 401: the key is wrong or revoked.
    Unauthorized,
    /// 403: the key may not use this model or feature.
    Forbidden,
    /// 404: the base URL or the model does not exist.
    NotFound,
    /// 429: too many requests, or the quota is used up.
    RateLimited,
    /// 503 / 529: the provider is overloaded.
    Overloaded,
    /// Another 5xx.
    Server(u16),
    /// The request was refused as invalid (400, 413, 422 …), with the
    /// provider's message: often a model that takes no images.
    Rejected { status: u16, message: String },
    /// A success whose body is not the API's shape.
    Decode,
}

/// Why recognizing a photo failed, as the review page explains it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VisionFailure {
    /// No connection, or the request broke off; the platform's words.
    Offline(String),
    /// No reply in time.
    Timeout,
    /// The provider answered with an error.
    Provider(ProviderError),
    /// The answer was cut off by its length limit.
    Truncated,
    /// The model declined.
    Refused,
    /// The answer was not the JSON the app asked for.
    Unreadable,
    /// The photo could not be prepared (an unsupported format).
    Photo,
}

impl VisionFailure {
    /// Whether trying again as it is may work (as opposed to changing the
    /// account or the photo first).
    pub fn is_retryable(&self) -> bool {
        match self {
            VisionFailure::Offline(_)
            | VisionFailure::Timeout
            | VisionFailure::Truncated
            | VisionFailure::Unreadable => true,
            VisionFailure::Provider(error) => matches!(
                error,
                ProviderError::RateLimited | ProviderError::Overloaded | ProviderError::Server(_)
            ),
            VisionFailure::Refused | VisionFailure::Photo => false,
        }
    }

    /// Whether the account's settings are the likely cause.
    pub fn points_to_settings(&self) -> bool {
        matches!(
            self,
            VisionFailure::Provider(
                ProviderError::Unauthorized
                    | ProviderError::Forbidden
                    | ProviderError::NotFound
                    | ProviderError::Rejected { .. }
            )
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn failures_suggest_the_right_recovery() {
        assert!(VisionFailure::Timeout.is_retryable());
        assert!(VisionFailure::Provider(ProviderError::Overloaded).is_retryable());
        assert!(!VisionFailure::Provider(ProviderError::Unauthorized).is_retryable());
        assert!(VisionFailure::Provider(ProviderError::Unauthorized).points_to_settings());
        assert!(!VisionFailure::Offline("down".into()).points_to_settings());
        assert!(!VisionFailure::Refused.is_retryable());
    }
}
