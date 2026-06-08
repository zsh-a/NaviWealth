//! Garmin Connect authentication state machine.
//!
//! Models the SSO flow: Unauthenticated → PendingMfa → Authenticated
//! → Refreshing → Authenticated (or Error at any step).

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
    Authenticated {
        expires_at: DateTime<Utc>,
    },
    /// Token expired, refresh in progress.
    Refreshing,
    /// Terminal error (wrong credentials, account locked, etc.).
    Error {
        message: String,
    },
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

    /// Whether the token needs refreshing.
    pub fn needs_refresh(&self) -> bool {
        if let GarminAuthState::Authenticated { expires_at } = self {
            // Refresh 5 minutes before expiry.
            *expires_at - chrono::Duration::minutes(5) < Utc::now()
        } else {
            false
        }
    }
}
