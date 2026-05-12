//! `POST /ai/chat` — the AI assistant entry point (FIR-59).

use std::rc::Rc;

use futures_channel::mpsc;
use gloo_timers::future::TimeoutFuture;
use serde::Deserialize;
use serde_json::Value;
use worker::{Headers, Request, Response, Result as WorkerResult, RouteContext};

use crate::ai::adapters::anthropic::{AnthropicAdapter, ChatMessage, LlmConfig, DEFAULT_MODEL};
use crate::ai::context::{ContextPack, CURRENT_CONTEXT_PACK_VERSION};
use crate::ai::guardrails::{self, MAX_REQUEST_BODY_BYTES};
use crate::ai::runtime::{AgentLoop, CloudToolDispatcher, Session, TurnBudget};
use crate::ai::sse::encode_comment;
use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::routes::common::check_protocol_version;

mod ingest;
mod sse_sink;
mod sse_sink_v2;

#[cfg(test)]
mod tests;

const SSE_KEEPALIVE_MS: u32 = 10_000;
const AI_PROTOCOL_HEADER: &str = "X-Naviwealth-AI-Protocol";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AiProtocolVersion {
    V1,
    V2,
}

#[derive(Deserialize)]
struct ChatRequest {
    messages: Vec<ChatMessage>,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    portfolio_snapshot: Option<Value>,
    #[serde(default)]
    context_pack: Option<ContextPack>,
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
    let ai_protocol = ai_protocol_version(req.headers());
    let auth = require_auth(&req, &ctx).await?;

    let body = parse_body(&mut req).await?;
    validate_messages(&body.messages)?;
    validate_context_pack(body.context_pack.as_ref())?;

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    ingest::ingest_context_pack(&db, &auth.user_id, body.context_pack.as_ref()).await?;
    guardrails::check_and_record_rate_limit(&db, &auth.user_id).await?;

    let api_key = ctx
        .env
        .secret("LLM_API_KEY")
        .or_else(|_| ctx.env.secret("ANTHROPIC_API_KEY"))
        .map(|s| s.to_string())
        .map_err(|_| AppError::Internal("LLM_API_KEY unbound".into()))?;
    let base_url = ctx.env.var("LLM_BASE_URL").map(|v| v.to_string()).ok();
    let default_model = ctx
        .env
        .var("LLM_MODEL")
        .map(|v| v.to_string())
        .unwrap_or_else(|_| DEFAULT_MODEL.to_string());
    let model = body
        .model
        .filter(|m| !m.is_empty())
        .unwrap_or(default_model);

    let context_tier = body.context_pack.as_ref().map(|p| p.budget.tier);
    let system_appendix = body
        .context_pack
        .as_ref()
        .map(crate::ai::context::format_context_pack);
    let mut session = Session::new(
        body.messages,
        body.portfolio_snapshot,
        context_tier,
        system_appendix,
    );

    let (tx, rx) = mpsc::unbounded::<Result<Vec<u8>, worker::Error>>();
    spawn_keepalive(tx.clone());

    wasm_bindgen_futures::spawn_local(async move {
        let adapter = AnthropicAdapter::new(LlmConfig::new(api_key, base_url));
        let dispatcher = Rc::new(CloudToolDispatcher::new(db, auth.user_id));
        let agent = AgentLoop::new(adapter, model, dispatcher, TurnBudget::default());
        match ai_protocol {
            AiProtocolVersion::V1 => {
                let mut sink = sse_sink::SseEventSink::new(tx);
                if let Err(e) = agent.run(&mut session, &mut sink).await {
                    e.log();
                }
            }
            AiProtocolVersion::V2 => {
                let mut sink = sse_sink_v2::SseEventSinkV2::new(tx);
                if let Err(e) = agent.run(&mut session, &mut sink).await {
                    e.log();
                }
            }
        }
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

fn ai_protocol_version(headers: &Headers) -> AiProtocolVersion {
    match headers.get(AI_PROTOCOL_HEADER) {
        Ok(Some(value)) => ai_protocol_version_from_header(Some(value.as_str())),
        _ => AiProtocolVersion::V1,
    }
}

fn ai_protocol_version_from_header(value: Option<&str>) -> AiProtocolVersion {
    match value {
        Some("2") => AiProtocolVersion::V2,
        _ => AiProtocolVersion::V1,
    }
}

async fn parse_body(req: &mut Request) -> Result<ChatRequest, AppError> {
    let raw = req
        .bytes()
        .await
        .map_err(|e| AppError::BadRequest(format!("body read: {e}")))?;
    if raw.len() > MAX_REQUEST_BODY_BYTES {
        return Err(AppError::payload_too_large());
    }
    serde_json::from_slice(&raw).map_err(|e| AppError::BadRequest(format!("invalid JSON: {e}")))
}

fn validate_messages(messages: &[ChatMessage]) -> Result<(), AppError> {
    if messages.is_empty() {
        return Err(AppError::BadRequest("messages must not be empty".into()));
    }
    if messages
        .iter()
        .any(|m| m.role != "user" && m.role != "assistant")
    {
        return Err(AppError::BadRequest("unsupported message role".into()));
    }
    Ok(())
}

fn validate_context_pack(pack: Option<&ContextPack>) -> Result<(), AppError> {
    let Some(pack) = pack else {
        return Ok(());
    };
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
    Ok(())
}

fn spawn_keepalive(tx: mpsc::UnboundedSender<Result<Vec<u8>, worker::Error>>) {
    wasm_bindgen_futures::spawn_local(async move {
        loop {
            TimeoutFuture::new(SSE_KEEPALIVE_MS).await;
            if tx.unbounded_send(Ok(encode_comment("keepalive"))).is_err() {
                break;
            }
        }
    });
}
