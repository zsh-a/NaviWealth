//! `POST /sync` — the single sync endpoint (docs/sync-v2.md §5.1).
//!
//! One round trip does push and pull: the client uploads its dirty rows and
//! its cursor, the server applies them (LWW) and returns everything newer
//! than the cursor authored by other devices.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use worker::{Request, Response, Result as WorkerResult, RouteContext};

use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::routes::common::check_protocol_version;
use crate::sync::store::{self, RowChange};

const SYNC_BODY_LIMIT: usize = 1024 * 1024;
const SYNC_MAX_CHANGES: usize = 500;
const PER_ROW_PAYLOAD_LIMIT: usize = 64 * 1024;
const PULL_LIMIT: i64 = 500;

/// Latency above which a sync request is logged as `slow=true`. See
/// docs/sync-monitoring.md for the alerting that consumes this.
const SLOW_REQUEST_THRESHOLD_MS: i64 = 30;

#[derive(Deserialize)]
struct SyncRequest {
    device_id: String,
    #[serde(default)]
    since: i64,
    #[serde(default)]
    changes: Vec<RowChange>,
}

#[derive(Serialize)]
struct SyncResponse {
    /// Cursor the client adopts after applying this page.
    seq: i64,
    changes: Vec<RowChange>,
    more: bool,
}

pub async fn sync(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let started_ms = Utc::now().timestamp_millis();
    let mut metrics = SyncMetrics::default();
    let result = sync_inner(req, ctx, &mut metrics).await;
    let (status, code) = match &result {
        Ok(r) => (r.status_code(), "ok"),
        Err(e) => (e.status(), e.code()),
    };
    log_request(status, code, started_ms, &metrics);
    match result {
        Ok(r) => Ok(r),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

async fn sync_inner(
    mut req: Request,
    ctx: RouteContext<()>,
    metrics: &mut SyncMetrics,
) -> Result<Response, AppError> {
    check_protocol_version(req.headers())?;
    let auth = require_auth(&req, &ctx).await?;

    let raw = req
        .bytes()
        .await
        .map_err(|e| AppError::BadRequest(format!("body read: {e}")))?;
    if raw.len() > SYNC_BODY_LIMIT {
        return Err(AppError::payload_too_large());
    }
    let body: SyncRequest = serde_json::from_slice(&raw)
        .map_err(|e| AppError::BadRequest(format!("invalid JSON: {e}")))?;

    if body.changes.len() > SYNC_MAX_CHANGES {
        return Err(AppError::payload_too_large());
    }
    // The JWT pins the caller to one device; the body must agree.
    if body.device_id != auth.device_id {
        return Err(AppError::device_mismatch());
    }
    for change in &body.changes {
        if let Some(payload) = &change.payload {
            let size = serde_json::to_string(payload).map(|s| s.len()).unwrap_or(0);
            if size > PER_ROW_PAYLOAD_LIMIT {
                return Err(AppError::payload_too_large());
            }
        }
    }

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    let user_id = &auth.user_id;
    let device_id = &auth.device_id;

    // Apply the caller's changes first, then pull — so a row the caller just
    // pushed and a peer's newer version of it resolve before the response is
    // built (docs/sync-v2.md §5.1).
    let pushed = store::apply_changes(&db, user_id, device_id, &body.changes).await?;
    let page = store::pull(&db, user_id, device_id, body.since, PULL_LIMIT).await?;

    metrics.pushed = pushed;
    metrics.pulled = page.changes.len();
    metrics.more = page.more;

    let resp = SyncResponse {
        seq: page.high_seq,
        changes: page.changes,
        more: page.more,
    };
    Response::from_json(&resp).map_err(AppError::from)
}

// ---------------------------------------------------------------------------
// Structured request log — consumed by `wrangler tail` and the dashboards in
// docs/sync-monitoring.md:
//
//     [SYNC] status=200 code=ok dur_ms=12 pushed=3 pulled=8 more=false slow=false
// ---------------------------------------------------------------------------

#[derive(Default)]
struct SyncMetrics {
    /// Rows stored from the caller's changes (post-LWW).
    pushed: usize,
    /// Rows returned to the caller in this page.
    pulled: usize,
    /// Whether the caller must sync again to drain.
    more: bool,
}

fn log_request(status: u16, code: &str, started_ms: i64, metrics: &SyncMetrics) {
    let dur_ms = (Utc::now().timestamp_millis() - started_ms).max(0);
    let slow = dur_ms > SLOW_REQUEST_THRESHOLD_MS;
    worker::console_log!(
        "[SYNC] status={} code={} dur_ms={} pushed={} pulled={} more={} slow={}",
        status,
        code,
        dur_ms,
        metrics.pushed,
        metrics.pulled,
        metrics.more,
        slow
    );
}
