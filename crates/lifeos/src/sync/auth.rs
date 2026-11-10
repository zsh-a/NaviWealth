//! Backend auth client: register / login / refresh against the NaviWealth
//! Workers backend (`apps/backend/src/routes/auth`). Sessions are stored by
//! the caller (the app keeps them in `settings`).

#[cfg(feature = "sync-http")]
use crate::error::{LifeosError, Result};

#[cfg(feature = "sync-http")]
pub const SYNC_PROTOCOL_VERSION: &str = "3";

#[derive(Debug, Clone, serde::Serialize)]
pub struct RegisterRequest {
    pub email: String,
    pub password: String,
    pub domains: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_id: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
    pub domains: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RefreshRequest {
    pub domains: Vec<String>,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct AuthSession {
    pub access_token: String,
    pub token_type: String,
    pub expires_at: i64,
    pub user_id: String,
    pub device_id: String,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct TokenPair {
    pub access_token: String,
    pub token_type: String,
    pub expires_at: i64,
}

#[cfg(feature = "sync-http")]
#[derive(Debug, Clone)]
pub struct AuthClient {
    base_url: String,
    client: reqwest::Client,
}

#[cfg(feature = "sync-http")]
impl AuthClient {
    pub fn new(base_url: impl Into<String>) -> Result<Self> {
        Ok(Self {
            base_url: base_url.into().trim_end_matches('/').to_owned(),
            client: reqwest::Client::new(),
        })
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    pub async fn register(&self, request: &RegisterRequest) -> Result<AuthSession> {
        self.post("/auth/register", request).await
    }

    pub async fn login(&self, request: &LoginRequest) -> Result<AuthSession> {
        self.post("/auth/login", request).await
    }

    pub async fn refresh(&self, bearer: &str, request: &RefreshRequest) -> Result<TokenPair> {
        let response = self
            .client
            .post(format!("{}/auth/refresh", self.base_url))
            .header("Authorization", format!("Bearer {bearer}"))
            .json(request)
            .send()
            .await
            .map_err(|e| LifeosError::Http(e.to_string()))?;
        let response = Self::check_status(response).await?;
        response
            .json::<TokenPair>()
            .await
            .map_err(|e| LifeosError::Http(format!("bad refresh response: {e}")))
    }

    async fn post<B: serde::Serialize, T: serde::de::DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T> {
        let response = self
            .client
            .post(format!("{}{}", self.base_url, path))
            .header("Sync-Protocol-Version", SYNC_PROTOCOL_VERSION)
            .json(body)
            .send()
            .await
            .map_err(|e| LifeosError::Http(e.to_string()))?;
        let response = Self::check_status(response).await?;
        response
            .json::<T>()
            .await
            .map_err(|e| LifeosError::Http(format!("bad auth response: {e}")))
    }

    async fn check_status(response: reqwest::Response) -> Result<reqwest::Response> {
        let status = response.status();
        if status.is_success() {
            return Ok(response);
        }
        let body = response.text().await.unwrap_or_default();
        if status.as_u16() == 409 {
            return Err(LifeosError::Auth(format!("registration closed: {body}")));
        }
        Err(LifeosError::Auth(format!("HTTP {status}: {body}")))
    }
}
