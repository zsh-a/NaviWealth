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
use serde_json::{json, Value};
use std::collections::BTreeMap;
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

#[cfg(test)]
fn serialize_payload(payload: &AnthropicRequest<'_>) -> Result<String, AppError> {
    serde_json::to_string(payload).map_err(|e| AppError::Internal(format!("ser: {e}")))
}

fn serialize_streaming_payload(payload: &AnthropicRequest<'_>) -> Result<String, AppError> {
    let mut body =
        serde_json::to_value(payload).map_err(|e| AppError::Internal(format!("ser: {e}")))?;
    body["stream"] = Value::Bool(true);
    serde_json::to_string(&body).map_err(|e| AppError::Internal(format!("ser: {e}")))
}

/// Non-streaming call. Returns the parsed message.
pub async fn call_blocking(
    config: &LlmConfig,
    payload: &AnthropicRequest<'_>,
) -> Result<AnthropicMessage, AppError> {
    let body = serialize_streaming_payload(payload)?;
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
    let text = resp
        .text()
        .await
        .map_err(|e| AppError::Internal(format!("llm body: {e}")))?;
    if text.trim_start().starts_with("event:") {
        parse_streaming_message(&text)
    } else {
        serde_json::from_str(&text).map_err(|e| AppError::Internal(format!("llm json: {e}")))
    }
}

#[derive(Default)]
struct StreamingBlock {
    ty: String,
    id: Option<String>,
    name: Option<String>,
    text: String,
    input_json: String,
    input: Option<Value>,
}

fn parse_streaming_message(sse: &str) -> Result<AnthropicMessage, AppError> {
    let mut blocks: BTreeMap<usize, StreamingBlock> = BTreeMap::new();
    let mut stop_reason: Option<String> = None;

    for frame in sse.split("\n\n") {
        let data = frame
            .lines()
            .filter_map(|line| line.strip_prefix("data: "))
            .collect::<Vec<_>>()
            .join("\n");
        if data.trim().is_empty() {
            continue;
        }
        let event: Value = serde_json::from_str(&data)
            .map_err(|e| AppError::Internal(format!("llm stream json: {e}")))?;
        match event.get("type").and_then(|v| v.as_str()) {
            Some("content_block_start") => {
                let index = event.get("index").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
                let content_block = event.get("content_block").unwrap_or(&Value::Null);
                let ty = content_block
                    .get("type")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();
                let block = blocks.entry(index).or_default();
                block.ty = ty;
                block.id = content_block
                    .get("id")
                    .and_then(|v| v.as_str())
                    .map(ToString::to_string);
                block.name = content_block
                    .get("name")
                    .and_then(|v| v.as_str())
                    .map(ToString::to_string);
                if let Some(text) = content_block.get("text").and_then(|v| v.as_str()) {
                    block.text.push_str(text);
                }
                block.input = content_block.get("input").cloned();
            }
            Some("content_block_delta") => {
                let index = event.get("index").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
                let delta = event.get("delta").unwrap_or(&Value::Null);
                let block = blocks.entry(index).or_default();
                match delta.get("type").and_then(|v| v.as_str()) {
                    Some("text_delta") => {
                        if let Some(text) = delta.get("text").and_then(|v| v.as_str()) {
                            block.text.push_str(text);
                        }
                    }
                    Some("input_json_delta") => {
                        if let Some(partial) = delta.get("partial_json").and_then(|v| v.as_str()) {
                            block.input_json.push_str(partial);
                        }
                    }
                    _ => {}
                }
            }
            Some("message_delta") => {
                stop_reason = event
                    .get("delta")
                    .and_then(|v| v.get("stop_reason"))
                    .and_then(|v| v.as_str())
                    .map(ToString::to_string);
            }
            Some("error") => {
                return Err(AppError::Internal(format!("llm stream error: {data}")));
            }
            _ => {}
        }
    }

    let content = blocks
        .into_values()
        .filter_map(|block| match block.ty.as_str() {
            "text" => Some(json!({"type": "text", "text": block.text})),
            "tool_use" => {
                let input = if block.input_json.trim().is_empty() {
                    block.input.unwrap_or_else(|| json!({}))
                } else {
                    serde_json::from_str(&block.input_json).unwrap_or(Value::Null)
                };
                Some(json!({
                    "type": "tool_use",
                    "id": block.id.unwrap_or_default(),
                    "name": block.name.unwrap_or_default(),
                    "input": input,
                }))
            }
            _ => None,
        })
        .collect();

    Ok(AnthropicMessage {
        content,
        stop_reason,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn messages_url_matches_modelscope_anthropic_compat_shape() {
        let default = LlmConfig::new("key".into(), None);
        assert_eq!(
            default.messages_url(),
            "https://api-inference.modelscope.cn/v1/messages"
        );

        let v1 = LlmConfig::new("key".into(), Some("https://example.test/v1".into()));
        assert_eq!(v1.messages_url(), "https://example.test/v1/messages");

        let exact = LlmConfig::new(
            "key".into(),
            Some("https://example.test/custom/messages".into()),
        );
        assert_eq!(exact.messages_url(), "https://example.test/custom/messages");
    }

    #[test]
    fn serializes_anthropic_messages_payload_for_llm_provider() {
        let messages = vec![
            ChatMessage {
                role: "user".into(),
                content: json!("你好"),
            },
            ChatMessage {
                role: "assistant".into(),
                content: json!([{"type": "text", "text": "你好，有什么可以帮你？"}]),
            },
        ];
        let tools = vec![ToolSchema {
            name: "get_holdings".into(),
            description: "Read holdings".into(),
            input_schema: json!({"type": "object", "properties": {}}),
        }];
        let payload = AnthropicRequest {
            model: DEFAULT_MODEL,
            max_tokens: 1024,
            system: "system prompt",
            messages: &messages,
            tools: &tools,
            stream: false,
        };

        let body = serialize_payload(&payload).unwrap();
        let decoded: Value = serde_json::from_str(&body).unwrap();

        assert_eq!(decoded["model"], DEFAULT_MODEL);
        assert_eq!(decoded["max_tokens"], 1024);
        assert_eq!(decoded["system"], "system prompt");
        assert_eq!(decoded["stream"], false);
        assert_eq!(decoded["messages"][0]["role"], "user");
        assert_eq!(decoded["messages"][0]["content"], "你好");
        assert_eq!(decoded["messages"][1]["role"], "assistant");
        assert_eq!(decoded["messages"][1]["content"][0]["type"], "text");
        assert_eq!(decoded["tools"][0]["name"], "get_holdings");
        assert!(decoded.get("api_key").is_none());
    }

    #[test]
    fn provider_payload_forces_streaming_for_modelscope_compat() {
        let messages = vec![ChatMessage {
            role: "user".into(),
            content: json!("你好"),
        }];
        let payload = AnthropicRequest {
            model: DEFAULT_MODEL,
            max_tokens: 128,
            system: "system prompt",
            messages: &messages,
            tools: &[],
            stream: false,
        };

        let body = serialize_streaming_payload(&payload).unwrap();
        let decoded: Value = serde_json::from_str(&body).unwrap();

        assert_eq!(decoded["stream"], true);
        assert_eq!(decoded["messages"][0]["content"], "你好");
    }

    #[test]
    fn parses_streaming_text_message() {
        let sse = concat!(
            "event: message_start\n",
            "data: {\"type\":\"message_start\",\"message\":{\"content\":[]}}\n\n",
            "event: content_block_start\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "event: content_block_delta\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"真实\"}}\n\n",
            "event: content_block_delta\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" API 验证通过\"}}\n\n",
            "event: message_delta\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n",
            "event: message_stop\n",
            "data: {\"type\":\"message_stop\"}\n\n",
        );

        let msg = parse_streaming_message(sse).unwrap();

        assert_eq!(msg.stop_reason.as_deref(), Some("end_turn"));
        assert_eq!(
            msg.content,
            vec![json!({"type": "text", "text": "真实 API 验证通过"})]
        );
    }

    #[test]
    fn parses_streaming_tool_use_message() {
        let sse = concat!(
            "event: content_block_start\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_risk_alerts\",\"input\":{}}}\n\n",
            "event: content_block_delta\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"as_of\\\":\"}}\n\n",
            "event: content_block_delta\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"\\\"2026-05-07\\\"}\"}}\n\n",
            "event: message_delta\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\n",
        );

        let msg = parse_streaming_message(sse).unwrap();

        assert_eq!(msg.stop_reason.as_deref(), Some("tool_use"));
        assert_eq!(
            msg.content,
            vec![json!({
                "type": "tool_use",
                "id": "toolu_1",
                "name": "get_risk_alerts",
                "input": {"as_of": "2026-05-07"}
            })]
        );
    }
}
