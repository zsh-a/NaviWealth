//! Agent runtime bridge implementation for schema-first runtime contracts.
//!
//! The FRB-visible primitive wrapper lives in `crate::api::agent_runtime`.
//! The shared Rust DTOs live in `agent-core`; Dart passes JSON strings across
//! the bridge.

mod chat;
mod contracts;
mod llm;
mod llm_provider;
mod steps;

use agent_chat::{
    ChatError, ChatToolCall, ChatToolResult, ChatTurnAdvance, ChatTurnEvent, ChatTurnEventKind,
    ChatTurnRequest, ChatTurnState, chat_turn_apply_response, chat_turn_apply_tool_results,
    chat_turn_initial_state, chat_turn_llm_request, chat_turn_next_round,
};
use agent_core::{
    AgentRuntimeCatalog, AgentSpec, AgentTrace, ProposalKindSpec, RunRequest, ScheduleSpec,
    ToolSpec, catalog_version, protocol_version,
};
use agent_llm::{
    LlmEvent, LlmEventKind, LlmFinishReason, LlmProvider, LlmRequest, LlmResponse, MockLlmProvider,
};
use anyhow::Result;
use futures::StreamExt;
use serde::Serialize;
use serde_json::{Map, Value, json};
use std::collections::HashSet;

use crate::frb_generated::StreamSink;

use contracts::CatalogSummary;
use llm_provider::profile_llm_provider;

pub fn agent_runtime_protocol_version() -> String {
    protocol_version()
}

pub fn agent_runtime_catalog_version() -> String {
    catalog_version()
}

pub fn agent_runtime_catalog_summary(catalog_json: String) -> Result<String> {
    let catalog: AgentRuntimeCatalog = serde_json::from_str(&catalog_json)?;
    contracts::require_catalog_contract(&catalog)?;
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
    contracts::normalize_run_request_contract(&mut request)?;
    Ok(serde_json::to_string(&request)?)
}

pub fn agent_runtime_validate_trace(trace_json: String) -> Result<String> {
    let trace: AgentTrace = serde_json::from_str(&trace_json)?;
    contracts::validate_agent_runtime_step_trace_events(&trace)?;
    Ok(serde_json::to_string(&trace)?)
}

pub fn agent_runtime_validate_tool_spec(tool_json: String) -> Result<String> {
    let tool: ToolSpec = serde_json::from_str(&tool_json)?;
    contracts::require_tool_spec_contract(&tool, "tool")?;
    Ok(serde_json::to_string(&tool)?)
}

pub fn agent_runtime_validate_llm_request(request_json: String) -> Result<String> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    contracts::normalize_llm_request_contract(&mut request)?;
    Ok(serde_json::to_string(&request)?)
}

pub fn agent_runtime_validate_llm_response(response_json: String) -> Result<String> {
    let mut response: LlmResponse = serde_json::from_str(&response_json)?;
    contracts::normalize_llm_response_contract(&mut response)?;
    Ok(serde_json::to_string(&response)?)
}

pub fn agent_runtime_validate_chat_turn_request(request_json: String) -> Result<String> {
    let mut request: ChatTurnRequest = serde_json::from_str(&request_json)?;
    contracts::normalize_chat_turn_request_contract(&mut request)?;
    Ok(serde_json::to_string(&request)?)
}

pub async fn agent_runtime_complete_mock_llm(
    request_json: String,
    response_text: String,
) -> Result<String> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    contracts::normalize_llm_request_contract(&mut request)?;
    let provider = MockLlmProvider::new("mock", request.model.clone(), response_text);
    let mut response = provider
        .complete(request)
        .await
        .map_err(|e| anyhow::anyhow!(e.record.message.clone()))?;
    contracts::normalize_llm_response_contract(&mut response)?;
    Ok(serde_json::to_string(&response)?)
}

pub async fn agent_runtime_complete_profile_llm(request_json: String) -> Result<String> {
    let request: LlmRequest = serde_json::from_str(&request_json)?;
    let response = llm::complete_profile_llm_response(request).await?;
    Ok(serde_json::to_string(&response)?)
}

pub async fn agent_runtime_stream_mock_llm(
    sink: StreamSink<String>,
    request_json: String,
    response_text: String,
) -> Result<()> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    contracts::normalize_llm_request_contract(&mut request)?;
    let provider = MockLlmProvider::new("mock", request.model.clone(), response_text);
    llm::stream_llm_response(sink, Box::new(provider), request).await
}

pub async fn agent_runtime_stream_profile_llm(
    sink: StreamSink<String>,
    request_json: String,
) -> Result<()> {
    let mut request: LlmRequest = serde_json::from_str(&request_json)?;
    contracts::normalize_llm_request_contract(&mut request)?;
    let provider = profile_llm_provider(&request)?;
    llm::stream_llm_response(sink, provider, request).await
}

pub async fn agent_runtime_stream_chat_turn(
    sink: StreamSink<String>,
    request_json: String,
) -> Result<()> {
    let mut request: ChatTurnRequest = serde_json::from_str(&request_json)?;
    contracts::normalize_chat_turn_request_contract(&mut request)?;
    let state = chat::chat_turn_state_from_request(&request)?;
    let llm_request = chat_turn_llm_request(&state);
    let provider = profile_llm_provider(&llm_request)?;
    chat::stream_chat_turn_response(sink, provider, state).await
}

pub async fn agent_runtime_start_profile_turn_step(
    catalog_json: String,
    llm_request_json: String,
    agent_id: String,
    run_metadata_json: String,
) -> Result<String> {
    let (llm_response, request) =
        profile_turn_request(&llm_request_json, &run_metadata_json).await?;
    let step_json = steps::agent_runtime_start_run_step(
        catalog_json,
        serde_json::to_string(&request)?,
        agent_id,
    )?;
    let step: Value = serde_json::from_str(&step_json)?;
    let output = json!({
        "protocol_version": protocol_version(),
        "llm_response": llm_response,
        "step": step,
    });
    Ok(serde_json::to_string(&output)?)
}

pub async fn agent_runtime_start_profile_turn_snapshot(
    catalog_json: String,
    llm_request_json: String,
    agent_id: String,
    run_metadata_json: String,
    max_effect_steps: u32,
    max_subagent_depth: u32,
) -> Result<String> {
    let (llm_response, request) =
        profile_turn_request(&llm_request_json, &run_metadata_json).await?;
    let snapshot_json = steps::agent_runtime_start_run_snapshot(
        catalog_json,
        serde_json::to_string(&request)?,
        agent_id,
        max_effect_steps,
        max_subagent_depth,
    )?;
    let snapshot: Value = serde_json::from_str(&snapshot_json)?;
    let output = json!({
        "protocol_version": protocol_version(),
        "llm_response": llm_response,
        "snapshot": snapshot,
    });
    Ok(serde_json::to_string(&output)?)
}

async fn profile_turn_request(
    llm_request_json: &str,
    run_metadata_json: &str,
) -> Result<(LlmResponse, RunRequest)> {
    let llm_request: LlmRequest = serde_json::from_str(llm_request_json)?;
    let llm_response = llm::complete_profile_llm_response(llm_request).await?;
    let mut metadata = llm::profile_turn_run_metadata(run_metadata_json)?;
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
        input: steps::runtime_input_from_llm_response(&llm_response)?,
        user: None,
        scope: None,
        trigger: agent_core::TriggerKind::Manual,
        trigger_envelope: None,
        workflow: None,
        metadata,
    };
    Ok((llm_response, request))
}

pub fn agent_runtime_start_run_step(
    catalog_json: String,
    request_json: String,
    agent_id: String,
) -> Result<String> {
    steps::agent_runtime_start_run_step(catalog_json, request_json, agent_id)
}

pub fn agent_runtime_continue_run_step(
    catalog_json: String,
    previous_step_json: String,
    effect_response_json: String,
    agent_id: String,
) -> Result<String> {
    steps::agent_runtime_continue_run_step(
        catalog_json,
        previous_step_json,
        effect_response_json,
        agent_id,
    )
}

pub fn agent_runtime_start_run_snapshot(
    catalog_json: String,
    request_json: String,
    agent_id: String,
    max_effect_steps: u32,
    max_subagent_depth: u32,
) -> Result<String> {
    steps::agent_runtime_start_run_snapshot(
        catalog_json,
        request_json,
        agent_id,
        max_effect_steps,
        max_subagent_depth,
    )
}

pub fn agent_runtime_continue_run_snapshot(
    catalog_json: String,
    snapshot_json: String,
    effect_response_json: String,
    agent_id: String,
) -> Result<String> {
    steps::agent_runtime_continue_run_snapshot(
        catalog_json,
        snapshot_json,
        effect_response_json,
        agent_id,
    )
}

pub fn agent_runtime_start_requested_subagent_snapshot(
    catalog_json: String,
    parent_snapshot_json: String,
) -> Result<String> {
    steps::agent_runtime_start_requested_subagent_snapshot(catalog_json, parent_snapshot_json)
}

pub fn agent_runtime_resume_parent_from_subagent_snapshot(
    catalog_json: String,
    parent_snapshot_json: String,
    child_snapshot_json: String,
) -> Result<String> {
    steps::agent_runtime_resume_parent_from_subagent_snapshot(
        catalog_json,
        parent_snapshot_json,
        child_snapshot_json,
    )
}

#[cfg(test)]
mod tests;
