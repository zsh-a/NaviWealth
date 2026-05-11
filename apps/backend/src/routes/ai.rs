//! `POST /ai/chat` — the AI assistant entry point (FIR-59).
//!
//! Wire flow:
//!
//! 1. Auth + protocol-version check (shared with the rest of the API).
//! 2. Body-size cap, then JSON parse into [`ChatRequest`].
//! 3. Per-user rate limit (60/h) — check happens *before* we spend money on
//!    the LLM provider.
//! 4. Hand the conversation off to a [`spawn_local`] task that runs the tool
//!    loop and writes SSE frames to a channel; the response body is just the
//!    receiving end of that channel.
//!
//! We deliberately do not pass the user's bearer token to the LLM provider; the
//! Worker authenticates with its own API key out of `wrangler secret`.

use chrono::Utc;
use futures_channel::mpsc;
use futures_util::future::{select, Either};
use gloo_timers::future::TimeoutFuture;
use serde::Deserialize;
use serde_json::{json, Value};
use worker::{Headers, Request, Response, Result as WorkerResult, RouteContext};

use crate::ai::anthropic::{
    self, AnthropicMessage, AnthropicRequest, ChatMessage, LlmConfig, DEFAULT_MODEL,
};
use crate::ai::context::{ContextPack, CURRENT_CONTEXT_PACK_VERSION};
use crate::ai::guardrails::{
    self, ANTHROPIC_MAX_OUTPUT_TOKENS, MAX_PROPOSALS_PER_CONVERSATION, MAX_REQUEST_BODY_BYTES,
    MAX_TOOL_ROUNDS, SYSTEM_PROMPT,
};
use crate::ai::sse::{encode_comment, encode_event};
use crate::ai::tools::{self, ToolCtx};
use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::routes::common::check_protocol_version;

/// Hard cap on a single chat turn (model rounds + tool dispatches combined).
/// If hit, the SSE stream is closed with a synthesized `error` + `done` so
/// the client never sits on a hung connection. 60s comfortably covers
/// healthy multi-tool turns; anything longer almost always means an
/// upstream call is stuck.
const CHAT_TURN_BUDGET_MS: u32 = 60_000;

/// Keepalive cadence on the SSE channel. Comment frames (no event name) keep
/// proxies / mobile radios from dropping the connection for being idle and
/// reset the client's idle watchdog. Should be well below the client's
/// idle timeout and any reverse-proxy idle drop.
const SSE_KEEPALIVE_MS: u32 = 10_000;

#[derive(Deserialize)]
struct ChatRequest {
    messages: Vec<ChatMessage>,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    portfolio_snapshot: Option<Value>,
    /// Phase 2-A: typed context summary built by the device
    /// `ContextCompressor`. Validated for version + budget here, but
    /// not yet threaded into the system prompt — that's a separate
    /// Phase 2.5 decision once the planner can actually consume it.
    #[serde(default)]
    context_pack: Option<ContextPack>,
}

#[derive(Debug, Clone, PartialEq)]
struct ToolUse {
    id: String,
    name: String,
    input: Value,
}

pub async fn chat(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    match chat_inner(req, ctx).await {
        Ok(r) => Ok(r),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

async fn chat_inner(mut req: Request, ctx: RouteContext<()>) -> Result<Response, AppError> {
    check_protocol_version(req.headers())?;
    let auth = require_auth(&req, &ctx).await?;

    let raw = req
        .bytes()
        .await
        .map_err(|e| AppError::BadRequest(format!("body read: {e}")))?;
    if raw.len() > MAX_REQUEST_BODY_BYTES {
        return Err(AppError::payload_too_large());
    }
    let body: ChatRequest = serde_json::from_slice(&raw)
        .map_err(|e| AppError::BadRequest(format!("invalid JSON: {e}")))?;
    if body.messages.is_empty() {
        return Err(AppError::BadRequest("messages must not be empty".into()));
    }
    if body
        .messages
        .iter()
        .any(|m| m.role != "user" && m.role != "assistant")
    {
        return Err(AppError::BadRequest("unsupported message role".into()));
    }
    if let Some(ref pack) = body.context_pack {
        pack.assert_version(&CURRENT_CONTEXT_PACK_VERSION)
            .map_err(|e| AppError::BadRequest(format!("context_pack: {e}")))?;
        pack.assert_budget()
            .map_err(|e| AppError::BadRequest(format!("context_pack: {e}")))?;
        worker::console_log!(
            "context_pack received: tier={:?} version={}.{} signals={} aggregates={}",
            pack.budget.tier,
            pack.version.major,
            pack.version.minor,
            pack.task.signals.len(),
            pack.task.aggregates.len(),
        );
    }

    // Freshness gate Phase 2 (docs/ai-architecture.md §4.2): if the
    // device flagged read models as stale on the previous turn, drop
    // their freshness_meta rows so this turn's tool dispatch triggers
    // a fresh `refresh()`. Idempotent + cheap; unknown names ignored.
    if let Some(ref pack) = body.context_pack {
        if let Some(ref hint) = pack.task.freshness_hint {
            let db_for_hint = ctx
                .env
                .d1("DB")
                .map_err(|_| AppError::Internal("DB unbound".into()))?;
            for name in &hint.force_refresh_read_models {
                if name.is_empty() {
                    continue;
                }
                crate::ai::read_models::projection::clear_freshness_meta(
                    &db_for_hint,
                    &auth.user_id,
                    name,
                )
                .await?;
                worker::console_log!(
                    "freshness_hint: cleared read_model={name} for user={}",
                    auth.user_id
                );
            }
        }
    }

    // Analytical layer ingest (docs/ai-architecture.md §4.3.3): device
    // detector output → device-sourced read models. Phase 1 routes
    // kind=='recurring_pattern' to the recurring_patterns table; other
    // kinds are silently ignored (next analytical models pick them up).
    if let Some(ref pack) = body.context_pack {
        if !pack.task.analytical_uploads.is_empty() {
            let device_hlc = pack
                .task
                .device_hlc
                .as_deref()
                .filter(|s| !s.is_empty())
                .unwrap_or("0.0000-00000000-0000-0000-0000-000000000000");
            let db_for_ingest = ctx
                .env
                .d1("DB")
                .map_err(|_| AppError::Internal("DB unbound".into()))?;
            let recurring: Vec<
                crate::ai::read_models::recurring_patterns::RecurringPatternUpload<'_>,
            > = pack
                .task
                .analytical_uploads
                .iter()
                .filter(|u| u.kind == "recurring_pattern")
                .map(|u| {
                    crate::ai::read_models::recurring_patterns::RecurringPatternUpload {
                        id: &u.id,
                        payload: &u.payload,
                        source_device_id: None, // device_id is on auth, not per-upload
                    }
                })
                .collect();
            if !recurring.is_empty() {
                let n = crate::ai::read_models::recurring_patterns::ingest(
                    &db_for_ingest,
                    &auth.user_id,
                    device_hlc,
                    &recurring,
                )
                .await?;
                worker::console_log!(
                    "analytical_uploads: ingested {n} recurring_patterns for user={}",
                    auth.user_id
                );
            }

            // kind == 'anomaly_flag' (Wave 11)
            let anomalies: Vec<
                crate::ai::read_models::anomaly_flags::AnomalyFlagUpload<'_>,
            > = pack
                .task
                .analytical_uploads
                .iter()
                .filter(|u| u.kind == "anomaly_flag")
                .map(|u| crate::ai::read_models::anomaly_flags::AnomalyFlagUpload {
                    id: &u.id,
                    payload: &u.payload,
                    source_device_id: None,
                })
                .collect();
            if !anomalies.is_empty() {
                let n = crate::ai::read_models::anomaly_flags::ingest(
                    &db_for_ingest,
                    &auth.user_id,
                    device_hlc,
                    &anomalies,
                )
                .await?;
                worker::console_log!(
                    "analytical_uploads: ingested {n} anomaly_flags for user={}",
                    auth.user_id
                );
            }

            // kind == 'refund_link' (Wave 16)
            let refunds: Vec<
                crate::ai::read_models::refund_links::RefundLinkUpload<'_>,
            > = pack
                .task
                .analytical_uploads
                .iter()
                .filter(|u| u.kind == "refund_link")
                .map(|u| crate::ai::read_models::refund_links::RefundLinkUpload {
                    id: &u.id,
                    payload: &u.payload,
                    source_device_id: None,
                })
                .collect();
            if !refunds.is_empty() {
                let n = crate::ai::read_models::refund_links::ingest(
                    &db_for_ingest,
                    &auth.user_id,
                    device_hlc,
                    &refunds,
                )
                .await?;
                worker::console_log!(
                    "analytical_uploads: ingested {n} refund_links for user={}",
                    auth.user_id
                );
            }

            // kind == 'transfer_link' (Wave 16)
            let transfers: Vec<
                crate::ai::read_models::transfer_links::TransferLinkUpload<'_>,
            > = pack
                .task
                .analytical_uploads
                .iter()
                .filter(|u| u.kind == "transfer_link")
                .map(|u| {
                    crate::ai::read_models::transfer_links::TransferLinkUpload {
                        id: &u.id,
                        payload: &u.payload,
                        source_device_id: None,
                    }
                })
                .collect();
            if !transfers.is_empty() {
                let n = crate::ai::read_models::transfer_links::ingest(
                    &db_for_ingest,
                    &auth.user_id,
                    device_hlc,
                    &transfers,
                )
                .await?;
                worker::console_log!(
                    "analytical_uploads: ingested {n} transfer_links for user={}",
                    auth.user_id
                );
            }
        }
    }

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    guardrails::check_and_record_rate_limit(&db, &auth.user_id).await?;

    let api_key = ctx
        .env
        .secret("LLM_API_KEY")
        .or_else(|_| ctx.env.secret("ANTHROPIC_API_KEY"))
        .map(|s| s.to_string())
        .map_err(|_| AppError::Internal("LLM_API_KEY unbound".into()))?;
    let base_url = ctx.env.var("LLM_BASE_URL").map(|v| v.to_string()).ok();
    let llm_config = LlmConfig::new(api_key, base_url);
    let default_model = ctx
        .env
        .var("LLM_MODEL")
        .map(|v| v.to_string())
        .unwrap_or_else(|_| DEFAULT_MODEL.to_string());

    let model = body
        .model
        .filter(|m| !m.is_empty())
        .unwrap_or(default_model);

    // Channel that backs Response::from_stream. Unbounded is fine: emissions
    // are bounded by MAX_TOOL_ROUNDS and the model's max_tokens, so backpressure
    // can't run away. Each message holds either an SSE frame or a worker error
    // we want to surface as a stream abort.
    let (tx, rx) = mpsc::unbounded::<Result<Vec<u8>, worker::Error>>();

    // Take ownership of everything the loop needs and hand it to the task.
    // D1Database, String, and Vec are all 'static + safe to move.
    let user_id = auth.user_id.clone();
    let initial_messages = body.messages;
    let portfolio_snapshot = body.portfolio_snapshot;
    let context_tier = body.context_pack.as_ref().map(|p| p.budget.tier);

    // Keepalive ticker — emits a `:` comment frame every SSE_KEEPALIVE_MS
    // so proxies / mobile radios don't drop the connection during slow
    // tool dispatches and the client's idle watchdog stays satisfied.
    // Lives in its own spawned task; cancelled when the work future
    // wins the `select` below (the receiver dropping closes the stream
    // and the next ticker iteration's `unbounded_send` becomes a no-op).
    let keepalive_tx = tx.clone();
    wasm_bindgen_futures::spawn_local(async move {
        loop {
            TimeoutFuture::new(SSE_KEEPALIVE_MS).await;
            if keepalive_tx
                .unbounded_send(Ok(encode_comment("keepalive")))
                .is_err()
            {
                break;
            }
        }
    });

    // Run the tool loop with an absolute time budget. If the loop
    // outlives CHAT_TURN_BUDGET_MS — almost always because an upstream
    // D1 read or Anthropic call is stuck inside the spawned-task
    // context — we synthesize an `error` + `done` so the client can
    // clean up the streaming row instead of hanging forever.
    wasm_bindgen_futures::spawn_local(async move {
        let work = Box::pin(run_tool_loop(
            &tx,
            llm_config,
            &model,
            db,
            &user_id,
            initial_messages,
            portfolio_snapshot,
            context_tier,
        ));
        let budget = Box::pin(TimeoutFuture::new(CHAT_TURN_BUDGET_MS));
        match select(work, budget).await {
            Either::Left(_) => { /* normal completion — done already sent */ }
            Either::Right(_) => {
                send_event(
                    &tx,
                    "error",
                    &json!({"message": "chat turn timed out", "code": "chat_timeout"}),
                )
                .await;
                send_event(
                    &tx,
                    "done",
                    &json!({"stop_reason": "error", "rounds": 0}),
                )
                .await;
            }
        }
        // `tx` drops here; receiver sees end-of-stream and the SSE body
        // closes, which also breaks the keepalive ticker on its next tick.
    });

    let headers = Headers::new();
    headers
        .set("content-type", "text/event-stream")
        .map_err(|e| AppError::Internal(format!("hdr: {e}")))?;
    headers
        .set("cache-control", "no-cache")
        .map_err(|e| AppError::Internal(format!("hdr: {e}")))?;
    headers
        .set("x-accel-buffering", "no")
        .map_err(|e| AppError::Internal(format!("hdr: {e}")))?;

    let resp =
        Response::from_stream(rx).map_err(|e| AppError::Internal(format!("from_stream: {e}")))?;
    Ok(resp.with_headers(headers))
}

/// Drive the LLM ↔ tool conversation. Writes SSE frames into `tx` as it goes:
///
/// - `event: tool_call`  — `{ "id", "name", "input" }`
/// - `event: tool_result` — `{ "id", "output" }`
/// - `event: text`        — `{ "text": "..." }`
/// - `event: error`       — `{ "message": "..." }` followed by `done`
/// - `event: done`        — `{ "stop_reason": "...", "rounds": n }`
///
/// The task must close `tx` (drop) when done so the client connection ends.
// 8 args is one over clippy's default but we deliberately keep the
// ownership story flat here — bundling into a struct would force a
// borrow lifetime onto the spawned task that doesn't pull its weight.
#[allow(clippy::too_many_arguments)]
async fn run_tool_loop(
    tx: &mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>,
    llm_config: LlmConfig,
    model: &str,
    db: worker::D1Database,
    user_id: &str,
    initial_messages: Vec<ChatMessage>,
    portfolio_snapshot: Option<Value>,
    context_tier: Option<crate::ai::context::BudgetTier>,
) {
    // Inject "current time" as a synthetic system suffix; the model is told
    // to rely on this rather than guess.
    let system_with_time = format!(
        "{SYSTEM_PROMPT}\n\n当前服务器时间: {}",
        Utc::now().to_rfc3339()
    );
    let tool_schemas = tools::schemas();
    let mut messages = initial_messages;

    let mut last_stop = "end_turn".to_string();
    let mut rounds_used = 0u8;
    for round in 0..MAX_TOOL_ROUNDS {
        rounds_used = round + 1;
        let payload = AnthropicRequest {
            model,
            max_tokens: ANTHROPIC_MAX_OUTPUT_TOKENS,
            system: &system_with_time,
            messages: &messages,
            tools: &tool_schemas,
            stream: false,
        };
        let response: AnthropicMessage = match anthropic::call_blocking(&llm_config, &payload).await
        {
            Ok(m) => m,
            Err(e) => {
                send_event(tx, "error", &json!({"message": e.to_string()})).await;
                send_event(
                    tx,
                    "done",
                    &json!({"stop_reason": "error", "rounds": rounds_used}),
                )
                .await;
                return;
            }
        };
        last_stop = response
            .stop_reason
            .clone()
            .unwrap_or_else(|| "unknown".into());

        // Emit text blocks immediately; collect tool_use blocks so we can
        // dispatch them after we've replayed the assistant turn.
        let (text_blocks, tool_uses) = split_model_content(&response.content);
        for text in text_blocks {
            if !text.is_empty() {
                send_event(tx, "text", &json!({"text": text})).await;
            }
        }

        if tool_uses.is_empty() {
            // No tools requested — model has finished its turn.
            break;
        }

        // Count `propose_*` calls already in the conversation *before* we
        // append the current assistant turn. Combined with `proposals_this_turn`
        // below this gives us the running total used to enforce
        // MAX_PROPOSALS_PER_CONVERSATION (FIR-66 guardrail).
        let proposals_before = guardrails::count_existing_proposals(&messages);

        // Push the assistant turn (with the original tool_use blocks) onto
        // the conversation, then dispatch each tool and queue the
        // tool_result blocks under a single user turn.
        messages.push(ChatMessage {
            role: "assistant".into(),
            content: Value::Array(response.content.clone()),
        });

        let ctx = ToolCtx {
            user_id,
            db: &db,
            portfolio_snapshot: portfolio_snapshot.as_ref(),
            context_tier,
        };
        let mut tool_results: Vec<Value> = Vec::with_capacity(tool_uses.len());
        let mut proposals_this_turn: u8 = 0;
        for tool_use in &tool_uses {
            send_event(
                tx,
                "tool_call",
                &json!({"id": tool_use.id, "name": tool_use.name, "input": tool_use.input}),
            )
            .await;
            let is_propose = tool_use.name.starts_with("propose_");
            let output = if is_propose
                && proposals_before.saturating_add(proposals_this_turn)
                    >= MAX_PROPOSALS_PER_CONVERSATION
            {
                // Cap reached. Return a synthesised tool_result so the model
                // sees the failure and can ask the user to wrap up the
                // pending confirmations rather than retrying. We deliberately
                // never invoke the proposal builder here — the dispatcher
                // doesn't even touch D1 for this call.
                json!({
                    "error":   "proposal_cap_exceeded",
                    "code":    "proposal_cap_exceeded",
                    "limit":   MAX_PROPOSALS_PER_CONVERSATION,
                    "message": format!(
                        "本次对话已达到 {MAX_PROPOSALS_PER_CONVERSATION} 个 propose_* 上限。\
                         请让用户先在前端确认页处理已有的提议（确认或取消），再继续录入。"
                    ),
                })
            } else {
                if is_propose {
                    proposals_this_turn = proposals_this_turn.saturating_add(1);
                }
                tools::dispatch(&ctx, &tool_use.name, &tool_use.input).await
            };
            send_event(
                tx,
                "tool_result",
                &json!({"id": tool_use.id, "name": tool_use.name, "output": output}),
            )
            .await;
            // Anthropic accepts either a string or an array of content blocks
            // for tool_result.content. Strings are simpler and round-trip
            // exactly through serde_json.
            tool_results.push(tool_result_block(&tool_use.id, &output));
        }
        messages.push(ChatMessage {
            role: "user".into(),
            content: Value::Array(tool_results),
        });

        // Loop. The next iteration sends the augmented conversation back to
        // the LLM so it can compose the user-facing reply.
    }

    if rounds_used >= MAX_TOOL_ROUNDS && last_stop == "tool_use" {
        send_event(
            tx,
            "error",
            &json!({"message": "tool round budget exhausted"}),
        )
        .await;
    }
    send_event(
        tx,
        "done",
        &json!({"stop_reason": last_stop, "rounds": rounds_used}),
    )
    .await;
    // Drop happens on scope exit; the receiver sees `None` and the response
    // body closes cleanly.
}

async fn send_event(
    tx: &mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>,
    name: &str,
    payload: &Value,
) {
    let body = serde_json::to_string(payload).unwrap_or_else(|_| "{}".into());
    let frame = encode_event(name, &body);
    // unbounded_send only fails when the receiver has been dropped — i.e. the
    // client closed the SSE connection. There's nothing useful we can do
    // about it from here; let the spawned task exit naturally on the next
    // iteration.
    let _ = tx.unbounded_send(Ok(frame));
}

fn split_model_content(content: &[Value]) -> (Vec<String>, Vec<ToolUse>) {
    let mut text_blocks = Vec::new();
    let mut tool_uses = Vec::new();
    for block in content {
        match block.get("type").and_then(|v| v.as_str()) {
            Some("text") => {
                if let Some(text) = block.get("text").and_then(|v| v.as_str()) {
                    if !text.is_empty() {
                        text_blocks.push(text.to_string());
                    }
                }
            }
            Some("tool_use") => {
                let id = block
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let name = block
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let input = block.get("input").cloned().unwrap_or(Value::Null);
                tool_uses.push(ToolUse { id, name, input });
            }
            _ => { /* ignore other block types */ }
        }
    }
    (text_blocks, tool_uses)
}

fn tool_result_block(tool_use_id: &str, output: &Value) -> Value {
    let serialized = serde_json::to_string(output).unwrap_or_else(|_| "null".into());
    json!({
        "type": "tool_result",
        "tool_use_id": tool_use_id,
        "content": serialized,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn split_model_content_extracts_text_and_tool_use_blocks() {
        let content = vec![
            json!({"type": "text", "text": "我先查看持仓。"}),
            json!({
                "type": "tool_use",
                "id": "toolu_1",
                "name": "get_risk_alerts",
                "input": {"as_of": "2026-05-07"}
            }),
            json!({"type": "image", "source": "ignored"}),
            json!({"type": "text", "text": ""}),
        ];

        let (texts, tools) = split_model_content(&content);

        assert_eq!(texts, vec!["我先查看持仓。"]);
        assert_eq!(
            tools,
            vec![ToolUse {
                id: "toolu_1".into(),
                name: "get_risk_alerts".into(),
                input: json!({"as_of": "2026-05-07"}),
            }]
        );
    }

    #[test]
    fn tool_result_block_serializes_output_for_next_llm_round() {
        let output = json!({
            "alerts": [
                {"kind": "asset_concentration", "severity": "high"}
            ],
            "base_currency": "CNY"
        });

        let block = tool_result_block("toolu_1", &output);

        assert_eq!(block["type"], "tool_result");
        assert_eq!(block["tool_use_id"], "toolu_1");
        let content = block["content"].as_str().unwrap();
        let decoded: Value = serde_json::from_str(content).unwrap();
        assert_eq!(decoded, output);
    }

    #[test]
    fn chat_request_parses_with_context_pack() {
        let raw = r#"{
            "messages": [{"role": "user", "content": "hi"}],
            "context_pack": {
                "version": {"major": 1, "minor": 0},
                "base": {
                    "preferred_currency": "USD",
                    "risk_preference": "moderate",
                    "accounts": {"total_count": 0, "by_kind": {}},
                    "cashflow": {
                        "base_currency": "USD",
                        "months_covered": 0,
                        "average_inflow_minor": "0",
                        "average_outflow_minor": "0",
                        "trend": "unknown"
                    }
                },
                "task": {
                    "route": {"path": "/expense", "area": "expense"},
                    "intent": {"capability": "analyze", "risk": "suggest"}
                },
                "budget": {"tier": "standard"}
            }
        }"#;

        let body: ChatRequest = serde_json::from_str(raw).expect("parse");
        let pack = body.context_pack.expect("context_pack present");
        assert!(pack.assert_version(&CURRENT_CONTEXT_PACK_VERSION).is_ok());
        assert!(pack.assert_budget().is_ok());
    }

    #[test]
    fn chat_request_parses_without_context_pack_for_legacy_clients() {
        let raw = r#"{"messages": [{"role": "user", "content": "hi"}]}"#;
        let body: ChatRequest = serde_json::from_str(raw).expect("parse");
        assert!(body.context_pack.is_none());
    }

    #[test]
    fn chat_request_parses_freshness_hint_with_force_refresh() {
        let raw = r#"{
            "messages": [{"role": "user", "content": "hi"}],
            "context_pack": {
                "version": {"major": 1, "minor": 0},
                "base": {
                    "preferred_currency": "USD",
                    "risk_preference": "moderate",
                    "accounts": {"total_count": 0, "by_kind": {}},
                    "cashflow": {
                        "base_currency": "USD",
                        "months_covered": 0,
                        "average_inflow_minor": "0",
                        "average_outflow_minor": "0",
                        "trend": "unknown"
                    }
                },
                "task": {
                    "route": {"path": "/", "area": "home"},
                    "intent": {"capability": "analyze", "risk": "info"},
                    "freshness_hint": {
                        "force_refresh_read_models": [
                            "monthly_spend_by_category",
                            "holdings_snapshot"
                        ]
                    }
                },
                "budget": {"tier": "standard"}
            }
        }"#;
        let body: ChatRequest = serde_json::from_str(raw).expect("parse");
        let pack = body.context_pack.expect("present");
        let hint = pack.task.freshness_hint.expect("hint present");
        assert_eq!(
            hint.force_refresh_read_models,
            vec![
                "monthly_spend_by_category".to_string(),
                "holdings_snapshot".to_string()
            ]
        );
    }

    #[test]
    fn freshness_hint_absent_defaults_to_none() {
        let raw = r#"{
            "messages": [{"role": "user", "content": "hi"}],
            "context_pack": {
                "version": {"major": 1, "minor": 0},
                "base": {
                    "preferred_currency": "USD",
                    "risk_preference": "moderate",
                    "accounts": {"total_count": 0, "by_kind": {}},
                    "cashflow": {
                        "base_currency": "USD",
                        "months_covered": 0,
                        "average_inflow_minor": "0",
                        "average_outflow_minor": "0",
                        "trend": "unknown"
                    }
                },
                "task": {
                    "route": {"path": "/", "area": "home"},
                    "intent": {"capability": "analyze", "risk": "info"}
                },
                "budget": {"tier": "small"}
            }
        }"#;
        let body: ChatRequest = serde_json::from_str(raw).expect("parse");
        let pack = body.context_pack.expect("present");
        assert!(pack.task.freshness_hint.is_none());
    }

    #[test]
    fn context_pack_rejects_incompatible_major_version() {
        use crate::ai::context::*;
        let pack = ContextPack {
            version: ContextPackVersion { major: 2, minor: 0 },
            base: BaseContext {
                preferred_currency: "USD".into(),
                risk_preference: RiskPreference::Moderate,
                accounts: AccountSummary {
                    total_count: 0,
                    by_kind: Default::default(),
                },
                cashflow: CashflowSummary {
                    base_currency: "USD".into(),
                    months_covered: 0,
                    average_inflow_minor: "0".into(),
                    average_outflow_minor: "0".into(),
                    trend: CashflowTrend::Unknown,
                },
                fire_goal: None,
            },
            task: TaskContext {
                route: RouteContext {
                    path: "/".into(),
                    area: "home".into(),
                },
                intent: IntentHint {
                    capability: Capability::Analyze,
                    risk: RiskLevel::Info,
                    side_effect: None,
                    label: None,
                },
                signals: Vec::new(),
                retrieved: Vec::new(),
                aggregates: Vec::new(),
                freshness_hint: None,
                analytical_uploads: Vec::new(),
                device_hlc: None,
            },
            budget: PrivacyBudget {
                tier: BudgetTier::Standard,
            },
        };
        let res = pack.assert_version(&CURRENT_CONTEXT_PACK_VERSION);
        assert!(matches!(
            res,
            Err(ContextPackError::VersionUnsupported { .. })
        ));
    }

    #[test]
    fn llm_tool_round_replays_assistant_tool_use_then_user_tool_result() {
        let mut messages = vec![ChatMessage {
            role: "user".into(),
            content: json!("帮我看看持仓里风险最高的资产。"),
        }];
        let response_content = vec![
            json!({"type": "text", "text": "我先检查风险提示。"}),
            json!({
                "type": "tool_use",
                "id": "toolu_1",
                "name": "get_risk_alerts",
                "input": {}
            }),
        ];
        let (_, tools) = split_model_content(&response_content);

        messages.push(ChatMessage {
            role: "assistant".into(),
            content: Value::Array(response_content.clone()),
        });
        messages.push(ChatMessage {
            role: "user".into(),
            content: Value::Array(vec![tool_result_block(
                &tools[0].id,
                &json!({"alerts": [], "approximation": true}),
            )]),
        });

        assert_eq!(messages.len(), 3);
        assert_eq!(messages[1].role, "assistant");
        assert_eq!(messages[1].content[1]["type"], "tool_use");
        assert_eq!(messages[1].content[1]["name"], "get_risk_alerts");
        assert_eq!(messages[2].role, "user");
        assert_eq!(messages[2].content[0]["type"], "tool_result");
        assert_eq!(messages[2].content[0]["tool_use_id"], "toolu_1");
        let tool_output: Value =
            serde_json::from_str(messages[2].content[0]["content"].as_str().unwrap()).unwrap();
        assert_eq!(tool_output["alerts"], json!([]));
    }
}
