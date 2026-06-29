//! Agent runtime bridge - FRB public surface for schema-first runtime contracts.
//!
//! Keep this module primitive-only for stable Dart bindings. The shared Rust
//! DTOs live in `agent-core`; Dart passes JSON strings across the bridge.

use agent_core::{
    AgentRuntimeCatalog, AgentTrace, RunId, RunRequest, ToolCallId, ToolSpec, catalog_version,
    protocol_version,
};
use agent_llm::{LlmProvider, LlmRequest, LlmResponse, MockLlmProvider};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

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

    let response = match parse_requested_tool_call(&request.input)? {
        Some(tool_call) => {
            let tool = catalog
                .tools
                .iter()
                .find(|tool| tool.name == tool_call.name)
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "tool '{}' requested by agent '{}' is not present in the catalog",
                        tool_call.name,
                        agent.id
                    )
                })?;
            json!({
                "protocol_version": protocol_version(),
                "run_id": run_id,
                "agent_id": agent.id,
                "agent_version": agent.version,
                "status": "tool_call_requested",
                "tool_call": {
                    "tool_call_id": ToolCallId::new_v7(),
                    "name": tool.name,
                    "input": tool_call.input,
                    "risk": tool.risk,
                    "metadata": tool.metadata,
                }
            })
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
        None => json!({
            "protocol_version": protocol_version(),
            "run_id": run_id,
            "agent_id": agent.id,
            "agent_version": agent.version,
            "status": "completed",
            "output": {
                "mode": "frb_tool_step",
                "tool_call": tool_call,
                "tool_result": tool_response.get("result").cloned().unwrap_or(Value::Null),
                "tool_response": tool_response,
            }
        }),
    };
    Ok(serde_json::to_string(&response)?)
}

fn normalize_json<T>(json: &str) -> Result<String>
where
    T: serde::de::DeserializeOwned + Serialize,
{
    let value: T = serde_json::from_str(json)?;
    Ok(serde_json::to_string(&value)?)
}

#[derive(Debug, Deserialize)]
struct RequestedToolCall {
    name: String,
    #[serde(default)]
    input: Value,
}

fn parse_requested_tool_call(input: &Value) -> Result<Option<RequestedToolCall>> {
    let Some(tool_call) = input.get("tool_call") else {
        return Ok(None);
    };
    Ok(Some(serde_json::from_value(tool_call.clone())?))
}
