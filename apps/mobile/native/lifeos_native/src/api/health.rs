//! Health module — FRB public surface for Garmin integration.
//!
//! This file is the ONLY thing FRB codegen sees for health.
//! All internal implementation lives in `crate::health` (outside `api/`)
//! so codegen doesn't scan internal types like `reqwest::Client` or
//! `chrono::NaiveDate`.
//!
//! All functions use only primitive types (String, bool, Option<String>).

use anyhow::Result;

use crate::frb_generated::StreamSink;

/// Progress event emitted during Garmin sync (only primitive fields for FRB).
pub struct GarminSyncProgress {
    /// Phase: "days" | "activities" | "done"
    pub phase: String,
    /// Current index (day offset or activity offset).
    pub current: i32,
    /// Total count (days or activities).
    pub total: i32,
    /// Running total of metrics fetched so far.
    pub metrics_count: i32,
    /// Accumulated error messages.
    pub errors: Vec<String>,
}

/// Initialize the Garmin client. Returns auth state as JSON.
pub async fn garmin_init(stored_token_json: Option<String>, is_cn: bool) -> Result<String> {
    crate::health::garmin_init(stored_token_json, is_cn).await
}

/// Authenticate with Garmin Connect. Returns JSON.
pub async fn garmin_authenticate(email: String, password: String) -> Result<String> {
    crate::health::garmin_authenticate(email, password).await
}

/// Submit MFA code. Returns JSON.
pub async fn garmin_submit_mfa(code: String) -> Result<String> {
    crate::health::garmin_submit_mfa(code).await
}

/// Get current auth state as JSON.
pub async fn garmin_auth_state() -> Result<String> {
    crate::health::garmin_auth_state().await
}

/// Sync health data for a date range. Returns SyncOutcome JSON.
pub async fn garmin_sync_range(from: String, to: String) -> Result<String> {
    crate::health::garmin_sync_range(from, to).await
}

/// Sync health data for a date range with streaming progress events.
///
/// Emits [GarminSyncProgress] events via [StreamSink] as each day and
/// the activities fetch complete. The stream closes when the sync is
/// done or cancelled.
pub async fn garmin_sync_range_stream(
    sink: StreamSink<GarminSyncProgress>,
    from: String,
    to: String,
) -> anyhow::Result<()> {
    crate::health::garmin_sync_range_stream(sink, from, to).await
}

/// Cancel an in-progress sync. The running sync will stop after the
/// current day finishes.
pub fn garmin_sync_cancel() {
    crate::health::garmin_sync_cancel();
}

/// Get sync cursors as JSON.
pub async fn garmin_sync_cursors() -> Result<String> {
    crate::health::garmin_sync_cursors().await
}

/// Logout and clear stored credentials.
pub async fn garmin_logout() -> Result<()> {
    crate::health::garmin_logout().await
}

/// Export the current session as JSON for Dart-side persistence.
///
/// Returns the StoredSession JSON if authenticated, or null.
pub async fn garmin_export_session() -> Result<Option<String>> {
    crate::health::garmin_export_session().await
}
