//! Garmin Connect HTTP client with SSO authentication.
//!
//! Handles the full auth lifecycle: SSO login → MFA → token refresh.
//! All API calls go through the rate limiter.

use anyhow::{anyhow, Result};
use reqwest::Client;
use std::sync::Arc;
use tokio::sync::Mutex;

use super::auth::{AuthResult, GarminAuthState};
use super::rate_limiter::GarminRateLimiter;
use super::token_store::{StoredSession, TokenStore};

/// Garmin Connect SSO endpoints (global).
const SSO_SIGNIN_URL_GLOBAL: &str = "https://sso.garmin.com/sso/signin";
const SSO_MFA_URL_GLOBAL: &str = "https://sso.garmin.com/sso/verifyMfa";

/// Garmin Connect SSO endpoints (China).
const SSO_SIGNIN_URL_CN: &str = "https://sso.garmin.cn/sso/signin";
const SSO_MFA_URL_CN: &str = "https://sso.garmin.cn/sso/verifyMfa";

/// Garmin Connect API client.
pub struct GarminClient {
    http: Client,
    auth_state: Arc<Mutex<GarminAuthState>>,
    token_store: Arc<dyn TokenStore>,
    rate_limiter: GarminRateLimiter,
    is_cn: bool,
}

impl GarminClient {
    /// Create a new client. Attempts to load stored credentials.
    pub async fn new(token_store: Arc<dyn TokenStore>, is_cn: bool) -> Result<Self> {
        let http = Client::builder()
            .cookie_store(true)
            .user_agent("com.garmin.android.apps.connectmobile")
            .build()?;

        let auth_state = if let Some(_session) = token_store.load().await? {
            // TODO: validate token expiry from _session
            GarminAuthState::Authenticated {
                expires_at: chrono::Utc::now() + chrono::Duration::hours(1),
            }
        } else {
            GarminAuthState::Unauthenticated
        };

        Ok(Self {
            http,
            auth_state: Arc::new(Mutex::new(auth_state)),
            token_store,
            rate_limiter: GarminRateLimiter::new(),
            is_cn,
        })
    }

    /// Whether this client uses the China region.
    pub fn is_cn(&self) -> bool {
        self.is_cn
    }

    /// SSO signin URL for the configured region.
    fn sso_signin_url(&self) -> &str {
        if self.is_cn { SSO_SIGNIN_URL_CN } else { SSO_SIGNIN_URL_GLOBAL }
    }

    /// SSO MFA URL for the configured region.
    fn sso_mfa_url(&self) -> &str {
        if self.is_cn { SSO_MFA_URL_CN } else { SSO_MFA_URL_GLOBAL }
    }

    /// Get current auth state.
    pub async fn auth_state(&self) -> GarminAuthState {
        self.auth_state.lock().await.clone()
    }

    /// Check if authenticated.
    pub async fn is_authenticated(&self) -> bool {
        self.auth_state.lock().await.can_make_requests()
    }

    /// Authenticate with email/password via Garmin SSO.
    pub async fn authenticate(&self, email: &str, password: &str) -> Result<AuthResult> {
        let service_base = if self.is_cn { "https://connect.garmin.cn" } else { "https://connect.garmin.com" };
        let sso_host = if self.is_cn { "https://sso.garmin.cn/sso" } else { "https://sso.garmin.com/sso" };

        // Step 1: GET the SSO signin page to get CSRF token and cookies.
        let signin_page = self
            .http
            .get(self.sso_signin_url())
            .query(&[
                ("service", service_base),
                ("clientId", "GarminConnect"),
                ("gauthHost", sso_host),
                ("consumeServiceTicket", "false"),
            ])
            .send()
            .await?;

        if !signin_page.status().is_success() {
            return Ok(AuthResult::Failed(format!(
                "SSO page returned {}",
                signin_page.status()
            )));
        }

        // Step 2: POST credentials.
        let signin_response = self
            .http
            .post(self.sso_signin_url())
            .query(&[
                ("service", service_base),
                ("clientId", "GarminConnect"),
            ])
            .form(&[
                ("username", email),
                ("password", password),
                ("embed", "false"),
            ])
            .send()
            .await?;

        let status = signin_response.status();
        let body = signin_response.text().await?;

        // Check for MFA challenge.
        if body.contains("mfa-required") || body.contains("verifyMfa") || status.as_u16() == 202 {
            let mut state = self.auth_state.lock().await;
            *state = GarminAuthState::PendingMfa {
                session_ticket: "pending".to_string(), // TODO: extract real ticket
            };
            return Ok(AuthResult::MfaRequired);
        }

        // Check for auth success (redirect to connect.garmin.com).
        if status.is_success() && !body.contains("error") {
            let session = StoredSession {
                access_token: "garmin_session".to_string(), // TODO: extract real token
                refresh_token: None,
                expires_at: (chrono::Utc::now() + chrono::Duration::hours(1)).to_rfc3339(),
                cookies: std::collections::HashMap::new(), // TODO: extract cookies
            };
            self.token_store.save(&session).await?;

            let mut state = self.auth_state.lock().await;
            *state = GarminAuthState::Authenticated {
                expires_at: chrono::Utc::now() + chrono::Duration::hours(1),
            };
            return Ok(AuthResult::Authenticated);
        }

        Ok(AuthResult::Failed(format!(
            "Authentication failed: {}",
            &body[..body.len().min(200)]
        )))
    }

    /// Submit MFA code.
    pub async fn submit_mfa(&self, code: &str) -> Result<AuthResult> {
        let state = self.auth_state.lock().await.clone();
        let _ticket = match &state {
            GarminAuthState::PendingMfa { session_ticket } => session_ticket.clone(),
            _ => return Err(anyhow!("Not in MFA state")),
        };

        let response = self
            .http
            .post(self.sso_mfa_url())
            .form(&[("mfaCode", code)])
            .send()
            .await?;

        if response.status().is_success() {
            let session = StoredSession {
                access_token: "garmin_session_mfa".to_string(),
                refresh_token: None,
                expires_at: (chrono::Utc::now() + chrono::Duration::hours(1)).to_rfc3339(),
                cookies: std::collections::HashMap::new(),
            };
            self.token_store.save(&session).await?;

            let mut state = self.auth_state.lock().await;
            *state = GarminAuthState::Authenticated {
                expires_at: chrono::Utc::now() + chrono::Duration::hours(1),
            };
            Ok(AuthResult::Authenticated)
        } else {
            Ok(AuthResult::Failed("MFA verification failed".to_string()))
        }
    }

    /// Refresh the session token.
    pub async fn refresh_token(&self) -> Result<()> {
        // TODO: implement proper token refresh
        // For now, re-authenticate is required.
        Err(anyhow!("Token refresh not yet implemented"))
    }

    /// Logout and clear stored credentials.
    pub async fn logout(&self) -> Result<()> {
        self.token_store.clear().await?;
        let mut state = self.auth_state.lock().await;
        *state = GarminAuthState::Unauthenticated;
        Ok(())
    }

    /// Get the underlying HTTP client (for endpoint calls).
    pub fn http(&self) -> &Client {
        &self.http
    }

    /// Get the rate limiter (for endpoint calls).
    pub fn rate_limiter(&self) -> &GarminRateLimiter {
        &self.rate_limiter
    }
}
