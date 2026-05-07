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
use serde::Deserialize;
use serde_json::{json, Value};
use worker::{Headers, Request, Response, Result as WorkerResult, RouteContext};

use crate::ai::anthropic::{
    self, AnthropicMessage, AnthropicRequest, ChatMessage, LlmConfig, DEFAULT_MODEL,
};
use crate::ai::guardrails::{
    self, ANTHROPIC_MAX_OUTPUT_TOKENS, MAX_PROPOSALS_PER_CONVERSATION, MAX_REQUEST_BODY_BYTES,
    MAX_TOOL_ROUNDS, SYSTEM_PROMPT,
};
use crate::ai::sse::encode_event;
use crate::ai::tools::{self, ToolCtx};
use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::routes::common::check_protocol_version;

#[derive(Deserialize)]
struct ChatRequest {
    messages: Vec<ChatMessage>,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    portfolio_snapshot: Option<Value>,
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
    wasm_bindgen_futures::spawn_local(async move {
        run_tool_loop(
            &tx,
            llm_config,
            &model,
            db,
            &user_id,
            initial_messages,
            portfolio_snapshot,
        )
        .await;
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
async fn run_tool_loop(
    tx: &mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>,
    llm_config: LlmConfig,
    model: &str,
    db: worker::D1Database,
    user_id: &str,
    initial_messages: Vec<ChatMessage>,
    portfolio_snapshot: Option<Value>,
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
        let mut tool_uses: Vec<(String, String, Value)> = Vec::new();
        for block in &response.content {
            match block.get("type").and_then(|v| v.as_str()) {
                Some("text") => {
                    if let Some(text) = block.get("text").and_then(|v| v.as_str()) {
                        if !text.is_empty() {
                            send_event(tx, "text", &json!({"text": text})).await;
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
                    tool_uses.push((id, name, input));
                }
                _ => { /* ignore other block types */ }
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
        };
        let mut tool_results: Vec<Value> = Vec::with_capacity(tool_uses.len());
        let mut proposals_this_turn: u8 = 0;
        for (id, name, input) in &tool_uses {
            send_event(
                tx,
                "tool_call",
                &json!({"id": id, "name": name, "input": input}),
            )
            .await;
            let is_propose = name.starts_with("propose_");
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
                tools::dispatch(&ctx, name, input).await
            };
            send_event(
                tx,
                "tool_result",
                &json!({"id": id, "name": name, "output": output}),
            )
            .await;
            // Anthropic accepts either a string or an array of content blocks
            // for tool_result.content. Strings are simpler and round-trip
            // exactly through serde_json.
            let serialized = serde_json::to_string(&output).unwrap_or_else(|_| "null".into());
            tool_results.push(json!({
                "type": "tool_result",
                "tool_use_id": id,
                "content": serialized,
            }));
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
