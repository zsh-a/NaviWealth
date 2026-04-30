use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use worker::{D1Type, Request, Response, Result as WorkerResult, RouteContext};

use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::hlc::{Hlc, CLOCK_SKEW_CAP_MS};
use crate::routes::common::check_protocol_version;
use crate::sync::{materialise, op::Op, op::OpType, state};

const PUSH_BODY_LIMIT: usize = 1024 * 1024;
const PUSH_MAX_OPS: usize = 500;
const PULL_DEFAULT_LIMIT: u32 = 500;
const PULL_BODY_BUDGET: usize = 900 * 1024;

/// Latency above which a sync request is logged as `slow=true` for D1
/// budget tracking. The spec carves a 50 ms D1 CPU budget per push/pull
/// (docs/sync-protocol.md §1) — this threshold is set well below the
/// platform's 50 ms isolate cap so we surface drift before customers do.
/// See docs/sync-monitoring.md for the alerting that consumes this.
const SLOW_REQUEST_THRESHOLD_MS: i64 = 30;

// ---------------------------------------------------------------------------
// POST /sync/push
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct PushBody {
    device_id: String,
    ops: Vec<Op>,
}

#[derive(Serialize)]
struct PushResponse {
    accepted: u32,
    rejected: Vec<RejectedOp>,
    server_hlc_high: String,
    server_now: String,
}

#[derive(Serialize)]
struct RejectedOp {
    op_id: String,
    code: &'static str,
    message: String,
}

pub async fn push(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let started_ms = Utc::now().timestamp_millis();
    let mut metrics = SyncMetrics::default();
    let result = push_inner(req, ctx, &mut metrics).await;
    let (status, code) = match &result {
        Ok(r) => (r.status_code(), "ok"),
        Err(e) => (e.status(), e.code()),
    };
    log_request("push", status, code, started_ms, &metrics);
    match result {
        Ok(r) => Ok(r),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

async fn push_inner(
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
    if raw.len() > PUSH_BODY_LIMIT {
        return Err(AppError::payload_too_large());
    }
    let body: PushBody = serde_json::from_slice(&raw)
        .map_err(|e| AppError::BadRequest(format!("invalid JSON: {e}")))?;

    if body.ops.len() > PUSH_MAX_OPS {
        return Err(AppError::payload_too_large());
    }

    // The JWT ties this caller to a specific device. Pin the batch's
    // declared device_id to that — anything else is a client bug or a token
    // being reused across devices.
    if body.device_id != auth.device_id {
        return Err(AppError::device_mismatch());
    }

    // Pre-flight: batch-level invariants. These bring down the whole batch
    // (HTTP 4xx) — they are not per-op rejections.
    let mut prev_hlc: Option<Hlc> = None;
    for op in &body.ops {
        if op.device_id != body.device_id {
            return Err(AppError::device_mismatch());
        }
        if let Some(prev) = &prev_hlc {
            if &op.hlc < prev {
                return Err(AppError::ops_unordered());
            }
        }
        prev_hlc = Some(op.hlc);
    }

    let server_now_ms = Utc::now().timestamp_millis();
    // Skew cap (docs/sync-protocol.md §3.5). Reject the whole batch up-front
    // so we don't half-apply.
    for op in &body.ops {
        if (op.hlc.phys_ms as i64) > server_now_ms + CLOCK_SKEW_CAP_MS {
            return Err(AppError::clock_skew_too_large());
        }
    }

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    let user_id = auth.user_id.clone();
    let mut clock = state::load(&db, &user_id).await?;
    let mut accepted = 0u32;
    let mut rejected: Vec<RejectedOp> = Vec::new();
    let mut server_hlc_high = clock.as_hlc();

    for op in body.ops.iter() {
        if let Err(e) = op.validate() {
            rejected.push(RejectedOp {
                op_id: op.op_id.clone(),
                code: e.code(),
                message: e.to_string(),
            });
            continue;
        }

        let server_hlc = state::stamp(&mut clock, op.hlc.phys_ms, server_now_ms);
        if server_hlc > server_hlc_high {
            server_hlc_high = server_hlc;
        }

        match materialise::apply(&db, &user_id, op, &server_hlc).await {
            Ok(outcome) => {
                if outcome.op_id_mutated {
                    rejected.push(RejectedOp {
                        op_id: op.op_id.clone(),
                        code: "op_id_mutated",
                        message: "op_id reused with a different client_hlc".into(),
                    });
                } else if outcome.accepted {
                    accepted += 1;
                    if outcome.shadowed {
                        worker::console_log!(
                            "shadowed op {} on {}/{}",
                            op.op_id,
                            op.table,
                            op.row_id
                        );
                    }
                }
            }
            Err(e) => {
                worker::console_log!("apply failed for {}: {e:?}", op.op_id);
                rejected.push(RejectedOp {
                    op_id: op.op_id.clone(),
                    code: e.code(),
                    message: e.to_string(),
                });
            }
        }
    }

    state::save(&db, &user_id, clock).await?;

    metrics.batch_size = body.ops.len();
    metrics.accepted = accepted as usize;
    metrics.rejected = rejected.len();

    let resp = PushResponse {
        accepted,
        rejected,
        server_hlc_high: server_hlc_high.to_canonical(),
        server_now: Utc::now().to_rfc3339(),
    };
    Response::from_json(&resp).map_err(AppError::from)
}

// ---------------------------------------------------------------------------
// GET /sync/pull?since=...&limit=...
//
// `device_id` is sourced from the JWT-bound device, not the query string —
// FIR-29 already pins each token to one device. Filtering ops by that device
// prevents echo loops (SP-G-1).
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct PullResponse {
    ops: Vec<Op>,
    server_hlc_high: String,
    has_more: bool,
    server_now: String,
}

#[derive(Deserialize)]
struct OpRow {
    op_id: String,
    table_name: String,
    row_id: String,
    op_type: String,
    fields_diff: Option<String>,
    hlc_text: String,
    device_id: String,
}

pub async fn pull(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    let started_ms = Utc::now().timestamp_millis();
    let mut metrics = SyncMetrics::default();
    let result = pull_inner(req, ctx, &mut metrics).await;
    let (status, code) = match &result {
        Ok(r) => (r.status_code(), "ok"),
        Err(e) => (e.status(), e.code()),
    };
    log_request("pull", status, code, started_ms, &metrics);
    match result {
        Ok(r) => Ok(r),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

async fn pull_inner(
    req: Request,
    ctx: RouteContext<()>,
    metrics: &mut SyncMetrics,
) -> Result<Response, AppError> {
    check_protocol_version(req.headers())?;
    let auth = require_auth(&req, &ctx).await?;

    let url = req.url().map_err(AppError::from)?;
    let mut since_raw: Option<String> = None;
    let mut limit_raw: Option<String> = None;
    for (k, v) in url.query_pairs() {
        match k.as_ref() {
            "since" => since_raw = Some(v.into_owned()),
            "limit" => limit_raw = Some(v.into_owned()),
            _ => {}
        }
    }

    let since_hlc = match since_raw.as_deref() {
        None | Some("") => Hlc::zero(),
        Some(s) => Hlc::parse(s).map_err(|_| AppError::invalid_hlc())?,
    };
    let limit = match limit_raw.as_deref() {
        Some(s) => s
            .parse::<u32>()
            .map_err(|_| AppError::BadRequest("invalid limit".into()))?
            .clamp(1, PULL_DEFAULT_LIMIT),
        None => PULL_DEFAULT_LIMIT,
    };

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    let user_id = &auth.user_id;
    let device_id = &auth.device_id;
    let since_text = since_hlc.to_canonical();

    // Fetch one extra row so `has_more` is detectable without a second query.
    // `limit` is clamped to PULL_DEFAULT_LIMIT (500); +1 still fits i32.
    let fetch_limit: i32 = (limit as i32) + 1;
    let stmt = db
        .prepare(
            "SELECT op_id, table_name, row_id, op_type, fields_diff, hlc_text, device_id
             FROM op_log
             WHERE user_id = ?1
               AND device_id <> ?2
               AND hlc_text > ?3
             ORDER BY hlc_text ASC
             LIMIT ?4",
        )
        .bind_refs([
            &D1Type::Text(user_id),
            &D1Type::Text(device_id),
            &D1Type::Text(&since_text),
            &D1Type::Integer(fetch_limit),
        ])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let rows: Vec<OpRow> = stmt
        .all()
        .await
        .map_err(|e| AppError::Internal(format!("d1 all: {e}")))?
        .results()
        .map_err(|e| AppError::Internal(format!("d1 results: {e}")))?;

    let mut has_more = false;
    let mut taken = rows;
    if (taken.len() as u32) > limit {
        taken.truncate(limit as usize);
        has_more = true;
    }

    let mut ops: Vec<Op> = Vec::with_capacity(taken.len());
    let mut body_bytes: usize = 0;
    for row in taken {
        let op_type = match row.op_type.as_str() {
            "insert" => OpType::Insert,
            "update" => OpType::Update,
            "delete" => OpType::Delete,
            other => {
                return Err(AppError::Internal(format!(
                    "unknown op_type in db: {other}"
                )));
            }
        };
        let fields_diff: Option<Value> = match row.fields_diff {
            Some(s) if !s.is_empty() => {
                Some(serde_json::from_str(&s).map_err(|e| AppError::Internal(e.to_string()))?)
            }
            _ => None,
        };
        let hlc = Hlc::parse(&row.hlc_text)
            .map_err(|e| AppError::Internal(format!("bad hlc in db: {e:?}")))?;
        let op = Op {
            op_id: row.op_id,
            table: row.table_name,
            row_id: row.row_id,
            op_type,
            fields_diff,
            hlc,
            device_id: row.device_id,
        };

        // Body-size cap (docs/sync-protocol.md §8.2). Stop early if the next
        // op would push the page past the budget.
        let estimated = serde_json::to_string(&op).map(|s| s.len()).unwrap_or(0);
        if !ops.is_empty() && body_bytes + estimated > PULL_BODY_BUDGET {
            has_more = true;
            break;
        }
        body_bytes += estimated;
        ops.push(op);
    }

    let high_row: Option<HighRow> = db
        .prepare("SELECT MAX(hlc_text) AS hlc_text FROM op_log WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("d1 first: {e}")))?;
    let server_hlc_high = match high_row.and_then(|r| r.hlc_text) {
        Some(s) => s,
        None => Hlc::zero().to_canonical(),
    };

    metrics.pulled = ops.len();
    metrics.has_more = has_more;

    let resp = PullResponse {
        ops,
        server_hlc_high,
        has_more,
        server_now: Utc::now().to_rfc3339(),
    };
    Response::from_json(&resp).map_err(AppError::from)
}

// ---------------------------------------------------------------------------
// Structured request log — consumed by `wrangler tail` and the dashboards
// described in docs/sync-monitoring.md. The format is intentionally stable
// and grep-friendly:
//
//     [SYNC] op=push status=200 code=ok dur_ms=12 batch=487 acc=487 rej=0 slow=false
//
// Adding a field is fine; reordering or renaming will break parsing on the
// monitoring side. Bump a small version tag in the log if you ever do that.
// ---------------------------------------------------------------------------

#[derive(Default)]
struct SyncMetrics {
    /// Push: total ops in the batch.
    batch_size: usize,
    /// Push: ops accepted into op_log.
    accepted: usize,
    /// Push: ops rejected per-op (op_id_mutated, unknown_table, …).
    rejected: usize,
    /// Pull: ops returned in this page.
    pulled: usize,
    /// Pull: whether the client must page again.
    has_more: bool,
}

fn log_request(op: &str, status: u16, code: &str, started_ms: i64, metrics: &SyncMetrics) {
    let dur_ms = (Utc::now().timestamp_millis() - started_ms).max(0);
    let slow = dur_ms > SLOW_REQUEST_THRESHOLD_MS;
    let detail = if op == "push" {
        format!(
            "batch={} acc={} rej={}",
            metrics.batch_size, metrics.accepted, metrics.rejected
        )
    } else {
        format!("pulled={} has_more={}", metrics.pulled, metrics.has_more)
    };
    worker::console_log!(
        "[SYNC] op={} status={} code={} dur_ms={} {} slow={}",
        op,
        status,
        code,
        dur_ms,
        detail,
        slow
    );
}

#[derive(Deserialize)]
struct HighRow {
    hlc_text: Option<String>,
}
