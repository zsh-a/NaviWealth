//! The sync transport seam: the engine talks to one endpoint; tests inject
//! a fake, production uses reqwest over the platform HTTP stack.

use async_trait::async_trait;

use crate::error::{LifeosError, Result};

use super::types::{Domain, ResetDomainResponse, SyncRequest, SyncResponse};

pub const SYNC_PROTOCOL_VERSION: &str = "3";

#[async_trait]
pub trait SyncTransport: Send + Sync {
    async fn post_sync(&self, request: SyncRequest, bearer: Option<String>)
    -> Result<SyncResponse>;

    async fn reset_domain(&self, domain: Domain, bearer: Option<String>) -> Result<i64>;
}

/// Reqwest-backed transport against the NaviWealth backend.
#[cfg(feature = "sync-http")]
pub struct HttpSyncTransport {
    base_url: String,
    client: reqwest::Client,
}

#[cfg(feature = "sync-http")]
impl HttpSyncTransport {
    pub fn new(base_url: impl Into<String>) -> Result<Self> {
        Ok(Self {
            base_url: base_url.into().trim_end_matches('/').to_owned(),
            client: reqwest::Client::new(),
        })
    }

    fn auth_headers(
        &self,
        request: reqwest::RequestBuilder,
        bearer: &Option<String>,
    ) -> reqwest::RequestBuilder {
        let request = request.header("Sync-Protocol-Version", SYNC_PROTOCOL_VERSION);
        match bearer {
            Some(token) if !token.is_empty() => {
                request.header("Authorization", format!("Bearer {token}"))
            }
            _ => request,
        }
    }
}

#[cfg(feature = "sync-http")]
#[async_trait]
impl SyncTransport for HttpSyncTransport {
    async fn post_sync(
        &self,
        request: SyncRequest,
        bearer: Option<String>,
    ) -> Result<SyncResponse> {
        let response = self
            .auth_headers(self.client.post(format!("{}/sync", self.base_url)), &bearer)
            .json(&request)
            .send()
            .await
            .map_err(|e| LifeosError::Http(e.to_string()))?;
        let response = Self::check_status(response).await?;
        let body = response
            .json::<SyncResponse>()
            .await
            .map_err(|e| LifeosError::Http(format!("bad sync response: {e}")))?;
        Ok(body)
    }

    async fn reset_domain(&self, domain: Domain, bearer: Option<String>) -> Result<i64> {
        let response = self
            .auth_headers(
                self.client
                    .post(format!("{}/sync/reset-domain", self.base_url)),
                &bearer,
            )
            .json(&serde_json::json!({ "domain": domain.as_str() }))
            .send()
            .await
            .map_err(|e| LifeosError::Http(e.to_string()))?;
        let response = Self::check_status(response).await?;
        let body = response
            .json::<ResetDomainResponse>()
            .await
            .map_err(|e| LifeosError::Http(format!("bad reset response: {e}")))?;
        Ok(body.generation)
    }
}

#[cfg(feature = "sync-http")]
impl HttpSyncTransport {
    async fn check_status(response: reqwest::Response) -> Result<reqwest::Response> {
        let status = response.status();
        if status.is_success() {
            return Ok(response);
        }
        let body = response.text().await.unwrap_or_default();
        Err(LifeosError::Http(format!("HTTP {status}: {body}")))
    }
}
