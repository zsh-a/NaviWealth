use std::{pin::Pin, sync::Arc};

use agent_core::{AgentErrorKind, AgentErrorRecord, AgentServices, PROTOCOL_VERSION, ToolSpec};
use agent_llm::{
    LlmError, LlmEvent, LlmEventKind, LlmFinishReason, LlmMessage, LlmProvider, LlmRequest,
    LlmResponse, LlmRole, LlmUsage,
};
use futures::{Stream, stream};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use thiserror::Error;
use tokio::sync::mpsc;

pub type ChatEventStream = Pin<Box<dyn Stream<Item = Result<ChatTurnEvent, ChatError>> + Send>>;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ChatTurnRequest {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub surface: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
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
    #[serde(default = "default_max_tool_rounds")]
    pub max_tool_rounds: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ChatTurnState {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub turn_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub surface: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thread_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
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
    #[serde(default = "default_max_tool_rounds")]
    pub max_tool_rounds: u32,
    #[serde(default)]
    pub round: u32,
    #[serde(default)]
    pub pending_tool_calls: Vec<ChatToolCall>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ChatToolCall {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub input: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ChatToolResult {
    pub tool_call_id: String,
    pub tool_name: String,
    #[serde(default)]
    pub output: Value,
    #[serde(default)]
    pub is_error: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ChatTurnAdvance {
    Completed {
        state: ChatTurnState,
        stop_reason: String,
    },
    RequiresToolResults {
        state: ChatTurnState,
        tool_calls: Vec<ChatToolCall>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ChatTurnEvent {
    pub kind: ChatTurnEventKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response: Option<LlmResponse>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_call_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partial_input_json: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_input: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_output: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub usage: Option<LlmUsage>,
    pub round: u32,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ChatTurnEventKind {
    Started,
    LlmStarted,
    Delta,
    ThinkingDelta,
    ThinkingSignatureDelta,
    ToolCallStart,
    ToolCallDelta,
    ToolCallEnd,
    ToolResult,
    Usage,
    RoundFinished,
    Error,
    Done,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ChatErrorRecord {
    pub code: String,
    pub message: String,
    pub retryable: bool,
    #[serde(default)]
    pub details: Value,
}

#[derive(Debug, Error)]
#[error("{record:?}")]
pub struct ChatError {
    pub record: Box<ChatErrorRecord>,
}

impl ChatError {
    pub fn validation(message: impl Into<String>) -> Self {
        Self {
            record: Box::new(ChatErrorRecord {
                code: "validation_error".to_owned(),
                message: message.into(),
                retryable: false,
                details: json!({}),
            }),
        }
    }

    fn llm(error: LlmError) -> Self {
        let record = error.record;
        Self {
            record: Box::new(ChatErrorRecord {
                code: record.code,
                message: record.message,
                retryable: record.retryable,
                details: record.details,
            }),
        }
    }
}

#[derive(Clone)]
pub struct ChatTurnRunner {
    provider: Arc<dyn LlmProvider>,
    services: Arc<dyn AgentServices>,
}

impl ChatTurnRunner {
    pub fn new(provider: Arc<dyn LlmProvider>, services: Arc<dyn AgentServices>) -> Self {
        Self { provider, services }
    }

    pub fn stream(&self, request: ChatTurnRequest) -> ChatEventStream {
        let (sender, receiver) = mpsc::channel(64);
        let provider = self.provider.clone();
        let services = self.services.clone();
        tokio::spawn(async move {
            run_chat_turn(provider, services, request, sender).await;
        });
        Box::pin(stream::unfold(receiver, |mut receiver| async move {
            receiver.recv().await.map(|event| (event, receiver))
        }))
    }
}

pub fn chat_turn_initial_state(request: &ChatTurnRequest) -> Result<ChatTurnState, ChatError> {
    if request.messages.is_empty() {
        return Err(ChatError::validation(
            "chat turn requires at least one message",
        ));
    }
    if !request.metadata.is_null() && !request.metadata.is_object() {
        return Err(ChatError::validation(
            "chat turn metadata must be a JSON object",
        ));
    }
    Ok(ChatTurnState {
        protocol_version: request.protocol_version.clone(),
        turn_id: request.turn_id.clone(),
        surface: request.surface.clone(),
        mode: request.mode.clone(),
        session_id: request.session_id.clone(),
        thread_id: request.thread_id.clone(),
        agent_id: request.agent_id.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        messages: request.messages.clone(),
        temperature: request.temperature,
        max_output_tokens: request.max_output_tokens,
        tools: request.tools.clone(),
        metadata: if request.metadata.is_null() {
            json!({})
        } else {
            request.metadata.clone()
        },
        max_tool_rounds: request.max_tool_rounds.max(1),
        round: 0,
        pending_tool_calls: Vec::new(),
    })
}

pub fn chat_turn_llm_request(state: &ChatTurnState) -> LlmRequest {
    LlmRequest {
        protocol_version: state.protocol_version.clone(),
        provider: state.provider.clone(),
        model: state.model.clone(),
        messages: state.messages.clone(),
        temperature: state.temperature,
        max_output_tokens: state.max_output_tokens,
        tools: state.tools.clone(),
        metadata: llm_metadata(state),
    }
}

pub fn chat_turn_next_round(state: &ChatTurnState) -> u32 {
    state.round.saturating_add(1)
}

pub fn chat_turn_apply_response(
    mut state: ChatTurnState,
    assistant_text: &str,
    tool_calls: Vec<ChatToolCall>,
    response: &LlmResponse,
) -> Result<ChatTurnAdvance, ChatError> {
    let round = chat_turn_next_round(&state);
    state.round = round;
    if !matches!(response.finish_reason, LlmFinishReason::ToolCall) || tool_calls.is_empty() {
        state.pending_tool_calls.clear();
        return Ok(ChatTurnAdvance::Completed {
            state,
            stop_reason: finish_reason(&response.finish_reason).to_owned(),
        });
    }
    if round >= state.max_tool_rounds {
        return Err(ChatError::validation(
            "chat turn exceeded the tool round budget",
        ));
    }

    state
        .messages
        .push(assistant_message(assistant_text, &tool_calls));
    state.pending_tool_calls = tool_calls.clone();
    Ok(ChatTurnAdvance::RequiresToolResults { state, tool_calls })
}

pub fn chat_turn_apply_tool_results(
    mut state: ChatTurnState,
    results: Vec<ChatToolResult>,
) -> Result<ChatTurnState, ChatError> {
    if state.pending_tool_calls.is_empty() {
        return Err(ChatError::validation(
            "chat turn has no pending tool calls to resume",
        ));
    }
    let mut result_blocks = Vec::new();
    for call in state.pending_tool_calls.clone() {
        let result = results
            .iter()
            .find(|result| result.tool_call_id == call.id)
            .ok_or_else(|| {
                ChatError::validation(format!("missing tool result for tool call '{}'", call.id))
            })?;
        result_blocks.push(tool_result_block(
            &call.id,
            ToolOutput {
                value: result.output.clone(),
                is_error: result.is_error,
            },
        ));
    }
    state.pending_tool_calls.clear();
    state.messages.push(LlmMessage {
        role: LlmRole::User,
        content: Value::Array(result_blocks),
        name: None,
        metadata: json!({}),
    });
    Ok(state)
}

async fn run_chat_turn(
    provider: Arc<dyn LlmProvider>,
    services: Arc<dyn AgentServices>,
    request: ChatTurnRequest,
    sender: mpsc::Sender<Result<ChatTurnEvent, ChatError>>,
) {
    let mut state = match chat_turn_initial_state(&request) {
        Ok(state) => state,
        Err(error) => {
            send_error(&sender, 0, error).await;
            return;
        }
    };
    send_event(
        &sender,
        ChatTurnEvent {
            kind: ChatTurnEventKind::Started,
            content: None,
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            tool_output: None,
            usage: None,
            round: 0,
            metadata: turn_metadata(&state),
        },
    )
    .await;

    loop {
        let round = chat_turn_next_round(&state);
        let llm_request = chat_turn_llm_request(&state);
        let mut stream = match provider.stream(llm_request).await {
            Ok(stream) => stream,
            Err(error) => {
                send_error(&sender, round, ChatError::llm(error)).await;
                return;
            }
        };

        let mut assistant_text = String::new();
        let mut tool_calls = Vec::new();
        let mut response = None;
        while let Some(event) = futures::StreamExt::next(&mut stream).await {
            let event = match event {
                Ok(event) => event,
                Err(error) => {
                    send_error(&sender, round, ChatError::llm(error)).await;
                    return;
                }
            };
            if let Some(content) = event.content.as_ref()
                && matches!(event.kind, LlmEventKind::Delta)
            {
                assistant_text.push_str(content);
            }
            if matches!(event.kind, LlmEventKind::ToolCallEnd) {
                let Some(id) = non_empty(event.tool_call_id.clone()) else {
                    send_error(
                        &sender,
                        round,
                        ChatError::validation("tool_call_end requires tool_call_id"),
                    )
                    .await;
                    return;
                };
                let Some(name) = non_empty(event.tool_name.clone()) else {
                    send_error(
                        &sender,
                        round,
                        ChatError::validation("tool_call_end requires tool_name"),
                    )
                    .await;
                    return;
                };
                tool_calls.push(ChatToolCall {
                    id,
                    name,
                    input: event.tool_input.clone().unwrap_or_else(|| json!({})),
                });
            }
            if matches!(event.kind, LlmEventKind::Finished) {
                response = event.response.clone();
                continue;
            }
            send_event(&sender, chat_event_from_llm_event(event, round)).await;
        }

        let Some(response) = response else {
            send_error(
                &sender,
                round,
                ChatError::validation("LLM stream ended without a finished event"),
            )
            .await;
            return;
        };
        if let Some(usage) = response.usage.clone() {
            send_event(
                &sender,
                ChatTurnEvent {
                    kind: ChatTurnEventKind::Usage,
                    content: None,
                    response: None,
                    tool_call_id: None,
                    tool_name: None,
                    partial_input_json: None,
                    tool_input: None,
                    tool_output: None,
                    usage: Some(usage),
                    round,
                    metadata: json!({}),
                },
            )
            .await;
        }
        send_event(
            &sender,
            ChatTurnEvent {
                kind: ChatTurnEventKind::RoundFinished,
                content: None,
                response: Some(response.clone()),
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                tool_output: None,
                usage: response.usage.clone(),
                round,
                metadata: json!({"finish_reason": response.finish_reason}),
            },
        )
        .await;

        let advance = match chat_turn_apply_response(state, &assistant_text, tool_calls, &response)
        {
            Ok(advance) => advance,
            Err(error) => {
                send_error(&sender, round, error).await;
                return;
            }
        };
        let (pending_state, tool_calls) = match advance {
            ChatTurnAdvance::Completed {
                state: _,
                stop_reason,
            } => {
                send_done(&sender, round, &stop_reason).await;
                return;
            }
            ChatTurnAdvance::RequiresToolResults { state, tool_calls } => (state, tool_calls),
        };

        let mut results = Vec::new();
        for tool_call in tool_calls {
            let output = match services
                .call_tool(&tool_call.name, tool_call.input.clone())
                .await
            {
                Ok(output) => ToolOutput {
                    value: output,
                    is_error: false,
                },
                Err(error) => ToolOutput {
                    value: json!({
                        "code": error.record.code,
                        "message": error.record.message,
                        "retryable": error.record.retryable,
                        "details": error.record.details,
                    }),
                    is_error: true,
                },
            };
            send_event(
                &sender,
                ChatTurnEvent {
                    kind: ChatTurnEventKind::ToolResult,
                    content: None,
                    response: None,
                    tool_call_id: Some(tool_call.id.clone()),
                    tool_name: Some(tool_call.name.clone()),
                    partial_input_json: None,
                    tool_input: Some(tool_call.input.clone()),
                    tool_output: Some(output.value.clone()),
                    usage: None,
                    round,
                    metadata: json!({"is_error": output.is_error}),
                },
            )
            .await;
            results.push(ChatToolResult {
                tool_call_id: tool_call.id,
                tool_name: tool_call.name,
                output: output.value,
                is_error: output.is_error,
            });
        }
        state = match chat_turn_apply_tool_results(pending_state, results) {
            Ok(state) => state,
            Err(error) => {
                send_error(&sender, round, error).await;
                return;
            }
        };
    }
}

#[derive(Debug, Clone)]
struct ToolOutput {
    value: Value,
    is_error: bool,
}

fn assistant_message(text: &str, tool_calls: &[ChatToolCall]) -> LlmMessage {
    let mut blocks = Vec::new();
    if !text.is_empty() {
        blocks.push(json!({"type": "text", "text": text}));
    }
    for call in tool_calls {
        blocks.push(json!({
            "type": "tool_use",
            "id": call.id,
            "name": call.name,
            "input": call.input,
        }));
    }
    LlmMessage {
        role: LlmRole::Assistant,
        content: Value::Array(blocks),
        name: None,
        metadata: json!({}),
    }
}

fn tool_result_block(tool_call_id: &str, output: ToolOutput) -> Value {
    json!({
        "type": "tool_result",
        "tool_use_id": tool_call_id,
        "content": match output.value {
            Value::String(value) => Value::String(value),
            value => Value::String(value.to_string()),
        },
        "is_error": output.is_error,
    })
}

fn chat_event_from_llm_event(event: LlmEvent, round: u32) -> ChatTurnEvent {
    ChatTurnEvent {
        kind: match event.kind {
            LlmEventKind::Started => ChatTurnEventKind::LlmStarted,
            LlmEventKind::Delta => ChatTurnEventKind::Delta,
            LlmEventKind::ThinkingDelta => ChatTurnEventKind::ThinkingDelta,
            LlmEventKind::ThinkingSignatureDelta => ChatTurnEventKind::ThinkingSignatureDelta,
            LlmEventKind::ToolCallStart => ChatTurnEventKind::ToolCallStart,
            LlmEventKind::ToolCallDelta => ChatTurnEventKind::ToolCallDelta,
            LlmEventKind::ToolCallEnd => ChatTurnEventKind::ToolCallEnd,
            LlmEventKind::Finished => ChatTurnEventKind::RoundFinished,
        },
        content: event.content,
        response: event.response,
        tool_call_id: event.tool_call_id,
        tool_name: event.tool_name,
        partial_input_json: event.partial_input_json,
        tool_input: event.tool_input,
        tool_output: None,
        usage: None,
        round,
        metadata: event.metadata,
    }
}

async fn send_done(
    sender: &mpsc::Sender<Result<ChatTurnEvent, ChatError>>,
    round: u32,
    reason: &str,
) {
    send_event(
        sender,
        ChatTurnEvent {
            kind: ChatTurnEventKind::Done,
            content: None,
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            tool_output: None,
            usage: None,
            round,
            metadata: json!({"stop_reason": reason}),
        },
    )
    .await;
}

async fn send_error(
    sender: &mpsc::Sender<Result<ChatTurnEvent, ChatError>>,
    round: u32,
    error: ChatError,
) {
    let _ = sender
        .send(Ok(ChatTurnEvent {
            kind: ChatTurnEventKind::Error,
            content: Some(error.record.message.clone()),
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            tool_output: None,
            usage: None,
            round,
            metadata: json!({
                "code": error.record.code,
                "retryable": error.record.retryable,
                "details": error.record.details,
            }),
        }))
        .await;
    let _ = sender.send(Err(error)).await;
}

async fn send_event(sender: &mpsc::Sender<Result<ChatTurnEvent, ChatError>>, event: ChatTurnEvent) {
    let _ = sender.send(Ok(event)).await;
}

fn turn_metadata(state: &ChatTurnState) -> Value {
    json!({
        "turn_id": state.turn_id,
        "session_id": state.session_id,
        "thread_id": state.thread_id,
        "agent_id": state.agent_id,
        "surface": state.surface,
        "mode": state.mode,
        "provider": state.provider,
        "model": state.model,
    })
}

fn llm_metadata(state: &ChatTurnState) -> Value {
    let mut metadata = if state.metadata.is_null() {
        json!({})
    } else {
        state.metadata.clone()
    };
    if let Some(object) = metadata.as_object_mut() {
        object.insert("chat_turn".to_owned(), Value::Bool(true));
        if let Some(value) = &state.turn_id {
            object.insert("turn_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &state.session_id {
            object.insert("session_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &state.thread_id {
            object.insert("thread_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &state.agent_id {
            object.insert("agent_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &state.surface {
            object.insert("surface".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &state.mode {
            object.insert("mode".to_owned(), Value::String(value.clone()));
        }
    }
    metadata
}

fn non_empty(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_owned())
        }
    })
}

fn finish_reason(reason: &LlmFinishReason) -> &'static str {
    match reason {
        LlmFinishReason::Stop => "end_turn",
        LlmFinishReason::Length => "max_tokens",
        LlmFinishReason::ToolCall => "tool_use",
        LlmFinishReason::ContentFilter => "content_filter",
        LlmFinishReason::Error => "error",
    }
}

fn default_max_tool_rounds() -> u32 {
    4
}

fn protocol_version() -> String {
    PROTOCOL_VERSION.to_owned()
}

impl From<ChatError> for agent_core::AgentError {
    fn from(error: ChatError) -> Self {
        agent_core::AgentError {
            record: AgentErrorRecord {
                kind: AgentErrorKind::LlmError,
                code: error.record.code,
                message: error.record.message,
                retryable: error.record.retryable,
                details: error.record.details,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    };

    use agent_core::{AgentError, AgentEvent, ToolError, TraceEvent};
    use agent_llm::{
        LlmError, LlmEventStream, LlmFinishReason, LlmProvider, LlmUsage, MockLlmProvider,
        user_message,
    };
    use async_trait::async_trait;
    use futures::{StreamExt, stream};

    use super::*;

    #[tokio::test]
    async fn mock_chat_turn_streams_text_and_done() {
        let runner = ChatTurnRunner::new(
            Arc::new(MockLlmProvider::new("mock", "mock-model", "hello")),
            Arc::new(TestServices),
        );
        let events = runner
            .stream(ChatTurnRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                turn_id: Some("turn_1".to_owned()),
                surface: None,
                mode: None,
                session_id: None,
                thread_id: None,
                agent_id: Some("chat".to_owned()),
                provider: "mock".to_owned(),
                model: "mock-model".to_owned(),
                messages: vec![user_message("ping")],
                temperature: None,
                max_output_tokens: None,
                tools: vec![],
                metadata: json!({}),
                max_tool_rounds: 4,
            })
            .collect::<Vec<_>>()
            .await
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .expect("events ok");

        assert!(
            events
                .iter()
                .any(|event| event.kind == ChatTurnEventKind::Delta)
        );
        assert!(
            events
                .iter()
                .any(|event| event.kind == ChatTurnEventKind::Done)
        );
        assert_eq!(
            events
                .iter()
                .filter(|event| event.kind == ChatTurnEventKind::RoundFinished)
                .count(),
            1
        );
    }

    #[tokio::test]
    async fn chat_turn_executes_tools_and_continues() {
        let provider = Arc::new(ScriptedToolProvider {
            calls: AtomicUsize::new(0),
        });
        let runner = ChatTurnRunner::new(provider, Arc::new(TestServices));
        let events = runner
            .stream(ChatTurnRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                turn_id: None,
                surface: None,
                mode: None,
                session_id: None,
                thread_id: None,
                agent_id: Some("chat".to_owned()),
                provider: "scripted".to_owned(),
                model: "scripted-model".to_owned(),
                messages: vec![user_message("use a tool")],
                temperature: None,
                max_output_tokens: None,
                tools: vec![],
                metadata: json!({}),
                max_tool_rounds: 4,
            })
            .collect::<Vec<_>>()
            .await
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .expect("events ok");

        assert!(
            events
                .iter()
                .any(|event| event.kind == ChatTurnEventKind::ToolResult)
        );
        assert!(
            events
                .iter()
                .any(|event| event.content.as_deref() == Some("done"))
        );
    }

    #[tokio::test]
    async fn chat_turn_forwards_turn_metadata_to_llm_request() {
        let provider = Arc::new(MetadataProvider {
            metadata: Mutex::new(None),
        });
        let runner = ChatTurnRunner::new(provider.clone(), Arc::new(TestServices));
        runner
            .stream(ChatTurnRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                turn_id: Some("turn_1".to_owned()),
                surface: Some("agent_tui".to_owned()),
                mode: Some("natural_language".to_owned()),
                session_id: Some("session_1".to_owned()),
                thread_id: Some("thread_1".to_owned()),
                agent_id: Some("chat".to_owned()),
                provider: "metadata".to_owned(),
                model: "metadata-model".to_owned(),
                messages: vec![user_message("ping")],
                temperature: None,
                max_output_tokens: None,
                tools: vec![],
                metadata: json!({"source": "test"}),
                max_tool_rounds: 4,
            })
            .collect::<Vec<_>>()
            .await
            .into_iter()
            .collect::<Result<Vec<_>, _>>()
            .expect("events ok");

        let metadata = provider
            .metadata
            .lock()
            .expect("metadata lock")
            .clone()
            .expect("metadata captured");
        assert_eq!(metadata["source"], "test");
        assert_eq!(metadata["chat_turn"], true);
        assert_eq!(metadata["turn_id"], "turn_1");
        assert_eq!(metadata["surface"], "agent_tui");
        assert_eq!(metadata["mode"], "natural_language");
        assert_eq!(metadata["session_id"], "session_1");
        assert_eq!(metadata["thread_id"], "thread_1");
        assert_eq!(metadata["agent_id"], "chat");
    }

    #[test]
    fn chat_turn_state_applies_tool_results_for_resume() {
        let state = chat_turn_initial_state(&ChatTurnRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            turn_id: Some("turn_1".to_owned()),
            surface: Some("agent_tui".to_owned()),
            mode: Some("natural_language".to_owned()),
            session_id: None,
            thread_id: None,
            agent_id: Some("chat".to_owned()),
            provider: "mock".to_owned(),
            model: "mock-model".to_owned(),
            messages: vec![user_message("use a tool")],
            temperature: None,
            max_output_tokens: None,
            tools: vec![],
            metadata: json!({}),
            max_tool_rounds: 4,
        })
        .expect("initial state");
        let response = LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "mock".to_owned(),
            model: "mock-model".to_owned(),
            content: String::new(),
            finish_reason: LlmFinishReason::ToolCall,
            usage: None,
            metadata: json!({}),
        };
        let advance = chat_turn_apply_response(
            state,
            "",
            vec![ChatToolCall {
                id: "call_1".to_owned(),
                name: "echo".to_owned(),
                input: json!({"value": "ok"}),
            }],
            &response,
        )
        .expect("requires tools");
        let pending = match advance {
            ChatTurnAdvance::RequiresToolResults { state, tool_calls } => {
                assert_eq!(tool_calls[0].id, "call_1");
                state
            }
            ChatTurnAdvance::Completed { .. } => panic!("expected tool results"),
        };

        let resumed = chat_turn_apply_tool_results(
            pending,
            vec![ChatToolResult {
                tool_call_id: "call_1".to_owned(),
                tool_name: "echo".to_owned(),
                output: json!({"value": "ok"}),
                is_error: false,
            }],
        )
        .expect("resume applies");

        assert_eq!(resumed.round, 1);
        assert!(resumed.pending_tool_calls.is_empty());
        assert_eq!(resumed.messages.len(), 3);
        assert_eq!(resumed.messages[1].role, LlmRole::Assistant);
        assert_eq!(resumed.messages[2].role, LlmRole::User);
        assert_eq!(
            resumed.messages[2].content[0]["tool_use_id"],
            Value::String("call_1".to_owned())
        );
    }

    #[test]
    fn committed_chat_turn_fixtures_match_runtime_types() {
        let request: ChatTurnRequest = serde_json::from_str(include_str!(
            "../../../fixtures/agent-runtime/chat-turn-request.valid.json"
        ))
        .expect("request fixture");
        let state = chat_turn_initial_state(&request).expect("request creates state");
        assert_eq!(state.provider, "mock");
        assert_eq!(state.max_tool_rounds, 4);

        let pending_state: ChatTurnState = serde_json::from_str(include_str!(
            "../../../fixtures/agent-runtime/chat-turn-state.requires-tool-results.valid.json"
        ))
        .expect("state fixture");
        let result: ChatToolResult = serde_json::from_str(include_str!(
            "../../../fixtures/agent-runtime/chat-tool-result.valid.json"
        ))
        .expect("tool result fixture");
        let resumed =
            chat_turn_apply_tool_results(pending_state, vec![result]).expect("resume fixture");
        assert_eq!(resumed.messages.len(), 3);
        assert!(resumed.pending_tool_calls.is_empty());

        let event: ChatTurnEvent = serde_json::from_str(include_str!(
            "../../../fixtures/agent-runtime/chat-turn-event.round-finished.requires-tool-results.valid.json"
        ))
        .expect("event fixture");
        assert_eq!(event.kind, ChatTurnEventKind::RoundFinished);
        assert_eq!(event.metadata["status"], "requires_tool_results");
    }

    #[test]
    fn shared_agent_chat_turn_event_fixture_matches_runtime_types() {
        let events: Vec<ChatTurnEvent> = serde_json::from_str(include_str!(
            "../../../docs/fixtures/agent_chat_turn_events.json"
        ))
        .expect("shared chat turn events fixture");

        assert_eq!(
            events
                .iter()
                .map(|event| event.kind.clone())
                .collect::<Vec<_>>(),
            vec![
                ChatTurnEventKind::Started,
                ChatTurnEventKind::Delta,
                ChatTurnEventKind::ToolCallStart,
                ChatTurnEventKind::ToolCallDelta,
                ChatTurnEventKind::ToolCallEnd,
                ChatTurnEventKind::Usage,
                ChatTurnEventKind::RoundFinished,
            ]
        );
        assert_eq!(events[2].tool_name.as_deref(), Some("get_holdings"));
        assert_eq!(
            events[4].tool_input.as_ref(),
            Some(&json!({"as_of": "today"}))
        );
        assert_eq!(events[5].usage.as_ref().expect("usage").total_tokens, 18);
        assert_eq!(events[6].metadata["status"], "requires_tool_results");
    }

    struct ScriptedToolProvider {
        calls: AtomicUsize,
    }

    #[async_trait]
    impl LlmProvider for ScriptedToolProvider {
        async fn complete(&self, _request: LlmRequest) -> Result<LlmResponse, LlmError> {
            unreachable!("test uses stream")
        }

        async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError> {
            let call = self.calls.fetch_add(1, Ordering::SeqCst);
            let response = if call == 0 {
                LlmResponse {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    provider: request.provider,
                    model: request.model,
                    content: String::new(),
                    finish_reason: LlmFinishReason::ToolCall,
                    usage: Some(LlmUsage {
                        input_tokens: 1,
                        output_tokens: 1,
                        total_tokens: 2,
                    }),
                    metadata: json!({}),
                }
            } else {
                LlmResponse {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    provider: request.provider,
                    model: request.model,
                    content: "done".to_owned(),
                    finish_reason: LlmFinishReason::Stop,
                    usage: None,
                    metadata: json!({}),
                }
            };
            let events = if call == 0 {
                vec![
                    Ok(LlmEvent {
                        kind: LlmEventKind::Started,
                        content: None,
                        response: None,
                        tool_call_id: None,
                        tool_name: None,
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({}),
                    }),
                    Ok(LlmEvent {
                        kind: LlmEventKind::ToolCallStart,
                        content: None,
                        response: None,
                        tool_call_id: Some("call_1".to_owned()),
                        tool_name: Some("echo".to_owned()),
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({}),
                    }),
                    Ok(LlmEvent {
                        kind: LlmEventKind::ToolCallEnd,
                        content: None,
                        response: None,
                        tool_call_id: Some("call_1".to_owned()),
                        tool_name: Some("echo".to_owned()),
                        partial_input_json: None,
                        tool_input: Some(json!({"value": "ok"})),
                        metadata: json!({}),
                    }),
                    Ok(LlmEvent {
                        kind: LlmEventKind::Finished,
                        content: None,
                        response: Some(response),
                        tool_call_id: None,
                        tool_name: None,
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({}),
                    }),
                ]
            } else {
                vec![
                    Ok(LlmEvent {
                        kind: LlmEventKind::Started,
                        content: None,
                        response: None,
                        tool_call_id: None,
                        tool_name: None,
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({}),
                    }),
                    Ok(LlmEvent {
                        kind: LlmEventKind::Delta,
                        content: Some("done".to_owned()),
                        response: None,
                        tool_call_id: None,
                        tool_name: None,
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({}),
                    }),
                    Ok(LlmEvent {
                        kind: LlmEventKind::Finished,
                        content: None,
                        response: Some(response),
                        tool_call_id: None,
                        tool_name: None,
                        partial_input_json: None,
                        tool_input: None,
                        metadata: json!({}),
                    }),
                ]
            };
            Ok(Box::pin(stream::iter(events)))
        }
    }

    struct MetadataProvider {
        metadata: Mutex<Option<Value>>,
    }

    #[async_trait]
    impl LlmProvider for MetadataProvider {
        async fn complete(&self, _request: LlmRequest) -> Result<LlmResponse, LlmError> {
            unreachable!("test uses stream")
        }

        async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError> {
            *self.metadata.lock().expect("metadata lock") = Some(request.metadata.clone());
            let response = LlmResponse {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                provider: request.provider,
                model: request.model,
                content: "done".to_owned(),
                finish_reason: LlmFinishReason::Stop,
                usage: None,
                metadata: json!({}),
            };
            Ok(Box::pin(stream::iter(vec![
                Ok(LlmEvent {
                    kind: LlmEventKind::Started,
                    content: None,
                    response: None,
                    tool_call_id: None,
                    tool_name: None,
                    partial_input_json: None,
                    tool_input: None,
                    metadata: json!({}),
                }),
                Ok(LlmEvent {
                    kind: LlmEventKind::Delta,
                    content: Some("done".to_owned()),
                    response: None,
                    tool_call_id: None,
                    tool_name: None,
                    partial_input_json: None,
                    tool_input: None,
                    metadata: json!({}),
                }),
                Ok(LlmEvent {
                    kind: LlmEventKind::Finished,
                    content: None,
                    response: Some(response),
                    tool_call_id: None,
                    tool_name: None,
                    partial_input_json: None,
                    tool_input: None,
                    metadata: json!({}),
                }),
            ])))
        }
    }

    struct TestServices;

    #[async_trait]
    impl AgentServices for TestServices {
        async fn call_tool(&self, name: &str, input: Value) -> Result<Value, ToolError> {
            Ok(json!({"tool": name, "input": input}))
        }

        async fn emit_event(&self, _event: AgentEvent) -> Result<(), AgentError> {
            Ok(())
        }

        async fn load_state(&self, _key: &str) -> Result<Option<Value>, AgentError> {
            Ok(None)
        }

        async fn save_state(&self, _key: &str, _value: Value) -> Result<(), AgentError> {
            Ok(())
        }
    }

    #[async_trait]
    impl agent_core::TraceSink for TestServices {
        async fn emit(&self, _event: TraceEvent) -> Result<(), AgentError> {
            Ok(())
        }
    }
}
