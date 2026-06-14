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

use anyhow::{anyhow, Result};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::frb_generated::StreamSink;

use garmin::client::GarminClient;
use garmin::token_store::{InMemoryTokenStore, StoredSession, TokenStore};
use garmin::GarminProvider;
use sync_engine::HealthSyncEngine;

/// Progress event for streaming sync (defined in `api/health.rs`).
use crate::api::health::GarminSyncProgress;
use provider::{BodyBatteryDay, DailyMetric};

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
            let snapshot = if snapshot_json.is_empty() {
                None
            } else {
                Some(snapshot_json)
            };
            if snapshot.is_some() {
                let _ = sink.add(GarminSyncProgress {
                    phase: "snapshot".to_string(),
                    current: 0,
                    total: 0,
                    metrics_count: metrics_count as i32,
                    errors: vec![],
                    snapshot_json: snapshot,
                });
            }
            let _ = sink.add(GarminSyncProgress {
                phase: "done".to_string(),
                current: total_days as i32,
                total: total_days as i32,
                metrics_count: metrics_count as i32,
                errors,
                snapshot_json: None,
            });
        }
        Err(e) => {
            let _ = sink.add(GarminSyncProgress {
                phase: "done".to_string(),
                current: 0,
                total: total_days as i32,
                metrics_count: 0,
                errors: vec![e.to_string()],
                snapshot_json: None,
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
        let token = client.fresh_access_token().await?;
        if let Ok(Some(session)) = client.export_session().await {
            cache_session_json(&session).await;
        }
        (
            client.http().clone(),
            client.rate_limiter().clone(),
            token,
            client.is_cn(),
        )
    };

    let mut errors = Vec::new();
    eprintln!(
        "[HealthOS][Garmin] sync start from={} to={} days={} region={}",
        from,
        to,
        total_days,
        if cn { "CN" } else { "Global" }
    );

    let display_name = match garmin::endpoints::fetch_social_profile(&http, &rl, &token, cn).await {
        Ok(json) => {
            let name = json
                .get("displayName")
                .and_then(|v| v.as_str())
                .filter(|v| !v.is_empty())
                .map(|v| v.to_string())
                .ok_or_else(|| anyhow!("Garmin profile missing displayName"))?;
            eprintln!("[HealthOS][Garmin] profile displayName loaded");
            name
        }
        Err(e) => {
            eprintln!("[HealthOS][Garmin] profile failed: {e}");
            record_endpoint_error(&mut errors, "profile", &e);
            return Err(e.context("Garmin profile fetch failed"));
        }
    };

    // -----------------------------------------------------------------------
    // Phase 1: Batch-fetch range-capable endpoints.
    // -----------------------------------------------------------------------

    let mut all_steps: Vec<DailyMetric> = Vec::new();
    let mut all_rhr: Vec<DailyMetric> = Vec::new();

    let mut all_bb: Vec<BodyBatteryDay> =
        match garmin::endpoints::fetch_body_battery(&http, &rl, &token, from, to, cn).await {
            Ok(json) => {
                let mapped = garmin::mapper::map_body_battery_range(&json);
                eprintln!(
                    "[HealthOS][Garmin] body_battery range mapped={}",
                    mapped.len()
                );
                mapped
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] body_battery range failed: {e}");
                record_endpoint_error(&mut errors, "body_battery range", &e);
                vec![]
            }
        };

    let mut all_stress: Vec<DailyMetric> =
        match garmin::endpoints::fetch_stress(&http, &rl, &token, from, to, cn).await {
            Ok(json) => {
                let mapped = garmin::mapper::map_stress_range(&json);
                eprintln!("[HealthOS][Garmin] stress range mapped={}", mapped.len());
                mapped
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] stress range failed: {e}");
                record_endpoint_error(&mut errors, "stress range", &e);
                vec![]
            }
        };

    let all_weight = match garmin::endpoints::fetch_weight(&http, &rl, &token, from, to, cn).await {
        Ok(json) => {
            let mapped = garmin::mapper::map_weight_range(&json);
            eprintln!("[HealthOS][Garmin] weight range mapped={}", mapped.len());
            mapped
        }
        Err(e) => {
            eprintln!("[HealthOS][Garmin] weight range failed: {e}");
            record_endpoint_error(&mut errors, "weight range", &e);
            vec![]
        }
    };

    // Emit progress after batch fetch.
    let batch_metrics = all_bb.len() + all_stress.len() + all_weight.len();

    let _ = sink.add(GarminSyncProgress {
        phase: "days".to_string(),
        current: 0,
        total: total_days as i32,
        metrics_count: batch_metrics as i32,
        errors: errors.clone(),
        snapshot_json: None,
    });

    // -----------------------------------------------------------------------
    // Phase 2: Per-day fetches matching scripts/garmin_probe.py.
    // -----------------------------------------------------------------------

    let mut all_sleep = Vec::new();
    let mut all_hrv: Vec<DailyMetric> = Vec::new();
    let mut all_hr: Vec<DailyMetric> = Vec::new();
    let mut all_active_energy: Vec<DailyMetric> = Vec::new();
    let mut all_distance: Vec<DailyMetric> = Vec::new();
    let mut all_total_energy: Vec<DailyMetric> = Vec::new();
    let mut all_floors: Vec<DailyMetric> = Vec::new();
    let mut all_respiration: Vec<DailyMetric> = Vec::new();
    let mut all_spo2: Vec<DailyMetric> = Vec::new();

    for i in 0..total_days {
        if SYNC_CANCEL.load(Ordering::Relaxed) {
            break;
        }

        let date = from + chrono::Duration::days(i);

        match garmin::endpoints::fetch_steps_day(&http, &rl, &token, date, &display_name, cn).await
        {
            Ok(json) => {
                let before = all_steps.len();
                if let Some(steps) = garmin::mapper::map_steps(&json, date) {
                    all_steps.retain(|metric| metric.date != date);
                    all_steps.push(steps);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} steps ok mapped_delta={} total={}",
                    date,
                    all_steps.len() - before,
                    all_steps.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} steps failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("steps {date}"), &e);
            }
        }

        match garmin::endpoints::fetch_sleep(&http, &rl, &token, date, &display_name, cn).await {
            Ok(json) => {
                if let Some(s) = garmin::mapper::map_sleep(&json, date) {
                    all_sleep.push(s);
                }
                // Fallback: extract HR from sleep if all-day HR fails.
                if let Some(hr) = garmin::mapper::map_heart_rate_from_sleep(&json, date) {
                    all_hr.push(hr);
                }
                if let Some(hrv) = garmin::mapper::map_hrv_from_sleep(&json, date) {
                    all_hrv.push(hrv);
                }
                if let Some(rhr) = garmin::mapper::map_rhr_from_sleep(&json, date) {
                    all_rhr.retain(|metric| metric.date != date);
                    all_rhr.push(rhr);
                }
                if let Some(stress) = garmin::mapper::map_stress_from_sleep(&json, date) {
                    all_stress.push(stress);
                }
                if !all_bb.iter().any(|metric| metric.date == date) {
                    if let Some(body_battery) =
                        garmin::mapper::map_body_battery_from_sleep(&json, date)
                    {
                        all_bb.push(body_battery);
                    }
                }
                if let Some(respiration) =
                    garmin::mapper::map_respiratory_rate_from_sleep(&json, date)
                {
                    all_respiration.push(respiration);
                }
                if let Some(spo2) = garmin::mapper::map_spo2_from_sleep(&json, date) {
                    all_spo2.push(spo2);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} sleep ok totals sleep={} hr={} hrv={} rhr={} body_battery={} stress={} respiration={} spo2={}",
                    date,
                    all_sleep.len(),
                    all_hr.len(),
                    all_hrv.len(),
                    all_rhr.len(),
                    all_bb.len(),
                    all_stress.len(),
                    all_respiration.len(),
                    all_spo2.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} sleep failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("sleep {date}"), &e);
            }
        }

        // All-day HR (preferred over sleep-based HR).
        match garmin::endpoints::fetch_heart_rate(&http, &rl, &token, date, &display_name, cn).await
        {
            Ok(json) => {
                if let Some(hr) = garmin::mapper::map_heart_rate_all_day(&json, date) {
                    // Replace sleep-based HR if all-day HR is available.
                    all_hr.retain(|m| m.date != date);
                    all_hr.push(hr);
                }
                if let Some(m) = garmin::mapper::map_rhr(&json, date) {
                    all_rhr.retain(|metric| metric.date != date);
                    all_rhr.push(m);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} heart_rate ok totals hr={} rhr={}",
                    date,
                    all_hr.len(),
                    all_rhr.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} heart_rate failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("heart_rate {date}"), &e);
            }
        }

        match garmin::endpoints::fetch_rhr_day(&http, &rl, &token, date, &display_name, cn).await {
            Ok(json) => {
                let before = all_rhr.len();
                if let Some(m) = garmin::mapper::map_rhr(&json, date) {
                    all_rhr.retain(|metric| metric.date != date);
                    all_rhr.push(m);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} rhr ok mapped_delta={} total={}",
                    date,
                    all_rhr.len() - before,
                    all_rhr.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} rhr failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("rhr {date}"), &e);
            }
        }

        match garmin::endpoints::fetch_hrv(&http, &rl, &token, date, cn).await {
            Ok(json) => {
                let before = all_hrv.len();
                if let Some(m) = garmin::mapper::map_hrv(&json, date) {
                    all_hrv.retain(|metric| metric.date != date);
                    all_hrv.push(m);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} hrv ok mapped_delta={} total={}",
                    date,
                    all_hrv.len() - before,
                    all_hrv.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} hrv failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("hrv {date}"), &e);
            }
        }

        match garmin::endpoints::fetch_daily_summary(&http, &rl, &token, date, &display_name, cn)
            .await
        {
            Ok(json) => {
                if let Some(steps) = garmin::mapper::map_steps_from_daily_summary(&json, date) {
                    all_steps.retain(|metric| metric.date != date);
                    all_steps.push(steps);
                }
                if let Some(rhr) = garmin::mapper::map_rhr(&json, date) {
                    all_rhr.retain(|metric| metric.date != date);
                    all_rhr.push(rhr);
                }
                if let Some(stress) = garmin::mapper::map_stress(&json, date) {
                    all_stress.retain(|metric| metric.date != date);
                    all_stress.push(stress);
                }
                if let Some(respiration) = garmin::mapper::map_respiratory_rate(&json, date) {
                    all_respiration.retain(|metric| metric.date != date);
                    all_respiration.push(respiration);
                }
                if let Some(spo2) = garmin::mapper::map_spo2(&json, date) {
                    all_spo2.retain(|metric| metric.date != date);
                    all_spo2.push(spo2);
                }
                if let Some(body_battery) =
                    garmin::mapper::map_body_battery_from_daily_summary(&json, date)
                {
                    all_bb.retain(|metric| metric.date != date);
                    all_bb.push(body_battery);
                }
                if let Some(f) = garmin::mapper::map_floors_climbed(&json, date) {
                    all_floors.push(f);
                }
                let (distance_metric, active_metric, total_metric) =
                    garmin::mapper::map_daily_summary_metrics(&json, date);
                if let Some(metric) = distance_metric {
                    all_distance.push(metric);
                }
                if let Some(metric) = active_metric {
                    all_active_energy.push(metric);
                }
                if let Some(metric) = total_metric {
                    all_total_energy.push(metric);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} summary ok totals steps={} rhr={} stress={} body_battery={} spo2={} respiration={} distance={} active={} total={} floors={}",
                    date,
                    all_steps.len(),
                    all_rhr.len(),
                    all_stress.len(),
                    all_bb.len(),
                    all_spo2.len(),
                    all_respiration.len(),
                    all_distance.len(),
                    all_active_energy.len(),
                    all_total_energy.len(),
                    all_floors.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} summary failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("summary {date}"), &e);
            }
        }

        match garmin::endpoints::fetch_stress_day(&http, &rl, &token, date, cn).await {
            Ok(json) => {
                let before = all_stress.len();
                if let Some(s) = garmin::mapper::map_stress(&json, date) {
                    all_stress.retain(|metric| metric.date != date);
                    all_stress.push(s);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} stress ok total={} changed={}",
                    date,
                    all_stress.len(),
                    all_stress.len() != before
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} stress failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("stress {date}"), &e);
            }
        }

        match garmin::endpoints::fetch_respiration(&http, &rl, &token, date, cn).await {
            Ok(json) => {
                let before = all_respiration.len();
                if let Some(r) = garmin::mapper::map_respiratory_rate(&json, date) {
                    all_respiration.retain(|metric| metric.date != date);
                    all_respiration.push(r);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} respiration ok mapped_delta={} total={}",
                    date,
                    all_respiration.len() - before,
                    all_respiration.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} respiration failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("respiration {date}"), &e);
            }
        }

        match garmin::endpoints::fetch_spo2(&http, &rl, &token, date, cn).await {
            Ok(json) => {
                let before = all_spo2.len();
                if let Some(s) = garmin::mapper::map_spo2(&json, date) {
                    all_spo2.retain(|metric| metric.date != date);
                    all_spo2.push(s);
                }
                eprintln!(
                    "[HealthOS][Garmin] day {} spo2 ok mapped_delta={} total={}",
                    date,
                    all_spo2.len() - before,
                    all_spo2.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] day {} spo2 failed: {e}", date);
                record_endpoint_error(&mut errors, &format!("spo2 {date}"), &e);
            }
        }

        // Emit day progress.
        let metrics_so_far = all_steps.len()
            + all_sleep.len()
            + all_rhr.len()
            + all_hrv.len()
            + all_hr.len()
            + all_bb.len()
            + all_stress.len()
            + all_weight.len()
            + all_active_energy.len()
            + all_distance.len()
            + all_total_energy.len()
            + all_floors.len()
            + all_respiration.len()
            + all_spo2.len();

        let _ = sink.add(GarminSyncProgress {
            phase: "days".to_string(),
            current: (i + 1) as i32,
            total: total_days as i32,
            metrics_count: metrics_so_far as i32,
            errors: errors.clone(),
            snapshot_json: None,
        });
    }

    // -----------------------------------------------------------------------
    // Phase 3: Activity / workout sessions.
    // -----------------------------------------------------------------------

    let mut all_activities = Vec::new();
    if !SYNC_CANCEL.load(Ordering::Relaxed) {
        let mut start: u32 = 0;
        let page_size: u32 = 50;
        let from_str = from.format("%Y-%m-%d").to_string();

        loop {
            match garmin::endpoints::fetch_activities(&http, &rl, &token, start, page_size, cn)
                .await
            {
                Ok(json) => {
                    let page = json.as_array();
                    let page_len = page.map(|a| a.len()).unwrap_or(0);
                    if page_len == 0 {
                        break;
                    }

                    let mut reached_boundary = false;
                    if let Some(arr) = page {
                        for item in arr {
                            if let Some(activity) = garmin::mapper::map_activity(item) {
                                let act_date =
                                    &activity.started_at[..10.min(activity.started_at.len())];
                                if act_date < from_str.as_str() {
                                    reached_boundary = true;
                                    break;
                                }
                                all_activities.push(activity);
                            }
                        }
                    }

                    let metrics_so_far = all_steps.len()
                        + all_sleep.len()
                        + all_rhr.len()
                        + all_hrv.len()
                        + all_hr.len()
                        + all_bb.len()
                        + all_stress.len()
                        + all_weight.len()
                        + all_active_energy.len()
                        + all_distance.len()
                        + all_total_energy.len()
                        + all_floors.len()
                        + all_respiration.len()
                        + all_spo2.len()
                        + all_activities.len();
                    let _ = sink.add(GarminSyncProgress {
                        phase: "activities".to_string(),
                        current: all_activities.len() as i32,
                        total: 0,
                        metrics_count: metrics_so_far as i32,
                        errors: errors.clone(),
                        snapshot_json: None,
                    });

                    if reached_boundary || page_len < page_size as usize {
                        break;
                    }
                    start += page_size;
                    if start >= 500 {
                        break;
                    }
                }
                Err(e) => {
                    // Activity history is an optional enrichment. Garmin CN can
                    // return 404 for this mobile endpoint while sleep, HRV,
                    // stress, body battery, and daily summaries still work.
                    // Do not fail the whole health sync for a missing workout
                    // list; the snapshot built below should still persist the
                    // recovery metrics we did fetch.
                    eprintln!("[HealthOS][Garmin] activities failed: {e}");
                    record_endpoint_error(&mut errors, "activities", &e);
                    if !is_optional_activity_error(&e) {
                        errors.push(format!("activities fetch failed: {e}"));
                    }
                    break;
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Phase 4: Training status / VO2 max (1 API call).
    // -----------------------------------------------------------------------

    let mut all_vo2 = Vec::new();
    let mut all_training_load = Vec::new();
    let mut all_training_effect = Vec::new();
    if !SYNC_CANCEL.load(Ordering::Relaxed) {
        match garmin::endpoints::fetch_training_status(&http, &rl, &token, to, cn).await {
            Ok(json) => {
                all_vo2 = garmin::mapper::map_vo2_max(&json, to).into_iter().collect();
                all_training_load = garmin::mapper::map_training_load(&json, to)
                    .into_iter()
                    .collect();
                all_training_effect = garmin::mapper::map_training_effect(&json, to)
                    .into_iter()
                    .collect();
                eprintln!(
                    "[HealthOS][Garmin] training_status ok vo2={} load={} effect={}",
                    all_vo2.len(),
                    all_training_load.len(),
                    all_training_effect.len()
                );
            }
            Err(e) => {
                eprintln!("[HealthOS][Garmin] training_status failed: {e}");
                record_endpoint_error(&mut errors, "training_status", &e);
            }
        }
    }

    // Update cursor.
    {
        let engine = SYNC_ENGINE.lock().await;
        engine.set_cursor("Garmin Connect".to_string(), to).await;
    }

    let metrics_count = all_steps.len()
        + all_sleep.len()
        + all_activities.len()
        + all_rhr.len()
        + all_hrv.len()
        + all_hr.len()
        + all_bb.len()
        + all_stress.len()
        + all_weight.len()
        + all_active_energy.len()
        + all_distance.len()
        + all_total_energy.len()
        + all_vo2.len()
        + all_floors.len()
        + all_respiration.len()
        + all_training_load.len()
        + all_training_effect.len()
        + all_spo2.len();

    eprintln!(
        "[HealthOS][Garmin] sync counts steps={} sleep={} activities={} rhr={} hrv={} hr={} body_battery={} stress={} weight={} active_energy={} distance={} total_energy={} vo2={} floors={} respiration={} training_load={} training_effect={} spo2={} total={}",
        all_steps.len(),
        all_sleep.len(),
        all_activities.len(),
        all_rhr.len(),
        all_hrv.len(),
        all_hr.len(),
        all_bb.len(),
        all_stress.len(),
        all_weight.len(),
        all_active_energy.len(),
        all_distance.len(),
        all_total_energy.len(),
        all_vo2.len(),
        all_floors.len(),
        all_respiration.len(),
        all_training_load.len(),
        all_training_effect.len(),
        all_spo2.len(),
        metrics_count
    );

    // Build and serialize the HealthSnapshot for Dart-side persistence.
    let snapshot = garmin::mapper::build_snapshot(
        all_steps,
        all_sleep,
        all_activities,
        all_rhr,
        all_hrv,
        all_hr,
        all_bb,
        all_stress,
        all_weight,
        all_active_energy,
        all_distance,
        all_total_energy,
        all_vo2,
        all_floors,
        all_respiration,
        all_training_load,
        all_training_effect,
        all_spo2,
    );
    let snapshot_json = serde_json::to_string(&snapshot).unwrap_or_default();
    eprintln!(
        "[HealthOS][Garmin] snapshot json bytes={}",
        snapshot_json.len()
    );

    Ok((metrics_count, errors, snapshot_json))
}

fn is_optional_activity_error(error: &anyhow::Error) -> bool {
    let msg = error.to_string().to_lowercase();
    msg.contains("404 not found") || msg.contains("garmin api error: 404")
}

fn record_endpoint_error(errors: &mut Vec<String>, endpoint: &str, error: &anyhow::Error) {
    if !is_auth_error(error) {
        return;
    }
    let msg = format!(
        "Garmin auth failed while fetching {endpoint}: token expired or unauthorized; reconnect Garmin"
    );
    if !errors.iter().any(|existing| existing == &msg) {
        errors.push(msg);
    }
}

fn is_auth_error(error: &anyhow::Error) -> bool {
    let msg = error.to_string().to_lowercase();
    msg.contains("401 unauthorized") || msg.contains("token may be expired")
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
