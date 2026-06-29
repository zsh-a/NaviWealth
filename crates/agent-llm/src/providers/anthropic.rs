use std::collections::{BTreeMap, VecDeque};
use std::pin::Pin;
use std::time::Duration;

use agent_core::{PROTOCOL_VERSION, ToolSpec};
use async_trait::async_trait;
use bytes::Bytes;
use futures::{Stream, StreamExt, stream};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::llm_content_as_text;
use crate::sse::{
    decode_json_value_or_null, sse_data, take_next_sse_frame, take_remaining_sse_frame,
};
use crate::types::{
    LlmError, LlmEvent, LlmEventKind, LlmEventStream, LlmFinishReason, LlmMessage, LlmProvider,
    LlmRequest, LlmResponse, LlmRole, LlmUsage,
};

#[derive(Debug, Clone)]
pub struct AnthropicProvider {
    provider: String,
    base_url: String,
    api_key: String,
    anthropic_version: String,
    client: reqwest::Client,
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
    index: Option<i64>,
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
    blocks: BTreeMap<i64, AnthropicBlockState>,
    finished: bool,
}

#[derive(Debug, Default)]
struct AnthropicBlockState {
    block_type: String,
    id: String,
    name: String,
    input: Option<Value>,
    partial_input_json: String,
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
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
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
            blocks: BTreeMap::new(),
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
                    if !self.buffer.trim().is_empty()
                        && let Some(frame) = take_remaining_sse_frame(&mut self.buffer)
                    {
                        self.handle_frame(&frame);
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
                let index = decoded.index.unwrap_or(0);
                if let Some(block) = decoded.content_block {
                    let block_type = block
                        .get("type")
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                        .to_owned();
                    match block_type.as_str() {
                        "text" => {
                            if let Some(text) = block.get("text").and_then(Value::as_str)
                                && !text.is_empty()
                            {
                                self.push_text_delta(text.to_owned());
                            }
                        }
                        "thinking" => {
                            if let Some(text) = block.get("thinking").and_then(Value::as_str)
                                && !text.is_empty()
                            {
                                self.push_thinking_delta(text.to_owned());
                            }
                            if let Some(signature) = block.get("signature").and_then(Value::as_str)
                                && !signature.is_empty()
                            {
                                self.push_thinking_signature(signature.to_owned());
                            }
                        }
                        "tool_use" => {
                            let state = AnthropicBlockState {
                                block_type: block_type.clone(),
                                id: block
                                    .get("id")
                                    .and_then(Value::as_str)
                                    .unwrap_or_default()
                                    .to_owned(),
                                name: block
                                    .get("name")
                                    .and_then(Value::as_str)
                                    .unwrap_or_default()
                                    .to_owned(),
                                input: block.get("input").cloned(),
                                partial_input_json: String::new(),
                            };
                            self.pending.push_back(Ok(LlmEvent {
                                kind: LlmEventKind::ToolCallStart,
                                content: None,
                                response: None,
                                tool_call_id: Some(state.id.clone()),
                                tool_name: Some(state.name.clone()),
                                partial_input_json: None,
                                tool_input: None,
                                metadata: json!({"api": "anthropic_messages", "stream": true}),
                            }));
                            self.blocks.insert(index, state);
                        }
                        _ => {}
                    }
                    self.raw_blocks.push(block);
                }
            }
            "content_block_delta" => {
                if let Some(delta) = decoded.delta {
                    match delta.get("type").and_then(Value::as_str) {
                        Some("text_delta") => {
                            if let Some(text) = delta.get("text").and_then(Value::as_str)
                                && !text.is_empty()
                            {
                                self.push_text_delta(text.to_owned());
                            }
                        }
                        Some("thinking_delta") => {
                            if let Some(text) = delta.get("thinking").and_then(Value::as_str)
                                && !text.is_empty()
                            {
                                self.push_thinking_delta(text.to_owned());
                            }
                        }
                        Some("signature_delta") => {
                            if let Some(signature) = delta.get("signature").and_then(Value::as_str)
                                && !signature.is_empty()
                            {
                                self.push_thinking_signature(signature.to_owned());
                            }
                        }
                        Some("input_json_delta") => {
                            let index = decoded.index.unwrap_or(0);
                            let partial = delta
                                .get("partial_json")
                                .and_then(Value::as_str)
                                .unwrap_or_default()
                                .to_owned();
                            let state = self.blocks.entry(index).or_default();
                            state.partial_input_json.push_str(&partial);
                            self.pending.push_back(Ok(LlmEvent {
                                kind: LlmEventKind::ToolCallDelta,
                                content: None,
                                response: None,
                                tool_call_id: Some(state.id.clone()),
                                tool_name: Some(state.name.clone()),
                                partial_input_json: Some(partial),
                                tool_input: None,
                                metadata: json!({"api": "anthropic_messages", "stream": true}),
                            }));
                        }
                        _ => {}
                    }
                }
            }
            "message_delta" => {
                if let Some(delta) = decoded.delta
                    && let Some(reason) = delta.get("stop_reason").and_then(Value::as_str)
                {
                    self.finish_reason = Some(anthropic_finish_reason(Some(reason)));
                }
                if let Some(usage) = decoded.usage {
                    self.output_tokens = usage.output_tokens;
                }
            }
            "content_block_stop" => {
                let index = decoded.index.unwrap_or(0);
                if let Some(state) = self.blocks.remove(&index)
                    && state.block_type == "tool_use"
                {
                    let input = if state.partial_input_json.trim().is_empty() {
                        Some(state.input.unwrap_or_else(|| json!({})))
                    } else {
                        decode_json_value_or_null(&state.partial_input_json)
                    };
                    self.pending.push_back(Ok(LlmEvent {
                        kind: LlmEventKind::ToolCallEnd,
                        content: None,
                        response: None,
                        tool_call_id: Some(state.id),
                        tool_name: Some(state.name),
                        partial_input_json: None,
                        tool_input: input,
                        metadata: json!({"api": "anthropic_messages", "stream": true}),
                    }));
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
            "ping" => {}
            _ => {}
        }
    }

    fn push_text_delta(&mut self, text: String) {
        self.content.push_str(&text);
        self.pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::Delta,
            content: Some(text),
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: json!({"api": "anthropic_messages", "stream": true}),
        }));
    }

    fn push_thinking_delta(&mut self, text: String) {
        self.pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::ThinkingDelta,
            content: Some(text),
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: json!({"api": "anthropic_messages", "stream": true}),
        }));
    }

    fn push_thinking_signature(&mut self, signature: String) {
        self.pending.push_back(Ok(LlmEvent {
            kind: LlmEventKind::ThinkingSignatureDelta,
            content: Some(signature),
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
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
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: json!({"api": "anthropic_messages", "stream": true}),
        }));
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

fn anthropic_finish_reason(value: Option<&str>) -> LlmFinishReason {
    match value {
        Some("end_turn") | Some("stop_sequence") | None => LlmFinishReason::Stop,
        Some("max_tokens") => LlmFinishReason::Length,
        Some("tool_use") => LlmFinishReason::ToolCall,
        _ => LlmFinishReason::Error,
    }
}
