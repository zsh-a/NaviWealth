//! Garmin Connect HTTP client with SSO authentication.
//!
//! Implements the mobile SSO login flow (strategy 1/2 from
//! python-garminconnect) and DI token exchange.
//!
//! Flow:
//!   1. POST credentials to `/mobile/api/login` → get `serviceTicketId`
//!   2. POST ticket to DI token endpoint → get `access_token` + `refresh_token`
//!   3. API calls use `Authorization: Bearer {access_token}`

use anyhow::{anyhow, Result};
use base64::Engine;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;

use super::auth::{AuthResult, GarminAuthState};
use super::rate_limiter::GarminRateLimiter;
use super::token_store::{StoredSession, TokenStore};

/// Garmin SSO mobile login endpoint.
const MOBILE_LOGIN_PATH: &str = "/mobile/api/login";
/// DI token exchange endpoint.
const DI_TOKEN_PATH: &str = "/di-oauth2-service/oauth/token";
/// DI grant type for service tickets.
const DI_GRANT_TYPE: &str =
    "https://connectapi.garmin.com/di-oauth2-service/oauth/grant/service_ticket";
/// DI client IDs to try in order.
const DI_CLIENT_IDS: &[&str] = &[
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
    "GARMIN_CONNECT_MOBILE_ANDROID_DI",
    "GARMIN_CONNECT_MOBILE_IOS_DI",
];
/// Mobile iOS service URL template.
const MOBILE_SERVICE_URL_TEMPLATE: &str = "https://mobile.integration.{domain}/gcm/ios";
/// Mobile login client ID.
const MOBILE_CLIENT_ID: &str = "GCM_IOS_DARK";
/// Mobile login User-Agent.
const MOBILE_USER_AGENT: &str = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148";
/// Native API User-Agent.
const NATIVE_USER_AGENT: &str = "GCM-Android-5.23";
/// Native X-Garmin-User-Agent.
const NATIVE_X_GARMIN_UA: &str = "com.garmin.android.apps.connectmobile/5.23; ; Google/sdk_gphone64_arm64/google; Android/33; Dalvik/2.1.0";

/// Stored DI token session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiSession {
    pub access_token: String,
    pub refresh_token: String,
    pub client_id: String,
    /// ISO 8601 UTC expiry.
    pub expires_at: String,
}

/// MFA session state (saved between login and MFA submission).
#[derive(Debug, Clone)]
struct MfaState {
    /// "mobile" or "portal"
    flow_path: String,
    /// Query params from the login request.
    login_params: String,
}

/// Garmin Connect API client.
///
/// All mutable state is behind `Arc<Mutex<>>` so the client is cheaply
/// cloneable — the clone shares auth state, token store, and DI session
/// with the original. This lets `GarminProvider` hold its own handle
/// without duplicating HTTP connections or auth state.
pub struct GarminClient {
    http: Client,
    auth_state: Arc<Mutex<GarminAuthState>>,
    token_store: Arc<dyn TokenStore>,
    rate_limiter: GarminRateLimiter,
    is_cn: bool,
    domain: String,
    di_session: Arc<Mutex<Option<DiSession>>>,
    mfa_state: Arc<Mutex<Option<MfaState>>>,
}

impl Clone for GarminClient {
    fn clone(&self) -> Self {
        Self {
            http: self.http.clone(),
            auth_state: Arc::clone(&self.auth_state),
            token_store: Arc::clone(&self.token_store),
            rate_limiter: self.rate_limiter.clone(),
            is_cn: self.is_cn,
            domain: self.domain.clone(),
            di_session: Arc::clone(&self.di_session),
            mfa_state: Arc::clone(&self.mfa_state),
        }
    }
}

impl GarminClient {
    /// Create a new client. Attempts to load stored credentials.
    pub async fn new(token_store: Arc<dyn TokenStore>, is_cn: bool) -> Result<Self> {
        let domain = if is_cn { "garmin.cn" } else { "garmin.com" };
        let http = Client::builder()
            .cookie_store(true)
            .redirect(reqwest::redirect::Policy::none())
            .timeout(std::time::Duration::from_secs(30))
            .build()?;

        // Try to restore DI session from token store.
        let stored = token_store.load().await?;
        let (auth_state, di_session) = if let Some(session) = stored {
            let di = DiSession {
                access_token: session.access_token.clone(),
                refresh_token: session.refresh_token.unwrap_or_default(),
                client_id: session
                    .client_id
                    .unwrap_or_else(|| "GARMIN_CONNECT_MOBILE_ANDROID_DI".to_string()),
                expires_at: session.expires_at.clone(),
            };
            let auth_state = match parse_session_expiry(&session.expires_at) {
                Some(expires_at) if expires_at > chrono::Utc::now() => {
                    GarminAuthState::Authenticated { expires_at }
                }
                _ => GarminAuthState::Error {
                    message: "DI token expired".to_string(),
                },
            };
            (auth_state, Some(di))
        } else {
            (GarminAuthState::Unauthenticated, None)
        };

        Ok(Self {
            http,
            auth_state: Arc::new(Mutex::new(auth_state)),
            token_store,
            rate_limiter: GarminRateLimiter::new(),
            is_cn,
            domain: domain.to_string(),
            di_session: Arc::new(Mutex::new(di_session)),
            mfa_state: Arc::new(Mutex::new(None)),
        })
    }

    pub fn is_cn(&self) -> bool {
        self.is_cn
    }

    fn sso_base(&self) -> String {
        format!("https://sso.{}", self.domain)
    }

    fn diauth_base(&self) -> String {
        format!("https://diauth.{}", self.domain)
    }

    fn mobile_service_url(&self) -> String {
        MOBILE_SERVICE_URL_TEMPLATE.replace("{domain}", &self.domain)
    }

    // -----------------------------------------------------------------------
    // Authentication
    // -----------------------------------------------------------------------

    /// Authenticate via mobile SSO flow.
    pub async fn authenticate(&self, email: &str, password: &str) -> Result<AuthResult> {
        let service_url = self.mobile_service_url();
        let login_url = format!(
            "{}{}?clientId={}&locale=en-US&service={}",
            self.sso_base(),
            MOBILE_LOGIN_PATH,
            MOBILE_CLIENT_ID,
            service_url,
        );

        let login_body = serde_json::json!({
            "username": email,
            "password": password,
            "rememberMe": true,
            "captchaToken": "",
        });

        let response = self
            .http
            .post(&login_url)
            .header("User-Agent", MOBILE_USER_AGENT)
            .header("Accept", "application/json, text/plain, */*")
            .header("Content-Type", "application/json")
            .header("Origin", self.sso_base())
            .json(&login_body)
            .send()
            .await?;

        let status = response.status();
        let body: serde_json::Value = response.json().await?;

        let status_type = body
            .get("responseStatus")
            .and_then(|s| s.get("type"))
            .and_then(|t| t.as_str())
            .unwrap_or("");

        match status_type {
            "SUCCESSFUL" => {
                let ticket = body
                    .get("serviceTicketId")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| anyhow!("login succeeded but no serviceTicketId"))?;

                self.exchange_service_ticket(ticket, &service_url).await?;
                self.save_session().await?;

                let mut state = self.auth_state.lock().await;
                *state = GarminAuthState::Authenticated {
                    expires_at: chrono::Utc::now() + chrono::Duration::hours(1),
                };
                Ok(AuthResult::Authenticated)
            }
            "MFA_REQUIRED" => {
                let mut mfa = self.mfa_state.lock().await;
                *mfa = Some(MfaState {
                    flow_path: "mobile".to_string(),
                    login_params: format!(
                        "clientId={}&locale=en-US&service={}",
                        MOBILE_CLIENT_ID, service_url,
                    ),
                });
                let mut state = self.auth_state.lock().await;
                *state = GarminAuthState::PendingMfa {
                    session_ticket: "mfa_required".to_string(),
                };
                Ok(AuthResult::MfaRequired)
            }
            "INVALID_USERNAME_PASSWORD" => Ok(AuthResult::Failed(
                "Invalid username or password".to_string(),
            )),
            "CAPTCHA_REQUIRED" => Ok(AuthResult::Failed(
                "CAPTCHA required — try again later".to_string(),
            )),
            _ => Ok(AuthResult::Failed(format!(
                "Unexpected login response ({}): {}",
                status,
                serde_json::to_string(&body).unwrap_or_default()
            ))),
        }
    }

    /// Submit MFA code.
    pub async fn submit_mfa(&self, code: &str) -> Result<AuthResult> {
        let mfa = self.mfa_state.lock().await.clone();
        let mfa = mfa.ok_or_else(|| anyhow!("No MFA session — call authenticate first"))?;

        let url = format!(
            "{}/{}/api/mfa/verifyCode?{}",
            self.sso_base(),
            mfa.flow_path,
            mfa.login_params,
        );

        let body = serde_json::json!({
            "mfaMethod": "email",
            "mfaVerificationCode": code,
            "rememberMyBrowser": true,
            "reconsentList": [],
            "mfaSetup": false,
        });

        let response = self
            .http
            .post(&url)
            .header("User-Agent", MOBILE_USER_AGENT)
            .header("Accept", "application/json, text/plain, */*")
            .header("Content-Type", "application/json")
            .header("Origin", self.sso_base())
            .json(&body)
            .send()
            .await?;

        let body: serde_json::Value = response.json().await?;
        let status_type = body
            .get("responseStatus")
            .and_then(|s| s.get("type"))
            .and_then(|t| t.as_str())
            .unwrap_or("");

        match status_type {
            "SUCCESSFUL" => {
                let ticket = body
                    .get("serviceTicketId")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| anyhow!("MFA succeeded but no serviceTicketId"))?;

                let service_url = self.mobile_service_url();
                self.exchange_service_ticket(ticket, &service_url).await?;
                self.save_session().await?;

                let mut state = self.auth_state.lock().await;
                *state = GarminAuthState::Authenticated {
                    expires_at: chrono::Utc::now() + chrono::Duration::hours(1),
                };
                *self.mfa_state.lock().await = None;
                Ok(AuthResult::Authenticated)
            }
            _ => Ok(AuthResult::Failed(format!(
                "MFA verification failed: {}",
                status_type
            ))),
        }
    }

    // -----------------------------------------------------------------------
    // DI Token Exchange
    // -----------------------------------------------------------------------

    /// Exchange a service ticket for a DI access token.
    async fn exchange_service_ticket(&self, ticket: &str, service_url: &str) -> Result<()> {
        let token_url = format!("{}{}", self.diauth_base(), DI_TOKEN_PATH);

        for client_id in DI_CLIENT_IDS {
            let basic = base64::engine::general_purpose::STANDARD.encode(format!("{}:", client_id));

            let form = [
                ("client_id", *client_id),
                ("service_ticket", ticket),
                ("grant_type", DI_GRANT_TYPE),
                ("service_url", service_url),
            ];

            let response = self
                .http
                .post(&token_url)
                .header("User-Agent", NATIVE_USER_AGENT)
                .header("X-Garmin-User-Agent", NATIVE_X_GARMIN_UA)
                .header("X-Garmin-Paired-App-Version", "10861")
                .header("X-Garmin-Client-Platform", "Android")
                .header("X-App-Ver", "10861")
                .header("X-Lang", "en")
                .header("X-GCExperience", "GC5")
                .header("Accept-Language", "en-US,en;q=0.9")
                .header("Authorization", format!("Basic {}", basic))
                .header("Accept", "application/json,text/html;q=0.9,*/*;q=0.8")
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Cache-Control", "no-cache")
                .form(&form)
                .send()
                .await?;

            if response.status().is_success() {
                let body: serde_json::Value = response.json().await?;
                let access_token = body
                    .get("access_token")
                    .and_then(|t| t.as_str())
                    .ok_or_else(|| anyhow!("DI response missing access_token"))?;
                let refresh_token = body
                    .get("refresh_token")
                    .and_then(|t| t.as_str())
                    .unwrap_or("");

                let expires_at = decode_jwt_expiry(access_token).unwrap_or_else(|| {
                    (chrono::Utc::now() + chrono::Duration::hours(1)).to_rfc3339()
                });

                let mut session = self.di_session.lock().await;
                *session = Some(DiSession {
                    access_token: access_token.to_string(),
                    refresh_token: refresh_token.to_string(),
                    client_id: client_id.to_string(),
                    expires_at,
                });
                return Ok(());
            }
        }

        Err(anyhow!("All DI client IDs failed for ticket exchange"))
    }

    // -----------------------------------------------------------------------
    // Session persistence
    // -----------------------------------------------------------------------

    async fn save_session(&self) -> Result<()> {
        let session = self.di_session.lock().await;
        if let Some(ref di) = *session {
            let stored = StoredSession {
                access_token: di.access_token.clone(),
                refresh_token: Some(di.refresh_token.clone()),
                client_id: Some(di.client_id.clone()),
                expires_at: di.expires_at.clone(),
                cookies: std::collections::HashMap::new(),
            };
            self.token_store.save(&stored).await?;
        }
        Ok(())
    }

    /// Export the stored session for Dart-side persistence.
    pub async fn export_session(&self) -> Result<Option<StoredSession>> {
        self.token_store.load().await
    }

    // -----------------------------------------------------------------------
    // API access
    // -----------------------------------------------------------------------

    pub async fn auth_state(&self) -> GarminAuthState {
        self.auth_state.lock().await.clone()
    }

    /// Synchronous auth state check (non-blocking).
    /// Returns `None` if the lock is contended.
    pub fn auth_state_sync(&self) -> Option<GarminAuthState> {
        self.auth_state.try_lock().ok().map(|s| s.clone())
    }

    /// Get the DI access token (for API calls).
    pub async fn access_token(&self) -> Result<String> {
        let session = self.di_session.lock().await;
        let session = session
            .as_ref()
            .ok_or_else(|| anyhow!("Not authenticated"))?;
        match parse_session_expiry(&session.expires_at) {
            Some(expires_at) if expires_at > chrono::Utc::now() => Ok(session.access_token.clone()),
            _ => {
                let message = "DI token expired";
                let mut state = self.auth_state.lock().await;
                *state = GarminAuthState::Error {
                    message: message.to_string(),
                };
                Err(anyhow!(message))
            }
        }
    }

    /// Get an access token, failing fast when the stored token is expired.
    pub async fn fresh_access_token(&self) -> Result<String> {
        self.access_token().await
    }

    pub fn http(&self) -> &Client {
        &self.http
    }

    pub fn rate_limiter(&self) -> &GarminRateLimiter {
        &self.rate_limiter
    }

    pub async fn logout(&self) -> Result<()> {
        self.token_store.clear().await?;
        *self.di_session.lock().await = None;
        *self.mfa_state.lock().await = None;
        let mut state = self.auth_state.lock().await;
        *state = GarminAuthState::Unauthenticated;
        Ok(())
    }
}

/// Decode JWT expiry claim to RFC 3339 string.
fn decode_jwt_expiry(token: &str) -> Option<String> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() < 2 {
        return None;
    }
    let payload = parts[1];
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .ok()?;
    let json: serde_json::Value = serde_json::from_slice(&decoded).ok()?;
    let exp = json.get("exp")?.as_i64()?;
    chrono::DateTime::from_timestamp(exp, 0).map(|dt| dt.to_rfc3339())
}

fn parse_session_expiry(expires_at: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::DateTime::parse_from_rfc3339(expires_at)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::health::garmin::token_store::InMemoryTokenStore;
    use std::collections::HashMap;

    fn stored_session(expires_at: String) -> StoredSession {
        StoredSession {
            access_token: "access".to_string(),
            refresh_token: Some("refresh".to_string()),
            client_id: Some("GARMIN_CONNECT_MOBILE_ANDROID_DI".to_string()),
            expires_at,
            cookies: HashMap::new(),
        }
    }

    #[tokio::test]
    async fn new_marks_expired_stored_session_as_error() {
        let store = Arc::new(InMemoryTokenStore::new());
        store
            .save(&stored_session(
                (chrono::Utc::now() - chrono::Duration::minutes(1)).to_rfc3339(),
            ))
            .await
            .unwrap();

        let client = GarminClient::new(store, true).await.unwrap();

        assert_eq!(
            client.auth_state().await,
            GarminAuthState::Error {
                message: "DI token expired".to_string(),
            },
        );
    }

    #[tokio::test]
    async fn access_token_returns_error_for_expired_session() {
        let store = Arc::new(InMemoryTokenStore::new());
        store
            .save(&stored_session(
                (chrono::Utc::now() - chrono::Duration::minutes(1)).to_rfc3339(),
            ))
            .await
            .unwrap();
        let client = GarminClient::new(store, true).await.unwrap();

        let err = client.access_token().await.unwrap_err();

        assert!(err.to_string().contains("DI token expired"));
        assert_eq!(
            client.auth_state().await,
            GarminAuthState::Error {
                message: "DI token expired".to_string(),
            },
        );
    }

    #[tokio::test]
    async fn access_token_allows_near_expiry_session_without_refresh() {
        let store = Arc::new(InMemoryTokenStore::new());
        store
            .save(&stored_session(
                (chrono::Utc::now() + chrono::Duration::minutes(2)).to_rfc3339(),
            ))
            .await
            .unwrap();
        let client = GarminClient::new(store, true).await.unwrap();

        let token = client.access_token().await.unwrap();

        assert_eq!(token, "access");
        assert!(matches!(
            client.auth_state().await,
            GarminAuthState::Authenticated { .. },
        ));
    }
}
