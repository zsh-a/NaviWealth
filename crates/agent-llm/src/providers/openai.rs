use std::collections::{BTreeMap, VecDeque};
use std::pin::Pin;
use std::time::Duration;

use agent_core::{PROTOCOL_VERSION, ToolSpec};
use async_trait::async_trait;
use bytes::Bytes;
use futures::{Stream, StreamExt, stream};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::sse::{
    decode_json_value_or_null, sse_data, take_next_sse_frame, take_remaining_sse_frame,
};
use crate::types::{
    LlmError, LlmEvent, LlmEventKind, LlmEventStream, LlmFinishReason, LlmMessage, LlmProvider,
    LlmRequest, LlmResponse, LlmRole, LlmUsage,
};

#[derive(Debug, Clone)]
pub struct OpenAiCompatibleProvider {
    provider: String,
    base_url: String,
    api_key: String,
    client: reqwest::Client,
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
struct OpenAiChatCompletionRequest {
    model: String,
    messages: Vec<OpenAiMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<u32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    tools: Vec<OpenAiTool>,
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
    #[serde(skip_serializing_if = "Value::is_null")]
    content: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    tool_call_id: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    tool_calls: Vec<OpenAiToolCall>,
}

#[derive(Debug, Serialize)]
struct OpenAiTool {
    r#type: String,
    function: OpenAiToolFunction,
}

#[derive(Debug, Serialize)]
struct OpenAiToolFunction {
    name: String,
    description: String,
    parameters: Value,
}

#[derive(Debug, Serialize)]
struct OpenAiToolCall {
    id: String,
    r#type: String,
    function: OpenAiToolCallFunction,
}

#[derive(Debug, Serialize)]
struct OpenAiToolCallFunction {
    name: String,
    arguments: String,
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
    #[serde(default)]
    reasoning_content: Option<String>,
    #[serde(default)]
    reasoning: Option<String>,
    #[serde(default)]
    tool_calls: Option<Vec<OpenAiStreamToolCall>>,
}

#[derive(Debug, Deserialize)]
struct OpenAiStreamToolCall {
    #[serde(default)]
    index: Option<i64>,
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    function: Option<OpenAiStreamToolFunction>,
}

#[derive(Debug, Deserialize)]
struct OpenAiStreamToolFunction {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    arguments: Option<String>,
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
    tools: BTreeMap<i64, OpenAiToolCallState>,
    finished: bool,
}

#[derive(Debug, Default)]
struct OpenAiToolCallState {
    id: String,
    name: String,
    arguments: String,
    started: bool,
    ended: bool,
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
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
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
            tools: BTreeMap::new(),
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
            if let Some(delta) = choice.delta {
                if let Some(content) = delta.content
                    && !content.is_empty()
                {
                    self.content.push_str(&content);
                    self.pending.push_back(Ok(LlmEvent {
                        kind: LlmEventKind::Delta,
                        content: Some(content),
                        response: None,
                        tool_call_id: None,
                        tool_name: None,
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({"api": "openai_chat_completions", "stream": true}),
                    }));
                }
                if let Some(reasoning) = delta.reasoning_content.or(delta.reasoning)
                    && !reasoning.is_empty()
                {
                    self.pending.push_back(Ok(LlmEvent {
                        kind: LlmEventKind::ThinkingDelta,
                        content: Some(reasoning),
                        response: None,
                        tool_call_id: None,
                        tool_name: None,
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({"api": "openai_chat_completions", "stream": true}),
                    }));
                }
                if let Some(tool_calls) = delta.tool_calls {
                    for tool_call in tool_calls {
                        let index = tool_call.index.unwrap_or(0);
                        let state = self.tools.entry(index).or_default();
                        if let Some(id) = tool_call.id
                            && !id.is_empty()
                        {
                            state.id = id;
                        }
                        if let Some(function) = tool_call.function {
                            if let Some(name) = function.name
                                && !name.is_empty()
                            {
                                state.name = name;
                            }
                            if let Some(arguments) = function.arguments {
                                if !state.started
                                    && (!state.id.is_empty() || !state.name.is_empty())
                                {
                                    state.started = true;
                                    self.pending.push_back(Ok(LlmEvent {
                                        kind: LlmEventKind::ToolCallStart,
                                        content: None,
                                        response: None,
                                        tool_call_id: Some(openai_tool_id(index, state)),
                                        tool_name: Some(state.name.clone()),
                                        partial_input_json: None,
                                        tool_input: None,
                                        metadata: json!({"api": "openai_chat_completions", "stream": true}),
                                    }));
                                }
                                if !arguments.is_empty() {
                                    state.arguments.push_str(&arguments);
                                    self.pending.push_back(Ok(LlmEvent {
                                        kind: LlmEventKind::ToolCallDelta,
                                        content: None,
                                        response: None,
                                        tool_call_id: Some(openai_tool_id(index, state)),
                                        tool_name: Some(state.name.clone()),
                                        partial_input_json: Some(arguments),
                                        tool_input: None,
                                        metadata: json!({"api": "openai_chat_completions", "stream": true}),
                                    }));
                                }
                            } else if !state.started
                                && (!state.id.is_empty() || !state.name.is_empty())
                            {
                                state.started = true;
                                self.pending.push_back(Ok(LlmEvent {
                                    kind: LlmEventKind::ToolCallStart,
                                    content: None,
                                    response: None,
                                    tool_call_id: Some(openai_tool_id(index, state)),
                                    tool_name: Some(state.name.clone()),
                                    partial_input_json: None,
                                    tool_input: None,
                                    metadata: json!({"api": "openai_chat_completions", "stream": true}),
                                }));
                            }
                        }
                    }
                }
            }
            if let Some(reason) = choice.finish_reason {
                self.finish_reason = Some(openai_finish_reason(Some(&reason)));
                if matches!(self.finish_reason, Some(LlmFinishReason::ToolCall)) {
                    self.push_openai_tool_call_ends();
                }
            }
        }
    }

    fn push_openai_tool_call_ends(&mut self) {
        for (index, state) in self.tools.iter_mut() {
            if state.ended {
                continue;
            }
            if !state.started {
                state.started = true;
                self.pending.push_back(Ok(LlmEvent {
                    kind: LlmEventKind::ToolCallStart,
                    content: None,
                    response: None,
                    tool_call_id: Some(openai_tool_id(*index, state)),
                    tool_name: Some(state.name.clone()),
                    partial_input_json: None,
                    tool_input: None,
                    metadata: json!({"api": "openai_chat_completions", "stream": true}),
                }));
            }
            state.ended = true;
            self.pending.push_back(Ok(LlmEvent {
                kind: LlmEventKind::ToolCallEnd,
                content: None,
                response: None,
                tool_call_id: Some(openai_tool_id(*index, state)),
                tool_name: Some(state.name.clone()),
                partial_input_json: None,
                tool_input: decode_json_value_or_null(&state.arguments),
                metadata: json!({"api": "openai_chat_completions", "stream": true}),
            }));
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
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: json!({"api": "openai_chat_completions", "stream": true}),
        }));
    }
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
                .map(openai_messages_from_llm)
                .collect::<Result<Vec<_>, _>>()?
                .into_iter()
                .flatten()
                .collect(),
            temperature: request.temperature,
            max_tokens: request.max_output_tokens,
            tools: request.tools.iter().map(openai_tool_from_spec).collect(),
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
                .map(openai_messages_from_llm)
                .collect::<Result<Vec<_>, _>>()?
                .into_iter()
                .flatten()
                .collect(),
            temperature: request.temperature,
            max_tokens: request.max_output_tokens,
            tools: request.tools.iter().map(openai_tool_from_spec).collect(),
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

fn openai_messages_from_llm(message: &LlmMessage) -> Result<Vec<OpenAiMessage>, LlmError> {
    match message.role {
        LlmRole::System => Ok(vec![openai_plain_message(
            "system",
            message.content.clone(),
            message.name.clone(),
        )]),
        LlmRole::User => openai_user_messages_from_llm(message),
        LlmRole::Assistant => Ok(vec![openai_assistant_message_from_llm(message)?]),
        LlmRole::Tool => Ok(vec![OpenAiMessage {
            role: "tool".to_owned(),
            content: openai_content_as_text_value(&message.content),
            name: message.name.clone(),
            tool_call_id: openai_tool_call_id_from_message(message),
            tool_calls: Vec::new(),
        }]),
    }
}

fn openai_plain_message(role: &str, content: Value, name: Option<String>) -> OpenAiMessage {
    OpenAiMessage {
        role: role.to_owned(),
        content,
        name,
        tool_call_id: None,
        tool_calls: Vec::new(),
    }
}

fn openai_user_messages_from_llm(message: &LlmMessage) -> Result<Vec<OpenAiMessage>, LlmError> {
    let Some(blocks) = message.content.as_array() else {
        return Ok(vec![openai_plain_message(
            "user",
            message.content.clone(),
            message.name.clone(),
        )]);
    };

    let mut messages = Vec::new();
    let mut text_parts = Vec::new();
    for block in blocks {
        match block.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(text) = block.get("text").and_then(Value::as_str)
                    && !text.is_empty()
                {
                    text_parts.push(json!({"type": "text", "text": text}));
                }
            }
            Some("tool_result") => messages.push(OpenAiMessage {
                role: "tool".to_owned(),
                tool_call_id: block
                    .get("tool_use_id")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
                    .or_else(|| openai_tool_call_id_from_message(message)),
                content: openai_content_as_text_value(block.get("content").unwrap_or(&Value::Null)),
                name: message.name.clone(),
                tool_calls: Vec::new(),
            }),
            _ => {}
        }
    }
    if !text_parts.is_empty() {
        messages.insert(
            0,
            openai_plain_message("user", Value::Array(text_parts), message.name.clone()),
        );
    }
    if messages.is_empty() {
        messages.push(openai_plain_message(
            "user",
            message.content.clone(),
            message.name.clone(),
        ));
    }
    Ok(messages)
}

fn openai_assistant_message_from_llm(message: &LlmMessage) -> Result<OpenAiMessage, LlmError> {
    let Some(blocks) = message.content.as_array() else {
        return Ok(openai_plain_message(
            "assistant",
            message.content.clone(),
            message.name.clone(),
        ));
    };

    let mut text = String::new();
    let mut tool_calls = Vec::new();
    for block in blocks {
        match block.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(value) = block.get("text").and_then(Value::as_str) {
                    text.push_str(value);
                }
            }
            Some("tool_use") => {
                let id = block
                    .get("id")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_owned();
                let name = block
                    .get("name")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_owned();
                if name.is_empty() {
                    return Err(LlmError::validation(
                        "OpenAI assistant tool_use block requires a name",
                    ));
                }
                tool_calls.push(OpenAiToolCall {
                    id,
                    r#type: "function".to_owned(),
                    function: OpenAiToolCallFunction {
                        name,
                        arguments: serde_json::to_string(block.get("input").unwrap_or(&json!({})))
                            .map_err(|err| {
                                LlmError::validation(format!(
                                    "OpenAI assistant tool input is not serializable: {err}"
                                ))
                            })?,
                    },
                });
            }
            _ => {}
        }
    }

    Ok(OpenAiMessage {
        role: "assistant".to_owned(),
        content: if text.is_empty() {
            Value::Null
        } else {
            Value::String(text)
        },
        name: message.name.clone(),
        tool_call_id: None,
        tool_calls,
    })
}

fn openai_tool_call_id_from_message(message: &LlmMessage) -> Option<String> {
    message
        .metadata
        .get("tool_call_id")
        .and_then(Value::as_str)
        .map(str::to_owned)
}

fn openai_content_as_text_value(value: &Value) -> Value {
    match value {
        Value::String(_) => value.clone(),
        Value::Null => Value::String(String::new()),
        _ => Value::String(value.to_string()),
    }
}

fn openai_tool_from_spec(tool: &ToolSpec) -> OpenAiTool {
    OpenAiTool {
        r#type: "function".to_owned(),
        function: OpenAiToolFunction {
            name: tool.name.clone(),
            description: tool.description.clone(),
            parameters: tool.input_schema.clone(),
        },
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

fn openai_tool_id(index: i64, state: &OpenAiToolCallState) -> String {
    if state.id.is_empty() {
        format!("call_{index}")
    } else {
        state.id.clone()
    }
}
