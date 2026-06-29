use std::sync::Arc;

use agent_core::{AgentRunResult, PROTOCOL_VERSION, RunId, RunRequest, TriggerKind};
use agent_runtime::AgentRunner;
use agent_store::{FileProposalStore, FileRunStore};
use camino::{Utf8Path, Utf8PathBuf};
use clap::ValueEnum;
use miette::{IntoDiagnostic, Result};
use serde::Serialize;
use serde_json::json;

use crate::{
    catalog::load_catalog_registry,
    config::execution_policy,
    print_json,
    registry::load_registry,
    tools::{CliServices, tool_overrides},
    trace_store::{read_trace, write_json, write_store_trace},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ValueEnum)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ReplayMode {
    View,
    Deterministic,
    Live,
}

#[derive(Debug, Serialize)]
pub(crate) struct ReplayExecutionReport {
    mode: ReplayMode,
    source_run_id: RunId,
    replay_run_id: RunId,
    agent_id: String,
    result: AgentRunResult,
    trace: agent_core::AgentTrace,
    output_matches: bool,
}

pub(crate) struct ReplayTraceOptions {
    pub(crate) trace_file: Utf8PathBuf,
    pub(crate) mode: ReplayMode,
    pub(crate) registry: Utf8PathBuf,
    pub(crate) catalog: Option<Utf8PathBuf>,
    pub(crate) tool_host: Vec<String>,
    pub(crate) mock_tool: Vec<String>,
    pub(crate) tool_source: Vec<Utf8PathBuf>,
    pub(crate) store: Utf8PathBuf,
    pub(crate) trace_out: Option<Utf8PathBuf>,
    pub(crate) timeout_seconds: u64,
    pub(crate) max_retries: u32,
    pub(crate) retry_backoff_ms: u64,
}

pub(crate) async fn replay_trace(options: ReplayTraceOptions) -> Result<()> {
    let source_trace = read_trace(options.trace_file).await?;
    if options.mode == ReplayMode::Deterministic {
        let report = deterministic_replay_report(source_trace);
        if let Some(path) = options.trace_out {
            write_json(path, &report.trace).await?;
        }
        return print_json(&report);
    }
    let registry = match options.catalog {
        Some(path) => load_catalog_registry(path).await?,
        None => load_registry(options.registry).await?.into_agent_registry(),
    };
    let store = Arc::new(
        FileRunStore::new(options.store.clone())
            .await
            .into_diagnostic()?,
    );
    let proposal_store = Arc::new(
        FileProposalStore::new(options.store.clone())
            .await
            .into_diagnostic()?,
    );
    let services = Arc::new(CliServices::with_proposal_store(
        tool_overrides(options.tool_host, options.mock_tool, options.tool_source).await?,
        proposal_store,
    ));
    let runner = AgentRunner::new(registry, store, services).with_policy(execution_policy(
        options.timeout_seconds,
        options.max_retries,
        options.retry_backoff_ms,
    ));
    let report = replay_source_trace(&runner, &options.store, source_trace, options.mode).await?;
    if let Some(path) = options.trace_out {
        write_json(path, &report.trace).await?;
    }
    print_json(&report)
}

pub(crate) async fn replay_source_trace(
    runner: &AgentRunner,
    store_path: &Utf8Path,
    source_trace: agent_core::AgentTrace,
    mode: ReplayMode,
) -> Result<ReplayExecutionReport> {
    let source_output = source_trace.output.clone();
    let outcome = runner
        .run_once(
            &source_trace.agent_id,
            run_request_from_trace(&source_trace),
        )
        .await
        .into_diagnostic()?;
    write_store_trace(store_path, &outcome.trace).await?;
    Ok(ReplayExecutionReport {
        mode,
        source_run_id: source_trace.run_id,
        replay_run_id: outcome.result.run_id.clone(),
        agent_id: outcome.result.agent_id.clone(),
        output_matches: source_output == outcome.result.output,
        result: outcome.result,
        trace: outcome.trace,
    })
}

fn deterministic_replay_report(source_trace: agent_core::AgentTrace) -> ReplayExecutionReport {
    let result = AgentRunResult {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        run_id: source_trace.run_id.clone(),
        agent_id: source_trace.agent_id.clone(),
        status: agent_core::AgentRunStatus::Completed,
        started_at: source_trace.started_at,
        finished_at: source_trace.finished_at,
        summary: Some("deterministic replay reused source trace output".to_owned()),
        output: source_trace.output.clone(),
        error: None,
    };
    ReplayExecutionReport {
        mode: ReplayMode::Deterministic,
        source_run_id: source_trace.run_id.clone(),
        replay_run_id: source_trace.run_id.clone(),
        agent_id: source_trace.agent_id.clone(),
        result,
        trace: source_trace,
        output_matches: true,
    }
}

fn run_request_from_trace(trace: &agent_core::AgentTrace) -> RunRequest {
    RunRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        run_id: None,
        input: trace.input.clone(),
        user: None,
        trigger: TriggerKind::Replay,
        metadata: json!({
            "source": "trace_replay",
            "source_run_id": trace.run_id.0
        }),
    }
}
