use std::collections::BTreeMap;

use agent_core::{AgentProposalStore, AgentRunStore, PROTOCOL_VERSION, ProposalStatus};
use agent_runtime::RUNTIME_VERSION;
use agent_store::{FileProposalStore, FileRunStore};
use camino::Utf8Path;
use miette::{IntoDiagnostic, Result};
use serde::Serialize;
use serde_json::Value;
use time::format_description::well_known::Rfc3339;

use crate::trace_store::read_store_trace;

#[derive(Debug, Serialize)]
pub(crate) struct RuntimeMetricsSummary {
    protocol_version: String,
    runtime_version: String,
    generated_at: String,
    store_root: String,
    run_count: usize,
    runs_by_status: BTreeMap<String, usize>,
    successful_run_count: usize,
    skipped_run_count: usize,
    failed_run_count: usize,
    timeout_count: usize,
    total_run_latency_ms: u64,
    average_run_latency_ms: Option<f64>,
    tool_call_count: usize,
    failed_tool_call_count: usize,
    total_tool_call_latency_ms: u64,
    average_tool_call_latency_ms: Option<f64>,
    replay_count: usize,
    proposal_count: usize,
    proposals_by_status: BTreeMap<String, usize>,
    proposal_created_count: usize,
    proposal_approved_count: usize,
    proposal_denied_count: usize,
    proposal_applied_count: usize,
    llm_total_tokens: u64,
}

pub(crate) async fn build_metrics_summary(
    store_path: &Utf8Path,
    run_store: &FileRunStore,
    proposal_store: &FileProposalStore,
) -> Result<RuntimeMetricsSummary> {
    let runs = run_store.list_runs(None, None).await.into_diagnostic()?;
    let proposals = proposal_store
        .list_proposals(None)
        .await
        .into_diagnostic()?;
    let mut runs_by_status = BTreeMap::new();
    let mut total_run_latency_ms = 0_u64;
    let mut completed_latency_count = 0_u64;
    let mut tool_call_count = 0_usize;
    let mut failed_tool_call_count = 0_usize;
    let mut total_tool_call_latency_ms = 0_u64;
    let mut replay_count = 0_usize;
    let mut llm_total_tokens = 0_u64;
    let mut proposal_created_count = 0_usize;
    let mut proposal_approved_count = 0_usize;
    let mut proposal_denied_count = 0_usize;
    let mut proposal_applied_count = 0_usize;

    for run in &runs {
        *runs_by_status
            .entry(run_status_key(&run.status))
            .or_insert(0) += 1;
        if let Some(finished_at) = run.finished_at {
            let latency_ms = (finished_at - run.started_at).whole_milliseconds();
            if latency_ms >= 0 {
                total_run_latency_ms =
                    total_run_latency_ms.saturating_add(u64::try_from(latency_ms).unwrap_or(0));
                completed_latency_count = completed_latency_count.saturating_add(1);
            }
        }
        if let Some(trace) = read_store_trace(store_path, &run.run_id).await? {
            if trace_started_by_replay(&trace) {
                replay_count += 1;
            }
            for event in event_records_from_trace(&trace) {
                let kind = event.get("kind").and_then(Value::as_str);
                let payload = event.get("payload").unwrap_or(&Value::Null);
                match kind {
                    Some("tool_call_finished") => {
                        tool_call_count += 1;
                        total_tool_call_latency_ms =
                            total_tool_call_latency_ms.saturating_add(payload_duration_ms(payload));
                    }
                    Some("tool_call_failed") => {
                        tool_call_count += 1;
                        failed_tool_call_count += 1;
                        total_tool_call_latency_ms =
                            total_tool_call_latency_ms.saturating_add(payload_duration_ms(payload));
                    }
                    Some("llm_response") | Some("llm.round.finished") => {
                        llm_total_tokens =
                            llm_total_tokens.saturating_add(payload_total_tokens(payload));
                    }
                    Some("proposal_created") => {
                        proposal_created_count += 1;
                    }
                    Some("proposal_decided") => {
                        match payload.get("decision").and_then(Value::as_str) {
                            Some("approve" | "approved") => proposal_approved_count += 1,
                            Some("deny" | "denied") => proposal_denied_count += 1,
                            _ => {}
                        }
                    }
                    Some("proposal_applied") => {
                        proposal_applied_count += 1;
                    }
                    _ => {}
                }
            }
        }
    }

    let mut proposals_by_status = BTreeMap::new();
    for proposal in &proposals {
        *proposals_by_status
            .entry(proposal_status_key(&proposal.status))
            .or_insert(0) += 1;
    }
    if proposal_created_count == 0 {
        proposal_created_count = proposals.len();
    }
    if proposal_approved_count == 0 {
        proposal_approved_count = count_run_status(&proposals_by_status, "approved");
    }
    if proposal_denied_count == 0 {
        proposal_denied_count = count_run_status(&proposals_by_status, "denied");
    }
    if proposal_applied_count == 0 {
        proposal_applied_count = count_run_status(&proposals_by_status, "applied");
    }
    let generated_at = time::OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .into_diagnostic()?;
    Ok(RuntimeMetricsSummary {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        runtime_version: RUNTIME_VERSION.to_owned(),
        generated_at,
        store_root: store_path.to_string(),
        run_count: runs.len(),
        successful_run_count: count_run_status(&runs_by_status, "completed"),
        skipped_run_count: count_run_status(&runs_by_status, "skipped"),
        failed_run_count: count_failure_runs(&runs_by_status),
        timeout_count: count_run_status(&runs_by_status, "timed_out"),
        total_run_latency_ms,
        average_run_latency_ms: average_ms(total_run_latency_ms, completed_latency_count),
        tool_call_count,
        failed_tool_call_count,
        total_tool_call_latency_ms,
        average_tool_call_latency_ms: average_ms(
            total_tool_call_latency_ms,
            tool_call_count as u64,
        ),
        replay_count,
        proposal_count: proposals.len(),
        proposal_created_count,
        proposal_approved_count,
        proposal_denied_count,
        proposal_applied_count,
        proposals_by_status,
        runs_by_status,
        llm_total_tokens,
    })
}

fn run_status_key(status: &agent_core::AgentRunStatus) -> String {
    serde_json::to_value(status)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| format!("{status:?}"))
}

fn proposal_status_key(status: &ProposalStatus) -> String {
    serde_json::to_value(status)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| format!("{status:?}"))
}

fn count_run_status(counts: &BTreeMap<String, usize>, status: &str) -> usize {
    counts.get(status).copied().unwrap_or(0)
}

fn count_failure_runs(counts: &BTreeMap<String, usize>) -> usize {
    ["failed", "cancelled", "timed_out", "abandoned"]
        .iter()
        .map(|status| count_run_status(counts, status))
        .sum()
}

fn average_ms(total: u64, count: u64) -> Option<f64> {
    (count > 0).then(|| total as f64 / count as f64)
}

fn payload_duration_ms(payload: &Value) -> u64 {
    payload
        .get("duration_ms")
        .and_then(Value::as_u64)
        .unwrap_or(0)
}

fn payload_total_tokens(payload: &Value) -> u64 {
    payload
        .get("usage")
        .and_then(|usage| usage.get("total_tokens"))
        .or_else(|| payload.get("total_tokens"))
        .and_then(Value::as_u64)
        .unwrap_or(0)
}

fn trace_started_by_replay(trace: &Value) -> bool {
    trace
        .get("events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .any(|event| {
            event.get("kind").and_then(Value::as_str) == Some("run_started")
                && event
                    .get("payload")
                    .and_then(|payload| payload.get("trigger"))
                    .and_then(Value::as_str)
                    == Some("replay")
        })
}

pub(crate) fn event_records_from_trace(trace: &Value) -> Vec<Value> {
    trace
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}
