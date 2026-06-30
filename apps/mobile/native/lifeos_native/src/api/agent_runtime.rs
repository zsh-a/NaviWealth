//! Agent runtime bridge - FRB public surface for schema-first runtime contracts.
//!
//! Keep this module primitive-only for stable Dart bindings. The shared Rust
//! DTOs live in `agent-core`; Dart passes JSON strings across the bridge.

use agent_core::{
    AgentRuntimeCatalog, AgentSpec, AgentTrace, ProposalKindSpec, RunId, RunRequest, ScheduleSpec,
    ToolCallId, ToolSpec, catalog_version, protocol_version,
};
use agent_chat::{
    ChatError, ChatToolCall, ChatToolResult, ChatTurnAdvance, ChatTurnEvent, ChatTurnEventKind,
    ChatTurnRequest as AgentTurnRequest, ChatTurnState, chat_turn_apply_response,
    chat_turn_apply_tool_results, chat_turn_initial_state, chat_turn_llm_request,
    chat_turn_next_round,
};
use agent_llm::{
    AnthropicProvider, LlmEvent, LlmEventKind, LlmFinishReason, LlmProvider, LlmRequest,
    LlmResponse, MockLlmProvider, OpenAiCompatibleProvider,
};
use anyhow::Result;
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use std::collections::HashSet;

use crate::frb_generated::StreamSink;

const CHAT_STATE_METADATA_KEY: &str = "chat_state";
const CHAT_TOOL_RESULTS_METADATA_KEY: &str = "tool_results";
const CHAT_STATUS_METADATA_KEY: &str = "status";
const CHAT_TOOL_CALLS_METADATA_KEY: &str = "tool_calls";
const CHAT_STATUS_COMPLETED: &str = "completed";
const CHAT_STATUS_REQUIRES_TOOL_RESULTS: &str = "requires_tool_results";

#[derive(Debug, Serialize)]
struct CatalogSummary {
    protocol_version: String,
    catalog_version: String,
    generated_at: String,
    active_domains: Vec<String>,
    agent_count: usize,
    tool_count: usize,
    proposal_kind_count: usize,
    prompt_block_count: usize,
}

#[derive(Debug, Clone)]
struct AgentTurnEnvelope {
    turn_id: Option<String>,
    session_id: Option<String>,
    thread_id: Option<String>,
    surface: Option<String>,
    agent_id: Option<String>,
    mode: Option<String>,
}

fn agent_turn_to_llm_request(request: &AgentTurnRequest) -> LlmRequest {
    let mut metadata = request.metadata.clone();
    if metadata.is_null() {
        metadata = json!({});
    }
    if let Some(object) = metadata.as_object_mut() {
        object.insert("agent_turn".to_owned(), Value::Bool(true));
        object.insert("chat_turn".to_owned(), Value::Bool(true));
        if let Some(turn_id) = &request.turn_id {
            object.insert("turn_id".to_owned(), Value::String(turn_id.clone()));
        }
        if let Some(surface) = &request.surface {
            object.insert("surface".to_owned(), Value::String(surface.clone()));
        }
        if let Some(agent_id) = &request.agent_id {
            object.insert("agent_id".to_owned(), Value::String(agent_id.clone()));
        }
        if let Some(mode) = &request.mode {
            object.insert("mode".to_owned(), Value::String(mode.clone()));
        }
        if let Some(session_id) = &request.session_id {
            object.insert("session_id".to_owned(), Value::String(session_id.clone()));
        }
        if let Some(thread_id) = &request.thread_id {
            object.insert("thread_id".to_owned(), Value::String(thread_id.clone()));
        }
    }
    LlmRequest {
        protocol_version: request.protocol_version.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        messages: request.messages.clone(),
        temperature: request.temperature,
        max_output_tokens: request.max_output_tokens,
        tools: request.tools.clone(),
        metadata,
    }
}

pub fn agent_runtime_protocol_version() -> String {
    protocol_version()
}

pub fn agent_runtime_catalog_version() -> String {
    catalog_version()
}

pub fn agent_runtime_catalog_summary(catalog_json: String) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
    require_catalog_contract(&catalog)?;
    let summary = CatalogSummary {
        protocol_version: catalog.protocol_version,
        catalog_version: catalog.catalog_version,
        generated_at: catalog.generated_at.to_string(),
        active_domains: catalog.active_domains,
        agent_count: catalog.agents.len(),
        tool_count: catalog.tools.len(),
        proposal_kind_count: catalog.proposal_kinds.len(),
        prompt_block_count: catalog.prompt_blocks.len(),
    };

    Ok(serde_json::to_string(&summary)?)
}

pub fn agent_runtime_validate_run_request(request_json: String) -> Result<String> {
    let mut request: RunRequest = serde_json::from_str(&request_json)?;
    normalize_run_request_contract(&mut request)?;
    Ok(serde_json::to_string(&request)?)
}

pub fn agent_runtime_validate_trace(trace_json: String) -> Result<String> {
    let trace: AgentTrace = serde_json::from_str(&trace_json)?;
    validate_agent_runtime_step_trace_events(&trace)?;
    Ok(serde_json::to_string(&trace)?)
}

pub fn agent_runtime_validate_tool_spec(tool_json: String) -> Result<String> {
    let tool: ToolSpec = serde_json::from_str(&tool_json)?;
    require_tool_spec_contract(&tool, "tool")?;
    Ok(serde_json::to_string(&tool)?)
}

pub fn agent_runtime_validate_llm_request(request_json: String) -> Result<String> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    normalize_llm_request_contract(&mut request)?;
    Ok(serde_json::to_string(&request)?)
}

pub fn agent_runtime_validate_llm_response(response_json: String) -> Result<String> {
    let mut response: LlmResponse = serde_json::from_str(&response_json)?;
    normalize_llm_response_contract(&mut response)?;
    Ok(serde_json::to_string(&response)?)
}

pub fn agent_runtime_validate_agent_turn_request(request_json: String) -> Result<String> {
    let mut request: AgentTurnRequest = serde_json::from_str(&request_json)?;
    normalize_agent_turn_request_contract(&mut request)?;
    Ok(serde_json::to_string(&request)?)
}

pub async fn agent_runtime_complete_mock_llm(
    request_json: String,
    response_text: String,
) -> Result<String> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    normalize_llm_request_contract(&mut request)?;
    let provider = MockLlmProvider::new("mock", request.model.clone(), response_text);
    let mut response = provider
        .complete(request)
        .await
        .map_err(|e| anyhow::anyhow!(e.record.message.clone()))?;
    normalize_llm_response_contract(&mut response)?;
    Ok(serde_json::to_string(&response)?)
}

pub async fn agent_runtime_complete_profile_llm(request_json: String) -> Result<String> {
    let request: LlmRequest = serde_json::from_str(&request_json)?;
    let response = complete_profile_llm_response(request).await?;
    Ok(serde_json::to_string(&response)?)
}

pub async fn agent_runtime_stream_mock_llm(
    sink: StreamSink<String>,
    request_json: String,
    response_text: String,
) -> Result<()> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    normalize_llm_request_contract(&mut request)?;
    let provider = MockLlmProvider::new("mock", request.model.clone(), response_text);
    stream_llm_response(sink, Box::new(provider), request).await
}

pub async fn agent_runtime_stream_profile_llm(
    sink: StreamSink<String>,
    request_json: String,
) -> Result<()> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    normalize_llm_request_contract(&mut request)?;
    let provider = profile_llm_provider(&request)?;
    stream_llm_response(sink, provider, request).await
}

pub async fn agent_runtime_stream_agent_turn(
    sink: StreamSink<String>,
    request_json: String,
) -> Result<()> {
    let mut request: AgentTurnRequest = serde_json::from_str(&request_json)?;
    normalize_agent_turn_request_contract(&mut request)?;
    let state = chat_turn_state_from_request(&request)?;
    let llm_request = chat_turn_llm_request(&state);
    let provider = profile_llm_provider(&llm_request)?;
    stream_agent_turn_response(sink, provider, state).await
}

pub async fn agent_runtime_start_profile_turn_step(
    catalog_json: String,
    llm_request_json: String,
    agent_id: String,
    run_metadata_json: String,
) -> Result<String> {
    let llm_request: LlmRequest = serde_json::from_str(&llm_request_json)?;
    let llm_response = complete_profile_llm_response(llm_request).await?;
    let mut metadata = profile_turn_run_metadata(&run_metadata_json)?;
    if let Some(object) = metadata.as_object_mut() {
        object.insert(
            "llm_response".to_owned(),
            serde_json::to_value(&llm_response)?,
        );
    } else {
        anyhow::bail!("run metadata must be a JSON object");
    }
    let request = RunRequest {
        protocol_version: protocol_version(),
        run_id: None,
        input: runtime_input_from_llm_response(&llm_response)?,
        user: None,
        trigger: agent_core::TriggerKind::Manual,
        metadata,
    };
    let step_json =
        agent_runtime_start_run_step(catalog_json, serde_json::to_string(&request)?, agent_id)?;
    let step: Value = serde_json::from_str(&step_json)?;
    let output = json!({
        "protocol_version": protocol_version(),
        "llm_response": llm_response,
        "step": step,
    });
    Ok(serde_json::to_string(&output)?)
}

fn profile_turn_run_metadata(run_metadata_json: &str) -> Result<Value> {
    if run_metadata_json.trim().is_empty() {
        return Ok(json!({}));
    }
    let metadata = serde_json::from_str::<Value>(run_metadata_json)?;
    if metadata.is_null() {
        return Ok(json!({}));
    }
    if !metadata.is_object() {
        anyhow::bail!("run metadata must be a JSON object");
    }
    Ok(metadata)
}

async fn complete_profile_llm_response(mut request: LlmRequest) -> Result<LlmResponse> {
    normalize_llm_request_contract(&mut request)?;
    let mut response = profile_llm_provider(&request)?
        .complete(request)
        .await
        .map_err(llm_error_to_anyhow)?;
    normalize_llm_response_contract(&mut response)?;
    Ok(response)
}

async fn stream_llm_response(
    sink: StreamSink<String>,
    provider: Box<dyn LlmProvider>,
    request: LlmRequest,
) -> Result<()> {
    let mut stream = provider
        .stream(request)
        .await
        .map_err(llm_error_to_anyhow)?;
    while let Some(event) = stream.next().await {
        match event {
            Ok(mut event) => {
                normalize_llm_event_contract(&mut event)?;
                let _ = sink.add(serde_json::to_string(&event)?);
            }
            Err(error) => {
                let record = error.record;
                let _ = sink.add(serde_json::to_string(&json!({
                    "kind": "error",
                    "content": null,
                    "metadata": {
                        "code": record.code,
                        "message": record.message,
                        "retryable": record.retryable,
                        "details": record.details,
                    }
                }))?);
                break;
            }
        }
    }
    Ok(())
}

async fn stream_agent_turn_response(
    sink: StreamSink<String>,
    provider: Box<dyn LlmProvider>,
    state: ChatTurnState,
) -> Result<()> {
    let envelope = agent_turn_envelope_from_state(&state);
    let round = chat_turn_next_round(&state);
    let request = chat_turn_llm_request(&state);
    let started = agent_turn_started_event(&envelope, &request)?;
    let _ = sink.add(serde_json::to_string(&started)?);
    let mut stream = provider
        .stream(request)
        .await
        .map_err(llm_error_to_anyhow)?;
    let mut saw_terminal_error = false;
    let mut assistant_text = String::new();
    let mut tool_calls = Vec::new();
    let mut response = None;
    while let Some(event) = stream.next().await {
        match event {
            Ok(mut event) => {
                normalize_llm_event_contract(&mut event)?;
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
                            let value = agent_turn_error_event(
                                &envelope,
                                chat_error_metadata("llm_stream_event_invalid", &error),
                            );
                            let _ = sink.add(serde_json::to_string(&value)?);
                            break;
                        }
                    }
                }
                let value = agent_turn_event_from_llm_event(&envelope, event)?;
                let _ = sink.add(serde_json::to_string(&value)?);
            }
            Err(error) => {
                saw_terminal_error = true;
                let record = error.record;
                let value = agent_turn_error_event(
                    &envelope,
                    json!({
                        "code": record.code,
                        "message": record.message,
                        "retryable": record.retryable,
                        "details": record.details,
                    }),
                );
                let _ = sink.add(serde_json::to_string(&value)?);
                break;
            }
        }
    }
    if saw_terminal_error {
        return Ok(());
    }
    let Some(response) = response else {
        let value = agent_turn_error_event(
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
        attach_agent_turn_envelope(&envelope, &mut usage_event);
        let _ = sink.add(serde_json::to_string(&usage_event)?);
    }

    let finish_reason = response.finish_reason.clone();
    let usage = response.usage.clone();
    match chat_turn_apply_response(state, &assistant_text, tool_calls, &response) {
        Ok(ChatTurnAdvance::Completed { state, stop_reason }) => {
            let metadata = round_finished_metadata(
                &state,
                CHAT_STATUS_COMPLETED,
                None,
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
            attach_agent_turn_envelope(&envelope, &mut round_finished);
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
            attach_agent_turn_envelope(&envelope, &mut done);
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
            attach_agent_turn_envelope(&envelope, &mut round_finished);
            let _ = sink.add(serde_json::to_string(&round_finished)?);
        }
        Err(error) => {
            let value = agent_turn_error_event(&envelope, chat_error_record_metadata(&error));
            let _ = sink.add(serde_json::to_string(&value)?);
        }
    }
    Ok(())
}

fn chat_turn_state_from_request(request: &AgentTurnRequest) -> Result<ChatTurnState> {
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
        metadata.insert("finish_reason".to_owned(), serde_json::to_value(finish_reason)?);
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

fn agent_turn_envelope_from_state(state: &ChatTurnState) -> AgentTurnEnvelope {
    AgentTurnEnvelope {
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

fn profile_llm_provider(request: &LlmRequest) -> Result<Box<dyn LlmProvider>> {
    match request.provider.as_str() {
        "mock" => Ok(Box::new(MockLlmProvider::new(
            "mock",
            request.model.clone(),
            "mock response",
        ))),
        "openai" | "openai-compatible" => {
            let api_key = llm_metadata_string(request, "api_key")?;
            let base_url = llm_metadata_string(request, "base_url")
                .map(normalize_openai_base_url)
                .unwrap_or_else(|_| "https://api.openai.com/v1".to_owned());
            let provider =
                OpenAiCompatibleProvider::new(request.provider.clone(), base_url, api_key)
                    .map_err(llm_error_to_anyhow)?;
            Ok(Box::new(provider))
        }
        "anthropic" => {
            let api_key = llm_metadata_string(request, "api_key")?;
            let base_url = llm_metadata_string(request, "base_url")
                .unwrap_or_else(|_| "https://api.anthropic.com/v1".to_owned());
            let version = llm_metadata_string(request, "anthropic_version")
                .unwrap_or_else(|_| "2023-06-01".to_owned());
            let provider =
                AnthropicProvider::new(request.provider.clone(), base_url, api_key, version)
                    .map_err(llm_error_to_anyhow)?;
            Ok(Box::new(provider))
        }
        other => anyhow::bail!("unsupported LLM provider '{other}'"),
    }
}

pub fn agent_runtime_start_run_step(
    catalog_json: String,
    request_json: String,
    agent_id: String,
) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
    require_catalog_contract(&catalog)?;
    let mut request: RunRequest = serde_json::from_str(&request_json)?;
    normalize_run_request_contract(&mut request)?;
    let agent = catalog
        .agents
        .iter()
        .find(|agent| agent.id == agent_id)
        .ok_or_else(|| anyhow::anyhow!("agent '{agent_id}' is not present in the catalog"))?;
    let run_id = request.run_id.clone().unwrap_or_else(RunId::new_v7);

    let mut response = match parse_initial_tool_request(&request.input)? {
        Some(tool_request) => {
            let continuation = tool_request.continuation();
            build_tool_call_requested_step(
                &catalog,
                &agent.id,
                &agent.version,
                serde_json::to_value(&run_id)?,
                tool_request.first,
                continuation,
            )?
        }
        None => {
            json!({
                "protocol_version": protocol_version(),
                "run_id": run_id,
                "agent_id": agent.id,
                "agent_version": agent.version,
                "step_index": 0,
                "status": "completed",
                "output": request.input,
            })
        }
    };
    attach_runtime_metadata(&mut response);
    Ok(serde_json::to_string(&response)?)
}

pub fn agent_runtime_continue_run_step(
    catalog_json: String,
    previous_step_json: String,
    tool_response_json: String,
    agent_id: String,
) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
    require_catalog_contract(&catalog)?;
    let previous_step: Value = serde_json::from_str(&previous_step_json)?;
    let tool_response: Value = serde_json::from_str(&tool_response_json)?;
    let agent = catalog
        .agents
        .iter()
        .find(|agent| agent.id == agent_id)
        .ok_or_else(|| anyhow::anyhow!("agent '{agent_id}' is not present in the catalog"))?;
    if previous_step.get("status").and_then(Value::as_str) != Some("tool_call_requested") {
        anyhow::bail!("previous step status must be 'tool_call_requested'");
    }
    require_previous_step_protocol_version(&previous_step)?;
    require_previous_step_agent(&previous_step, &agent.id, &agent.version)?;
    let run_id = require_previous_step_run_id(&previous_step)?;
    let previous_step_index = require_previous_step_index(&previous_step)?;
    let tool_call = previous_step
        .get("tool_call")
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("previous step is missing tool_call"))?;
    require_previous_tool_call_id(&tool_call)?;
    require_previous_tool_call_catalog_tool(&catalog, &agent.id, &tool_call)?;
    require_previous_step_runtime_metadata(&previous_step, &run_id, previous_step_index)?;
    require_tool_response_envelope(&tool_response)?;
    require_matching_tool_response_id(&tool_call, &tool_response)?;
    require_continuation_next_step_index(&previous_step, previous_step_index)?;
    let mut tool_results = continuation_tool_results(&previous_step, &catalog, &agent.id)?;
    let tool_terminal_status = tool_response_terminal_status(&tool_response);
    if tool_terminal_status != Some("closed_early") {
        tool_results.push(json!({
            "tool_call": tool_call.clone(),
            "tool_response": tool_response.clone(),
        }));
    }

    let next_step_index = previous_step_index + 1;

    let mut response = match tool_terminal_status {
        Some(status) => {
            let error = tool_response_error_payload(&tool_response).unwrap_or(Value::Null);
            json!({
            "protocol_version": protocol_version(),
            "run_id": run_id,
            "agent_id": agent.id,
            "agent_version": agent.version,
            "step_index": next_step_index,
            "status": status,
            "tool_call": tool_call,
            "tool_response": tool_response,
            "tool_results": tool_results,
            "error": error,
            })
        }
        None => match next_tool_request_from_continuation(&previous_step, tool_results.clone())? {
            Some(next) => {
                let continuation = next.continuation();
                build_tool_call_requested_step(
                    &catalog,
                    &agent.id,
                    &agent.version,
                    run_id,
                    next.first,
                    continuation,
                )?
            }
            None => json!({
                "protocol_version": protocol_version(),
                "run_id": run_id,
                "agent_id": agent.id,
                "agent_version": agent.version,
                "step_index": next_step_index,
                "status": "completed",
                "output": {
                    "mode": if tool_results.len() > 1 {
                        "frb_tool_loop"
                    } else {
                        "frb_tool_step"
                    },
                    "tool_call": tool_call,
                    "tool_result": tool_response.get("result").cloned().unwrap_or(Value::Null),
                    "tool_response": tool_response,
                    "tool_results": tool_results,
                }
            }),
        },
    };
    attach_runtime_metadata(&mut response);
    Ok(serde_json::to_string(&response)?)
}

fn require_previous_step_agent(
    previous_step: &Value,
    agent_id: &str,
    agent_version: &str,
) -> Result<()> {
    let previous_agent_id = previous_step
        .get("agent_id")
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow::anyhow!("previous step is missing agent_id"))?;
    if previous_agent_id != agent_id {
        anyhow::bail!(
            "previous step agent_id '{previous_agent_id}' does not match requested agent '{agent_id}'"
        );
    }
    let previous_agent_version = previous_step
        .get("agent_version")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("previous step agent_version must be a non-empty string"))?;
    if previous_agent_version != agent_version {
        anyhow::bail!(
            "previous step agent_version '{previous_agent_version}' does not match catalog agent version '{agent_version}'"
        );
    }
    Ok(())
}

fn require_previous_step_protocol_version(previous_step: &Value) -> Result<()> {
    let previous_protocol_version = previous_step
        .get("protocol_version")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            anyhow::anyhow!("previous step protocol_version must be a non-empty string")
        })?;
    let expected = protocol_version();
    if previous_protocol_version != expected {
        anyhow::bail!(
            "previous step protocol_version '{previous_protocol_version}' does not match runtime protocol_version '{expected}'"
        );
    }
    Ok(())
}

fn require_previous_step_run_id(previous_step: &Value) -> Result<Value> {
    let run_id = previous_step
        .get("run_id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("previous step run_id must be a non-empty string"))?;
    Ok(Value::String(run_id.to_owned()))
}

fn require_previous_step_index(previous_step: &Value) -> Result<u64> {
    previous_step
        .get("step_index")
        .and_then(Value::as_u64)
        .ok_or_else(|| anyhow::anyhow!("previous step_index must be a non-negative integer"))
}

fn require_previous_tool_call_catalog_tool(
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
    tool_call: &Value,
) -> Result<()> {
    let name = tool_call
        .get("name")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("previous step tool_call.name is required"))?;
    if catalog.tools.iter().any(|tool| tool.name == name) {
        require_tool_call_input_object(tool_call, "previous step tool_call")?;
        return Ok(());
    }
    anyhow::bail!("tool '{name}' requested by agent '{agent_id}' is not present in the catalog");
}

fn require_previous_tool_call_id(tool_call: &Value) -> Result<()> {
    tool_call
        .get("tool_call_id")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            anyhow::anyhow!("previous step tool_call.tool_call_id must be a non-empty string")
        })?;
    Ok(())
}

fn require_previous_step_runtime_metadata(
    previous_step: &Value,
    run_id: &Value,
    step_index: u64,
) -> Result<()> {
    if let Some(run_state) = previous_step.get("run_state") {
        require_previous_step_run_state(previous_step, run_state, step_index)
            .map_err(|error| anyhow::anyhow!("previous step run_state: {error}"))?;
    }
    if let Some(trace_event) = previous_step.get("trace_event") {
        require_previous_step_trace_event(previous_step, trace_event, run_id, step_index)
            .map_err(|error| anyhow::anyhow!("previous step trace_event: {error}"))?;
    }
    Ok(())
}

fn require_previous_step_run_state(
    previous_step: &Value,
    run_state: &Value,
    step_index: u64,
) -> Result<()> {
    let run_state = run_state
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("previous step run_state must be an object"))?;
    require_step_status(run_state, "status")?;
    require_matching_string(
        run_state,
        "status",
        previous_step
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )?;
    match run_state.get("step_index").and_then(Value::as_u64) {
        Some(value) if value == step_index => {}
        _ => anyhow::bail!("previous step run_state.step_index must match step_index"),
    }
    let expected_remaining_tool_count = previous_step
        .get("continuation")
        .and_then(|value| value.get("tool_plan"))
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0) as u64;
    match run_state
        .get("remaining_tool_count")
        .and_then(Value::as_u64)
    {
        Some(value) if value == expected_remaining_tool_count => {}
        _ => anyhow::bail!(
            "previous step run_state.remaining_tool_count must match continuation.tool_plan"
        ),
    }
    let expected_tool_result_count = previous_step
        .get("continuation")
        .and_then(|value| value.get("tool_results"))
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0) as u64;
    match run_state.get("tool_result_count").and_then(Value::as_u64) {
        Some(value) if value == expected_tool_result_count => {}
        _ => anyhow::bail!(
            "previous step run_state.tool_result_count must match continuation.tool_results"
        ),
    }
    require_terminal_reason(run_state, "terminal_reason")?;
    require_terminal_reason_matches_status(run_state)?;
    Ok(())
}

fn require_previous_step_trace_event(
    previous_step: &Value,
    trace_event: &Value,
    run_id: &Value,
    step_index: u64,
) -> Result<()> {
    let trace_event = trace_event
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("previous step trace_event must be an object"))?;
    require_matching_string(trace_event, "kind", "agent_runtime_step")?;
    require_matching_string(trace_event, "run_id", run_id.as_str().unwrap_or_default())?;
    require_matching_string(
        trace_event,
        "agent_id",
        previous_step
            .get("agent_id")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )?;
    require_matching_string(
        trace_event,
        "status",
        previous_step
            .get("status")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    )?;
    match trace_event.get("step_index").and_then(Value::as_u64) {
        Some(value) if value == step_index => {}
        _ => anyhow::bail!("previous step trace_event.step_index must match step_index"),
    }
    if let Some(run_state) = previous_step.get("run_state") {
        match trace_event.get("run_state") {
            Some(value) if value == run_state => {}
            _ => anyhow::bail!("previous step trace_event.run_state must match run_state"),
        }
    }
    let expected_tool_name = previous_step
        .get("tool_call")
        .and_then(|tool_call| tool_call.get("name"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    require_matching_nullable_string(trace_event, "tool_name", expected_tool_name)?;
    Ok(())
}

fn require_matching_tool_response_id(tool_call: &Value, tool_response: &Value) -> Result<()> {
    let Some(expected_id) = tool_call.get("tool_call_id").and_then(Value::as_str) else {
        return Ok(());
    };
    let Some(response_id) = tool_response.get("id") else {
        return Ok(());
    };
    match response_id.as_str() {
        Some(value) if value == expected_id => Ok(()),
        Some(value) => anyhow::bail!(
            "tool response id '{value}' does not match requested tool_call_id '{expected_id}'"
        ),
        None => anyhow::bail!("tool response id must be a string when present"),
    }
}

fn require_tool_response_envelope(tool_response: &Value) -> Result<()> {
    let Some(object) = tool_response.as_object() else {
        anyhow::bail!("tool response must be an object");
    };
    if let Some(jsonrpc) = object.get("jsonrpc") {
        match jsonrpc.as_str() {
            Some("2.0") => {}
            Some(_) => anyhow::bail!("tool response jsonrpc must be '2.0'"),
            None => anyhow::bail!("tool response jsonrpc must be a string"),
        }
        if !object.contains_key("id") {
            anyhow::bail!("tool response id is required when jsonrpc is present");
        }
        match (object.contains_key("result"), object.contains_key("error")) {
            (true, false) | (false, true) => {}
            (true, true) => anyhow::bail!("tool response cannot contain both result and error"),
            (false, false) => anyhow::bail!("tool response must contain result or error"),
        }
        if let Some(error) = object.get("error") {
            let error = error
                .as_object()
                .ok_or_else(|| anyhow::anyhow!("tool response error must be an object"))?;
            if error.get("code").and_then(Value::as_i64).is_none() {
                anyhow::bail!("tool response error.code must be an integer");
            }
            if error.get("message").and_then(Value::as_str).is_none() {
                anyhow::bail!("tool response error.message must be a string");
            }
        }
    }
    if !object.contains_key("jsonrpc")
        && object.contains_key("result")
        && object.contains_key("error")
    {
        anyhow::bail!("tool response cannot contain both result and error");
    }
    Ok(())
}

fn require_continuation_next_step_index(
    previous_step: &Value,
    previous_step_index: u64,
) -> Result<()> {
    let Some(continuation) = previous_step_continuation(previous_step)? else {
        return Ok(());
    };
    let next_step_index = continuation.get("next_step_index").ok_or_else(|| {
        anyhow::anyhow!("continuation.next_step_index must be present when continuation is present")
    })?;
    let next_step_index = next_step_index.as_u64().ok_or_else(|| {
        anyhow::anyhow!("continuation.next_step_index must be a non-negative integer")
    })?;
    let expected = previous_step_index + 1;
    if next_step_index != expected {
        anyhow::bail!(
            "continuation.next_step_index {next_step_index} must equal previous step_index + 1 ({expected})"
        );
    }
    Ok(())
}

fn previous_step_continuation(previous_step: &Value) -> Result<Option<&Map<String, Value>>> {
    let Some(continuation) = previous_step.get("continuation") else {
        return Ok(None);
    };
    let continuation = continuation
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("continuation must be an object"))?;
    Ok(Some(continuation))
}

fn tool_response_terminal_status(tool_response: &Value) -> Option<&'static str> {
    let code = tool_response_error_code(tool_response);
    match code.as_deref() {
        Some("tool_call_budget_exhausted") => Some("closed_early"),
        Some("policy_denied") => Some("policy_denied"),
        Some("user_cancel" | "user_cancelled" | "cancelled") => Some("cancelled"),
        Some("tool_timeout" | "timeout" | "timed_out") => Some("timed_out"),
        Some(_) => Some("failed"),
        None if tool_response_error_payload(tool_response).is_some() => Some("failed"),
        None => None,
    }
}

fn tool_response_error_code(tool_response: &Value) -> Option<String> {
    tool_response
        .get("error")
        .and_then(|error| error.get("code"))
        .and_then(Value::as_str)
        .or_else(|| tool_response.get("code").and_then(Value::as_str))
        .or_else(|| {
            tool_response
                .get("result")
                .and_then(|result| result.get("error"))
                .and_then(|error| error.get("code"))
                .and_then(Value::as_str)
        })
        .or_else(|| {
            tool_response
                .get("result")
                .and_then(|result| result.get("code"))
                .and_then(Value::as_str)
        })
        .map(str::to_owned)
}

fn tool_response_error_payload(tool_response: &Value) -> Option<Value> {
    if let Some(error) = tool_response.get("error") {
        return Some(error.clone());
    }
    let result = tool_response.get("result")?;
    if let Some(error) = result.get("error") {
        if error.is_object() {
            return Some(error.clone());
        }
        let mut object = Map::new();
        if let Some(code) = result.get("code").and_then(Value::as_str) {
            object.insert("code".to_owned(), Value::String(code.to_owned()));
        }
        object.insert("message".to_owned(), error.clone());
        return Some(Value::Object(object));
    }
    if let Some(code) = result.get("code").and_then(Value::as_str) {
        return Some(json!({ "code": code }));
    }
    None
}

fn llm_metadata_string(request: &LlmRequest, key: &str) -> Result<String> {
    let value = request
        .metadata
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_owned();
    if value.is_empty() {
        anyhow::bail!("LLM request metadata.{key} is required");
    }
    Ok(value)
}

fn normalize_openai_base_url(base_url: String) -> String {
    let base = base_url.trim().trim_end_matches('/').to_owned();
    if let Some(prefix) = base.strip_suffix("/v1/chat/completions") {
        return prefix.to_owned() + "/v1";
    }
    if let Some(prefix) = base.strip_suffix("/chat/completions") {
        return prefix.to_owned();
    }
    if base.ends_with("/v1") {
        base
    } else {
        base + "/v1"
    }
}

fn llm_error_to_anyhow(error: agent_llm::LlmError) -> anyhow::Error {
    anyhow::anyhow!(error.record.message.clone())
}

fn normalize_json<T>(json: &str) -> Result<String>
where
    T: serde::de::DeserializeOwned + Serialize,
{
    let value: T = serde_json::from_str(json)?;
    Ok(serde_json::to_string(&value)?)
}

fn normalize_run_request_contract(request: &mut RunRequest) -> Result<()> {
    let expected = protocol_version();
    if request.protocol_version != expected {
        anyhow::bail!(
            "run request protocol_version '{}' does not match runtime protocol_version '{expected}'",
            request.protocol_version
        );
    }
    if request.input.is_null() {
        request.input = json!({});
    } else if !request.input.is_object() {
        anyhow::bail!("run request input must be a JSON object");
    }
    if request.metadata.is_null() {
        request.metadata = json!({});
    } else if !request.metadata.is_object() {
        anyhow::bail!("run request metadata must be a JSON object");
    }
    if let Some(user) = &mut request.user {
        if user.user_id.trim().is_empty() {
            anyhow::bail!("run request user.user_id must be a non-empty string");
        }
        if user.metadata.is_null() {
            user.metadata = json!({});
        } else if !user.metadata.is_object() {
            anyhow::bail!("run request user.metadata must be a JSON object");
        }
    }
    Ok(())
}

fn require_catalog_contract(catalog: &AgentRuntimeCatalog) -> Result<()> {
    let expected_protocol = protocol_version();
    if catalog.protocol_version != expected_protocol {
        anyhow::bail!(
            "catalog protocol_version '{}' does not match runtime protocol_version '{expected_protocol}'",
            catalog.protocol_version
        );
    }
    let expected_catalog = catalog_version();
    if catalog.catalog_version != expected_catalog {
        anyhow::bail!(
            "catalog catalog_version '{}' does not match runtime catalog_version '{expected_catalog}'",
            catalog.catalog_version
        );
    }
    for (index, active_domain) in catalog.active_domains.iter().enumerate() {
        if active_domain.trim().is_empty() {
            anyhow::bail!("catalog.active_domains[{index}] must be a non-empty string");
        }
    }
    let mut agent_ids = HashSet::new();
    let mut tool_names = HashSet::new();
    let mut proposal_kinds = HashSet::new();
    let mut prompt_block_indexes = HashSet::new();
    for (index, tool) in catalog.tools.iter().enumerate() {
        require_tool_spec_contract(tool, &format!("catalog.tools[{index}]"))?;
        if !tool_names.insert(tool.name.as_str()) {
            anyhow::bail!("catalog.tools[{index}].name '{}' is duplicated", tool.name);
        }
    }
    for (index, agent) in catalog.agents.iter().enumerate() {
        require_agent_spec_contract(agent, &format!("catalog.agents[{index}]"))?;
        if !agent_ids.insert(agent.id.as_str()) {
            anyhow::bail!("catalog.agents[{index}].id '{}' is duplicated", agent.id);
        }
    }
    for (index, proposal_kind) in catalog.proposal_kinds.iter().enumerate() {
        require_proposal_kind_contract(proposal_kind, &format!("catalog.proposal_kinds[{index}]"))?;
        if !tool_names.contains(proposal_kind.tool_name.as_str()) {
            anyhow::bail!(
                "catalog.proposal_kinds[{index}].tool_name '{}' does not match any catalog tool",
                proposal_kind.tool_name
            );
        }
        if !proposal_kinds.insert(proposal_kind.kind.as_str()) {
            anyhow::bail!(
                "catalog.proposal_kinds[{index}].kind '{}' is duplicated",
                proposal_kind.kind
            );
        }
    }
    for (index, prompt_block) in catalog.prompt_blocks.iter().enumerate() {
        if !prompt_block_indexes.insert(prompt_block.index) {
            anyhow::bail!(
                "catalog.prompt_blocks[{index}].index {} is duplicated",
                prompt_block.index
            );
        }
    }
    Ok(())
}

fn normalize_llm_request_contract(request: &mut LlmRequest) -> Result<()> {
    let expected = protocol_version();
    if request.protocol_version != expected {
        anyhow::bail!(
            "LLM request protocol_version '{}' does not match runtime protocol_version '{expected}'",
            request.protocol_version
        );
    }
    if request.provider.trim().is_empty() {
        anyhow::bail!("LLM request provider must be a non-empty string");
    }
    if request.model.trim().is_empty() {
        anyhow::bail!("LLM request model must be a non-empty string");
    }
    if request.messages.is_empty() {
        anyhow::bail!("LLM request messages must contain at least one message");
    }
    if matches!(request.temperature, Some(value) if value < 0.0) {
        anyhow::bail!("LLM request temperature must be greater than or equal to zero");
    }
    if matches!(request.max_output_tokens, Some(0)) {
        anyhow::bail!("LLM request max_output_tokens must be greater than zero");
    }
    for (index, message) in request.messages.iter_mut().enumerate() {
        if message.metadata.is_null() {
            message.metadata = json!({});
        } else if !message.metadata.is_object() {
            anyhow::bail!("LLM request messages[{index}].metadata must be a JSON object");
        }
    }
    if request.metadata.is_null() {
        request.metadata = json!({});
    } else if !request.metadata.is_object() {
        anyhow::bail!("LLM request metadata must be a JSON object");
    }
    for (index, tool) in request.tools.iter().enumerate() {
        require_tool_spec_contract(tool, &format!("LLM request tools[{index}]"))?;
    }
    Ok(())
}

fn normalize_agent_turn_request_contract(request: &mut AgentTurnRequest) -> Result<()> {
    require_optional_non_empty(&request.turn_id, "Agent turn turn_id")?;
    require_optional_non_empty(&request.surface, "Agent turn surface")?;
    require_optional_non_empty(&request.session_id, "Agent turn session_id")?;
    require_optional_non_empty(&request.thread_id, "Agent turn thread_id")?;
    require_optional_non_empty(&request.agent_id, "Agent turn agent_id")?;
    require_optional_non_empty(&request.mode, "Agent turn mode")?;
    let mut llm_request = agent_turn_to_llm_request(request);
    normalize_llm_request_contract(&mut llm_request)?;
    request.protocol_version = llm_request.protocol_version;
    request.provider = llm_request.provider;
    request.model = llm_request.model;
    request.messages = llm_request.messages;
    request.temperature = llm_request.temperature;
    request.max_output_tokens = llm_request.max_output_tokens;
    request.tools = llm_request.tools;
    request.metadata = llm_request.metadata;
    Ok(())
}

fn require_optional_non_empty(value: &Option<String>, label: &str) -> Result<()> {
    if matches!(value.as_deref(), Some(value) if value.trim().is_empty()) {
        anyhow::bail!("{label} must be a non-empty string when present");
    }
    Ok(())
}

fn normalize_llm_response_contract(response: &mut LlmResponse) -> Result<()> {
    let expected = protocol_version();
    if response.protocol_version != expected {
        anyhow::bail!(
            "LLM response protocol_version '{}' does not match runtime protocol_version '{expected}'",
            response.protocol_version
        );
    }
    if response.provider.trim().is_empty() {
        anyhow::bail!("LLM response provider must be a non-empty string");
    }
    if response.model.trim().is_empty() {
        anyhow::bail!("LLM response model must be a non-empty string");
    }
    if response.metadata.is_null() {
        response.metadata = json!({});
    } else if !response.metadata.is_object() {
        anyhow::bail!("LLM response metadata must be a JSON object");
    }
    normalize_llm_response_tool_metadata(&mut response.metadata)?;
    if let Some(usage) = &response.usage {
        let expected_total = usage
            .input_tokens
            .checked_add(usage.output_tokens)
            .ok_or_else(|| anyhow::anyhow!("LLM response usage total_tokens overflowed"))?;
        if usage.total_tokens != expected_total {
            anyhow::bail!(
                "LLM response usage.total_tokens must equal input_tokens + output_tokens"
            );
        }
    }
    Ok(())
}

fn normalize_llm_response_tool_metadata(metadata: &mut Value) -> Result<()> {
    let object = metadata
        .as_object_mut()
        .ok_or_else(|| anyhow::anyhow!("LLM response metadata must be a JSON object"))?;
    for key in ["tool_plan", "tool_calls"] {
        if let Some(tool_plan) = object.get_mut(key) {
            let plan = tool_plan
                .as_array()
                .ok_or_else(|| anyhow::anyhow!("LLM response metadata.{key} must be an array"))?;
            let normalized = plan
                .iter()
                .enumerate()
                .map(|(index, value)| {
                    let requested = parse_requested_tool_call(
                        value,
                        &format!("LLM response metadata.{key}[{index}]"),
                    )?;
                    Ok(serde_json::to_value(requested)?)
                })
                .collect::<Result<Vec<_>>>()?;
            *tool_plan = Value::Array(normalized);
        }
    }
    if let Some(tool_call) = object.get_mut("tool_call") {
        let requested = parse_requested_tool_call(tool_call, "LLM response metadata.tool_call")?;
        *tool_call = serde_json::to_value(requested)?;
    }
    Ok(())
}

fn agent_turn_event_from_llm_event(envelope: &AgentTurnEnvelope, event: LlmEvent) -> Result<Value> {
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
    attach_agent_turn_envelope(envelope, &mut value);
    Ok(value)
}

fn agent_turn_started_event(envelope: &AgentTurnEnvelope, request: &LlmRequest) -> Result<Value> {
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
    attach_agent_turn_envelope(envelope, &mut value);
    Ok(value)
}

#[cfg(test)]
fn agent_turn_finished_events(envelope: &AgentTurnEnvelope, event: LlmEvent) -> Result<Vec<Value>> {
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
        attach_agent_turn_envelope(envelope, &mut value);
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
    attach_agent_turn_envelope(envelope, &mut round_finished);
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
        attach_agent_turn_envelope(envelope, &mut done);
        values.push(done);
    }
    Ok(values)
}

fn agent_turn_error_event(envelope: &AgentTurnEnvelope, metadata: Value) -> Value {
    let mut value = json!({
        "kind": "error",
        "content": null,
        "round": 1,
        "metadata": metadata,
    });
    attach_agent_turn_envelope(envelope, &mut value);
    value
}

fn attach_agent_turn_envelope(envelope: &AgentTurnEnvelope, value: &mut Value) {
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

fn normalize_llm_event_contract(event: &mut LlmEvent) -> Result<()> {
    if event.metadata.is_null() {
        event.metadata = json!({});
    } else if !event.metadata.is_object() {
        anyhow::bail!("LLM stream event metadata must be a JSON object");
    }
    if let Some(response) = &mut event.response {
        normalize_llm_response_contract(response)?;
    }
    Ok(())
}

fn require_tool_spec_contract(tool: &ToolSpec, label: &str) -> Result<()> {
    if tool.name.trim().is_empty() {
        anyhow::bail!("{label}.name must be a non-empty string");
    }
    if tool.description.trim().is_empty() {
        anyhow::bail!("{label}.description must be a non-empty string");
    }
    if !tool.input_schema.is_object() {
        anyhow::bail!("{label}.input_schema must be an object");
    }
    if matches!(tool.output_schema.as_ref(), Some(value) if !value.is_object()) {
        anyhow::bail!("{label}.output_schema must be an object when present");
    }
    Ok(())
}

fn require_agent_spec_contract(agent: &AgentSpec, label: &str) -> Result<()> {
    let expected = protocol_version();
    if agent.protocol_version != expected {
        anyhow::bail!(
            "{label}.protocol_version '{}' does not match runtime protocol_version '{expected}'",
            agent.protocol_version
        );
    }
    if agent.id.trim().is_empty() {
        anyhow::bail!("{label}.id must be a non-empty string");
    }
    if agent.name.trim().is_empty() {
        anyhow::bail!("{label}.name must be a non-empty string");
    }
    if agent.version.trim().is_empty() {
        anyhow::bail!("{label}.version must be a non-empty string");
    }
    require_schedule_spec_contract(&agent.schedule, &format!("{label}.schedule"))?;
    Ok(())
}

fn require_schedule_spec_contract(schedule: &ScheduleSpec, label: &str) -> Result<()> {
    match schedule {
        ScheduleSpec::Manual => {}
        ScheduleSpec::Interval {
            every_seconds,
            preferred_hour_local,
            jitter_seconds: _,
        } => {
            if *every_seconds == 0 {
                anyhow::bail!("{label}.every_seconds must be greater than zero");
            }
            if matches!(preferred_hour_local, Some(hour) if *hour > 23) {
                anyhow::bail!("{label}.preferred_hour_local must be between 0 and 23");
            }
        }
    }
    Ok(())
}

fn require_proposal_kind_contract(proposal_kind: &ProposalKindSpec, label: &str) -> Result<()> {
    if proposal_kind.kind.trim().is_empty() {
        anyhow::bail!("{label}.kind must be a non-empty string");
    }
    if proposal_kind.tool_name.trim().is_empty() {
        anyhow::bail!("{label}.tool_name must be a non-empty string");
    }
    Ok(())
}

fn validate_agent_runtime_step_trace_events(trace: &AgentTrace) -> Result<()> {
    for event in &trace.events {
        if event.kind != "agent_runtime_step" {
            continue;
        }
        let payload = event
            .payload
            .as_object()
            .ok_or_else(|| anyhow::anyhow!("agent_runtime_step payload must be an object"))?;
        require_matching_string(payload, "run_id", trace.run_id.0.as_str())?;
        require_matching_string(payload, "agent_id", &trace.agent_id)?;
        require_step_status(payload, "status")?;
        require_non_negative_integer(payload, "step_index")?;
        require_nullable_non_empty_string(payload, "tool_name")?;
        let run_state = payload
            .get("run_state")
            .and_then(Value::as_object)
            .ok_or_else(|| anyhow::anyhow!("agent_runtime_step payload.run_state is required"))?;
        require_step_status(run_state, "status")?;
        require_matching_string(
            run_state,
            "status",
            payload
                .get("status")
                .and_then(Value::as_str)
                .unwrap_or_default(),
        )?;
        require_nullable_non_negative_integer(run_state, "step_index")?;
        require_matching_nullable_integer(run_state, "step_index", payload, "step_index")?;
        require_non_negative_integer(run_state, "remaining_tool_count")?;
        require_non_negative_integer(run_state, "tool_result_count")?;
        require_terminal_reason(run_state, "terminal_reason")?;
        require_terminal_reason_matches_status(run_state)?;
    }
    Ok(())
}

fn require_non_empty_string(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field).and_then(Value::as_str) {
        Some(value) if !value.is_empty() => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be a non-empty string"),
    }
}

fn require_matching_string(object: &Map<String, Value>, field: &str, expected: &str) -> Result<()> {
    require_non_empty_string(object, field)?;
    match object.get(field).and_then(Value::as_str) {
        Some(value) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must match trace {field}"),
    }
}

fn require_non_negative_integer(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field).and_then(Value::as_u64) {
        Some(_) => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be a non-negative integer"),
    }
}

fn require_nullable_non_negative_integer(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field) {
        Some(Value::Null) => Ok(()),
        Some(value) if value.as_u64().is_some() => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be null or a non-negative integer"),
    }
}

fn require_nullable_non_empty_string(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field) {
        Some(Value::Null) => Ok(()),
        Some(Value::String(value)) if !value.is_empty() => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must be null or a non-empty string"),
    }
}

fn require_matching_nullable_string(
    object: &Map<String, Value>,
    field: &str,
    expected: &str,
) -> Result<()> {
    if matches!(object.get(field), Some(Value::Null)) {
        return Ok(());
    }
    require_nullable_non_empty_string(object, field)?;
    match object.get(field).and_then(Value::as_str) {
        Some(value) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must match expected {field}"),
    }
}

fn require_matching_nullable_integer(
    object: &Map<String, Value>,
    field: &str,
    expected_object: &Map<String, Value>,
    expected_field: &str,
) -> Result<()> {
    if matches!(object.get(field), Some(Value::Null)) {
        return Ok(());
    }
    let value = object.get(field).and_then(Value::as_u64);
    let expected = expected_object.get(expected_field).and_then(Value::as_u64);
    match (value, expected) {
        (Some(value), Some(expected)) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} must match payload {expected_field}"),
    }
}

fn require_step_status(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field).and_then(Value::as_str) {
        Some(
            "tool_call_requested"
            | "completed"
            | "failed"
            | "cancelled"
            | "policy_denied"
            | "closed_early"
            | "timed_out",
        ) => Ok(()),
        _ => anyhow::bail!("agent_runtime_step {field} is not a supported status"),
    }
}

fn require_terminal_reason(object: &Map<String, Value>, field: &str) -> Result<()> {
    match object.get(field) {
        Some(Value::Null) => Ok(()),
        Some(Value::String(value))
            if matches!(
                value.as_str(),
                "done" | "stream_error" | "user_cancel" | "policy_denied" | "closed_early"
            ) =>
        {
            Ok(())
        }
        _ => anyhow::bail!("agent_runtime_step {field} is not a supported terminal reason"),
    }
}

fn require_terminal_reason_matches_status(object: &Map<String, Value>) -> Result<()> {
    let expected = match object.get("status").and_then(Value::as_str) {
        Some("tool_call_requested") => None,
        Some("completed") => Some("done"),
        Some("failed") => Some("stream_error"),
        Some("cancelled") => Some("user_cancel"),
        Some("policy_denied") => Some("policy_denied"),
        Some("closed_early" | "timed_out") => Some("closed_early"),
        _ => return Ok(()),
    };

    match (expected, object.get("terminal_reason")) {
        (None, Some(Value::Null)) => Ok(()),
        (Some(expected), Some(Value::String(value))) if value == expected => Ok(()),
        _ => anyhow::bail!("agent_runtime_step terminal_reason must match run_state.status"),
    }
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct RequestedToolCall {
    name: String,
    #[serde(default)]
    input: Value,
}

#[derive(Debug)]
struct ToolRequestState {
    first: RequestedToolCall,
    remaining: Vec<Value>,
    tool_results: Vec<Value>,
    llm_response: Option<Value>,
    step_index: u64,
}

impl ToolRequestState {
    fn continuation(&self) -> Option<Value> {
        if self.remaining.is_empty()
            && self.tool_results.is_empty()
            && self.llm_response.is_none()
            && self.step_index == 0
        {
            return None;
        }
        let mut object = Map::new();
        object.insert("tool_plan".to_owned(), Value::Array(self.remaining.clone()));
        object.insert(
            "tool_results".to_owned(),
            Value::Array(self.tool_results.clone()),
        );
        if let Some(llm_response) = &self.llm_response {
            object.insert("llm_response".to_owned(), llm_response.clone());
        }
        object.insert(
            "next_step_index".to_owned(),
            Value::Number(serde_json::Number::from(self.step_index + 1)),
        );
        Some(Value::Object(object))
    }
}

fn parse_initial_tool_request(input: &Value) -> Result<Option<ToolRequestState>> {
    if let Some(tool_plan) = input.get("tool_plan") {
        let plan = tool_plan
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("tool_plan must be an array"))?;
        if plan.is_empty() {
            return Ok(None);
        }
        let first = parse_requested_tool_call(&plan[0], "tool_plan[0]")?;
        return Ok(Some(ToolRequestState {
            first,
            remaining: plan[1..].to_vec(),
            tool_results: Vec::new(),
            llm_response: input.get("llm_response").cloned(),
            step_index: 0,
        }));
    }

    let Some(tool_call) = input.get("tool_call") else {
        return Ok(None);
    };
    Ok(Some(ToolRequestState {
        first: parse_requested_tool_call(tool_call, "tool_call")?,
        remaining: Vec::new(),
        tool_results: Vec::new(),
        llm_response: input.get("llm_response").cloned(),
        step_index: 0,
    }))
}

fn next_tool_request_from_continuation(
    previous_step: &Value,
    tool_results: Vec<Value>,
) -> Result<Option<ToolRequestState>> {
    let Some(continuation) = previous_step_continuation(previous_step)? else {
        return Ok(None);
    };
    let plan = match continuation.get("tool_plan") {
        Some(value) => value
            .as_array()
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("continuation.tool_plan must be an array"))?,
        None => Vec::new(),
    };
    if plan.is_empty() {
        return Ok(None);
    }
    let first = parse_requested_tool_call(&plan[0], "continuation.tool_plan[0]")?;
    let step_index = continuation
        .get("next_step_index")
        .and_then(Value::as_u64)
        .ok_or_else(|| {
            anyhow::anyhow!("continuation.next_step_index must be a non-negative integer")
        })?;
    Ok(Some(ToolRequestState {
        first,
        remaining: plan[1..].to_vec(),
        tool_results,
        llm_response: continuation.get("llm_response").cloned(),
        step_index,
    }))
}

fn parse_requested_tool_call(value: &Value, label: &str) -> Result<RequestedToolCall> {
    let object = value
        .as_object()
        .ok_or_else(|| anyhow::anyhow!("{label} must be an object"))?;
    let name = object
        .get("name")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| anyhow::anyhow!("{label}.name is required"))?
        .to_owned();
    let input = match object.get("input") {
        Some(input) if input.is_object() => input.clone(),
        Some(_) => anyhow::bail!("{label}.input must be an object"),
        None => json!({}),
    };
    Ok(RequestedToolCall { name, input })
}

fn require_tool_call_input_object(tool_call: &Value, label: &str) -> Result<()> {
    if matches!(tool_call.get("input"), Some(input) if !input.is_object()) {
        anyhow::bail!("{label}.input must be an object");
    }
    Ok(())
}

fn continuation_tool_results(
    previous_step: &Value,
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
) -> Result<Vec<Value>> {
    let Some(continuation) = previous_step_continuation(previous_step)? else {
        return Ok(Vec::new());
    };
    let Some(results) = continuation.get("tool_results") else {
        return Ok(Vec::new());
    };
    let results = results
        .as_array()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("continuation.tool_results must be an array"))?;
    for (index, result) in results.iter().enumerate() {
        let object = result.as_object().ok_or_else(|| {
            anyhow::anyhow!("continuation.tool_results[{index}] must be an object")
        })?;
        let tool_call = object.get("tool_call").ok_or_else(|| {
            anyhow::anyhow!("continuation.tool_results[{index}].tool_call is required")
        })?;
        require_previous_tool_call_catalog_tool(catalog, agent_id, tool_call)?;
        let tool_response = object.get("tool_response").ok_or_else(|| {
            anyhow::anyhow!("continuation.tool_results[{index}].tool_response is required")
        })?;
        require_tool_response_envelope(tool_response).map_err(|error| {
            anyhow::anyhow!("continuation.tool_results[{index}].tool_response: {error}")
        })?;
        require_matching_tool_response_id(tool_call, tool_response).map_err(|error| {
            anyhow::anyhow!("continuation.tool_results[{index}].tool_response: {error}")
        })?;
    }
    Ok(results)
}

fn build_tool_call_requested_step(
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
    agent_version: &str,
    run_id: Value,
    tool_call: RequestedToolCall,
    continuation: Option<Value>,
) -> Result<Value> {
    validate_continuation_tool_plan(catalog, agent_id, &continuation)?;
    let tool = catalog
        .tools
        .iter()
        .find(|tool| tool.name == tool_call.name)
        .ok_or_else(|| {
            anyhow::anyhow!(
                "tool '{}' requested by agent '{}' is not present in the catalog",
                tool_call.name,
                agent_id
            )
        })?;
    let mut step = json!({
        "protocol_version": protocol_version(),
        "run_id": run_id,
        "agent_id": agent_id,
        "agent_version": agent_version,
        "step_index": tool_call_step_index(&continuation),
        "status": "tool_call_requested",
        "tool_call": {
            "tool_call_id": ToolCallId::new_v7(),
            "name": tool.name,
            "input": tool_call.input,
            "risk": tool.risk,
            "metadata": tool.metadata,
        }
    });
    if let Some(continuation) = continuation {
        step.as_object_mut()
            .expect("step is an object")
            .insert("continuation".to_owned(), continuation);
    }
    attach_runtime_metadata(&mut step);
    Ok(step)
}

fn validate_continuation_tool_plan(
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
    continuation: &Option<Value>,
) -> Result<()> {
    let Some(continuation) = continuation else {
        return Ok(());
    };
    let Some(plan) = continuation.get("tool_plan") else {
        return Ok(());
    };
    let plan = plan
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("continuation.tool_plan must be an array"))?;
    for (index, tool_call) in plan.iter().enumerate() {
        require_previous_tool_call_catalog_tool(catalog, agent_id, tool_call)
            .map_err(|error| anyhow::anyhow!("continuation.tool_plan[{index}]: {error}"))?;
    }
    Ok(())
}

fn tool_call_step_index(continuation: &Option<Value>) -> u64 {
    continuation
        .as_ref()
        .and_then(|value| value.get("next_step_index"))
        .and_then(Value::as_u64)
        .map(|next| next.saturating_sub(1))
        .unwrap_or(0)
}

fn attach_runtime_metadata(step: &mut Value) {
    attach_run_state(step);
    attach_trace_event(step);
}

fn attach_run_state(step: &mut Value) {
    let Some(object) = step.as_object_mut() else {
        return;
    };
    let continuation = object.get("continuation");
    let remaining_tool_count = continuation
        .and_then(|value| value.get("tool_plan"))
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);
    let continuation_result_count = continuation
        .and_then(|value| value.get("tool_results"))
        .and_then(Value::as_array)
        .map(Vec::len);
    let output_result_count = object
        .get("output")
        .and_then(|value| value.get("tool_results"))
        .and_then(Value::as_array)
        .map(Vec::len);
    let root_result_count = object
        .get("tool_results")
        .and_then(Value::as_array)
        .map(Vec::len);
    let tool_result_count = continuation_result_count
        .or(output_result_count)
        .or(root_result_count)
        .unwrap_or(0);
    let status = object.get("status").cloned().unwrap_or(Value::Null);
    let state = json!({
        "status": status,
        "step_index": object.get("step_index").cloned().unwrap_or(Value::Null),
        "remaining_tool_count": remaining_tool_count,
        "tool_result_count": tool_result_count,
        "terminal_reason": terminal_reason_for_status(object.get("status").and_then(Value::as_str)),
    });
    object.insert("run_state".to_owned(), state);
}

fn terminal_reason_for_status(status: Option<&str>) -> Value {
    match status {
        Some("completed") => Value::String("done".to_owned()),
        Some("failed") => Value::String("stream_error".to_owned()),
        Some("cancelled") => Value::String("user_cancel".to_owned()),
        Some("policy_denied") => Value::String("policy_denied".to_owned()),
        Some("closed_early") | Some("timed_out") => Value::String("closed_early".to_owned()),
        _ => Value::Null,
    }
}

fn attach_trace_event(step: &mut Value) {
    let Some(object) = step.as_object_mut() else {
        return;
    };
    let event = json!({
        "kind": "agent_runtime_step",
        "run_id": object.get("run_id").cloned().unwrap_or(Value::Null),
        "agent_id": object.get("agent_id").cloned().unwrap_or(Value::Null),
        "status": object.get("status").cloned().unwrap_or(Value::Null),
        "step_index": object.get("step_index").cloned().unwrap_or(Value::Null),
        "run_state": object.get("run_state").cloned().unwrap_or(Value::Null),
        "tool_name": object
            .get("tool_call")
            .and_then(|tool_call| tool_call.get("name"))
            .or_else(|| {
                object
                    .get("output")
                    .and_then(|output| output.get("tool_call"))
                    .and_then(|tool_call| tool_call.get("name"))
            })
            .cloned()
            .unwrap_or(Value::Null),
    });
    object.insert("trace_event".to_owned(), event);
}

fn runtime_input_from_llm_response(response: &LlmResponse) -> Result<Value> {
    if let Some(tool_plan) = response
        .metadata
        .get("tool_plan")
        .or_else(|| response.metadata.get("tool_calls"))
    {
        let plan = tool_plan
            .as_array()
            .ok_or_else(|| anyhow::anyhow!("LLM metadata tool plan must be an array"))?;
        if !plan.is_empty() {
            return Ok(json!({
                "tool_plan": plan,
                "llm_response": response,
            }));
        }
    }
    if let Some(tool_call) = response.metadata.get("tool_call") {
        return Ok(json!({
            "tool_call": tool_call,
            "llm_response": response,
        }));
    }
    Ok(json!({
        "content": response.content,
        "llm_response": response,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn catalog_json() -> String {
        json!({
            "protocol_version": "agent.v1",
            "catalog_version": "agent_catalog.v1",
            "generated_at": "2026-06-29T00:00:00Z",
            "agents": [
                {
                    "id": "execution_review",
                    "name": "Execution Review",
                    "version": "0.1.0",
                    "schedule": {"type": "manual"},
                    "capabilities": ["scheduled_agent"],
                    "metadata": {"domain": "execution"}
                }
            ],
            "tools": [
                {
                    "name": "read_first",
                    "description": "Read first",
                    "input_schema": {"type": "object"},
                    "risk": "read_only",
                    "metadata": {}
                },
                {
                    "name": "read_second",
                    "description": "Read second",
                    "input_schema": {"type": "object"},
                    "risk": "read_only",
                    "metadata": {}
                }
            ],
            "proposal_kinds": [],
            "prompt_blocks": []
        })
        .to_string()
    }

    #[test]
    fn agent_turn_event_wraps_llm_event_with_envelope() {
        let envelope = AgentTurnEnvelope {
            turn_id: Some("turn_1".to_owned()),
            session_id: Some("session_1".to_owned()),
            thread_id: Some("thread_1".to_owned()),
            surface: Some("ai_chat".to_owned()),
            agent_id: Some("ai_chat".to_owned()),
            mode: Some("chat".to_owned()),
        };
        let event = LlmEvent {
            kind: agent_llm::LlmEventKind::Delta,
            content: Some("done".to_owned()),
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: json!({"stream": true}),
        };

        let value = agent_turn_event_from_llm_event(&envelope, event).expect("event wraps");

        assert_eq!(value["protocol_version"], "agent.v1");
        assert_eq!(value["turn_id"], "turn_1");
        assert_eq!(value["session_id"], "session_1");
        assert_eq!(value["thread_id"], "thread_1");
        assert_eq!(value["surface"], "ai_chat");
        assert_eq!(value["agent_id"], "ai_chat");
        assert_eq!(value["mode"], "chat");
        assert_eq!(value["kind"], "delta");
        assert_eq!(value["round"], 1);
        assert_eq!(value["content"], "done");
    }

    #[test]
    fn agent_turn_finished_event_expands_to_chat_turn_events() {
        let envelope = AgentTurnEnvelope {
            turn_id: Some("turn_1".to_owned()),
            session_id: Some("session_1".to_owned()),
            thread_id: Some("thread_1".to_owned()),
            surface: Some("ai_chat".to_owned()),
            agent_id: Some("ai_chat".to_owned()),
            mode: Some("chat".to_owned()),
        };
        let event = LlmEvent {
            kind: agent_llm::LlmEventKind::Finished,
            content: None,
            response: Some(LlmResponse {
                protocol_version: protocol_version(),
                provider: "mock".to_owned(),
                model: "mock-model".to_owned(),
                content: "done".to_owned(),
                finish_reason: agent_llm::LlmFinishReason::Stop,
                usage: Some(agent_llm::LlmUsage {
                    input_tokens: 1,
                    output_tokens: 2,
                    total_tokens: 3,
                }),
                metadata: json!({}),
            }),
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: json!({"stream": true}),
        };

        let values = agent_turn_finished_events(&envelope, event).expect("event expands");

        assert_eq!(values.len(), 3);
        assert_eq!(values[0]["kind"], "usage");
        assert_eq!(values[0]["usage"]["total_tokens"], 3);
        assert_eq!(values[1]["kind"], "round_finished");
        assert_eq!(values[1]["response"]["content"], "done");
        assert_eq!(values[2]["kind"], "done");
        assert_eq!(values[2]["metadata"]["stop_reason"], "end_turn");
    }

    #[test]
    fn agent_turn_error_event_wraps_error_metadata() {
        let envelope = AgentTurnEnvelope {
            turn_id: Some("turn_1".to_owned()),
            session_id: None,
            thread_id: None,
            surface: None,
            agent_id: None,
            mode: None,
        };

        let value = agent_turn_error_event(
            &envelope,
            json!({"code": "provider_error", "message": "bad key"}),
        );

        assert_eq!(value["protocol_version"], "agent.v1");
        assert_eq!(value["turn_id"], "turn_1");
        assert_eq!(value["kind"], "error");
        assert_eq!(value["metadata"]["code"], "provider_error");
    }

    #[test]
    fn native_tool_plan_steps_own_step_index_and_trace_events() {
        let request_json = json!({
            "protocol_version": "agent.v1",
            "run_id": "run_native_trace",
            "input": {
                "tool_plan": [
                    {"name": "read_first", "input": {"id": "first"}},
                    {"name": "read_second", "input": {"id": "second"}}
                ]
            },
            "trigger": "manual",
            "metadata": {}
        })
        .to_string();

        let first: Value = serde_json::from_str(
            &agent_runtime_start_run_step(
                catalog_json(),
                request_json,
                "execution_review".to_owned(),
            )
            .expect("start step"),
        )
        .expect("first step json");
        assert_eq!(first["status"], "tool_call_requested");
        assert_eq!(first["step_index"], 0);
        assert_eq!(first["tool_call"]["name"], "read_first");
        assert_eq!(first["trace_event"]["kind"], "agent_runtime_step");
        assert_eq!(first["trace_event"]["step_index"], 0);
        assert_eq!(first["trace_event"]["tool_name"], "read_first");
        assert_eq!(first["trace_event"]["run_state"]["remaining_tool_count"], 1);
        assert_eq!(first["trace_event"]["run_state"]["tool_result_count"], 0);
        assert_eq!(first["run_state"]["remaining_tool_count"], 1);
        assert_eq!(first["run_state"]["tool_result_count"], 0);
        assert_eq!(first["run_state"]["terminal_reason"], Value::Null);
        let first_tool_call_id = first["tool_call"]["tool_call_id"]
            .as_str()
            .expect("first tool_call_id")
            .to_owned();

        let second: Value = serde_json::from_str(
            &agent_runtime_continue_run_step(
                catalog_json(),
                first.to_string(),
                json!({"jsonrpc": "2.0", "id": first_tool_call_id, "result": {"ok": true}})
                    .to_string(),
                "execution_review".to_owned(),
            )
            .expect("second step"),
        )
        .expect("second step json");
        assert_eq!(second["status"], "tool_call_requested");
        assert_eq!(second["step_index"], 1);
        assert_eq!(second["tool_call"]["name"], "read_second");
        assert_eq!(second["trace_event"]["step_index"], 1);
        assert_eq!(second["trace_event"]["tool_name"], "read_second");
        assert_eq!(
            second["trace_event"]["run_state"]["remaining_tool_count"],
            0
        );
        assert_eq!(second["trace_event"]["run_state"]["tool_result_count"], 1);
        assert_eq!(second["run_state"]["remaining_tool_count"], 0);
        assert_eq!(second["run_state"]["tool_result_count"], 1);
        assert_eq!(second["run_state"]["terminal_reason"], Value::Null);
        let second_tool_call_id = second["tool_call"]["tool_call_id"]
            .as_str()
            .expect("second tool_call_id")
            .to_owned();

        let terminal: Value = serde_json::from_str(
            &agent_runtime_continue_run_step(
                catalog_json(),
                second.to_string(),
                json!({"jsonrpc": "2.0", "id": second_tool_call_id, "result": {"done": true}})
                    .to_string(),
                "execution_review".to_owned(),
            )
            .expect("terminal step"),
        )
        .expect("terminal step json");
        assert_eq!(terminal["status"], "completed");
        assert_eq!(terminal["step_index"], 2);
        assert_eq!(terminal["trace_event"]["step_index"], 2);
        assert_eq!(terminal["trace_event"]["tool_name"], "read_second");
        assert_eq!(
            terminal["trace_event"]["run_state"]["terminal_reason"],
            "done"
        );
        assert_eq!(terminal["trace_event"]["run_state"]["tool_result_count"], 2);
        assert_eq!(terminal["output"]["mode"], "frb_tool_loop");
        assert_eq!(terminal["run_state"]["remaining_tool_count"], 0);
        assert_eq!(terminal["run_state"]["tool_result_count"], 2);
        assert_eq!(terminal["run_state"]["terminal_reason"], "done");
    }

    #[test]
    fn native_tool_response_errors_set_stream_error_terminal_reason() {
        let request_json = json!({
            "protocol_version": "agent.v1",
            "run_id": "run_native_error_trace",
            "input": {
                "tool_call": {"name": "read_first", "input": {"id": "first"}}
            },
            "trigger": "manual",
            "metadata": {}
        })
        .to_string();

        let first: Value = serde_json::from_str(
            &agent_runtime_start_run_step(
                catalog_json(),
                request_json,
                "execution_review".to_owned(),
            )
            .expect("start step"),
        )
        .expect("first step json");
        let first_tool_call_id = first["tool_call"]["tool_call_id"]
            .as_str()
            .expect("first tool_call_id")
            .to_owned();

        let failed: Value = serde_json::from_str(
            &agent_runtime_continue_run_step(
                catalog_json(),
                first.to_string(),
                json!({
                    "jsonrpc": "2.0",
                    "id": first_tool_call_id,
                    "error": {"code": -32000, "message": "no"}
                })
                .to_string(),
                "execution_review".to_owned(),
            )
            .expect("failed step"),
        )
        .expect("failed step json");

        assert_eq!(failed["status"], "failed");
        assert_eq!(failed["trace_event"]["status"], "failed");
        assert_eq!(
            failed["trace_event"]["run_state"]["terminal_reason"],
            "stream_error"
        );
        assert_eq!(failed["trace_event"]["run_state"]["tool_result_count"], 1);
        assert_eq!(failed["run_state"]["terminal_reason"], "stream_error");
    }

    #[test]
    fn llm_stream_event_contract_normalizes_metadata() {
        let mut event = LlmEvent {
            kind: agent_llm::LlmEventKind::Delta,
            content: Some("hello".to_owned()),
            response: None,
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: Value::Null,
        };

        normalize_llm_event_contract(&mut event).expect("event should normalize");

        assert_eq!(event.metadata, json!({}));
    }

    #[test]
    fn llm_stream_event_contract_validates_finished_response() {
        let mut event = LlmEvent {
            kind: agent_llm::LlmEventKind::Finished,
            content: None,
            response: Some(LlmResponse {
                protocol_version: protocol_version(),
                provider: "mock".to_owned(),
                model: "mock-model".to_owned(),
                content: "hello".to_owned(),
                finish_reason: agent_llm::LlmFinishReason::Stop,
                usage: Some(agent_llm::LlmUsage {
                    input_tokens: 2,
                    output_tokens: 3,
                    total_tokens: 4,
                }),
                metadata: json!({}),
            }),
            tool_call_id: None,
            tool_name: None,
            partial_input_json: None,
            tool_input: None,
            metadata: json!({}),
        };

        let err = normalize_llm_event_contract(&mut event)
            .expect_err("mismatched finished usage should fail");

        assert!(err.to_string().contains("usage.total_tokens"));
    }
}
