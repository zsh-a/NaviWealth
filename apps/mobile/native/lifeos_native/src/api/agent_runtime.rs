//! Agent runtime FRB surface.
//!
//! Keep this module primitive-only for stable Dart bindings. The protocol
//! implementation lives in `crate::agent_runtime`, outside `api/`, so FRB
//! codegen scans only this small facade.

use anyhow::Result;

use crate::agent_runtime as runtime;
use crate::frb_generated::StreamSink;

pub fn agent_runtime_protocol_version() -> String {
    runtime::agent_runtime_protocol_version()
}

pub fn agent_runtime_catalog_version() -> String {
    runtime::agent_runtime_catalog_version()
}

pub fn agent_runtime_catalog_summary(catalog_json: String) -> Result<String> {
    runtime::agent_runtime_catalog_summary(catalog_json)
}

pub fn agent_runtime_validate_run_request(request_json: String) -> Result<String> {
    runtime::agent_runtime_validate_run_request(request_json)
}

pub fn agent_runtime_validate_trace(trace_json: String) -> Result<String> {
    runtime::agent_runtime_validate_trace(trace_json)
}

pub fn agent_runtime_validate_tool_spec(tool_json: String) -> Result<String> {
    runtime::agent_runtime_validate_tool_spec(tool_json)
}

pub fn agent_runtime_validate_llm_request(request_json: String) -> Result<String> {
    runtime::agent_runtime_validate_llm_request(request_json)
}

pub fn agent_runtime_validate_llm_response(response_json: String) -> Result<String> {
    runtime::agent_runtime_validate_llm_response(response_json)
}

pub fn agent_runtime_validate_chat_turn_request(request_json: String) -> Result<String> {
    runtime::agent_runtime_validate_chat_turn_request(request_json)
}

pub async fn agent_runtime_complete_mock_llm(
    request_json: String,
    response_text: String,
) -> Result<String> {
    runtime::agent_runtime_complete_mock_llm(request_json, response_text).await
}

pub async fn agent_runtime_complete_profile_llm(request_json: String) -> Result<String> {
    runtime::agent_runtime_complete_profile_llm(request_json).await
}

pub async fn agent_runtime_stream_mock_llm(
    sink: StreamSink<String>,
    request_json: String,
    response_text: String,
) -> Result<()> {
    runtime::agent_runtime_stream_mock_llm(sink, request_json, response_text).await
}

pub async fn agent_runtime_stream_profile_llm(
    sink: StreamSink<String>,
    request_json: String,
) -> Result<()> {
    runtime::agent_runtime_stream_profile_llm(sink, request_json).await
}

pub async fn agent_runtime_stream_chat_turn(
    sink: StreamSink<String>,
    request_json: String,
) -> Result<()> {
    runtime::agent_runtime_stream_chat_turn(sink, request_json).await
}

pub async fn agent_runtime_start_profile_turn_snapshot(
    catalog_json: String,
    llm_request_json: String,
    agent_id: String,
    run_metadata_json: String,
    max_effect_steps: u32,
    max_subagent_depth: u32,
) -> Result<String> {
    runtime::agent_runtime_start_profile_turn_snapshot(
        catalog_json,
        llm_request_json,
        agent_id,
        run_metadata_json,
        max_effect_steps,
        max_subagent_depth,
    )
    .await
}

pub fn agent_runtime_start_run_snapshot(
    catalog_json: String,
    request_json: String,
    agent_id: String,
    max_effect_steps: u32,
    max_subagent_depth: u32,
) -> Result<String> {
    runtime::agent_runtime_start_run_snapshot(
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
    runtime::agent_runtime_continue_run_snapshot(
        catalog_json,
        snapshot_json,
        effect_response_json,
        agent_id,
    )
}

pub fn agent_runtime_cancel_run_snapshot(
    catalog_json: String,
    snapshot_json: String,
    agent_id: String,
    reason: String,
) -> Result<String> {
    runtime::agent_runtime_cancel_run_snapshot(catalog_json, snapshot_json, agent_id, reason)
}

pub fn agent_runtime_start_requested_subagent_snapshot(
    catalog_json: String,
    parent_snapshot_json: String,
) -> Result<String> {
    runtime::agent_runtime_start_requested_subagent_snapshot(catalog_json, parent_snapshot_json)
}

pub fn agent_runtime_resume_parent_from_subagent_snapshot(
    catalog_json: String,
    parent_snapshot_json: String,
    child_snapshot_json: String,
) -> Result<String> {
    runtime::agent_runtime_resume_parent_from_subagent_snapshot(
        catalog_json,
        parent_snapshot_json,
        child_snapshot_json,
    )
}
