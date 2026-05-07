//! Thin Anthropic-compatible Messages API client.
//!
//! Exposes a single non-streaming entry point ([`call_blocking`]). The tool
//! loop in `routes::ai` uses it to inspect `stop_reason` and the `tool_use`
//! blocks the model emitted before deciding whether to dispatch tools and
//! re-call. Each emitted text/tool_use block is forwarded to the client as
//! its own SSE frame, so the user-facing stream is still incremental even
//! though we don't subscribe to the provider's own SSE feed.
//!
//! We deliberately do not pass the user's bearer token through to the LLM;
//! the Worker holds the API key in `wrangler secret` and authenticates
//! itself, isolating model billing from end-user identity.
//!
//! Default provider is ModelScope's Anthropic-compatible endpoint. The base
//! URL and model are configurable so deployments can switch providers without
//! code changes.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use worker::wasm_bindgen::JsValue;
use worker::{Fetch, Headers, Method, Request, RequestInit};

use crate::error::AppError;

const DEFAULT_BASE_URL: &str = "https://api-inference.modelscope.cn";
const ANTHROPIC_VERSION: &str = "2023-06-01";

/// Default model id when neither env vars nor the client override it.
pub const DEFAULT_MODEL: &str = "deepseek-ai/DeepSeek-V4-Flash";

#[derive(Debug, Clone)]
pub struct LlmConfig {
    pub api_key: String,
    pub base_url: String,
}

impl LlmConfig {
    pub fn new(api_key: String, base_url: Option<String>) -> Self {
        Self {
            api_key,
            base_url: base_url
                .filter(|u| !u.trim().is_empty())
                .unwrap_or_else(|| DEFAULT_BASE_URL.to_string()),
        }
    }

    fn messages_url(&self) -> String {
        let base = self.base_url.trim_end_matches('/');
        if base.ends_with("/v1/messages") || base.ends_with("/messages") {
            base.to_string()
        } else if base.ends_with("/v1") {
            format!("{base}/messages")
        } else {
            format!("{base}/v1/messages")
        }
    }
}

/// Top-level message in the Anthropic Messages API. Roles are `user` or
/// `assistant`; system instructions ride on the request's `system` field.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    /// Either a plain string (when the client sends a free-form user turn)
    /// or an array of typed blocks (`text`, `tool_use`, `tool_result`).
    /// Anthropic accepts both shapes interchangeably; we keep the wire form
    /// opaque here and let serde do the round-trip.
    pub content: Value,
}

/// Tool schema as Anthropic expects it. We assemble these from the registry
/// in `tools.rs`.
#[derive(Debug, Clone, Serialize)]
pub struct ToolSchema {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct AnthropicRequest<'a> {
    pub model: &'a str,
    pub max_tokens: u32,
    pub system: &'a str,
    pub messages: &'a [ChatMessage],
    pub tools: &'a [ToolSchema],
    pub stream: bool,
}

/// Decoded non-streaming response (`stream=false`). We model only the fields
/// the tool loop reads — `stop_reason`, plus the typed `content` blocks. The
/// blocks pass through to the next request as part of the assistant turn, so
/// we keep them as opaque `Value` rather than enumerating every variant.
#[derive(Debug, Clone, Deserialize)]
pub struct AnthropicMessage {
    pub content: Vec<Value>,
    pub stop_reason: Option<String>,
}

fn auth_headers(api_key: &str) -> Result<Headers, AppError> {
    let h = Headers::new();
    h.set("x-api-key", api_key)
        .map_err(|e| AppError::Internal(format!("hdr: {e}")))?;
    h.set("anthropic-version", ANTHROPIC_VERSION)
        .map_err(|e| AppError::Internal(format!("hdr: {e}")))?;
    h.set("content-type", "application/json")
        .map_err(|e| AppError::Internal(format!("hdr: {e}")))?;
    Ok(h)
}

fn build_request(config: &LlmConfig, body: &str) -> Result<Request, AppError> {
    let mut init = RequestInit::new();
    init.with_method(Method::Post)
        .with_headers(auth_headers(&config.api_key)?)
        .with_body(Some(JsValue::from_str(body)));
    Request::new_with_init(&config.messages_url(), &init)
        .map_err(|e| AppError::Internal(format!("req: {e}")))
}

/// Non-streaming call. Returns the parsed message.
pub async fn call_blocking(
    config: &LlmConfig,
    payload: &AnthropicRequest<'_>,
) -> Result<AnthropicMessage, AppError> {
    let body =
        serde_json::to_string(payload).map_err(|e| AppError::Internal(format!("ser: {e}")))?;
    let req = build_request(config, &body)?;
    let mut resp = Fetch::Request(req)
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("llm fetch: {e}")))?;
    if resp.status_code() >= 400 {
        let text = resp.text().await.unwrap_or_else(|_| "<unreadable>".into());
        return Err(AppError::Internal(format!(
            "llm {}: {}",
            resp.status_code(),
            text
        )));
    }
    let msg: AnthropicMessage = resp
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("llm json: {e}")))?;
    Ok(msg)
}
