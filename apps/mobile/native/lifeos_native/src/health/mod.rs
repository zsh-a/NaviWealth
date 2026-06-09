//! Health module — FRB public surface for Garmin integration.
//!
//! This module exposes:
//! - `provider`: HealthProvider trait + normalized types
//! - `garmin`: Garmin Connect provider implementation
//! - `sync_engine`: Cursor-based incremental sync
//!
//! FRB scans this `mod.rs` and generates Dart bindings for all
//! public functions and types.
//!
//! IMPORTANT: All FRB-facing functions must use only primitive types
//! (String, bool, i32, Vec<u8>, etc.) to avoid FRB codegen generating
//! references to internal types like `reqwest::Client` or
//! `chrono::NaiveDate` in `frb_generated.rs`.

// Internal modules — `pub(crate)` so FRB codegen only sees the
// functions in this file, not the internal types (reqwest::Client,
// chrono::NaiveDate, etc.) that would confuse the generated code.
pub(crate) mod garmin;
pub(crate) mod provider;
pub(crate) mod sync_engine;

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::Mutex;

use garmin::client::GarminClient;
use garmin::GarminProvider;
use garmin::token_store::{InMemoryTokenStore, StoredSession, TokenStore};
use sync_engine::HealthSyncEngine;

// ---------------------------------------------------------------------------
// Global state (singleton per app lifecycle).
// In production, this would be managed by Riverpod / DI.
// ---------------------------------------------------------------------------

static GARMIN_CLIENT: once_cell::sync::Lazy<Mutex<Option<GarminClient>>> =
    once_cell::sync::Lazy::new(|| Mutex::new(None));

/// Persisted session JSON — set by `save_session` callbacks, read by
/// `garmin_export_session`. This bridges the Rust in-memory token store
/// to Dart's `FlutterSecureStorage` without adding FRB callbacks.
static LAST_SESSION_JSON: once_cell::sync::Lazy<Mutex<Option<String>>> =
    once_cell::sync::Lazy::new(|| Mutex::new(None));

static SYNC_ENGINE: once_cell::sync::Lazy<Mutex<HealthSyncEngine>> =
    once_cell::sync::Lazy::new(|| Mutex::new(HealthSyncEngine::new()));

/// Called internally after a session is saved to the token store.
/// Caches the JSON so `garmin_export_session` can return it to Dart.
async fn cache_session_json(session: &StoredSession) {
    if let Ok(json) = serde_json::to_string(session) {
        *LAST_SESSION_JSON.lock().await = Some(json);
    }
}

// ---------------------------------------------------------------------------
// FRB public API — all params/returns are primitive or String types.
// ---------------------------------------------------------------------------

/// Initialize the Garmin client. Returns auth state as JSON.
///
/// `is_cn` selects between China (connect.garmin.cn) and global
/// (connect.garmin.com) endpoints.
pub async fn garmin_init(stored_token_json: Option<String>, is_cn: bool) -> Result<String> {
    let token_store: Arc<dyn TokenStore> = Arc::new(InMemoryTokenStore::new());

    if let Some(json) = stored_token_json {
        if let Ok(session) = serde_json::from_str::<garmin::token_store::StoredSession>(&json) {
            token_store.save(&session).await?;
        }
    }

    let client = GarminClient::new(token_store, is_cn).await?;

    // If restored from stored token, cache the session for future export.
    if let Ok(Some(session)) = client.export_session().await {
        cache_session_json(&session).await;
    }

    let state = client.auth_state().await;
    let state_json = serde_json::to_string(&state)?;

    // Register a Garmin provider with the sync engine.
    // The provider clones the client, sharing auth state and token store.
    let provider = GarminProvider::from_client(client.clone());
    {
        let mut engine = SYNC_ENGINE.lock().await;
        engine.add_provider(Arc::new(provider));
    }

    let mut global = GARMIN_CLIENT.lock().await;
    *global = Some(client);

    Ok(state_json)
}

/// Authenticate with Garmin Connect. Returns JSON: `{ "result": ..., "state": ... }`.
pub async fn garmin_authenticate(email: String, password: String) -> Result<String> {
    let global = GARMIN_CLIENT.lock().await;
    let client = global
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("Garmin client not initialized"))?;

    let result = client.authenticate(&email, &password).await?;

    // Cache session for Dart-side persistence on successful auth.
    if matches!(result, garmin::auth::AuthResult::Authenticated) {
        if let Ok(Some(session)) = client.export_session().await {
            cache_session_json(&session).await;
        }
    }

    let state = client.auth_state().await;

    let response = serde_json::json!({
        "result": serde_json::to_value(&result)?,
        "state": serde_json::to_value(&state)?,
    });

    Ok(serde_json::to_string(&response)?)
}

/// Submit MFA code. Returns JSON: `{ "result": ..., "state": ... }`.
pub async fn garmin_submit_mfa(code: String) -> Result<String> {
    let global = GARMIN_CLIENT.lock().await;
    let client = global
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("Garmin client not initialized"))?;

    let result = client.submit_mfa(&code).await?;

    // Cache session for Dart-side persistence on successful MFA.
    if matches!(result, garmin::auth::AuthResult::Authenticated) {
        if let Ok(Some(session)) = client.export_session().await {
            cache_session_json(&session).await;
        }
    }

    let state = client.auth_state().await;

    let response = serde_json::json!({
        "result": serde_json::to_value(&result)?,
        "state": serde_json::to_value(&state)?,
    });

    Ok(serde_json::to_string(&response)?)
}

/// Get current auth state as JSON.
pub async fn garmin_auth_state() -> Result<String> {
    let global = GARMIN_CLIENT.lock().await;
    let client = global
        .as_ref()
        .ok_or_else(|| anyhow::anyhow!("Garmin client not initialized"))?;

    let state = client.auth_state().await;
    Ok(serde_json::to_string(&state)?)
}

/// Sync health data for a date range. Returns SyncOutcome JSON array.
///
/// `from` and `to` are ISO date strings (YYYY-MM-DD).
pub async fn garmin_sync_range(from: String, to: String) -> Result<String> {
    let from_date = chrono::NaiveDate::parse_from_str(&from, "%Y-%m-%d")?;
    let to_date = chrono::NaiveDate::parse_from_str(&to, "%Y-%m-%d")?;

    let engine = SYNC_ENGINE.lock().await;
    let outcomes = engine.sync_range(from_date, to_date).await?;

    Ok(serde_json::to_string(&outcomes)?)
}

/// Get sync cursors as JSON.
pub async fn garmin_sync_cursors() -> Result<String> {
    let engine = SYNC_ENGINE.lock().await;
    let cursors = engine.cursors().await;
    Ok(serde_json::to_string(&cursors)?)
}

/// Export the current session as JSON for Dart-side persistence.
///
/// Returns the cached `StoredSession` JSON if authenticated, or `None`.
/// Dart stores this in `FlutterSecureStorage` and passes it back
/// via `garmin_init(stored_token_json:)` on next app launch.
pub async fn garmin_export_session() -> Result<Option<String>> {
    let cached = LAST_SESSION_JSON.lock().await;
    Ok(cached.clone())
}

/// Logout and clear stored credentials.
pub async fn garmin_logout() -> Result<()> {
    let global = GARMIN_CLIENT.lock().await;
    if let Some(client) = global.as_ref() {
        client.logout().await?;
    }
    Ok(())
}
