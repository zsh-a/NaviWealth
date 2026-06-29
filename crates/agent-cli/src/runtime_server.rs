use std::sync::Arc;

use agent_core::{
    AgentProposalStore, AgentRunRecord, AgentRunResult, AgentRunStore, AgentRuntimeCatalog,
    AgentServices, AgentSessionStore, ApprovalDecision, ApprovalDecisionKind, PROTOCOL_VERSION,
    ProposalEnvelope, ProposalId, ProposalStatus, RunId, RunRequest, SessionId, SessionRecord,
    ThreadId, ThreadRecord,
};
use agent_runtime::AgentRunner;
use agent_store::{FileProposalStore, FileRunStore, FileSessionStore};
use camino::Utf8PathBuf;
use miette::{IntoDiagnostic, Result, miette};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{
    catalog::{read_catalog, registry_from_catalog},
    metrics::{RuntimeMetricsSummary, build_metrics_summary},
    proposal::{
        ProposalAction, ProposalActionResponse, ProposalDecisionResponse,
        append_proposal_action_trace_event, append_proposal_created_trace_event,
        append_proposal_decision_trace_event, execute_proposal_action_with_store,
        parse_approval_decision, proposal_action_tool,
    },
    replay::{ReplayExecutionReport, ReplayMode, replay_source_trace},
    session::{
        HttpSessionCreateParams, HttpSessionCreateResponse, HttpThreadForkParams,
        SessionShowReport, ThreadForkReport, ThreadWithSteps, record_session_step, run_metadata,
    },
    tools::{CliServices, ToolOverrides},
    trace_store::{read_store_trace, write_store_trace},
};

#[derive(Clone)]
pub(crate) struct RuntimeServer {
    pub(crate) catalog: Arc<AgentRuntimeCatalog>,
    runner: Arc<AgentRunner>,
    services: Arc<CliServices>,
    run_store: Arc<FileRunStore>,
    proposal_store: Arc<FileProposalStore>,
    session_store: Arc<FileSessionStore>,
    store_path: Utf8PathBuf,
}

#[derive(Debug, Serialize)]
pub(crate) struct AgentRunResponse {
    pub(crate) result: AgentRunResult,
    pub(crate) trace: agent_core::AgentTrace,
}

#[derive(Debug, Serialize)]
pub(crate) struct ToolCallResponse {
    tool: String,
    output: Value,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpProposalCreateParams {
    pub(crate) run_id: String,
    pub(crate) agent_id: String,
    pub(crate) kind: String,
    pub(crate) summary: String,
    #[serde(default)]
    pub(crate) payload: Value,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpProposalListParams {
    #[serde(default)]
    pub(crate) run_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpRunListParams {
    #[serde(default)]
    pub(crate) agent_id: Option<String>,
    #[serde(default)]
    pub(crate) limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpProposalDecisionParams {
    pub(crate) decision: String,
    #[serde(default)]
    pub(crate) comment: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct AgentRunParams {
    pub(crate) agent_id: String,
    #[serde(default)]
    pub(crate) input: Value,
    #[serde(default)]
    pub(crate) session_id: Option<String>,
    #[serde(default)]
    pub(crate) thread_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpAgentRunParams {
    #[serde(default)]
    pub(crate) input: Value,
    #[serde(default)]
    pub(crate) session_id: Option<String>,
    #[serde(default)]
    pub(crate) thread_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpToolCallParams {
    #[serde(default)]
    pub(crate) input: Value,
}

impl RuntimeServer {
    pub(crate) async fn new(
        catalog_path: Utf8PathBuf,
        store_path: Utf8PathBuf,
        tool_overrides: ToolOverrides,
    ) -> Result<Self> {
        let mut catalog = read_catalog(catalog_path).await?;
        catalog.tools.extend(tool_overrides.source_specs.clone());
        let catalog = Arc::new(catalog);
        let registry = registry_from_catalog(&catalog);
        let store = Arc::new(
            FileRunStore::new(store_path.clone())
                .await
                .into_diagnostic()?,
        );
        let proposal_store = Arc::new(
            FileProposalStore::new(store_path.clone())
                .await
                .into_diagnostic()?,
        );
        let services = Arc::new(CliServices::with_proposal_store(
            tool_overrides,
            proposal_store.clone(),
        ));
        let runner = Arc::new(AgentRunner::new(registry, store.clone(), services.clone()));
        let session_store = Arc::new(
            FileSessionStore::new(store_path.clone())
                .await
                .into_diagnostic()?,
        );
        Ok(Self {
            catalog,
            runner,
            services,
            run_store: store,
            proposal_store,
            session_store,
            store_path,
        })
    }

    pub(crate) async fn run_agent(
        &self,
        agent_id: String,
        input: Value,
        session_id: Option<String>,
        thread_id: Option<String>,
    ) -> Result<AgentRunResponse> {
        let outcome = self
            .runner
            .run_once(
                &agent_id,
                RunRequest {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    run_id: None,
                    input,
                    user: None,
                    trigger: agent_core::TriggerKind::Manual,
                    metadata: run_metadata(session_id.as_deref(), thread_id.as_deref()),
                },
            )
            .await
            .into_diagnostic()?;
        record_session_step(&self.store_path, thread_id.as_deref(), &outcome).await?;
        write_store_trace(&self.store_path, &outcome.trace).await?;
        Ok(AgentRunResponse {
            result: outcome.result,
            trace: outcome.trace,
        })
    }

    pub(crate) async fn call_tool(&self, name: String, input: Value) -> Result<ToolCallResponse> {
        ensure_catalog_has_tool(&self.catalog, &name)?;
        let output = self
            .services
            .call_tool(&name, input)
            .await
            .map_err(|err| miette!(err.record.message))?;
        Ok(ToolCallResponse { tool: name, output })
    }

    pub(crate) async fn get_run(&self, run_id: RunId) -> Result<AgentRunRecord> {
        self.run_store
            .get_run(&run_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("run '{}' was not found", run_id.0))
    }

    pub(crate) async fn list_runs(
        &self,
        agent_id: Option<String>,
        limit: Option<usize>,
    ) -> Result<Vec<AgentRunRecord>> {
        self.run_store
            .list_runs(agent_id.as_deref(), limit)
            .await
            .into_diagnostic()
    }

    pub(crate) async fn get_run_trace(&self, run_id: RunId) -> Result<Value> {
        read_store_trace(&self.store_path, &run_id)
            .await?
            .ok_or_else(|| miette!("trace for run '{}' was not found", run_id.0))
    }

    pub(crate) async fn replay_run(&self, run_id: RunId) -> Result<ReplayExecutionReport> {
        let trace_value = self.get_run_trace(run_id.clone()).await?;
        let source_trace: agent_core::AgentTrace = serde_json::from_value(trace_value)
            .map_err(|e| miette!("failed to parse trace for run '{}': {e}", run_id.0))?;
        replay_source_trace(
            self.runner.as_ref(),
            &self.store_path,
            source_trace,
            ReplayMode::Live,
        )
        .await
    }

    pub(crate) async fn metrics_summary(&self) -> Result<RuntimeMetricsSummary> {
        build_metrics_summary(
            &self.store_path,
            self.run_store.as_ref(),
            self.proposal_store.as_ref(),
        )
        .await
    }

    pub(crate) async fn create_proposal(
        &self,
        params: HttpProposalCreateParams,
    ) -> Result<ProposalEnvelope> {
        let proposal = ProposalEnvelope::new(
            RunId(params.run_id),
            params.agent_id,
            params.kind,
            params.summary,
            params.payload,
        );
        self.proposal_store
            .create_proposal(proposal.clone())
            .await
            .into_diagnostic()?;
        append_proposal_created_trace_event(&self.store_path, &proposal).await?;
        Ok(proposal)
    }

    pub(crate) async fn list_proposals(
        &self,
        run_id: Option<String>,
    ) -> Result<Vec<ProposalEnvelope>> {
        let run_id = run_id.map(RunId);
        self.proposal_store
            .list_proposals(run_id.as_ref())
            .await
            .into_diagnostic()
    }

    pub(crate) async fn create_session(
        &self,
        params: HttpSessionCreateParams,
    ) -> Result<HttpSessionCreateResponse> {
        if params.title.trim().is_empty() {
            return Err(miette!("session title cannot be empty"));
        }
        let session = SessionRecord::new(params.title.clone(), params.metadata);
        let thread = ThreadRecord::root(
            session.session_id.clone(),
            Some(params.title),
            json!({"source": "http"}),
        );
        self.session_store
            .create_session(session.clone())
            .await
            .into_diagnostic()?;
        self.session_store
            .create_thread(thread.clone())
            .await
            .into_diagnostic()?;
        Ok(HttpSessionCreateResponse { session, thread })
    }

    pub(crate) async fn list_sessions(&self) -> Result<Vec<SessionRecord>> {
        self.session_store.list_sessions().await.into_diagnostic()
    }

    pub(crate) async fn show_session(&self, session_id: SessionId) -> Result<SessionShowReport> {
        let session = self
            .session_store
            .get_session(&session_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
        let mut threads = Vec::new();
        for thread in self
            .session_store
            .list_threads(&session.session_id)
            .await
            .into_diagnostic()?
        {
            let steps = self
                .session_store
                .list_steps(&thread.thread_id)
                .await
                .into_diagnostic()?;
            threads.push(ThreadWithSteps { thread, steps });
        }
        Ok(SessionShowReport { session, threads })
    }

    pub(crate) async fn fork_thread(
        &self,
        session_id: SessionId,
        params: HttpThreadForkParams,
    ) -> Result<ThreadForkReport> {
        self.session_store
            .get_session(&session_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
        let parent_thread_id = ThreadId(params.parent_thread_id);
        let parent = self
            .session_store
            .get_thread(&parent_thread_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("thread '{}' was not found", parent_thread_id.0))?;
        if parent.session_id != session_id {
            return Err(miette!(
                "thread '{}' does not belong to session '{}'",
                parent_thread_id.0,
                session_id.0
            ));
        }
        let thread = ThreadRecord::fork(
            session_id.clone(),
            parent_thread_id.clone(),
            params.title,
            params.metadata,
        );
        self.session_store
            .create_thread(thread.clone())
            .await
            .into_diagnostic()?;
        Ok(ThreadForkReport {
            session_id: session_id.0,
            parent_thread_id: parent_thread_id.0,
            thread,
        })
    }

    pub(crate) async fn get_proposal(&self, proposal_id: ProposalId) -> Result<ProposalEnvelope> {
        self.proposal_store
            .get_proposal(&proposal_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("proposal '{}' was not found", proposal_id.0))
    }

    pub(crate) async fn decide_proposal(
        &self,
        proposal_id: ProposalId,
        params: HttpProposalDecisionParams,
    ) -> Result<ProposalDecisionResponse> {
        let mut proposal = self.get_proposal(proposal_id.clone()).await?;
        let decision = parse_approval_decision(&params.decision)?;
        proposal.status = match decision {
            ApprovalDecisionKind::Approve => ProposalStatus::Approved,
            ApprovalDecisionKind::Deny => ProposalStatus::Denied,
        };
        self.proposal_store
            .update_proposal(proposal.clone())
            .await
            .into_diagnostic()?;
        let response = ProposalDecisionResponse {
            decision: ApprovalDecision {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                proposal_id,
                decision,
                decided_at: time::OffsetDateTime::now_utc(),
                comment: params.comment,
            },
            proposal,
        };
        append_proposal_decision_trace_event(&self.store_path, &response).await?;
        Ok(response)
    }

    pub(crate) async fn apply_proposal(
        &self,
        proposal_id: ProposalId,
    ) -> Result<ProposalActionResponse> {
        self.execute_proposal_action(proposal_id, ProposalAction::Apply)
            .await
    }

    pub(crate) async fn undo_proposal(
        &self,
        proposal_id: ProposalId,
    ) -> Result<ProposalActionResponse> {
        self.execute_proposal_action(proposal_id, ProposalAction::Undo)
            .await
    }

    async fn execute_proposal_action(
        &self,
        proposal_id: ProposalId,
        action: ProposalAction,
    ) -> Result<ProposalActionResponse> {
        let mut proposal = self.get_proposal(proposal_id).await?;
        let tool = proposal_action_tool(&self.catalog, &proposal.kind)?;
        let response = execute_proposal_action_with_store(
            self.proposal_store.as_ref(),
            self.services.as_ref(),
            &mut proposal,
            tool,
            action,
        )
        .await?;
        append_proposal_action_trace_event(&self.store_path, &response).await?;
        Ok(response)
    }
}

fn ensure_catalog_has_tool(catalog: &AgentRuntimeCatalog, name: &str) -> Result<()> {
    if catalog.tools.iter().any(|tool| tool.name == name) {
        return Ok(());
    }
    Err(miette!(
        "tool '{name}' is not present in the active catalog"
    ))
}
