//! HTTP client for Anthropic-compatible streaming messages.

use async_trait::async_trait;
use futures_util::stream::{self, BoxStream, StreamExt};
use serde_json::Value;
use worker::wasm_bindgen::JsValue;
use worker::{Fetch, Headers, Method, Request, RequestInit};

use super::event_map::map_sse_text;
use super::wire::{AnthropicRequest, ChatMessage, ToolSchema};
use crate::ai::runtime::{AgentEvent, AgentRequest, LlmAdapter};
use crate::error::AppError;

const DEFAULT_BASE_URL: &str = "https://api-inference.modelscope.cn";
const ANTHROPIC_VERSION: &str = "2023-06-01";

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

    pub(crate) fn messages_url(&self) -> String {
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

#[derive(Debug, Clone)]
pub struct AnthropicAdapter {
    config: LlmConfig,
}

impl AnthropicAdapter {
    pub fn new(config: LlmConfig) -> Self {
        Self { config }
    }

    pub async fn stream_anthropic(
        &self,
        payload: &AnthropicRequest<'_>,
    ) -> Result<BoxStream<'static, AgentEvent>, AppError> {
        let body = serialize_streaming_payload(payload)?;
        let req = build_request(&self.config, &body)?;
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
        let events = map_sse_text(&text)?;
        Ok(stream::iter(events).boxed())
    }
}

#[async_trait(?Send)]
impl LlmAdapter for AnthropicAdapter {
    async fn stream(&self, req: AgentRequest<'_>) -> Result<BoxStream<'_, AgentEvent>, AppError> {
        let messages = decode_values::<ChatMessage>(req.messages, "message")?;
        let tools = decode_values::<ToolSchema>(req.tools, "tool")?;
        let payload = AnthropicRequest {
            model: req.model,
            max_tokens: req.max_tokens,
            system: req.system,
            messages: &messages,
            tools: &tools,
            stream: true,
        };

        self.stream_anthropic(&payload)
            .await
            .map(|events| events.boxed())
    }
}

fn decode_values<T>(values: &[Value], label: &str) -> Result<Vec<T>, AppError>
where
    T: serde::de::DeserializeOwned,
{
    values
        .iter()
        .cloned()
        .map(|value| {
            serde_json::from_value(value)
                .map_err(|e| AppError::Internal(format!("invalid anthropic {label}: {e}")))
        })
        .collect()
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

fn serialize_streaming_payload(payload: &AnthropicRequest<'_>) -> Result<String, AppError> {
    let mut body =
        serde_json::to_value(payload).map_err(|e| AppError::Internal(format!("ser: {e}")))?;
    body["stream"] = Value::Bool(true);
    serde_json::to_string(&body).map_err(|e| AppError::Internal(format!("ser: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::adapters::anthropic::wire::DEFAULT_MODEL;
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
    fn provider_payload_forces_streaming_for_modelscope_compat() {
        let messages = vec![ChatMessage {
            role: "user".into(),
            content: json!("hello"),
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
        assert_eq!(decoded["messages"][0]["content"], "hello");
    }
}
