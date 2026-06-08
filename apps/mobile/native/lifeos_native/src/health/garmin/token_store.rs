//! Token persistence trait.
//!
//! The Rust side defines the interface; Dart provides the actual
//! persistence via `flutter_secure_storage` through an FRB callback.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Stored Garmin session (token + cookies).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredSession {
    pub access_token: String,
    pub refresh_token: Option<String>,
    /// ISO 8601 UTC.
    pub expires_at: String,
    /// Cookie jar (Garmin SSO uses cookie auth).
    pub cookies: HashMap<String, String>,
}

/// Persistence interface for Garmin credentials.
///
/// Implementations:
/// - `InMemoryTokenStore` for testing
/// - Dart `FlutterSecureTokenStore` via FRB callback bridge
#[async_trait::async_trait]
pub trait TokenStore: Send + Sync {
    async fn load(&self) -> anyhow::Result<Option<StoredSession>>;
    async fn save(&self, session: &StoredSession) -> anyhow::Result<()>;
    async fn clear(&self) -> anyhow::Result<()>;
}

/// In-memory implementation for tests.
pub struct InMemoryTokenStore {
    inner: tokio::sync::Mutex<Option<StoredSession>>,
}

impl InMemoryTokenStore {
    pub fn new() -> Self {
        Self {
            inner: tokio::sync::Mutex::new(None),
        }
    }
}

impl Default for InMemoryTokenStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl TokenStore for InMemoryTokenStore {
    async fn load(&self) -> anyhow::Result<Option<StoredSession>> {
        Ok(self.inner.lock().await.clone())
    }

    async fn save(&self, session: &StoredSession) -> anyhow::Result<()> {
        *self.inner.lock().await = Some(session.clone());
        Ok(())
    }

    async fn clear(&self) -> anyhow::Result<()> {
        *self.inner.lock().await = None;
        Ok(())
    }
}
