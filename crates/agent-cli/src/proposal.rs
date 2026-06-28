use agent_core::{
    AgentProposalStore, AgentRuntimeCatalog, AgentServices, ApprovalDecision, ApprovalDecisionKind,
    ProposalEnvelope, ProposalStatus, RunId, TraceEvent,
};
use camino::{Utf8Path, Utf8PathBuf};
use miette::{IntoDiagnostic, Result, miette};
use serde::Serialize;
use serde_json::{Value, json};

#[derive(Debug, Serialize)]
pub(crate) struct ProposalDecisionResponse {
    pub(crate) decision: ApprovalDecision,
    pub(crate) proposal: ProposalEnvelope,
}

#[derive(Debug, Serialize)]
pub(crate) struct ProposalActionResponse {
    pub(crate) action: String,
    pub(crate) tool: String,
    pub(crate) tool_output: Value,
    pub(crate) proposal: ProposalEnvelope,
}

#[derive(Debug, Clone, Copy)]
pub(crate) enum ProposalAction {
    Apply,
    Undo,
}

impl ProposalAction {
    fn as_str(self) -> &'static str {
        match self {
            Self::Apply => "apply",
            Self::Undo => "undo",
        }
    }

    fn required_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::Approved,
            Self::Undo => ProposalStatus::Applied,
        }
    }

    fn in_progress_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::Applying,
            Self::Undo => ProposalStatus::Undoing,
        }
    }

    fn success_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::Applied,
            Self::Undo => ProposalStatus::Undone,
        }
    }

    fn failure_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::ApplyFailed,
            Self::Undo => ProposalStatus::UndoFailed,
        }
    }
}

pub(crate) async fn execute_proposal_action_with_store(
    store: &dyn AgentProposalStore,
    services: &dyn AgentServices,
    proposal: &mut ProposalEnvelope,
    tool: String,
    action: ProposalAction,
) -> Result<ProposalActionResponse> {
    let required = action.required_status();
    if proposal.status != required {
        return Err(miette!(
            "proposal '{}' must be {:?} before {} but is {:?}",
            proposal.proposal_id.0,
            required,
            action.as_str(),
            proposal.status
        ));
    }

    proposal.status = action.in_progress_status();
    store
        .update_proposal(proposal.clone())
        .await
        .into_diagnostic()?;

    let tool_input = json!({
        "action": action.as_str(),
        "proposal": proposal.clone(),
    });
    let tool_output = match services.call_tool(&tool, tool_input).await {
        Ok(output) => output,
        Err(err) => {
            proposal.status = action.failure_status();
            store
                .update_proposal(proposal.clone())
                .await
                .into_diagnostic()?;
            return Err(miette!(err.record.message));
        }
    };

    proposal.status = action.success_status();
    store
        .update_proposal(proposal.clone())
        .await
        .into_diagnostic()?;
    Ok(ProposalActionResponse {
        action: action.as_str().to_owned(),
        tool,
        tool_output,
        proposal: proposal.clone(),
    })
}

pub(crate) fn proposal_action_tool(catalog: &AgentRuntimeCatalog, kind: &str) -> Result<String> {
    catalog
        .proposal_kinds
        .iter()
        .find(|spec| spec.kind == kind)
        .map(|spec| spec.tool_name.clone())
        .ok_or_else(|| miette!("proposal kind '{kind}' is not present in the active catalog"))
}

pub(crate) async fn append_proposal_created_trace_event(
    store_path: &Utf8Path,
    proposal: &ProposalEnvelope,
) -> Result<()> {
    append_store_trace_event(
        store_path,
        &proposal.run_id,
        TraceEvent::new(
            "proposal_created",
            json!({
                "proposal_id": proposal.proposal_id.0.clone(),
                "run_id": proposal.run_id.0.clone(),
                "agent_id": proposal.agent_id.clone(),
                "kind": proposal.kind.clone(),
                "summary": proposal.summary.clone(),
                "status": proposal.status.clone(),
            }),
        ),
    )
    .await
}

pub(crate) async fn append_proposal_decision_trace_event(
    store_path: &Utf8Path,
    response: &ProposalDecisionResponse,
) -> Result<()> {
    append_store_trace_event(
        store_path,
        &response.proposal.run_id,
        TraceEvent::new(
            "proposal_decided",
            json!({
                "proposal_id": response.proposal.proposal_id.0.clone(),
                "run_id": response.proposal.run_id.0.clone(),
                "agent_id": response.proposal.agent_id.clone(),
                "kind": response.proposal.kind.clone(),
                "decision": response.decision.decision.clone(),
                "status": response.proposal.status.clone(),
                "comment": response.decision.comment.clone(),
            }),
        ),
    )
    .await
}

pub(crate) async fn append_proposal_action_trace_event(
    store_path: &Utf8Path,
    response: &ProposalActionResponse,
) -> Result<()> {
    let event_kind = match response.action.as_str() {
        "apply" => "proposal_applied",
        "undo" => "proposal_undone",
        _ => "proposal_action_finished",
    };
    append_store_trace_event(
        store_path,
        &response.proposal.run_id,
        TraceEvent::new(
            event_kind,
            json!({
                "proposal_id": response.proposal.proposal_id.0.clone(),
                "run_id": response.proposal.run_id.0.clone(),
                "agent_id": response.proposal.agent_id.clone(),
                "kind": response.proposal.kind.clone(),
                "action": response.action,
                "status": response.proposal.status.clone(),
                "tool": response.tool.clone(),
                "tool_output": response.tool_output.clone(),
            }),
        ),
    )
    .await
}

pub(crate) fn parse_approval_decision(value: &str) -> Result<ApprovalDecisionKind> {
    match value {
        "approve" | "approved" => Ok(ApprovalDecisionKind::Approve),
        "deny" | "denied" => Ok(ApprovalDecisionKind::Deny),
        other => Err(miette!(
            "unsupported approval decision '{other}', expected approve or deny"
        )),
    }
}

async fn append_store_trace_event(
    store: &Utf8Path,
    run_id: &RunId,
    event: TraceEvent,
) -> Result<()> {
    let Some(mut trace) = read_store_trace(store, run_id).await? else {
        return Ok(());
    };
    let events = trace
        .get_mut("events")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| miette!("trace for run '{}' has no events array", run_id.0))?;
    events.push(serde_json::to_value(event).into_diagnostic()?);
    write_json_file(store_trace_path(store, run_id), &trace).await
}

async fn read_store_trace(store: &Utf8Path, run_id: &RunId) -> Result<Option<Value>> {
    let path = store_trace_path(store, run_id);
    if !path.exists() {
        return Ok(None);
    }
    read_json_file(path).await.map(Some)
}

fn store_trace_path(store: &Utf8Path, run_id: &RunId) -> Utf8PathBuf {
    store
        .join("traces")
        .join(format!("{}.trace.json", run_id.0))
}

async fn read_json_file(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
}

async fn write_json_file(path: Utf8PathBuf, value: &impl Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    let bytes = serde_json::to_vec_pretty(value).into_diagnostic()?;
    fs_err::tokio::write(&path, bytes)
        .await
        .map_err(|e| miette!("failed to write JSON at {path}: {e}"))
}
