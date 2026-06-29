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
    normalize_json::<AgentTrace>(&trace_json)
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

    let response = match parse_initial_tool_request(&request.input)? {
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
                "status": "completed",
                "output": request.input,
            })
        }
    };
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
    let run_id = previous_step
        .get("run_id")
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("previous step is missing run_id"))?;
    let tool_call = previous_step
        .get("tool_call")
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("previous step is missing tool_call"))?;
    let mut tool_results = continuation_tool_results(&previous_step)?;
    tool_results.push(json!({
        "tool_call": tool_call.clone(),
        "tool_response": tool_response.clone(),
    }));

    let response = match tool_response.get("error") {
        Some(error) => json!({
            "protocol_version": protocol_version(),
            "run_id": run_id,
            "agent_id": agent.id,
            "agent_version": agent.version,
            "status": "failed",
            "tool_call": tool_call,
            "tool_response": tool_response,
            "error": error,
        }),
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
    Ok(serde_json::to_string(&response)?)
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
}

impl ToolRequestState {
    fn continuation(&self) -> Option<Value> {
        if self.remaining.is_empty() && self.tool_results.is_empty() && self.llm_response.is_none()
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
        let first = serde_json::from_value(plan[0].clone())?;
        return Ok(Some(ToolRequestState {
            first,
            remaining: plan[1..].to_vec(),
            tool_results: Vec::new(),
            llm_response: input.get("llm_response").cloned(),
        }));
    }

    let Some(tool_call) = input.get("tool_call") else {
        return Ok(None);
    };
    Ok(Some(ToolRequestState {
        first: serde_json::from_value(tool_call.clone())?,
        remaining: Vec::new(),
        tool_results: Vec::new(),
        llm_response: input.get("llm_response").cloned(),
    }))
}

fn next_tool_request_from_continuation(
    previous_step: &Value,
    tool_results: Vec<Value>,
) -> Result<Option<ToolRequestState>> {
    let Some(continuation) = previous_step.get("continuation") else {
        return Ok(None);
    };
    let plan = continuation
        .get("tool_plan")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if plan.is_empty() {
        return Ok(None);
    }
    let first = serde_json::from_value(plan[0].clone())?;
    Ok(Some(ToolRequestState {
        first,
        remaining: plan[1..].to_vec(),
        tool_results,
        llm_response: continuation.get("llm_response").cloned(),
    }))
}

fn continuation_tool_results(previous_step: &Value) -> Result<Vec<Value>> {
    let Some(continuation) = previous_step.get("continuation") else {
        return Ok(Vec::new());
    };
    let Some(results) = continuation.get("tool_results") else {
        return Ok(Vec::new());
    };
    results
        .as_array()
        .cloned()
        .ok_or_else(|| anyhow::anyhow!("continuation.tool_results must be an array"))
}

fn build_tool_call_requested_step(
    catalog: &AgentRuntimeCatalog,
    agent_id: &str,
    agent_version: &str,
    run_id: Value,
    tool_call: RequestedToolCall,
    continuation: Option<Value>,
) -> Result<Value> {
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
    Ok(step)
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
