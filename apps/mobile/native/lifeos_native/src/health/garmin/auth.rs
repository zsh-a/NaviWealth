//! Garmin Connect authentication state machine.
//!
//! Models the SSO flow: Unauthenticated → PendingMfa → Authenticated
//! (or Error at any step). DI tokens are refreshed shortly before expiry.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Garmin Connect SSO auth states.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum GarminAuthState {
    /// No credentials stored.
    Unauthenticated,
    /// SSO returned an MFA challenge.
    PendingMfa {
        /// Opaque session ticket from the SSO flow.
        session_ticket: String,
    },
    /// Authenticated and token is valid.
    Authenticated { expires_at: DateTime<Utc> },
    /// Legacy wire variant. The client no longer emits this state.
    Refreshing,
    /// Terminal error (wrong credentials, account locked, etc.).
    Error { message: String },
}

/// Result of an authentication attempt.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AuthResult {
    /// Successfully authenticated.
    Authenticated,
    /// MFA code required — caller should prompt the user.
    MfaRequired,
    /// Authentication failed.
    Failed(String),
}

impl GarminAuthState {
    /// Whether the client can make API calls in this state.
    pub fn can_make_requests(&self) -> bool {
        matches!(self, GarminAuthState::Authenticated { .. })
    }

    /// Whether the access token is inside the proactive refresh window.
    pub fn needs_refresh(&self) -> bool {
        if let GarminAuthState::Authenticated { expires_at } = self {
            *expires_at <= Utc::now() + chrono::Duration::minutes(5)
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unauthenticated_cannot_make_requests() {
        assert!(!GarminAuthState::Unauthenticated.can_make_requests());
    }

    #[test]
    fn pending_mfa_cannot_make_requests() {
        assert!(
            !GarminAuthState::PendingMfa {
                session_ticket: "ticket".into()
            }
            .can_make_requests()
        );
    }

    #[test]
    fn authenticated_can_make_requests() {
        assert!(
            GarminAuthState::Authenticated {
                expires_at: Utc::now() + chrono::Duration::hours(1)
            }
            .can_make_requests()
        );
    }

    #[test]
    fn legacy_refreshing_cannot_make_requests() {
        assert!(!GarminAuthState::Refreshing.can_make_requests());
    }

    #[test]
    fn error_cannot_make_requests() {
        assert!(
            !GarminAuthState::Error {
                message: "fail".into()
            }
            .can_make_requests()
        );
    }

    #[test]
    fn authenticated_not_expired_no_refresh() {
        let state = GarminAuthState::Authenticated {
            expires_at: Utc::now() + chrono::Duration::hours(1),
        };
        assert!(!state.needs_refresh());
    }

    #[test]
    fn authenticated_near_expiry_needs_refresh() {
        let state = GarminAuthState::Authenticated {
            expires_at: Utc::now() + chrono::Duration::minutes(2),
        };
        assert!(state.needs_refresh());
    }

    #[test]
    fn authenticated_expired_needs_reconnect() {
        let state = GarminAuthState::Authenticated {
            expires_at: Utc::now() - chrono::Duration::minutes(1),
        };
        assert!(state.needs_refresh());
    }

    #[test]
    fn non_authenticated_never_needs_refresh() {
        assert!(!GarminAuthState::Unauthenticated.needs_refresh());
        assert!(
            !GarminAuthState::PendingMfa {
                session_ticket: "t".into()
            }
            .needs_refresh()
        );
        assert!(!GarminAuthState::Refreshing.needs_refresh());
    }

    #[test]
    fn auth_result_serialization_roundtrip() {
        let cases = vec![
            AuthResult::Authenticated,
            AuthResult::MfaRequired,
            AuthResult::Failed("bad password".into()),
        ];
        for case in cases {
            let json = serde_json::to_string(&case).unwrap();
            let back: AuthResult = serde_json::from_str(&json).unwrap();
            // Verify round-trip produces same Debug output.
            assert_eq!(format!("{:?}", case), format!("{:?}", back));
        }
    }
}
