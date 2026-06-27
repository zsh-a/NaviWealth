//! `POST /sync` — the single sync endpoint (docs/sync/sync-v2.md §5.1).
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

/// Map of wire-prefix → JWT `domains` claim value. Mirrors
/// `apps/mobile/lib/core/sync/domain_prefix.dart` (D-1.4); kept as a
/// small constant set rather than parsing because the active LifeOS
/// domain set is curated, not user-extensible. Note that the wire
/// prefix is a *short tag* (`fin:`, `health:`) while the claim spells
/// the domain in full (`finance`, `health`).
const RECOGNISED_DOMAIN_PREFIXES: &[(&str, &str)] = &[
    ("fin:", "finance"),
    ("health:", "health"),
    ("know:", "knowledge"),
];

/// True when `wire_table` carries a domain prefix that's both recognised
/// by the server and present in the caller's `domains` claim.
/// Rows that fail the check are dropped at the sync boundary so a
/// claim revocation (e.g. user disables HealthOS) takes effect on the
/// next request without an additional `DELETE`.
fn caller_owns_prefix(wire_table: &str, claim_domains: &[String]) -> bool {
    for (prefix, domain) in RECOGNISED_DOMAIN_PREFIXES {
        if wire_table.starts_with(prefix) {
            return claim_domains.iter().any(|d| d == domain);
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &str) -> String {
        v.to_string()
    }

    #[test]
    fn finance_only_claim_accepts_fin_rows() {
        let claim = vec![s("finance")];
        assert!(caller_owns_prefix("fin:accounts", &claim));
        assert!(caller_owns_prefix("fin:journal_entries", &claim));
    }

    #[test]
    fn finance_only_claim_rejects_health_rows() {
        let claim = vec![s("finance")];
        assert!(!caller_owns_prefix("health:sleep_session", &claim));
    }

    #[test]
    fn health_claim_accepts_health_rows() {
        let claim = vec![s("finance"), s("health")];
        assert!(caller_owns_prefix("health:hrv_daily", &claim));
        assert!(caller_owns_prefix("fin:accounts", &claim));
    }

    #[test]
    fn knowledge_claim_accepts_knowledge_rows() {
        let claim = vec![s("finance"), s("knowledge")];
        assert!(caller_owns_prefix("know:knowledge_notes", &claim));
        assert!(caller_owns_prefix("fin:accounts", &claim));
    }

    #[test]
    fn unprefixed_rows_are_always_rejected() {
        let claim = vec![s("finance"), s("health")];
        assert!(!caller_owns_prefix("accounts", &claim));
        assert!(!caller_owns_prefix("", &claim));
    }

    #[test]
    fn unknown_prefix_is_rejected_even_if_claim_contains_it() {
        // The recognised-domain set is curated server-side; a claim
        // can't grow it by listing a name that the server doesn't
        // already accept.
        let claim = vec![s("finance"), s("time")];
        assert!(!caller_owns_prefix("time:slot", &claim));
    }
}

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
pub struct SyncResponse {
    /// Cursor the client adopts after applying this page.
    pub seq: i64,
    pub changes: Vec<RowChange>,
    pub more: bool,
    /// Push rows accepted at the domain/protocol boundary. The client only
    /// clears matching outbox pointers, so rejected-domain rows cannot be
    /// silently lost.
    pub accepted: Vec<RowAck>,
}

#[derive(Serialize)]
pub struct RowAck {
    pub table: String,
    pub id: String,
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

    // D-1.5: drop rows whose domain prefix is not in the caller's
    // `domains` claim. Today every caller's claim is `["finance"]` so
    // only `fin:*` rows flow; once a user opts into HealthOS the next
    // token rotation expands the claim and `health:*` rows are
    // accepted on subsequent requests.
    let body_changes_len = body.changes.len();
    let allowed_changes: Vec<RowChange> = body
        .changes
        .into_iter()
        .filter(|c| caller_owns_prefix(&c.table, &auth.domains))
        .collect();
    let accepted: Vec<RowAck> = allowed_changes
        .iter()
        .map(|c| RowAck {
            table: c.table.clone(),
            id: c.id.clone(),
        })
        .collect();
    metrics.dropped_push = body_changes_len.saturating_sub(allowed_changes.len());

    // Apply the caller's changes first, then pull — so a row the caller just
    // pushed and a peer's newer version of it resolve before the response is
    // built (docs/sync/sync-v2.md §5.1).
    let pushed = store::apply_changes(&db, user_id, device_id, &allowed_changes).await?;
    let mut page = store::pull(&db, user_id, device_id, body.since, PULL_LIMIT).await?;

    // Pull-side filter: the server might have rows in domains the caller
    // can no longer see (e.g. they revoked Health). Drop them here rather
    // than at the client so revocation is server-enforced.
    let before = page.changes.len();
    page.changes
        .retain(|c| caller_owns_prefix(&c.table, &auth.domains));
    metrics.dropped_pull = before.saturating_sub(page.changes.len());

    metrics.pushed = pushed;
    metrics.pulled = page.changes.len();
    metrics.more = page.more;

    let resp = SyncResponse {
        seq: page.high_seq,
        changes: page.changes,
        more: page.more,
        accepted,
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
    /// D-1.5 — rows the caller pushed but couldn't store because their
    /// JWT `domains` claim didn't include the row's domain prefix.
    dropped_push: usize,
    /// D-1.5 — rows that exist server-side but the caller no longer has
    /// the domain claim to pull.
    dropped_pull: usize,
}

fn log_request(status: u16, code: &str, started_ms: i64, metrics: &SyncMetrics) {
    let dur_ms = (Utc::now().timestamp_millis() - started_ms).max(0);
    let slow = dur_ms > SLOW_REQUEST_THRESHOLD_MS;
    worker::console_log!(
        "[SYNC] status={} code={} dur_ms={} pushed={} pulled={} more={} slow={} dropped_push={} dropped_pull={}",
        status,
        code,
        dur_ms,
        metrics.pushed,
        metrics.pulled,
        metrics.more,
        slow,
        metrics.dropped_push,
        metrics.dropped_pull,
    );
}
