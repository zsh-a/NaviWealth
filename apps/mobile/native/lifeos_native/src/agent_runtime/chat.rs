use super::llm_provider::llm_error_record_metadata;
use super::*;

const CHAT_STATE_METADATA_KEY: &str = "chat_state";
const CHAT_TOOL_RESULTS_METADATA_KEY: &str = "tool_results";
const CHAT_STATUS_METADATA_KEY: &str = "status";
const CHAT_TOOL_CALLS_METADATA_KEY: &str = "tool_calls";
const CHAT_STATUS_COMPLETED: &str = "completed";
const CHAT_STATUS_REQUIRES_TOOL_RESULTS: &str = "requires_tool_results";

#[derive(Debug, Clone)]
pub(super) struct ChatTurnEnvelope {
    pub(super) turn_id: Option<String>,
    pub(super) session_id: Option<String>,
    pub(super) thread_id: Option<String>,
    pub(super) surface: Option<String>,
    pub(super) agent_id: Option<String>,
    pub(super) mode: Option<String>,
}

pub(super) async fn stream_chat_turn_response(
    sink: StreamSink<String>,
    provider: Box<dyn LlmProvider>,
    state: ChatTurnState,
) -> Result<()> {
    let envelope = chat_turn_envelope_from_state(&state);
    let round = chat_turn_next_round(&state);
    let request = chat_turn_llm_request(&state);
    let started = chat_turn_started_event(&envelope, &request)?;
    let _ = sink.add(serde_json::to_string(&started)?);
    let mut stream = match provider.stream(request).await {
        Ok(stream) => stream,
        Err(error) => {
            let value = chat_turn_error_event(&envelope, llm_error_record_metadata(error));
            let _ = sink.add(serde_json::to_string(&value)?);
            return Ok(());
        }
    };
    let mut saw_terminal_error = false;
    let mut assistant_text = String::new();
    let mut tool_calls = Vec::new();
    let mut response = None;
    while let Some(event) = stream.next().await {
        match event {
            Ok(mut event) => {
                contracts::normalize_llm_event_contract(&mut event)?;
                if matches!(event.kind, LlmEventKind::Finished) {
                    response = event.response.clone();
                    continue;
                }
                if let Some(content) = event.content.as_ref()
                    && matches!(event.kind, LlmEventKind::Delta)
                {
                    assistant_text.push_str(content);
                }
                if matches!(event.kind, LlmEventKind::ToolCallEnd) {
                    match tool_call_from_event(&event) {
                        Ok(tool_call) => tool_calls.push(tool_call),
                        Err(error) => {
                            saw_terminal_error = true;
                            let value = chat_turn_error_event(
                                &envelope,
                                chat_error_metadata("llm_stream_event_invalid", &error),
                            );
                            let _ = sink.add(serde_json::to_string(&value)?);
                            break;
                        }
                    }
                }
                let value = chat_turn_event_from_llm_event(&envelope, event)?;
                let _ = sink.add(serde_json::to_string(&value)?);
            }
            Err(error) => {
                saw_terminal_error = true;
                let value = chat_turn_error_event(&envelope, llm_error_record_metadata(error));
                let _ = sink.add(serde_json::to_string(&value)?);
                break;
            }
        }
    }
    if saw_terminal_error {
        return Ok(());
    }
    let Some(response) = response else {
        let value = chat_turn_error_event(
            &envelope,
            json!({
                "code": "llm_stream_incomplete",
                "message": "LLM stream ended without a finished event",
                "retryable": false,
                "details": {},
            }),
        );
        let _ = sink.add(serde_json::to_string(&value)?);
        return Ok(());
    };

    if let Some(usage) = response.usage.clone() {
        let mut usage_event = serde_json::to_value(ChatTurnEvent {
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
        })?;
        attach_chat_turn_envelope(&envelope, &mut usage_event);
        let _ = sink.add(serde_json::to_string(&usage_event)?);
    }

    let finish_reason = response.finish_reason.clone();
    let usage = response.usage.clone();
    match chat_turn_apply_response(state, &assistant_text, tool_calls, &response) {
        Ok(ChatTurnAdvance::Completed { state, stop_reason }) => {
            let metadata =
                round_finished_metadata(&state, CHAT_STATUS_COMPLETED, None, Some(finish_reason))?;
            let mut round_finished = serde_json::to_value(ChatTurnEvent {
                kind: ChatTurnEventKind::RoundFinished,
                content: None,
                response: Some(response),
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                tool_output: None,
                usage,
                round,
                metadata,
            })?;
            attach_chat_turn_envelope(&envelope, &mut round_finished);
            let _ = sink.add(serde_json::to_string(&round_finished)?);
            let mut done = serde_json::to_value(ChatTurnEvent {
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
                metadata: json!({"stop_reason": stop_reason}),
            })?;
            attach_chat_turn_envelope(&envelope, &mut done);
            let _ = sink.add(serde_json::to_string(&done)?);
        }
        Ok(ChatTurnAdvance::RequiresToolResults { state, tool_calls }) => {
            let metadata = round_finished_metadata(
                &state,
                CHAT_STATUS_REQUIRES_TOOL_RESULTS,
                Some(&tool_calls),
                Some(finish_reason),
            )?;
            let mut round_finished = serde_json::to_value(ChatTurnEvent {
                kind: ChatTurnEventKind::RoundFinished,
                content: None,
                response: Some(response),
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                tool_output: None,
                usage,
                round,
                metadata,
            })?;
            attach_chat_turn_envelope(&envelope, &mut round_finished);
            let _ = sink.add(serde_json::to_string(&round_finished)?);
        }
        Err(error) => {
            let value = chat_turn_error_event(&envelope, chat_error_record_metadata(&error));
            let _ = sink.add(serde_json::to_string(&value)?);
        }
    }
    Ok(())
}

pub(super) fn chat_turn_state_from_request(request: &ChatTurnRequest) -> Result<ChatTurnState> {
    if let Some(state_value) = request.metadata.get(CHAT_STATE_METADATA_KEY) {
        let mut state: ChatTurnState = serde_json::from_value(state_value.clone())?;
        let tool_results_value = request
            .metadata
            .get(CHAT_TOOL_RESULTS_METADATA_KEY)
            .cloned()
            .unwrap_or_else(|| json!([]));
        let tool_results: Vec<ChatToolResult> = serde_json::from_value(tool_results_value)?;
        state.provider = request.provider.clone();
        state.model = request.model.clone();
        state.temperature = request.temperature;
        state.max_output_tokens = request.max_output_tokens;
        state.tools = request.tools.clone();
        state.metadata = chat_request_runtime_metadata(&request.metadata);
        chat_turn_apply_tool_results(state, tool_results).map_err(chat_error_to_anyhow)
    } else {
        chat_turn_initial_state(request).map_err(chat_error_to_anyhow)
    }
}

fn chat_request_runtime_metadata(metadata: &Value) -> Value {
    let mut metadata = metadata.clone();
    let Some(object) = metadata.as_object_mut() else {
        return json!({});
    };
    object.remove(CHAT_STATE_METADATA_KEY);
    object.remove(CHAT_TOOL_RESULTS_METADATA_KEY);
    object.remove(CHAT_STATUS_METADATA_KEY);
    object.remove(CHAT_TOOL_CALLS_METADATA_KEY);
    Value::Object(object.clone())
}

fn round_finished_metadata(
    state: &ChatTurnState,
    status: &str,
    tool_calls: Option<&[ChatToolCall]>,
    finish_reason: Option<LlmFinishReason>,
) -> Result<Value> {
    let mut metadata = Map::new();
    metadata.insert(
        CHAT_STATUS_METADATA_KEY.to_owned(),
        Value::String(status.to_owned()),
    );
    metadata.insert(
        CHAT_STATE_METADATA_KEY.to_owned(),
        sanitized_chat_state_value(state)?,
    );
    if let Some(tool_calls) = tool_calls {
        metadata.insert(
            CHAT_TOOL_CALLS_METADATA_KEY.to_owned(),
            serde_json::to_value(tool_calls)?,
        );
    }
    if let Some(finish_reason) = finish_reason {
        metadata.insert(
            "finish_reason".to_owned(),
            serde_json::to_value(finish_reason)?,
        );
    }
    Ok(Value::Object(metadata))
}

fn sanitized_chat_state_value(state: &ChatTurnState) -> Result<Value> {
    let mut state = state.clone();
    if let Some(object) = state.metadata.as_object_mut() {
        object.remove("api_key");
    }
    Ok(serde_json::to_value(state)?)
}

fn tool_call_from_event(event: &LlmEvent) -> Result<ChatToolCall> {
    let id = non_empty(event.tool_call_id.clone())
        .ok_or_else(|| anyhow::anyhow!("tool_call_end requires tool_call_id"))?;
    let name = non_empty(event.tool_name.clone())
        .ok_or_else(|| anyhow::anyhow!("tool_call_end requires tool_name"))?;
    Ok(ChatToolCall {
        id,
        name,
        input: event.tool_input.clone().unwrap_or_else(|| json!({})),
    })
}

fn chat_error_to_anyhow(error: ChatError) -> anyhow::Error {
    anyhow::anyhow!(error.record.message.clone())
}

fn chat_error_metadata(code: &str, error: &anyhow::Error) -> Value {
    json!({
        "code": code,
        "message": error.to_string(),
        "retryable": false,
        "details": {},
    })
}

fn chat_error_record_metadata(error: &ChatError) -> Value {
    json!({
        "code": error.record.code,
        "message": error.record.message,
        "retryable": error.record.retryable,
        "details": error.record.details,
    })
}

fn chat_turn_envelope_from_state(state: &ChatTurnState) -> ChatTurnEnvelope {
    ChatTurnEnvelope {
        turn_id: state.turn_id.clone(),
        session_id: state.session_id.clone(),
        thread_id: state.thread_id.clone(),
        surface: state.surface.clone(),
        agent_id: state.agent_id.clone(),
        mode: state.mode.clone(),
    }
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

pub(super) fn chat_turn_event_from_llm_event(
    envelope: &ChatTurnEnvelope,
    event: LlmEvent,
) -> Result<Value> {
    let mut value = serde_json::to_value(ChatTurnEvent {
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
        round: 1,
        metadata: event.metadata,
    })?;
    attach_chat_turn_envelope(envelope, &mut value);
    Ok(value)
}

fn chat_turn_started_event(envelope: &ChatTurnEnvelope, request: &LlmRequest) -> Result<Value> {
    let mut value = serde_json::to_value(ChatTurnEvent {
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
        metadata: json!({
            "provider": request.provider.clone(),
            "model": request.model.clone(),
        }),
    })?;
    attach_chat_turn_envelope(envelope, &mut value);
    Ok(value)
}

#[cfg(test)]
pub(super) fn chat_turn_finished_events(
    envelope: &ChatTurnEnvelope,
    event: LlmEvent,
) -> Result<Vec<Value>> {
    let Some(response) = event.response else {
        anyhow::bail!("LLM finished event response is required");
    };
    let mut values = Vec::new();
    if let Some(usage) = response.usage.clone() {
        let mut value = serde_json::to_value(ChatTurnEvent {
            kind: ChatTurnEventKind::Usage,
            content: None,
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            tool_output: None,
            usage: Some(usage),
            round: 1,
            metadata: json!({}),
        })?;
        attach_chat_turn_envelope(envelope, &mut value);
        values.push(value);
    }

    let finish_reason = response.finish_reason.clone();
    let usage = response.usage.clone();
    let mut round_finished = serde_json::to_value(ChatTurnEvent {
        kind: ChatTurnEventKind::RoundFinished,
        content: None,
        response: Some(response),
        tool_call_id: None,
        tool_name: None,
        partial_input_json: None,
        tool_input: None,
        tool_output: None,
        usage,
        round: 1,
        metadata: json!({"finish_reason": finish_reason.clone()}),
    })?;
    attach_chat_turn_envelope(envelope, &mut round_finished);
    values.push(round_finished);

    if !matches!(finish_reason, LlmFinishReason::ToolCall) {
        let mut done = serde_json::to_value(ChatTurnEvent {
            kind: ChatTurnEventKind::Done,
            content: None,
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            tool_output: None,
            usage: None,
            round: 1,
            metadata: json!({"stop_reason": chat_stop_reason(&finish_reason)}),
        })?;
        attach_chat_turn_envelope(envelope, &mut done);
        values.push(done);
    }
    Ok(values)
}

pub(super) fn chat_turn_error_event(envelope: &ChatTurnEnvelope, metadata: Value) -> Value {
    let mut value = json!({
        "kind": "error",
        "content": null,
        "round": 1,
        "metadata": metadata,
    });
    attach_chat_turn_envelope(envelope, &mut value);
    value
}

fn attach_chat_turn_envelope(envelope: &ChatTurnEnvelope, value: &mut Value) {
    let Some(object) = value.as_object_mut() else {
        return;
    };
    object.insert(
        "protocol_version".to_owned(),
        Value::String(protocol_version()),
    );
    if let Some(turn_id) = &envelope.turn_id {
        object.insert("turn_id".to_owned(), Value::String(turn_id.clone()));
    }
    if let Some(session_id) = &envelope.session_id {
        object.insert("session_id".to_owned(), Value::String(session_id.clone()));
    }
    if let Some(thread_id) = &envelope.thread_id {
        object.insert("thread_id".to_owned(), Value::String(thread_id.clone()));
    }
    if let Some(surface) = &envelope.surface {
        object.insert("surface".to_owned(), Value::String(surface.clone()));
    }
    if let Some(agent_id) = &envelope.agent_id {
        object.insert("agent_id".to_owned(), Value::String(agent_id.clone()));
    }
    if let Some(mode) = &envelope.mode {
        object.insert("mode".to_owned(), Value::String(mode.clone()));
    }
}

#[cfg(test)]
fn chat_stop_reason(reason: &LlmFinishReason) -> &'static str {
    match reason {
        LlmFinishReason::Stop => "end_turn",
        LlmFinishReason::Length => "max_tokens",
        LlmFinishReason::ToolCall => "tool_use",
        LlmFinishReason::ContentFilter => "content_filter",
        LlmFinishReason::Error => "error",
    }
}
