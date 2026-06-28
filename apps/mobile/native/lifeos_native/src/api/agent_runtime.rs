//! Agent runtime bridge - FRB public surface for schema-first runtime contracts.
//!
//! Keep this module primitive-only for stable Dart bindings. The shared Rust
//! DTOs live in `agent-core`; Dart passes JSON strings across the bridge.

use agent_core::{
    catalog_version, protocol_version, AgentRuntimeCatalog, AgentTrace, RunRequest, ToolSpec,
};
use anyhow::Result;
use serde::Serialize;

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

fn normalize_json<T>(json: &str) -> Result<String>
where
    T: serde::de::DeserializeOwned + Serialize,
{
    let value: T = serde_json::from_str(json)?;
    Ok(serde_json::to_string(&value)?)
}
