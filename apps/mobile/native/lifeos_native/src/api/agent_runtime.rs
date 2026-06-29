//! Agent runtime bridge - FRB public surface for schema-first runtime contracts.
//!
//! Keep this module primitive-only for stable Dart bindings. The shared Rust
//! DTOs live in `agent-core`; Dart passes JSON strings across the bridge.

use agent_core::{
    AgentRuntimeCatalog, AgentTrace, RunId, RunRequest, ToolCallId, ToolSpec, catalog_version,
    protocol_version,
};
use agent_llm::{
    AnthropicProvider, LlmProvider, LlmRequest, LlmResponse, MockLlmProvider,
    OpenAiCompatibleProvider,
};
use anyhow::Result;
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

use crate::frb_generated::StreamSink;

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

pub fn agent_runtime_protocol_version() -> String {
    protocol_version()
}

pub fn agent_runtime_catalog_version() -> String {
    catalog_version()
}

pub fn agent_runtime_catalog_summary(catalog_json: String) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
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
    normalize_json::<RunRequest>(&request_json)
}

pub fn agent_runtime_validate_trace(trace_json: String) -> Result<String> {
    let trace: AgentTrace = serde_json::from_str(&trace_json)?;
    validate_agent_runtime_step_trace_events(&trace)?;
    Ok(serde_json::to_string(&trace)?)
}

pub fn agent_runtime_validate_tool_spec(tool_json: String) -> Result<String> {
    normalize_json::<ToolSpec>(&tool_json)
}

pub fn agent_runtime_validate_llm_request(request_json: String) -> Result<String> {
    normalize_json::<LlmRequest>(&request_json)
}

pub fn agent_runtime_validate_llm_response(response_json: String) -> Result<String> {
    normalize_json::<LlmResponse>(&response_json)
}

pub async fn agent_runtime_complete_mock_llm(
    request_json: String,
    response_text: String,
) -> Result<String> {
    let request: LlmRequest = serde_json::from_str(&request_json)?;
    let provider = MockLlmProvider::new("mock", request.model.clone(), response_text);
    let response = provider
        .complete(request)
        .await
        .map_err(|e| anyhow::anyhow!(e.record.message.clone()))?;
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
    let request: LlmRequest = serde_json::from_str(&request_json)?;
    let provider = MockLlmProvider::new("mock", request.model.clone(), response_text);
    stream_llm_response(sink, Box::new(provider), request).await
}

pub async fn agent_runtime_stream_profile_llm(
    sink: StreamSink<String>,
    request_json: String,
) -> Result<()> {
    let request: LlmRequest = serde_json::from_str(&request_json)?;
    let provider = profile_llm_provider(&request)?;
    stream_llm_response(sink, provider, request).await
}

pub async fn agent_runtime_start_profile_turn_step(
    catalog_json: String,
    llm_request_json: String,
    agent_id: String,
    run_metadata_json: String,
) -> Result<String> {
    let llm_request: LlmRequest = serde_json::from_str(&llm_request_json)?;
    let llm_response = complete_profile_llm_response(llm_request).await?;
    let mut metadata = if run_metadata_json.trim().is_empty() {
        json!({})
    } else {
        serde_json::from_str::<Value>(&run_metadata_json)?
    };
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

async fn complete_profile_llm_response(request: LlmRequest) -> Result<LlmResponse> {
    profile_llm_provider(&request)?
        .complete(request)
        .await
        .map_err(llm_error_to_anyhow)
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
            Ok(event) => {
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
    let request: RunRequest = serde_json::from_str(&request_json)?;
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
    let Some(continuation) = previous_step.get("continuation") else {
        return Ok(());
    };
    let Some(next_step_index) = continuation.get("next_step_index") else {
        return Ok(());
    };
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
    let Some(continuation) = previous_step.get("continuation") else {
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
        .unwrap_or_else(|| {
            previous_step
                .get("step_index")
                .and_then(Value::as_u64)
                .unwrap_or(0)
                + 1
        });
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
    Ok(RequestedToolCall {
        name,
        input: object.get("input").cloned().unwrap_or(Value::Null),
    })
}

fn continuation_tool_results(
    previous_step: &Value,
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
) -> Result<Vec<Value>> {
    let Some(continuation) = previous_step.get("continuation") else {
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

        let second: Value = serde_json::from_str(
            &agent_runtime_continue_run_step(
                catalog_json(),
                first.to_string(),
                json!({"jsonrpc": "2.0", "id": "call_1", "result": {"ok": true}}).to_string(),
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

        let terminal: Value = serde_json::from_str(
            &agent_runtime_continue_run_step(
                catalog_json(),
                second.to_string(),
                json!({"jsonrpc": "2.0", "id": "call_2", "result": {"done": true}}).to_string(),
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

        let failed: Value = serde_json::from_str(
            &agent_runtime_continue_run_step(
                catalog_json(),
                first.to_string(),
                json!({
                    "jsonrpc": "2.0",
                    "id": "call_1",
                    "error": {"code": "denied", "message": "no"}
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
}
