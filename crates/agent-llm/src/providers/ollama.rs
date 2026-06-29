use std::time::Duration;

use agent_core::PROTOCOL_VERSION;
use async_trait::async_trait;
use futures::stream;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::llm_content_as_text;
use crate::types::{
    LlmError, LlmEvent, LlmEventKind, LlmEventStream, LlmFinishReason, LlmMessage, LlmProvider,
    LlmRequest, LlmResponse, LlmRole, LlmUsage,
};

#[derive(Debug, Clone)]
pub struct OllamaProvider {
    provider: String,
    base_url: String,
    client: reqwest::Client,
}

impl OllamaProvider {
    pub fn new(provider: impl Into<String>, base_url: impl Into<String>) -> Result<Self, LlmError> {
        let base_url = base_url.into().trim_end_matches('/').to_owned();
        if base_url.is_empty() {
            return Err(LlmError::validation("Ollama base URL is required"));
        }
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(120))
            .build()
            .map_err(|err| {
                LlmError::provider(
                    "http_client_build_failed",
                    err.to_string(),
                    false,
                    json!({}),
                )
            })?;
        Ok(Self {
            provider: provider.into(),
            base_url,
            client,
        })
    }

    fn chat_url(&self) -> String {
        format!("{}/api/chat", self.base_url)
    }
}

#[derive(Debug, Serialize)]
struct OllamaChatRequest {
    model: String,
    messages: Vec<OllamaMessage>,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    options: Option<OllamaOptions>,
}

#[derive(Debug, Serialize)]
struct OllamaMessage {
    role: String,
    content: String,
}

#[derive(Debug, Serialize)]
struct OllamaOptions {
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    num_predict: Option<u32>,
}

#[derive(Debug, Deserialize)]
struct OllamaChatResponse {
    #[serde(default)]
    message: Option<OllamaMessageResponse>,
    #[serde(default)]
    done_reason: Option<String>,
    #[serde(default)]
    prompt_eval_count: Option<u32>,
    #[serde(default)]
    eval_count: Option<u32>,
    #[serde(default)]
    error: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OllamaMessageResponse {
    #[serde(default)]
    content: String,
}

#[async_trait]
impl LlmProvider for OllamaProvider {
    async fn complete(&self, request: LlmRequest) -> Result<LlmResponse, LlmError> {
        if request.messages.is_empty() {
            return Err(LlmError::validation(
                "llm request requires at least one message",
            ));
        }
        let options = (request.temperature.is_some() || request.max_output_tokens.is_some())
            .then_some(OllamaOptions {
                temperature: request.temperature,
                num_predict: request.max_output_tokens,
            });
        let payload = OllamaChatRequest {
            model: request.model.clone(),
            messages: request
                .messages
                .iter()
                .map(ollama_message_from_llm)
                .collect::<Result<Vec<_>, _>>()?,
            stream: false,
            options,
        };
        let response = self
            .client
            .post(self.chat_url())
            .json(&payload)
            .send()
            .await
            .map_err(|err| {
                LlmError::provider("provider_request_failed", err.to_string(), true, json!({}))
            })?;
        let status = response.status();
        let body = response.text().await.map_err(|err| {
            LlmError::provider(
                "provider_body_read_failed",
                err.to_string(),
                true,
                json!({}),
            )
        })?;
        if !status.is_success() {
            let details = serde_json::from_str::<Value>(&body).unwrap_or_else(|_| json!({}));
            let message = details
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or(&body)
                .to_owned();
            return Err(LlmError::provider(
                format!("provider_http_{}", status.as_u16()),
                message,
                status.is_server_error(),
                details,
            ));
        }
        let decoded = serde_json::from_str::<OllamaChatResponse>(&body).map_err(|err| {
            LlmError::provider(
                "provider_decode_failed",
                err.to_string(),
                false,
                json!({"body": body}),
            )
        })?;
        if let Some(error) = decoded.error {
            return Err(LlmError::provider(
                "provider_error",
                error,
                false,
                json!({}),
            ));
        }
        let input_tokens = decoded.prompt_eval_count.unwrap_or(0);
        let output_tokens = decoded.eval_count.unwrap_or(0);
        Ok(LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: self.provider.clone(),
            model: request.model,
            content: decoded
                .message
                .map(|message| message.content)
                .unwrap_or_default(),
            finish_reason: ollama_finish_reason(decoded.done_reason.as_deref()),
            usage: Some(LlmUsage {
                input_tokens,
                output_tokens,
                total_tokens: input_tokens + output_tokens,
            }),
            metadata: json!({"api": "ollama_chat"}),
        })
    }

    async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError> {
        let response = self.complete(request).await?;
        let events = vec![
            Ok(LlmEvent {
                kind: LlmEventKind::Started,
                content: None,
                response: None,
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                metadata: json!({"provider": response.provider, "model": response.model}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Delta,
                content: Some(response.content.clone()),
                response: None,
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                metadata: json!({"synthetic_stream": true}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Finished,
                content: None,
                response: Some(response),
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                metadata: json!({"synthetic_stream": true}),
            }),
        ];
        Ok(Box::pin(stream::iter(events)))
    }
}

fn ollama_message_from_llm(message: &LlmMessage) -> Result<OllamaMessage, LlmError> {
    let role = match message.role {
        LlmRole::System => "system",
        LlmRole::User => "user",
        LlmRole::Assistant => "assistant",
        LlmRole::Tool => "tool",
    };
    Ok(OllamaMessage {
        role: role.to_owned(),
        content: llm_content_as_text(&message.content, "Ollama")?.to_owned(),
    })
}

fn ollama_finish_reason(value: Option<&str>) -> LlmFinishReason {
    match value {
        Some("stop") | None => LlmFinishReason::Stop,
        Some("length") => LlmFinishReason::Length,
        _ => LlmFinishReason::Error,
    }
}
