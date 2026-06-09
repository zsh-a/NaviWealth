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
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::frb_generated::StreamSink;

use garmin::client::GarminClient;
use garmin::GarminProvider;
use garmin::token_store::{InMemoryTokenStore, StoredSession, TokenStore};
use sync_engine::HealthSyncEngine;

/// Progress event for streaming sync (defined in `api/health.rs`).
use crate::api::health::GarminSyncProgress;

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

/// Cancellation flag for in-progress sync.
static SYNC_CANCEL: AtomicBool = AtomicBool::new(false);

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

/// Sync health data with streaming progress events.
///
/// Async — runs on FRB's Tokio runtime. Emits [GarminSyncProgress] via
/// [StreamSink] after each day completes. The stream closes when the
/// sync finishes or is cancelled via [garmin_sync_cancel].
pub async fn garmin_sync_range_stream(
    sink: StreamSink<GarminSyncProgress>,
    from: String,
    to: String,
) -> anyhow::Result<()> {
    // Reset cancel flag at sync start.
    SYNC_CANCEL.store(false, Ordering::Relaxed);

    let from_date = chrono::NaiveDate::parse_from_str(&from, "%Y-%m-%d")?;
    let to_date = chrono::NaiveDate::parse_from_str(&to, "%Y-%m-%d")?;
    let total_days = (to_date - from_date).num_days() + 1;

    let result = run_streaming_sync(&sink, from_date, to_date, total_days).await;

    // Emit final events: snapshot data + "done".
    match result {
        Ok((metrics_count, errors, snapshot_json)) => {
            // Emit snapshot data so Dart can persist it to Drift.
            if !snapshot_json.is_empty() {
                let _ = sink.add(GarminSyncProgress {
                    phase: "snapshot".to_string(),
                    current: 0,
                    total: 0,
                    metrics_count: metrics_count as i32,
                    errors: vec![snapshot_json],
                });
            }
            let _ = sink.add(GarminSyncProgress {
                phase: "done".to_string(),
                current: total_days as i32,
                total: total_days as i32,
                metrics_count: metrics_count as i32,
                errors,
            });
        }
        Err(e) => {
            let _ = sink.add(GarminSyncProgress {
                phase: "done".to_string(),
                current: 0,
                total: total_days as i32,
                metrics_count: 0,
                errors: vec![e.to_string()],
            });
        }
    }
    // `sink` is dropped here → stream closes on Dart side.
    Ok(())
}

/// Cancel an in-progress sync.
pub fn garmin_sync_cancel() {
    SYNC_CANCEL.store(true, Ordering::Relaxed);
}

/// Core streaming sync logic.
///
/// Optimization: 5 endpoints support date ranges (steps, RHR, body battery,
/// stress, weight) and are fetched once for the full window. Only sleep and
/// HRV require per-day calls. Total API calls: 5 + (days × 2) + 1.
async fn run_streaming_sync(
    sink: &StreamSink<GarminSyncProgress>,
    from: chrono::NaiveDate,
    to: chrono::NaiveDate,
    total_days: i64,
) -> anyhow::Result<(usize, Vec<String>, String)> {
    // Clone the client from the global to avoid holding the lock during sync.
    let (http, rl, token, cn) = {
        let global = GARMIN_CLIENT.lock().await;
        let client = global
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("Garmin client not initialized"))?;
        let token = client.access_token().await?;
        (
            client.http().clone(),
            client.rate_limiter().clone(),
            token,
            client.is_cn(),
        )
    };

    let mut errors = Vec::new();

    // -----------------------------------------------------------------------
    // Phase 1: Batch-fetch range-capable endpoints (5 API calls total).
    // -----------------------------------------------------------------------

    let mut all_steps = if let Ok(json) =
        garmin::endpoints::fetch_steps(&http, &rl, &token, from, to, cn).await
    {
        garmin::mapper::map_steps_range(&json)
    } else {
        vec![]
    };

    let mut all_rhr = if let Ok(json) =
        garmin::endpoints::fetch_rhr(&http, &rl, &token, from, to, cn).await
    {
        garmin::mapper::map_rhr_range(&json)
    } else {
        vec![]
    };

    let mut all_bb = if let Ok(json) =
        garmin::endpoints::fetch_body_battery(&http, &rl, &token, from, to, cn).await
    {
        garmin::mapper::map_body_battery_range(&json)
    } else {
        vec![]
    };

    let mut all_stress = if let Ok(json) =
        garmin::endpoints::fetch_stress(&http, &rl, &token, from, to, cn).await
    {
        garmin::mapper::map_stress_range(&json)
    } else {
        vec![]
    };

    let mut all_weight = if let Ok(json) =
        garmin::endpoints::fetch_weight(&http, &rl, &token, from, to, cn).await
    {
        garmin::mapper::map_weight_range(&json)
    } else {
        vec![]
    };

    // Emit progress after batch fetch.
    let batch_metrics = all_steps.len()
        + all_rhr.len()
        + all_bb.len()
        + all_stress.len()
        + all_weight.len();

    let _ = sink.add(GarminSyncProgress {
        phase: "days".to_string(),
        current: 0,
        total: total_days as i32,
        metrics_count: batch_metrics as i32,
        errors: errors.clone(),
    });

    // -----------------------------------------------------------------------
    // Phase 2: Per-day fetch for sleep + HRV only (2 API calls per day).
    // -----------------------------------------------------------------------

    let mut all_sleep = Vec::new();
    let mut all_hrv = Vec::new();
    let mut all_hr = Vec::new();

    for i in 0..total_days {
        if SYNC_CANCEL.load(Ordering::Relaxed) {
            break;
        }

        let date = from + chrono::Duration::days(i);

        if let Ok(json) = garmin::endpoints::fetch_sleep(&http, &rl, &token, date, cn).await {
            if let Some(s) = garmin::mapper::map_sleep(&json, date) {
                all_sleep.push(s);
            }
            if let Some(hr) = garmin::mapper::map_heart_rate_from_sleep(&json, date) {
                all_hr.push(hr);
            }
        }

        if let Ok(json) = garmin::endpoints::fetch_hrv(&http, &rl, &token, date, cn).await {
            if let Some(m) = garmin::mapper::map_hrv(&json, date) {
                all_hrv.push(m);
            }
        }

        // Emit day progress.
        let metrics_so_far = batch_metrics
            + all_sleep.len()
            + all_hrv.len()
            + all_hr.len();

        let _ = sink.add(GarminSyncProgress {
            phase: "days".to_string(),
            current: (i + 1) as i32,
            total: total_days as i32,
            metrics_count: metrics_so_far as i32,
            errors: errors.clone(),
        });
    }

    // -----------------------------------------------------------------------
    // Phase 3: Training status / VO2 max (1 API call).
    // -----------------------------------------------------------------------

    let mut all_vo2 = Vec::new();
    if !SYNC_CANCEL.load(Ordering::Relaxed) {
        if let Ok(json) =
            garmin::endpoints::fetch_training_status(&http, &rl, &token, cn).await
        {
            all_vo2 = garmin::mapper::map_vo2_max(&json, to).into_iter().collect();
        }
    }

    // Update cursor.
    {
        let engine = SYNC_ENGINE.lock().await;
        engine.set_cursor("Garmin Connect".to_string(), to).await;
    }

    let metrics_count = all_steps.len()
        + all_sleep.len()
        + all_rhr.len()
        + all_hrv.len()
        + all_hr.len()
        + all_bb.len()
        + all_stress.len()
        + all_weight.len()
        + all_vo2.len();

    // Build and serialize the HealthSnapshot for Dart-side persistence.
    let snapshot = garmin::mapper::build_snapshot(
        all_steps,
        all_sleep,
        all_rhr,
        all_hrv,
        all_hr,
        all_bb,
        all_stress,
        all_weight,
        all_vo2,
    );
    let snapshot_json = serde_json::to_string(&snapshot).unwrap_or_default();

    Ok((metrics_count, errors, snapshot_json))
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
