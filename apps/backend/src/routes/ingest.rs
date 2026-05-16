//! `POST /ingest/parse` — Layer 4 cloud Vision parse (§5.10.10 /
//! S5b-vision).
//!
//! One receipt image / statement PDF in → structured draft
//! transactions out, via a single forced `tool_use` call on a
//! multimodal model. **Nothing is persisted**: the image lives only
//! for the duration of this request and is discarded when it returns
//! (§5.10.10 — "图像在 Worker 内即用即弃，云端零留存"). The mobile
//! side runs dedup + the draft queue + confirmation locally.
//!
//! Auth + rate-limit gated like `/ai/chat` (a Vision call is
//! expensive). The privacy gate (`amounts_local` → no cloud) is
//! enforced client-side before this endpoint is ever called (S5b-gate).

use serde::{Deserialize, Serialize};
use worker::{Request, Response, Result as WorkerResult, RouteContext};

use crate::ai::adapters::anthropic::{
    AnthropicAdapter, AnthropicRequest, LlmConfig, DEFAULT_MODEL,
};
use crate::ai::guardrails;
use crate::ai::ingest::{
    build_messages, extract_drafts, parse_tool_schema, system_prompt, ParsedDraftWire,
};
use crate::auth::middleware::require_auth;
use crate::error::AppError;
use crate::routes::common::check_protocol_version;

/// Max raw JSON body — a base64 image is bulky. ~12 MiB of JSON ≈ a
/// ~9 MiB binary, comfortably above any phone-camera receipt.
const MAX_INGEST_BODY_BYTES: usize = 12 * 1024 * 1024;
const VISION_MAX_TOKENS: u32 = 4096;

#[derive(Deserialize)]
struct ParseRequest {
    /// `receipt_image` | `statement_pdf` — mirrors `IngestSourceKind`.
    kind: String,
    mime: String,
    content_base64: String,
    #[serde(default)]
    currency_hint: Option<String>,
}

#[derive(Serialize)]
struct ParseResponse {
    model: String,
    drafts: Vec<ParsedDraftWire>,
}

pub async fn parse(req: Request, ctx: RouteContext<()>) -> WorkerResult<Response> {
    match parse_inner(req, ctx).await {
        Ok(r) => Ok(r),
        Err(e) => {
            e.log();
            e.into_response()
        }
    }
}

async fn parse_inner(mut req: Request, ctx: RouteContext<()>) -> Result<Response, AppError> {
    check_protocol_version(req.headers())?;
    let auth = require_auth(&req, &ctx).await?;

    let raw = req
        .bytes()
        .await
        .map_err(|e| AppError::BadRequest(format!("body read: {e}")))?;
    if raw.len() > MAX_INGEST_BODY_BYTES {
        return Err(AppError::payload_too_large());
    }
    let body: ParseRequest = serde_json::from_slice(&raw)
        .map_err(|e| AppError::BadRequest(format!("invalid JSON: {e}")))?;

    validate_kind(&body.kind)?;
    if body.content_base64.trim().is_empty() {
        return Err(AppError::BadRequest("content_base64 is empty".into()));
    }

    let db = ctx
        .env
        .d1("DB")
        .map_err(|_| AppError::Internal("DB unbound".into()))?;
    guardrails::check_and_record_rate_limit(&db, &auth.user_id).await?;

    let token = env_secret(&ctx, "ANTHROPIC_AUTH_TOKEN")
        .or_else(|| env_secret(&ctx, "LLM_API_KEY"))
        .or_else(|| env_secret(&ctx, "ANTHROPIC_API_KEY"))
        .ok_or_else(|| AppError::Internal("ANTHROPIC_AUTH_TOKEN unbound".into()))?;
    let base_url = env_var(&ctx, "ANTHROPIC_BASE_URL").or_else(|| env_var(&ctx, "LLM_BASE_URL"));
    let model = resolve_model(
        env_var(&ctx, "ANTHROPIC_DEFAULT_OPUS_MODEL").or_else(|| env_var(&ctx, "LLM_MODEL")),
    );

    let adapter = AnthropicAdapter::new(LlmConfig::new(token, base_url));
    let messages = build_messages(
        &body.mime,
        &body.content_base64,
        body.currency_hint.as_deref(),
    );
    let tools = [parse_tool_schema()];
    let payload = AnthropicRequest {
        model: &model,
        max_tokens: VISION_MAX_TOKENS,
        system: system_prompt(),
        messages: &messages,
        tools: &tools,
        stream: false,
    };

    let reply = adapter.complete(&payload).await?;
    let drafts = extract_drafts(&reply)?;

    Response::from_json(&ParseResponse { model, drafts }).map_err(AppError::from)
}

/// Accepted ingest kinds. Anything else is a client bug, not a parse
/// failure — fail fast with 400 rather than burn a Vision call.
fn validate_kind(kind: &str) -> Result<(), AppError> {
    match kind {
        "receipt_image" | "statement_pdf" => Ok(()),
        other => Err(AppError::BadRequest(format!(
            "unsupported ingest kind: {other}"
        ))),
    }
}

/// Env → effective model, with the documented fallback to the bundled
/// default. Pure so the precedence is unit-testable.
fn resolve_model(env_model: Option<String>) -> String {
    env_model
        .filter(|m| !m.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_MODEL.to_string())
}

fn env_secret(ctx: &RouteContext<()>, name: &str) -> Option<String> {
    ctx.env
        .secret(name)
        .ok()
        .map(|s| s.to_string())
        .filter(|s| !s.trim().is_empty())
}

fn env_var(ctx: &RouteContext<()>, name: &str) -> Option<String> {
    ctx.env
        .var(name)
        .ok()
        .map(|v| v.to_string())
        .filter(|s| !s.trim().is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_kind_accepts_only_the_two_cloud_kinds() {
        assert!(validate_kind("receipt_image").is_ok());
        assert!(validate_kind("statement_pdf").is_ok());
        assert_eq!(validate_kind("csv").unwrap_err().status(), 400);
        assert_eq!(validate_kind("pasteText").unwrap_err().status(), 400);
    }

    #[test]
    fn resolve_model_prefers_env_then_falls_back() {
        assert_eq!(resolve_model(Some("mimo-v2.5-pro".into())), "mimo-v2.5-pro");
        assert_eq!(resolve_model(Some("   ".into())), DEFAULT_MODEL);
        assert_eq!(resolve_model(None), DEFAULT_MODEL);
    }
}
