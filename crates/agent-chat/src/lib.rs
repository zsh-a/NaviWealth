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

async fn run_chat_turn(
    provider: Arc<dyn LlmProvider>,
    services: Arc<dyn AgentServices>,
    request: ChatTurnRequest,
    sender: mpsc::Sender<Result<ChatTurnEvent, ChatError>>,
) {
    if request.messages.is_empty() {
        send_error(
            &sender,
            0,
            ChatError::validation("chat turn requires at least one message"),
        )
        .await;
        return;
    }
    if !request.metadata.is_null() && !request.metadata.is_object() {
        send_error(
            &sender,
            0,
            ChatError::validation("chat turn metadata must be a JSON object"),
        )
        .await;
        return;
    }
    let max_tool_rounds = request.max_tool_rounds.max(1);
    let mut conversation = request.messages.clone();
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
            metadata: turn_metadata(&request),
        },
    )
    .await;

    for round in 1..=max_tool_rounds {
        let llm_request = LlmRequest {
            protocol_version: request.protocol_version.clone(),
            provider: request.provider.clone(),
            model: request.model.clone(),
            messages: conversation.clone(),
            temperature: request.temperature,
            max_output_tokens: request.max_output_tokens,
            tools: request.tools.clone(),
            metadata: llm_metadata(&request),
        };
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

        if !matches!(response.finish_reason, LlmFinishReason::ToolCall) || tool_calls.is_empty() {
            send_done(&sender, round, finish_reason(&response.finish_reason)).await;
            return;
        }
        if round >= max_tool_rounds {
            send_error(
                &sender,
                round,
                ChatError::validation("chat turn exceeded the tool round budget"),
            )
            .await;
            return;
        }

        conversation.push(assistant_message(&assistant_text, &tool_calls));
        let mut result_blocks = Vec::new();
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
            result_blocks.push(tool_result_block(&tool_call.id, output));
        }
        conversation.push(LlmMessage {
            role: LlmRole::User,
            content: Value::Array(result_blocks),
            name: None,
            metadata: json!({}),
        });
    }
}

#[derive(Debug, Clone)]
struct ChatToolCall {
    id: String,
    name: String,
    input: Value,
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

fn turn_metadata(request: &ChatTurnRequest) -> Value {
    json!({
        "turn_id": request.turn_id,
        "session_id": request.session_id,
        "thread_id": request.thread_id,
        "agent_id": request.agent_id,
        "surface": request.surface,
        "mode": request.mode,
        "provider": request.provider,
        "model": request.model,
    })
}

fn llm_metadata(request: &ChatTurnRequest) -> Value {
    let mut metadata = if request.metadata.is_null() {
        json!({})
    } else {
        request.metadata.clone()
    };
    if let Some(object) = metadata.as_object_mut() {
        object.insert("chat_turn".to_owned(), Value::Bool(true));
        if let Some(value) = &request.turn_id {
            object.insert("turn_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &request.session_id {
            object.insert("session_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &request.thread_id {
            object.insert("thread_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &request.agent_id {
            object.insert("agent_id".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &request.surface {
            object.insert("surface".to_owned(), Value::String(value.clone()));
        }
        if let Some(value) = &request.mode {
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
