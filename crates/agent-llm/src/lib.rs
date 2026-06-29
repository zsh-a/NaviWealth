use std::collections::VecDeque;
use std::pin::Pin;
use std::time::Duration;

use agent_core::{PROTOCOL_VERSION, ToolSpec};
use async_trait::async_trait;
use bytes::Bytes;
use futures::{Stream, StreamExt, stream};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use thiserror::Error;

pub type LlmEventStream = Pin<Box<dyn Stream<Item = Result<LlmEvent, LlmError>> + Send>>;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct LlmRequest {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub provider: String,
    pub model: String,
    pub messages: Vec<LlmMessage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_output_tokens: Option<u32>,
    #[serde(default)]
    pub tools: Vec<ToolSpec>,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct LlmMessage {
    pub role: LlmRole,
    pub content: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LlmRole {
    System,
    User,
    Assistant,
    Tool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct LlmResponse {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub provider: String,
    pub model: String,
    pub content: String,
    pub finish_reason: LlmFinishReason,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub usage: Option<LlmUsage>,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LlmFinishReason {
    Stop,
    Length,
    ToolCall,
    ContentFilter,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct LlmUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    pub total_tokens: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct LlmEvent {
    pub kind: LlmEventKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response: Option<LlmResponse>,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LlmEventKind {
    Started,
    Delta,
    Finished,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct LlmErrorRecord {
    pub kind: LlmErrorKind,
    pub code: String,
    pub message: String,
    pub retryable: bool,
    #[serde(default)]
    pub details: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum LlmErrorKind {
    ValidationError,
    ProviderError,
    TransientProviderError,
    RateLimited,
    Timeout,
    InternalError,
}

#[derive(Debug, Error)]
#[error("{record:?}")]
pub struct LlmError {
    pub record: Box<LlmErrorRecord>,
}

impl LlmError {
    pub fn validation(message: impl Into<String>) -> Self {
        Self {
            record: Box::new(LlmErrorRecord {
                kind: LlmErrorKind::ValidationError,
                code: "validation_error".to_owned(),
                message: message.into(),
                retryable: false,
                details: json!({}),
            }),
        }
    }

    fn provider(
        code: impl Into<String>,
        message: impl Into<String>,
        retryable: bool,
        details: Value,
    ) -> Self {
        Self {
            record: Box::new(LlmErrorRecord {
                kind: if retryable {
                    LlmErrorKind::TransientProviderError
                } else {
                    LlmErrorKind::ProviderError
                },
                code: code.into(),
                message: message.into(),
                retryable,
                details,
            }),
        }
    }

    fn rate_limited(message: impl Into<String>, details: Value) -> Self {
        Self {
            record: Box::new(LlmErrorRecord {
                kind: LlmErrorKind::RateLimited,
                code: "rate_limited".to_owned(),
                message: message.into(),
                retryable: true,
                details,
            }),
        }
    }
}

#[async_trait]
pub trait LlmProvider: Send + Sync {
    async fn complete(&self, request: LlmRequest) -> Result<LlmResponse, LlmError>;
    async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError>;
}

#[derive(Debug, Clone)]
pub struct MockLlmProvider {
    provider: String,
    model: String,
    response_text: String,
}

impl Default for MockLlmProvider {
    fn default() -> Self {
        Self {
            provider: "mock".to_owned(),
            model: "mock-model".to_owned(),
            response_text: "mock response".to_owned(),
        }
    }
}

impl MockLlmProvider {
    pub fn new(
        provider: impl Into<String>,
        model: impl Into<String>,
        response_text: impl Into<String>,
    ) -> Self {
        Self {
            provider: provider.into(),
            model: model.into(),
            response_text: response_text.into(),
        }
    }

    fn response_for(&self, request: &LlmRequest) -> Result<LlmResponse, LlmError> {
        if request.messages.is_empty() {
            return Err(LlmError::validation(
                "llm request requires at least one message",
            ));
        }
        let content = request
            .metadata
            .get("mock_response")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .unwrap_or_else(|| self.response_text.clone());
        Ok(LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: self.provider.clone(),
            model: if request.model.is_empty() {
                self.model.clone()
            } else {
                request.model.clone()
            },
            usage: Some(estimate_usage(request, &content)),
            content,
            finish_reason: LlmFinishReason::Stop,
            metadata: json!({"mock": true}),
        })
    }
}

#[async_trait]
impl LlmProvider for MockLlmProvider {
    async fn complete(&self, request: LlmRequest) -> Result<LlmResponse, LlmError> {
        self.response_for(&request)
    }

    async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError> {
        let response = self.response_for(&request)?;
        let events = vec![
            Ok(LlmEvent {
                kind: LlmEventKind::Started,
                content: None,
                response: None,
                metadata: json!({"provider": response.provider, "model": response.model}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Delta,
                content: Some(response.content.clone()),
                response: None,
                metadata: json!({}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Finished,
                content: None,
                response: Some(response),
                metadata: json!({}),
            }),
        ];
        Ok(Box::pin(stream::iter(events)))
    }
}

#[derive(Debug, Clone)]
pub struct OpenAiCompatibleProvider {
    provider: String,
    base_url: String,
    api_key: String,
    client: reqwest::Client,
}

#[derive(Debug, Clone)]
pub struct AnthropicProvider {
    provider: String,
    base_url: String,
    api_key: String,
    anthropic_version: String,
    client: reqwest::Client,
}

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

impl AnthropicProvider {
    pub fn new(
        provider: impl Into<String>,
        base_url: impl Into<String>,
        api_key: impl Into<String>,
        anthropic_version: impl Into<String>,
    ) -> Result<Self, LlmError> {
        let base_url = base_url.into().trim_end_matches('/').to_owned();
        let api_key = api_key.into();
        let anthropic_version = anthropic_version.into();
        if base_url.is_empty() {
            return Err(LlmError::validation("Anthropic base URL is required"));
        }
        if api_key.is_empty() {
            return Err(LlmError::validation("Anthropic API key is required"));
        }
        if anthropic_version.is_empty() {
            return Err(LlmError::validation("Anthropic API version is required"));
        }
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(60))
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
            api_key,
            anthropic_version,
            client,
        })
    }

    fn messages_url(&self) -> String {
        format!("{}/messages", self.base_url)
    }
}

impl OpenAiCompatibleProvider {
    pub fn new(
        provider: impl Into<String>,
        base_url: impl Into<String>,
        api_key: impl Into<String>,
    ) -> Result<Self, LlmError> {
        let base_url = base_url.into().trim_end_matches('/').to_owned();
        let api_key = api_key.into();
        if base_url.is_empty() {
            return Err(LlmError::validation(
                "OpenAI-compatible base URL is required",
            ));
        }
        if api_key.is_empty() {
            return Err(LlmError::validation(
                "OpenAI-compatible API key is required",
            ));
        }
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(60))
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
            api_key,
            client,
        })
    }

    fn completions_url(&self) -> String {
        format!("{}/chat/completions", self.base_url)
    }
}

#[derive(Debug, Serialize)]
struct AnthropicMessagesRequest {
    model: String,
    max_tokens: u32,
    messages: Vec<AnthropicMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    system: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    tools: Vec<AnthropicTool>,
    stream: bool,
}

#[derive(Debug, Serialize)]
struct AnthropicMessage {
    role: String,
    content: Value,
}

#[derive(Debug, Serialize)]
struct AnthropicTool {
    name: String,
    description: String,
    input_schema: Value,
}

#[derive(Debug, Deserialize)]
struct AnthropicMessagesResponse {
    #[serde(default)]
    content: Vec<Value>,
    #[serde(default)]
    stop_reason: Option<String>,
    #[serde(default)]
    usage: Option<AnthropicUsage>,
    #[serde(default)]
    error: Option<AnthropicErrorBody>,
}

#[derive(Debug, Deserialize)]
struct AnthropicUsage {
    #[serde(default)]
    input_tokens: u32,
    #[serde(default)]
    output_tokens: u32,
}

#[derive(Debug, Deserialize)]
struct AnthropicErrorBody {
    #[serde(default)]
    r#type: Option<String>,
    #[serde(default)]
    message: String,
}

#[derive(Debug, Deserialize)]
struct AnthropicStreamEvent {
    #[serde(rename = "type")]
    event_type: String,
    #[serde(default)]
    content_block: Option<Value>,
    #[serde(default)]
    delta: Option<Value>,
    #[serde(default)]
    usage: Option<AnthropicUsage>,
    #[serde(default)]
    message: Option<AnthropicStreamMessage>,
    #[serde(default)]
    error: Option<AnthropicErrorBody>,
}

#[derive(Debug, Deserialize)]
struct AnthropicStreamMessage {
    #[serde(default)]
    usage: Option<AnthropicUsage>,
}

struct AnthropicSseState {
    provider: String,
    model: String,
    anthropic_version: String,
    chunks: Pin<Box<dyn Stream<Item = Result<Bytes, reqwest::Error>> + Send>>,
    buffer: String,
    pending: VecDeque<Result<LlmEvent, LlmError>>,
    content: String,
    finish_reason: Option<LlmFinishReason>,
    input_tokens: u32,
    output_tokens: u32,
    raw_blocks: Vec<Value>,
    finished: bool,
}

impl AnthropicSseState {
    fn new(
        provider: String,
        model: String,
        anthropic_version: String,
        chunks: Pin<Box<dyn Stream<Item = Result<Bytes, reqwest::Error>> + Send>>,
    ) -> Self {
        let mut pending = VecDeque::new();
        pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::Started,
            content: None,
            response: None,
            metadata: json!({"provider": provider, "model": model, "stream": true}),
        }));
        Self {
            provider,
            model,
            anthropic_version,
            chunks,
            buffer: String::new(),
            pending,
            content: String::new(),
            finish_reason: None,
            input_tokens: 0,
            output_tokens: 0,
            raw_blocks: Vec::new(),
            finished: false,
        }
    }

    async fn next_event(&mut self) -> Option<Result<LlmEvent, LlmError>> {
        loop {
            if let Some(event) = self.pending.pop_front() {
                return Some(event);
            }
            if self.finished {
                return None;
            }
            match self.chunks.next().await {
                Some(Ok(bytes)) => {
                    self.buffer.push_str(&String::from_utf8_lossy(&bytes));
                    self.drain_frames();
                }
                Some(Err(err)) => {
                    self.finished = true;
                    return Some(Err(LlmError::provider(
                        "provider_stream_read_failed",
                        err.to_string(),
                        true,
                        json!({}),
                    )));
                }
                None => {
                    if !self.buffer.trim().is_empty() {
                        if let Some(frame) = take_remaining_sse_frame(&mut self.buffer) {
                            self.handle_frame(&frame);
                        }
                    }
                    if !self.finished {
                        self.push_finished();
                    }
                }
            }
        }
    }

    fn drain_frames(&mut self) {
        while let Some(frame) = take_next_sse_frame(&mut self.buffer) {
            self.handle_frame(&frame);
        }
    }

    fn handle_frame(&mut self, frame: &str) {
        let data = sse_data(frame);
        if data.is_empty() || data.trim() == "[DONE]" {
            return;
        }
        let decoded = match serde_json::from_str::<AnthropicStreamEvent>(&data) {
            Ok(decoded) => decoded,
            Err(err) => {
                self.pending.push_back(Err(LlmError::provider(
                    "provider_stream_decode_failed",
                    err.to_string(),
                    false,
                    json!({"frame": data}),
                )));
                return;
            }
        };
        match decoded.event_type.as_str() {
            "message_start" => {
                if let Some(usage) = decoded
                    .message
                    .and_then(|message| message.usage)
                    .or(decoded.usage)
                {
                    self.input_tokens = usage.input_tokens;
                    self.output_tokens = usage.output_tokens;
                }
            }
            "content_block_start" => {
                if let Some(block) = decoded.content_block {
                    if block.get("type").and_then(Value::as_str) == Some("text") {
                        if let Some(text) = block.get("text").and_then(Value::as_str) {
                            if !text.is_empty() {
                                self.push_text_delta(text.to_owned());
                            }
                        }
                    }
                    self.raw_blocks.push(block);
                }
            }
            "content_block_delta" => {
                if let Some(delta) = decoded.delta {
                    match delta.get("type").and_then(Value::as_str) {
                        Some("text_delta") => {
                            if let Some(text) = delta.get("text").and_then(Value::as_str) {
                                if !text.is_empty() {
                                    self.push_text_delta(text.to_owned());
                                }
                            }
                        }
                        Some("thinking_delta") => {
                            if let Some(text) = delta.get("thinking").and_then(Value::as_str) {
                                if !text.is_empty() {
                                    self.pending.push_back(Ok(LlmEvent {
                                        kind: LlmEventKind::Delta,
                                        content: None,
                                        response: None,
                                        metadata: json!({
                                            "api": "anthropic_messages",
                                            "stream": true,
                                            "thinking": text,
                                        }),
                                    }));
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }
            "message_delta" => {
                if let Some(delta) = decoded.delta {
                    if let Some(reason) = delta.get("stop_reason").and_then(Value::as_str) {
                        self.finish_reason = Some(anthropic_finish_reason(Some(reason)));
                    }
                }
                if let Some(usage) = decoded.usage {
                    self.output_tokens = usage.output_tokens;
                }
            }
            "message_stop" => self.push_finished(),
            "error" => {
                let error = decoded.error.unwrap_or(AnthropicErrorBody {
                    r#type: Some("provider_error".to_owned()),
                    message: "provider stream error".to_owned(),
                });
                self.pending.push_back(Err(LlmError::provider(
                    error.r#type.unwrap_or_else(|| "provider_error".to_owned()),
                    error.message,
                    false,
                    json!({}),
                )));
            }
            "ping" | "content_block_stop" => {}
            _ => {}
        }
    }

    fn push_text_delta(&mut self, text: String) {
        self.content.push_str(&text);
        self.pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::Delta,
            content: Some(text),
            response: None,
            metadata: json!({"api": "anthropic_messages", "stream": true}),
        }));
    }

    fn push_finished(&mut self) {
        if self.finished {
            return;
        }
        self.finished = true;
        let usage = (self.input_tokens > 0 || self.output_tokens > 0).then_some(LlmUsage {
            input_tokens: self.input_tokens,
            output_tokens: self.output_tokens,
            total_tokens: self.input_tokens + self.output_tokens,
        });
        let response = LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: self.provider.clone(),
            model: self.model.clone(),
            content: self.content.clone(),
            finish_reason: self.finish_reason.clone().unwrap_or(LlmFinishReason::Stop),
            usage,
            metadata: json!({
                "api": "anthropic_messages",
                "stream": true,
                "anthropic_version": self.anthropic_version,
                "anthropic_content": self.raw_blocks,
            }),
        };
        self.pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::Finished,
            content: None,
            response: Some(response),
            metadata: json!({"api": "anthropic_messages", "stream": true}),
        }));
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

#[derive(Debug, Serialize)]
struct OpenAiChatCompletionRequest {
    model: String,
    messages: Vec<OpenAiMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<u32>,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    stream_options: Option<OpenAiStreamOptions>,
}

#[derive(Debug, Serialize)]
struct OpenAiStreamOptions {
    include_usage: bool,
}

#[derive(Debug, Serialize)]
struct OpenAiMessage {
    role: String,
    content: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAiChatCompletionResponse {
    #[serde(default)]
    choices: Vec<OpenAiChoice>,
    #[serde(default)]
    usage: Option<OpenAiUsage>,
    #[serde(default)]
    error: Option<OpenAiErrorBody>,
}

#[derive(Debug, Deserialize)]
struct OpenAiChoice {
    message: Option<OpenAiMessageResponse>,
    #[serde(default)]
    delta: Option<OpenAiMessageResponse>,
    #[serde(default)]
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAiMessageResponse {
    #[serde(default)]
    content: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAiUsage {
    #[serde(default)]
    prompt_tokens: u32,
    #[serde(default)]
    completion_tokens: u32,
    #[serde(default)]
    total_tokens: u32,
}

#[derive(Debug, Deserialize)]
struct OpenAiErrorBody {
    #[serde(default)]
    message: String,
    #[serde(default)]
    r#type: Option<String>,
    #[serde(default)]
    code: Option<Value>,
}

struct OpenAiSseState {
    provider: String,
    model: String,
    chunks: Pin<Box<dyn Stream<Item = Result<Bytes, reqwest::Error>> + Send>>,
    buffer: String,
    pending: VecDeque<Result<LlmEvent, LlmError>>,
    content: String,
    finish_reason: Option<LlmFinishReason>,
    usage: Option<LlmUsage>,
    finished: bool,
}

impl OpenAiSseState {
    fn new(
        provider: String,
        model: String,
        chunks: Pin<Box<dyn Stream<Item = Result<Bytes, reqwest::Error>> + Send>>,
    ) -> Self {
        let mut pending = VecDeque::new();
        pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::Started,
            content: None,
            response: None,
            metadata: json!({"provider": provider, "model": model, "stream": true}),
        }));
        Self {
            provider,
            model,
            chunks,
            buffer: String::new(),
            pending,
            content: String::new(),
            finish_reason: None,
            usage: None,
            finished: false,
        }
    }

    async fn next_event(&mut self) -> Option<Result<LlmEvent, LlmError>> {
        loop {
            if let Some(event) = self.pending.pop_front() {
                return Some(event);
            }
            if self.finished {
                return None;
            }
            match self.chunks.next().await {
                Some(Ok(bytes)) => {
                    self.buffer.push_str(&String::from_utf8_lossy(&bytes));
                    self.drain_frames();
                }
                Some(Err(err)) => {
                    self.finished = true;
                    return Some(Err(LlmError::provider(
                        "provider_stream_read_failed",
                        err.to_string(),
                        true,
                        json!({}),
                    )));
                }
                None => {
                    if !self.buffer.trim().is_empty() {
                        if let Some(frame) = take_remaining_sse_frame(&mut self.buffer) {
                            self.handle_frame(&frame);
                        }
                    }
                    if !self.finished {
                        self.push_finished();
                    }
                }
            }
        }
    }

    fn drain_frames(&mut self) {
        while let Some(frame) = take_next_sse_frame(&mut self.buffer) {
            self.handle_frame(&frame);
        }
    }

    fn handle_frame(&mut self, frame: &str) {
        let data = sse_data(frame);
        if data.is_empty() {
            return;
        }
        if data.trim() == "[DONE]" {
            self.push_finished();
            return;
        }
        let decoded = match serde_json::from_str::<OpenAiChatCompletionResponse>(&data) {
            Ok(decoded) => decoded,
            Err(err) => {
                self.pending.push_back(Err(LlmError::provider(
                    "provider_stream_decode_failed",
                    err.to_string(),
                    false,
                    json!({"frame": data}),
                )));
                return;
            }
        };
        if let Some(error) = decoded.error {
            self.pending.push_back(Err(LlmError::provider(
                error.r#type.unwrap_or_else(|| "provider_error".to_owned()),
                error.message,
                false,
                json!({"code": error.code}),
            )));
            return;
        }
        if let Some(usage) = decoded.usage {
            self.usage = Some(LlmUsage {
                input_tokens: usage.prompt_tokens,
                output_tokens: usage.completion_tokens,
                total_tokens: usage.total_tokens,
            });
        }
        for choice in decoded.choices {
            if let Some(content) = choice.delta.and_then(|message| message.content) {
                if !content.is_empty() {
                    self.content.push_str(&content);
                    self.pending.push_back(Ok(LlmEvent {
                        kind: LlmEventKind::Delta,
                        content: Some(content),
                        response: None,
                        metadata: json!({"api": "openai_chat_completions", "stream": true}),
                    }));
                }
            }
            if let Some(reason) = choice.finish_reason {
                self.finish_reason = Some(openai_finish_reason(Some(&reason)));
            }
        }
    }

    fn push_finished(&mut self) {
        if self.finished {
            return;
        }
        self.finished = true;
        let response = LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: self.provider.clone(),
            model: self.model.clone(),
            content: self.content.clone(),
            finish_reason: self.finish_reason.clone().unwrap_or(LlmFinishReason::Stop),
            usage: self.usage.clone(),
            metadata: json!({"api": "openai_chat_completions", "stream": true}),
        };
        self.pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::Finished,
            content: None,
            response: Some(response),
            metadata: json!({"api": "openai_chat_completions", "stream": true}),
        }));
    }
}

fn take_next_sse_frame(buffer: &mut String) -> Option<String> {
    let lf = buffer.find("\n\n").map(|idx| (idx, 2));
    let crlf = buffer.find("\r\n\r\n").map(|idx| (idx, 4));
    let (idx, len) = match (lf, crlf) {
        (Some(a), Some(b)) => {
            if a.0 <= b.0 {
                a
            } else {
                b
            }
        }
        (Some(a), None) => a,
        (None, Some(b)) => b,
        (None, None) => return None,
    };
    let frame = buffer[..idx].to_owned();
    buffer.drain(..idx + len);
    Some(frame)
}

fn take_remaining_sse_frame(buffer: &mut String) -> Option<String> {
    let frame = buffer.trim().to_owned();
    buffer.clear();
    if frame.is_empty() { None } else { Some(frame) }
}

fn sse_data(frame: &str) -> String {
    let mut data = String::new();
    for line in frame.lines() {
        let line = line.trim_end_matches('\r');
        if line.starts_with(':') {
            continue;
        }
        if let Some(piece) = line.strip_prefix("data:") {
            if !data.is_empty() {
                data.push('\n');
            }
            data.push_str(piece.trim_start());
        }
    }
    data
}

#[async_trait]
impl LlmProvider for OpenAiCompatibleProvider {
    async fn complete(&self, request: LlmRequest) -> Result<LlmResponse, LlmError> {
        if request.messages.is_empty() {
            return Err(LlmError::validation(
                "llm request requires at least one message",
            ));
        }
        let payload = OpenAiChatCompletionRequest {
            model: request.model.clone(),
            messages: request
                .messages
                .iter()
                .map(openai_message_from_llm)
                .collect::<Result<Vec<_>, _>>()?,
            temperature: request.temperature,
            max_tokens: request.max_output_tokens,
            stream: false,
            stream_options: None,
        };
        let response = self
            .client
            .post(self.completions_url())
            .bearer_auth(&self.api_key)
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
                .pointer("/error/message")
                .and_then(Value::as_str)
                .unwrap_or(&body)
                .to_owned();
            if status.as_u16() == 429 {
                return Err(LlmError::rate_limited(message, details));
            }
            return Err(LlmError::provider(
                format!("provider_http_{}", status.as_u16()),
                message,
                status.is_server_error(),
                details,
            ));
        }
        let decoded =
            serde_json::from_str::<OpenAiChatCompletionResponse>(&body).map_err(|err| {
                LlmError::provider(
                    "provider_decode_failed",
                    err.to_string(),
                    false,
                    json!({"body": body}),
                )
            })?;
        if let Some(error) = decoded.error {
            return Err(LlmError::provider(
                error.r#type.unwrap_or_else(|| "provider_error".to_owned()),
                error.message,
                false,
                json!({"code": error.code}),
            ));
        }
        let choice = decoded.choices.into_iter().next().ok_or_else(|| {
            LlmError::provider(
                "provider_missing_choice",
                "OpenAI-compatible response did not include a choice",
                false,
                json!({}),
            )
        })?;
        let content = choice
            .message
            .and_then(|message| message.content)
            .unwrap_or_default();
        Ok(LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: self.provider.clone(),
            model: request.model,
            content,
            finish_reason: openai_finish_reason(choice.finish_reason.as_deref()),
            usage: decoded.usage.map(|usage| LlmUsage {
                input_tokens: usage.prompt_tokens,
                output_tokens: usage.completion_tokens,
                total_tokens: usage.total_tokens,
            }),
            metadata: json!({"api": "openai_chat_completions"}),
        })
    }

    async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError> {
        if request.messages.is_empty() {
            return Err(LlmError::validation(
                "llm request requires at least one message",
            ));
        }
        let payload = OpenAiChatCompletionRequest {
            model: request.model.clone(),
            messages: request
                .messages
                .iter()
                .map(openai_message_from_llm)
                .collect::<Result<Vec<_>, _>>()?,
            temperature: request.temperature,
            max_tokens: request.max_output_tokens,
            stream: true,
            stream_options: Some(OpenAiStreamOptions {
                include_usage: true,
            }),
        };
        let response = self
            .client
            .post(self.completions_url())
            .bearer_auth(&self.api_key)
            .json(&payload)
            .send()
            .await
            .map_err(|err| {
                LlmError::provider("provider_request_failed", err.to_string(), true, json!({}))
            })?;
        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.map_err(|err| {
                LlmError::provider(
                    "provider_body_read_failed",
                    err.to_string(),
                    true,
                    json!({}),
                )
            })?;
            let details = serde_json::from_str::<Value>(&body).unwrap_or_else(|_| json!({}));
            let message = details
                .pointer("/error/message")
                .and_then(Value::as_str)
                .unwrap_or(&body)
                .to_owned();
            if status.as_u16() == 429 {
                return Err(LlmError::rate_limited(message, details));
            }
            return Err(LlmError::provider(
                format!("provider_http_{}", status.as_u16()),
                message,
                status.is_server_error(),
                details,
            ));
        }
        let state = OpenAiSseState::new(
            self.provider.clone(),
            request.model,
            Box::pin(response.bytes_stream()),
        );
        Ok(Box::pin(stream::unfold(state, |mut state| async move {
            state.next_event().await.map(|event| (event, state))
        })))
    }
}

#[async_trait]
impl LlmProvider for AnthropicProvider {
    async fn complete(&self, request: LlmRequest) -> Result<LlmResponse, LlmError> {
        if request.messages.is_empty() {
            return Err(LlmError::validation(
                "llm request requires at least one message",
            ));
        }
        let (system, messages) = anthropic_messages_from_llm(&request.messages)?;
        if messages.is_empty() {
            return Err(LlmError::validation(
                "Anthropic request requires at least one user or assistant message",
            ));
        }
        let payload = AnthropicMessagesRequest {
            model: request.model.clone(),
            max_tokens: request.max_output_tokens.unwrap_or(1024),
            messages,
            system,
            temperature: request.temperature,
            tools: request.tools.iter().map(anthropic_tool_from_spec).collect(),
            stream: false,
        };
        let response = self
            .client
            .post(self.messages_url())
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", &self.anthropic_version)
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
                .pointer("/error/message")
                .and_then(Value::as_str)
                .unwrap_or(&body)
                .to_owned();
            if status.as_u16() == 429 {
                return Err(LlmError::rate_limited(message, details));
            }
            return Err(LlmError::provider(
                format!("provider_http_{}", status.as_u16()),
                message,
                status.is_server_error(),
                details,
            ));
        }
        let decoded = serde_json::from_str::<AnthropicMessagesResponse>(&body).map_err(|err| {
            LlmError::provider(
                "provider_decode_failed",
                err.to_string(),
                false,
                json!({"body": body}),
            )
        })?;
        if let Some(error) = decoded.error {
            return Err(LlmError::provider(
                error.r#type.unwrap_or_else(|| "provider_error".to_owned()),
                error.message,
                false,
                json!({}),
            ));
        }
        let raw_content = serde_json::to_value(&decoded.content).map_err(|err| {
            LlmError::provider("provider_decode_failed", err.to_string(), false, json!({}))
        })?;
        let content = anthropic_text_from_blocks(&decoded.content);
        Ok(LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: self.provider.clone(),
            model: request.model,
            content,
            finish_reason: anthropic_finish_reason(decoded.stop_reason.as_deref()),
            usage: decoded.usage.map(|usage| LlmUsage {
                input_tokens: usage.input_tokens,
                output_tokens: usage.output_tokens,
                total_tokens: usage.input_tokens + usage.output_tokens,
            }),
            metadata: json!({
                "api": "anthropic_messages",
                "anthropic_version": self.anthropic_version,
                "anthropic_content": raw_content,
            }),
        })
    }

    async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError> {
        if request.messages.is_empty() {
            return Err(LlmError::validation(
                "llm request requires at least one message",
            ));
        }
        let (system, messages) = anthropic_messages_from_llm(&request.messages)?;
        if messages.is_empty() {
            return Err(LlmError::validation(
                "Anthropic request requires at least one user or assistant message",
            ));
        }
        let payload = AnthropicMessagesRequest {
            model: request.model.clone(),
            max_tokens: request.max_output_tokens.unwrap_or(1024),
            messages,
            system,
            temperature: request.temperature,
            tools: request.tools.iter().map(anthropic_tool_from_spec).collect(),
            stream: true,
        };
        let response = self
            .client
            .post(self.messages_url())
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", &self.anthropic_version)
            .json(&payload)
            .send()
            .await
            .map_err(|err| {
                LlmError::provider("provider_request_failed", err.to_string(), true, json!({}))
            })?;
        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.map_err(|err| {
                LlmError::provider(
                    "provider_body_read_failed",
                    err.to_string(),
                    true,
                    json!({}),
                )
            })?;
            let details = serde_json::from_str::<Value>(&body).unwrap_or_else(|_| json!({}));
            let message = details
                .pointer("/error/message")
                .and_then(Value::as_str)
                .unwrap_or(&body)
                .to_owned();
            if status.as_u16() == 429 {
                return Err(LlmError::rate_limited(message, details));
            }
            return Err(LlmError::provider(
                format!("provider_http_{}", status.as_u16()),
                message,
                status.is_server_error(),
                details,
            ));
        }
        let state = AnthropicSseState::new(
            self.provider.clone(),
            request.model,
            self.anthropic_version.clone(),
            Box::pin(response.bytes_stream()),
        );
        Ok(Box::pin(stream::unfold(state, |mut state| async move {
            state.next_event().await.map(|event| (event, state))
        })))
    }
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
                metadata: json!({"provider": response.provider, "model": response.model}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Delta,
                content: Some(response.content.clone()),
                response: None,
                metadata: json!({"synthetic_stream": true}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Finished,
                content: None,
                response: Some(response),
                metadata: json!({"synthetic_stream": true}),
            }),
        ];
        Ok(Box::pin(stream::iter(events)))
    }
}

fn openai_message_from_llm(message: &LlmMessage) -> Result<OpenAiMessage, LlmError> {
    let role = match message.role {
        LlmRole::System => "system",
        LlmRole::User => "user",
        LlmRole::Assistant => "assistant",
        LlmRole::Tool => {
            return Err(LlmError::validation(
                "OpenAI-compatible provider does not yet support tool role messages",
            ));
        }
    };
    Ok(OpenAiMessage {
        role: role.to_owned(),
        content: message.content.clone(),
        name: message.name.clone(),
    })
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

fn anthropic_messages_from_llm(
    messages: &[LlmMessage],
) -> Result<(Option<String>, Vec<AnthropicMessage>), LlmError> {
    let mut system = Vec::new();
    let mut mapped = Vec::new();
    for message in messages {
        match message.role {
            LlmRole::System => system.push(
                llm_content_as_text(&message.content, "Anthropic system message")?.to_owned(),
            ),
            LlmRole::User => mapped.push(AnthropicMessage {
                role: "user".to_owned(),
                content: message.content.clone(),
            }),
            LlmRole::Assistant => mapped.push(AnthropicMessage {
                role: "assistant".to_owned(),
                content: message.content.clone(),
            }),
            LlmRole::Tool => {
                return Err(LlmError::validation(
                    "Anthropic provider does not yet support tool role messages",
                ));
            }
        }
    }
    let system = if system.is_empty() {
        None
    } else {
        Some(system.join("\n\n"))
    };
    Ok((system, mapped))
}

fn anthropic_tool_from_spec(tool: &ToolSpec) -> AnthropicTool {
    AnthropicTool {
        name: tool.name.clone(),
        description: tool.description.clone(),
        input_schema: tool.input_schema.clone(),
    }
}

fn anthropic_text_from_blocks(blocks: &[Value]) -> String {
    blocks
        .iter()
        .filter(|block| block.get("type").and_then(Value::as_str) == Some("text"))
        .filter_map(|block| block.get("text").and_then(Value::as_str))
        .collect::<Vec<_>>()
        .join("")
}

fn llm_content_as_text<'a>(content: &'a Value, provider: &str) -> Result<&'a str, LlmError> {
    content.as_str().ok_or_else(|| {
        LlmError::validation(format!(
            "{provider} provider only supports text message content"
        ))
    })
}

fn anthropic_finish_reason(value: Option<&str>) -> LlmFinishReason {
    match value {
        Some("end_turn") | Some("stop_sequence") | None => LlmFinishReason::Stop,
        Some("max_tokens") => LlmFinishReason::Length,
        Some("tool_use") => LlmFinishReason::ToolCall,
        _ => LlmFinishReason::Error,
    }
}

fn openai_finish_reason(value: Option<&str>) -> LlmFinishReason {
    match value {
        Some("stop") | None => LlmFinishReason::Stop,
        Some("length") => LlmFinishReason::Length,
        Some("tool_calls") | Some("function_call") => LlmFinishReason::ToolCall,
        Some("content_filter") => LlmFinishReason::ContentFilter,
        _ => LlmFinishReason::Error,
    }
}

pub fn user_message(content: impl Into<String>) -> LlmMessage {
    LlmMessage {
        role: LlmRole::User,
        content: Value::String(content.into()),
        name: None,
        metadata: json!({}),
    }
}

fn estimate_usage(request: &LlmRequest, output: &str) -> LlmUsage {
    let input_tokens = request
        .messages
        .iter()
        .map(|message| rough_token_count(&content_for_usage(&message.content)))
        .sum::<u32>();
    let output_tokens = rough_token_count(output);
    LlmUsage {
        input_tokens,
        output_tokens,
        total_tokens: input_tokens + output_tokens,
    }
}

fn content_for_usage(content: &Value) -> String {
    content
        .as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| content.to_string())
}

fn rough_token_count(text: &str) -> u32 {
    text.split_whitespace().count().max(1) as u32
}

fn protocol_version() -> String {
    PROTOCOL_VERSION.to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Json, Router, routing::post};
    use futures::StreamExt;
    use tokio::net::TcpListener;

    #[tokio::test]
    async fn mock_provider_completes_and_streams() {
        let provider = MockLlmProvider::new("mock", "mock-fast", "hello");
        let request = LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "mock".to_owned(),
            model: "mock-fast".to_owned(),
            messages: vec![user_message("ping")],
            temperature: None,
            max_output_tokens: Some(16),
            tools: vec![],
            metadata: json!({}),
        };

        let response = provider
            .complete(request.clone())
            .await
            .expect("mock completes");
        assert_eq!(response.content, "hello");
        assert_eq!(response.finish_reason, LlmFinishReason::Stop);

        let events = provider
            .stream(request)
            .await
            .expect("mock streams")
            .collect::<Vec<_>>()
            .await;
        assert_eq!(events.len(), 3);
        assert!(matches!(
            events[2].as_ref().expect("event ok").kind,
            LlmEventKind::Finished
        ));
    }

    #[tokio::test]
    async fn openai_compatible_provider_completes_against_chat_api() {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("listener binds");
        let addr = listener.local_addr().expect("local addr");
        let app = Router::new().route(
            "/chat/completions",
            post(|Json(body): Json<Value>| async move {
                assert_eq!(body["model"], "gpt-test");
                assert_eq!(body["messages"][0]["role"], "user");
                Json(json!({
                    "choices": [{
                        "message": {"content": "provider answer"},
                        "finish_reason": "stop"
                    }],
                    "usage": {
                        "prompt_tokens": 3,
                        "completion_tokens": 2,
                        "total_tokens": 5
                    }
                }))
            }),
        );
        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("test server runs");
        });

        let provider = OpenAiCompatibleProvider::new(
            "openai-compatible",
            format!("http://{addr}"),
            "test-key",
        )
        .expect("provider builds");
        let response = provider
            .complete(LlmRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: "openai-compatible".to_owned(),
                model: "gpt-test".to_owned(),
                messages: vec![user_message("ping")],
                temperature: Some(0.2),
                max_output_tokens: Some(32),
                tools: vec![],
                metadata: json!({}),
            })
            .await
            .expect("provider completes");

        assert_eq!(response.provider, "openai-compatible");
        assert_eq!(response.model, "gpt-test");
        assert_eq!(response.content, "provider answer");
        assert_eq!(response.finish_reason, LlmFinishReason::Stop);
        assert_eq!(
            response.usage.expect("usage").total_tokens,
            5,
            "usage maps from provider response"
        );
    }

    #[tokio::test]
    async fn openai_compatible_provider_streams_sse_text_and_usage() {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("listener binds");
        let addr = listener.local_addr().expect("local addr");
        let app = Router::new().route(
            "/chat/completions",
            post(|Json(body): Json<Value>| async move {
                assert_eq!(body["model"], "gpt-stream-test");
                assert_eq!(body["stream"], true);
                assert_eq!(body["stream_options"]["include_usage"], true);
                (
                    [("content-type", "text/event-stream")],
                    concat!(
                        "data: {\"choices\":[{\"delta\":{\"content\":\"hel\"},\"finish_reason\":null}]}\n\n",
                        "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":null}]}\n\n",
                        "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
                        "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":2,\"total_tokens\":6}}\n\n",
                        "data: [DONE]\n\n"
                    ),
                )
            }),
        );
        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("test server runs");
        });

        let provider = OpenAiCompatibleProvider::new(
            "openai-compatible",
            format!("http://{addr}"),
            "test-key",
        )
        .expect("provider builds");
        let events = provider
            .stream(LlmRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: "openai-compatible".to_owned(),
                model: "gpt-stream-test".to_owned(),
                messages: vec![user_message("ping")],
                temperature: None,
                max_output_tokens: Some(32),
                tools: vec![],
                metadata: json!({}),
            })
            .await
            .expect("provider streams")
            .collect::<Vec<_>>()
            .await
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .expect("stream events ok");

        assert!(matches!(events[0].kind, LlmEventKind::Started));
        assert_eq!(events[1].content.as_deref(), Some("hel"));
        assert_eq!(events[2].content.as_deref(), Some("lo"));
        let finished = events.last().expect("finished event");
        assert!(matches!(finished.kind, LlmEventKind::Finished));
        let response = finished.response.as_ref().expect("response");
        assert_eq!(response.content, "hello");
        assert_eq!(response.finish_reason, LlmFinishReason::Stop);
        assert_eq!(response.usage.as_ref().expect("usage").total_tokens, 6);
        assert_eq!(response.metadata["stream"], true);
    }

    #[tokio::test]
    async fn anthropic_provider_completes_against_messages_api() {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("listener binds");
        let addr = listener.local_addr().expect("local addr");
        let app = Router::new().route(
            "/messages",
            post(|Json(body): Json<Value>| async move {
                assert_eq!(body["model"], "claude-test");
                assert_eq!(body["max_tokens"], 64);
                assert_eq!(body["system"], "be concise");
                assert_eq!(body["messages"][0]["role"], "user");
                Json(json!({
                    "content": [{"type": "text", "text": "anthropic answer"}],
                    "stop_reason": "end_turn",
                    "usage": {
                        "input_tokens": 5,
                        "output_tokens": 3
                    }
                }))
            }),
        );
        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("test server runs");
        });

        let provider = AnthropicProvider::new(
            "anthropic",
            format!("http://{addr}"),
            "test-key",
            "2023-06-01",
        )
        .expect("provider builds");
        let response = provider
            .complete(LlmRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: "anthropic".to_owned(),
                model: "claude-test".to_owned(),
                messages: vec![
                    LlmMessage {
                        role: LlmRole::System,
                        content: json!("be concise"),
                        name: None,
                        metadata: json!({}),
                    },
                    user_message("ping"),
                ],
                temperature: Some(0.1),
                max_output_tokens: Some(64),
                tools: vec![],
                metadata: json!({}),
            })
            .await
            .expect("provider completes");

        assert_eq!(response.provider, "anthropic");
        assert_eq!(response.model, "claude-test");
        assert_eq!(response.content, "anthropic answer");
        assert_eq!(response.finish_reason, LlmFinishReason::Stop);
        assert_eq!(
            response.usage.expect("usage").total_tokens,
            8,
            "Anthropic usage totals input plus output tokens"
        );
    }

    #[tokio::test]
    async fn anthropic_provider_streams_sse_text_and_usage() {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("listener binds");
        let addr = listener.local_addr().expect("local addr");
        let app = Router::new().route(
            "/messages",
            post(|Json(body): Json<Value>| async move {
                assert_eq!(body["model"], "claude-stream-test");
                assert_eq!(body["stream"], true);
                assert_eq!(body["messages"][0]["role"], "user");
                (
                    [("content-type", "text/event-stream")],
                    concat!(
                        "event: message_start\n",
                        "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}\n\n",
                        "event: content_block_start\n",
                        "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
                        "event: content_block_delta\n",
                        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hel\"}}\n\n",
                        "event: content_block_delta\n",
                        "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n\n",
                        "event: message_delta\n",
                        "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":3}}\n\n",
                        "event: message_stop\n",
                        "data: {\"type\":\"message_stop\"}\n\n"
                    ),
                )
            }),
        );
        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("test server runs");
        });

        let provider = AnthropicProvider::new(
            "anthropic",
            format!("http://{addr}"),
            "test-key",
            "2023-06-01",
        )
        .expect("provider builds");
        let events = provider
            .stream(LlmRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: "anthropic".to_owned(),
                model: "claude-stream-test".to_owned(),
                messages: vec![user_message("ping")],
                temperature: None,
                max_output_tokens: Some(64),
                tools: vec![],
                metadata: json!({}),
            })
            .await
            .expect("provider streams")
            .collect::<Vec<_>>()
            .await
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .expect("stream events ok");

        assert!(matches!(events[0].kind, LlmEventKind::Started));
        assert_eq!(events[1].content.as_deref(), Some("hel"));
        assert_eq!(events[2].content.as_deref(), Some("lo"));
        let finished = events.last().expect("finished event");
        assert!(matches!(finished.kind, LlmEventKind::Finished));
        let response = finished.response.as_ref().expect("response");
        assert_eq!(response.content, "hello");
        assert_eq!(response.finish_reason, LlmFinishReason::Stop);
        let usage = response.usage.as_ref().expect("usage");
        assert_eq!(usage.input_tokens, 5);
        assert_eq!(usage.output_tokens, 3);
        assert_eq!(usage.total_tokens, 8);
        assert_eq!(response.metadata["stream"], true);
    }

    #[tokio::test]
    async fn anthropic_provider_preserves_multimodal_content_tools_and_raw_blocks() {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("listener binds");
        let addr = listener.local_addr().expect("local addr");
        let app = Router::new().route(
            "/messages",
            post(|Json(body): Json<Value>| async move {
                assert_eq!(body["model"], "claude-vision-test");
                assert_eq!(body["messages"][0]["role"], "user");
                assert_eq!(body["messages"][0]["content"][0]["type"], "image");
                assert_eq!(
                    body["messages"][0]["content"][0]["source"]["media_type"],
                    "image/png"
                );
                assert_eq!(body["tools"][0]["name"], "emit_parsed_transactions");
                assert_eq!(
                    body["tools"][0]["input_schema"]["required"][0],
                    "transactions"
                );
                Json(json!({
                    "content": [{
                        "type": "tool_use",
                        "id": "toolu_1",
                        "name": "emit_parsed_transactions",
                        "input": {
                            "transactions": [{
                                "description": "Coffee",
                                "amount_minor": -450,
                                "currency": "USD",
                                "occurred_at": "2026-06-01"
                            }]
                        }
                    }],
                    "stop_reason": "tool_use",
                    "usage": {
                        "input_tokens": 7,
                        "output_tokens": 5
                    }
                }))
            }),
        );
        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("test server runs");
        });

        let provider = AnthropicProvider::new(
            "anthropic",
            format!("http://{addr}"),
            "test-key",
            "2023-06-01",
        )
        .expect("provider builds");
        let response = provider
            .complete(LlmRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: "anthropic".to_owned(),
                model: "claude-vision-test".to_owned(),
                messages: vec![LlmMessage {
                    role: LlmRole::User,
                    content: json!([
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": "image/png",
                                "data": "ZmFrZQ=="
                            }
                        },
                        {
                            "type": "text",
                            "text": "Extract transactions."
                        }
                    ]),
                    name: None,
                    metadata: json!({}),
                }],
                temperature: None,
                max_output_tokens: Some(1024),
                tools: vec![ToolSpec {
                    name: "emit_parsed_transactions".to_owned(),
                    description: "Emit rows".to_owned(),
                    input_schema: json!({
                        "type": "object",
                        "properties": {"transactions": {"type": "array"}},
                        "required": ["transactions"]
                    }),
                    output_schema: None,
                    risk: agent_core::ToolRisk::ReadOnly,
                    metadata: json!({}),
                }],
                metadata: json!({}),
            })
            .await
            .expect("provider completes");

        assert_eq!(response.content, "");
        assert_eq!(response.finish_reason, LlmFinishReason::ToolCall);
        assert_eq!(
            response.metadata["anthropic_content"][0]["name"],
            "emit_parsed_transactions"
        );
        assert_eq!(
            response.metadata["anthropic_content"][0]["input"]["transactions"][0]["description"],
            "Coffee"
        );
    }

    #[tokio::test]
    async fn ollama_provider_completes_against_chat_api() {
        let listener = TcpListener::bind(("127.0.0.1", 0))
            .await
            .expect("listener binds");
        let addr = listener.local_addr().expect("local addr");
        let app = Router::new().route(
            "/api/chat",
            post(|Json(body): Json<Value>| async move {
                assert_eq!(body["model"], "llama-test");
                assert_eq!(body["stream"], false);
                assert_eq!(body["messages"][0]["role"], "user");
                assert_eq!(body["options"]["num_predict"], 32);
                Json(json!({
                    "message": {"role": "assistant", "content": "local answer"},
                    "done_reason": "stop",
                    "prompt_eval_count": 6,
                    "eval_count": 4
                }))
            }),
        );
        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("test server runs");
        });

        let provider =
            OllamaProvider::new("ollama", format!("http://{addr}")).expect("provider builds");
        let response = provider
            .complete(LlmRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: "ollama".to_owned(),
                model: "llama-test".to_owned(),
                messages: vec![user_message("ping")],
                temperature: Some(0.3),
                max_output_tokens: Some(32),
                tools: vec![],
                metadata: json!({}),
            })
            .await
            .expect("provider completes");

        assert_eq!(response.provider, "ollama");
        assert_eq!(response.model, "llama-test");
        assert_eq!(response.content, "local answer");
        assert_eq!(response.finish_reason, LlmFinishReason::Stop);
        assert_eq!(response.usage.expect("usage").total_tokens, 10);
    }
}
