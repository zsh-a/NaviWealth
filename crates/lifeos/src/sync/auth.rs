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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_id: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct RefreshRequest {
    pub domains: Vec<String>,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct AuthSession {
    pub access_token: String,
    pub token_type: String,
    #[serde(deserialize_with = "deserialize_expiry")]
    pub expires_at: i64,
    pub user_id: String,
    pub device_id: String,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct TokenPair {
    pub access_token: String,
    pub token_type: String,
    #[serde(deserialize_with = "deserialize_expiry")]
    pub expires_at: i64,
}

/// The Worker sends RFC 3339 timestamps; application storage uses epoch seconds.
fn deserialize_expiry<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> std::result::Result<i64, D::Error> {
    let value = <String as serde::Deserialize>::deserialize(deserializer)?;
    chrono::DateTime::parse_from_rfc3339(&value)
        .map(|expiry| expiry.timestamp())
        .map_err(serde::de::Error::custom)
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
        let base_url = base_url.into().trim().trim_end_matches('/').to_owned();
        let parsed = reqwest::Url::parse(&base_url)
            .map_err(|_| LifeosError::Auth("请输入有效的后端地址".to_owned()))?;
        if !matches!(parsed.scheme(), "http" | "https")
            || parsed.query().is_some()
            || parsed.fragment().is_some()
        {
            return Err(LifeosError::Auth(
                "后端地址应为 HTTP 或 HTTPS 地址".to_owned(),
            ));
        }
        Ok(Self {
            base_url,
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(30))
                .build()
                .map_err(|e| LifeosError::Http(e.to_string()))?,
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
            .header("Sync-Protocol-Version", SYNC_PROTOCOL_VERSION)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn worker_auth_response_parses_rfc3339_expiry() {
        let session: AuthSession = serde_json::from_value(serde_json::json!({
            "access_token": "token", "token_type": "Bearer", "expires_at": "2026-11-11T02:00:00Z",
            "user_id": "user", "device_id": "device"
        }))
        .unwrap();
        assert_eq!(session.expires_at, 1_794_362_400);
        let token: TokenPair = serde_json::from_value(serde_json::json!({
            "access_token": "token", "token_type": "Bearer", "expires_at": "2026-11-11T10:00:00+08:00"
        })).unwrap();
        assert_eq!(token.expires_at, session.expires_at);
    }

    #[cfg(feature = "sync-http")]
    #[tokio::test]
    async fn login_matches_worker_http_contract() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(std::time::Duration::from_secs(5)))
                .unwrap();
            let mut request = Vec::new();
            let mut buffer = [0; 1024];
            loop {
                let count = stream.read(&mut buffer).unwrap();
                assert!(count > 0);
                request.extend_from_slice(&buffer[..count]);
                if let Some(header_end) = request.windows(4).position(|bytes| bytes == b"\r\n\r\n")
                {
                    let headers =
                        String::from_utf8_lossy(&request[..header_end]).to_ascii_lowercase();
                    let length: usize = headers
                        .lines()
                        .find_map(|line| line.strip_prefix("content-length:").map(str::trim))
                        .unwrap()
                        .parse()
                        .unwrap();
                    if request.len() < header_end + 4 + length {
                        continue;
                    }
                    assert!(headers.starts_with("post /auth/login "));
                    assert!(headers.contains("sync-protocol-version: 3"));
                    let body: serde_json::Value =
                        serde_json::from_slice(&request[header_end + 4..]).unwrap();
                    assert_eq!(body["device_id"], "stable-device");
                    assert_eq!(body["domains"], serde_json::json!(["finance"]));
                    break;
                }
            }
            let body = r#"{"access_token":"token","token_type":"Bearer","expires_at":"2026-11-11T02:00:00Z","user_id":"user","device_id":"stable-device"}"#;
            write!(stream,"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",body.len(),body).unwrap();
        });
        let session = AuthClient::new(format!("http://{address}"))
            .unwrap()
            .login(&LoginRequest {
                email: "me@example.com".into(),
                password: "password".into(),
                domains: vec!["finance".into()],
                device_name: Some("NaviWealth".into()),
                device_id: Some("stable-device".into()),
            })
            .await
            .unwrap();
        assert_eq!(session.device_id, "stable-device");
        assert_eq!(session.expires_at, 1_794_362_400);
        server.join().unwrap();
    }

    #[test]
    fn invalid_server_expiry_is_rejected() {
        for expiry in [serde_json::json!("invalid"), serde_json::json!(123)] {
            assert!(
                serde_json::from_value::<TokenPair>(serde_json::json!({
                    "access_token": "token", "token_type": "Bearer", "expires_at": expiry,
                }))
                .is_err()
            );
        }
    }

    #[test]
    fn login_carries_stable_device_identity() {
        let value = serde_json::to_value(LoginRequest {
            email: "me@example.com".into(),
            password: "password".into(),
            domains: vec!["finance".into()],
            device_name: Some("NaviWealth".into()),
            device_id: Some("stable-device".into()),
        })
        .unwrap();
        assert_eq!(value["device_id"], "stable-device");
    }
}
