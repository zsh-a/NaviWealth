use agent_core::{
    Agent, AgentContext, AgentError, AgentRunResult, AgentRuntimeCatalog, AgentSpec,
    PROTOCOL_VERSION, PromptManifest, PromptManifestBlock, ProposalEnvelope, ToolCallId,
    TraceEvent,
};
use agent_runtime::InMemoryAgentRegistry;
use camino::Utf8PathBuf;
use miette::{Result, miette};
use serde::Serialize;
use serde_json::{Value, json};
use std::sync::Arc;
use time::format_description::well_known::Rfc3339;

#[derive(Debug, Serialize)]
pub(crate) struct CatalogSummary {
    pub(crate) protocol_version: String,
    pub(crate) catalog_version: String,
    pub(crate) generated_at: String,
    pub(crate) active_domains: Vec<String>,
    pub(crate) agent_count: usize,
    pub(crate) tool_count: usize,
    pub(crate) proposal_kind_count: usize,
    pub(crate) prompt_block_count: usize,
}

impl CatalogSummary {
    pub(crate) fn from_catalog(catalog: &AgentRuntimeCatalog) -> Self {
        Self {
            protocol_version: catalog.protocol_version.clone(),
            catalog_version: catalog.catalog_version.clone(),
            generated_at: catalog
                .generated_at
                .format(&Rfc3339)
                .unwrap_or_else(|_| catalog.generated_at.to_string()),
            active_domains: catalog.active_domains.clone(),
            agent_count: catalog.agents.len(),
            tool_count: catalog.tools.len(),
            proposal_kind_count: catalog.proposal_kinds.len(),
            prompt_block_count: catalog.prompt_blocks.len(),
        }
    }
}

pub(crate) async fn read_catalog(path: Utf8PathBuf) -> Result<AgentRuntimeCatalog> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read catalog at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse catalog at {path}: {e}"))
}

pub(crate) fn build_prompt_manifest(
    catalog: &AgentRuntimeCatalog,
    agent_id: Option<&str>,
) -> Result<PromptManifest> {
    let agent = select_prompt_manifest_agent(catalog, agent_id)?;
    let prompt_version = string_metadata(&agent.metadata, "prompt_version")
        .unwrap_or_else(|| format!("{}.prompt.v1", agent.id));
    let manifest_id = string_metadata(&agent.metadata, "prompt_id")
        .unwrap_or_else(|| format!("{}_prompt", agent.id));
    let model_family =
        string_metadata(&agent.metadata, "model_family").unwrap_or_else(|| "unknown".to_owned());
    let provider =
        string_metadata(&agent.metadata, "provider").unwrap_or_else(|| "unknown".to_owned());
    let model = string_metadata(&agent.metadata, "model").unwrap_or_else(|| "unknown".to_owned());
    let tool_schema_version = string_metadata(&agent.metadata, "tool_schema_version")
        .unwrap_or_else(|| catalog.catalog_version.clone());
    let blocks = catalog
        .prompt_blocks
        .iter()
        .map(|block| PromptManifestBlock {
            index: block.index,
            source: format!("catalog.prompt_blocks[{}]", block.index),
            content_hash: prompt_block_hash(&block.text),
            text: block.text.clone(),
        })
        .collect();
    Ok(PromptManifest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        id: manifest_id,
        version: prompt_version,
        agent_id: agent.id.clone(),
        agent_version: agent.version.clone(),
        catalog_version: catalog.catalog_version.clone(),
        generated_at: catalog.generated_at,
        model_family,
        provider,
        model,
        tool_schema_version,
        active_domains: catalog.active_domains.clone(),
        blocks,
    })
}

pub(crate) fn string_metadata(metadata: &Value, key: &str) -> Option<String> {
    metadata
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) async fn load_catalog_registry(path: Utf8PathBuf) -> Result<Arc<InMemoryAgentRegistry>> {
    let catalog = read_catalog(path).await?;
    Ok(registry_from_catalog(&catalog))
}

pub(crate) fn registry_from_catalog(catalog: &AgentRuntimeCatalog) -> Arc<InMemoryAgentRegistry> {
    let agents = catalog
        .agents
        .iter()
        .cloned()
        .map(|spec| Arc::new(CatalogDryRunAgent { spec }) as Arc<dyn Agent>)
        .collect::<Vec<_>>();
    InMemoryAgentRegistry::shared(agents)
}

struct CatalogDryRunAgent {
    spec: AgentSpec,
}

#[async_trait::async_trait]
impl Agent for CatalogDryRunAgent {
    fn spec(&self) -> AgentSpec {
        self.spec.clone()
    }

    async fn run(&self, ctx: AgentContext) -> std::result::Result<AgentRunResult, AgentError> {
        ctx.trace
            .emit(TraceEvent::new(
                "catalog_dry_run.agent_selected",
                json!({
                    "agent_id": self.spec.id.clone(),
                    "agent_version": self.spec.version.clone(),
                    "source": "agent_catalog.v1"
                }),
            ))
            .await?;
        let tool_result = match ctx.input.get("tool_call") {
            Some(call) => Some(run_requested_tool_call(&ctx, call).await?),
            None => None,
        };
        let proposal_result = match ctx.input.get("proposal") {
            Some(proposal) => Some(run_requested_proposal(&ctx, &self.spec.id, proposal).await?),
            None => None,
        };
        Ok(AgentRunResult::completed(
            ctx.run_id,
            self.spec.id.clone(),
            ctx.now,
            json!({
                "mode": "catalog_dry_run",
                "agent": self.spec.clone(),
                "input": ctx.input,
                "tool_result": tool_result,
                "proposal": proposal_result,
                "note": "Catalog dry-run validates Rust runtime lifecycle only; Flutter business logic is not executed."
            }),
            Some("catalog dry-run completed".to_owned()),
        ))
    }
}

async fn run_requested_proposal(
    ctx: &AgentContext,
    agent_id: &str,
    proposal: &Value,
) -> Result<ProposalEnvelope, AgentError> {
    let kind = proposal
        .get("kind")
        .and_then(Value::as_str)
        .ok_or_else(|| AgentError::validation("proposal.kind is required"))?;
    let summary = proposal
        .get("summary")
        .and_then(Value::as_str)
        .ok_or_else(|| AgentError::validation("proposal.summary is required"))?;
    let payload = proposal
        .get("payload")
        .cloned()
        .unwrap_or_else(|| json!({}));
    let envelope = ProposalEnvelope::new(
        ctx.run_id.clone(),
        agent_id.to_owned(),
        kind.to_owned(),
        summary.to_owned(),
        payload,
    );
    ctx.services.create_proposal(envelope.clone()).await?;
    Ok(envelope)
}

async fn run_requested_tool_call(ctx: &AgentContext, call: &Value) -> Result<Value, AgentError> {
    let name = call
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| AgentError::validation("tool_call.name is required"))?;
    let input = call.get("input").cloned().unwrap_or_else(|| json!({}));
    ctx.trace
        .emit(TraceEvent::new(
            "catalog_dry_run.tool_call_requested",
            json!({"name": name, "input": input}),
        ))
        .await?;
    call_traced_tool(ctx, name, input).await
}

pub(crate) async fn call_traced_tool(
    ctx: &AgentContext,
    name: &str,
    input: Value,
) -> Result<Value, AgentError> {
    let tool_call_id = ToolCallId::new_v7();
    let input_hash = tool_input_hash(&input);
    let started_at = std::time::Instant::now();
    ctx.trace
        .emit(TraceEvent::new(
            "tool_call_started",
            json!({
                "tool_call_id": tool_call_id.0.clone(),
                "tool_name": name,
                "input_hash": input_hash.clone(),
                "input": input.clone(),
            }),
        ))
        .await?;

    match ctx.services.call_tool(name, input.clone()).await {
        Ok(output) => {
            ctx.trace
                .emit(TraceEvent::new(
                    "tool_call_finished",
                    json!({
                        "tool_call_id": tool_call_id.0.clone(),
                        "tool_name": name,
                        "input_hash": input_hash.clone(),
                        "duration_ms": started_at.elapsed().as_millis(),
                        "status": "completed",
                        "output": output.clone(),
                    }),
                ))
                .await?;
            Ok(output)
        }
        Err(error) => {
            ctx.trace
                .emit(TraceEvent::new(
                    "tool_call_failed",
                    json!({
                        "tool_call_id": tool_call_id.0.clone(),
                        "tool_name": name,
                        "input_hash": input_hash.clone(),
                        "duration_ms": started_at.elapsed().as_millis(),
                        "status": "failed",
                        "error": error.record.clone(),
                    }),
                ))
                .await?;
            Err(AgentError {
                record: error.record,
            })
        }
    }
}

fn select_prompt_manifest_agent<'a>(
    catalog: &'a AgentRuntimeCatalog,
    agent_id: Option<&str>,
) -> Result<&'a AgentSpec> {
    if let Some(agent_id) = agent_id {
        return catalog
            .agents
            .iter()
            .find(|agent| agent.id == agent_id)
            .ok_or_else(|| miette!("agent '{agent_id}' not found in catalog"));
    }
    match catalog.agents.as_slice() {
        [agent] => Ok(agent),
        [] => Err(miette!(
            "catalog has no agents; pass --agent-id after adding one"
        )),
        _ => Err(miette!(
            "catalog has multiple agents; pass --agent-id to choose a prompt manifest"
        )),
    }
}

fn prompt_block_hash(text: &str) -> String {
    format!("blake3:{}", blake3::hash(text.as_bytes()).to_hex())
}

fn tool_input_hash(input: &Value) -> String {
    let bytes = serde_json::to_vec(input).unwrap_or_default();
    format!("blake3:{}", blake3::hash(&bytes).to_hex())
}
