use std::{sync::Arc, time::Duration};

use async_trait::async_trait;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use thiserror::Error;
use time::OffsetDateTime;
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

pub const PROTOCOL_VERSION: &str = "agent.v1";
pub const CATALOG_VERSION: &str = "agent_catalog.v1";

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(transparent)]
pub struct RunId(pub String);

impl RunId {
    pub fn new_v7() -> Self {
        Self(format!("run_{}", Uuid::now_v7()))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(transparent)]
pub struct SessionId(pub String);

impl SessionId {
    pub fn new_v7() -> Self {
        Self(format!("session_{}", Uuid::now_v7()))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(transparent)]
pub struct ThreadId(pub String);

impl ThreadId {
    pub fn new_v7() -> Self {
        Self(format!("thread_{}", Uuid::now_v7()))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(transparent)]
pub struct StepId(pub String);

impl StepId {
    pub fn new_v7() -> Self {
        Self(format!("step_{}", Uuid::now_v7()))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(transparent)]
pub struct ProposalId(pub String);

impl ProposalId {
    pub fn new_v7() -> Self {
        Self(format!("proposal_{}", Uuid::now_v7()))
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(transparent)]
pub struct ToolCallId(pub String);

impl ToolCallId {
    pub fn new_v7() -> Self {
        Self(format!("tool_{}", Uuid::now_v7()))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct AgentSpec {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub version: String,
    pub schedule: ScheduleSpec,
    #[serde(default)]
    pub capabilities: Vec<String>,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ScheduleSpec {
    Manual,
    Interval {
        every_seconds: u64,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        preferred_hour_local: Option<u8>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        jitter_seconds: Option<u64>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct UserContext {
    pub user_id: String,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum TriggerKind {
    Manual,
    Scheduled,
    Replay,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct RunRequest {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_id: Option<RunId>,
    #[serde(default)]
    pub input: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub user: Option<UserContext>,
    #[serde(default = "default_trigger")]
    pub trigger: TriggerKind,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AgentRunStatus {
    Running,
    Completed,
    Skipped,
    Failed,
    Cancelled,
    TimedOut,
    Abandoned,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct AgentRunResult {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub run_id: RunId,
    pub agent_id: String,
    pub status: AgentRunStatus,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub started_at: OffsetDateTime,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub finished_at: OffsetDateTime,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(default)]
    pub output: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<AgentErrorRecord>,
}

impl AgentRunResult {
    pub fn completed(
        run_id: RunId,
        agent_id: impl Into<String>,
        started_at: OffsetDateTime,
        output: Value,
        summary: Option<String>,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            run_id,
            agent_id: agent_id.into(),
            status: AgentRunStatus::Completed,
            started_at,
            finished_at: OffsetDateTime::now_utc(),
            summary,
            output,
            error: None,
        }
    }

    pub fn skipped(
        run_id: RunId,
        agent_id: impl Into<String>,
        started_at: OffsetDateTime,
        reason: Option<String>,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            run_id,
            agent_id: agent_id.into(),
            status: AgentRunStatus::Skipped,
            started_at,
            finished_at: OffsetDateTime::now_utc(),
            summary: reason,
            output: json!({}),
            error: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct AgentRunRecord {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub run_id: RunId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub idempotency_key: Option<String>,
    pub agent_id: String,
    pub status: AgentRunStatus,
    pub scope: RunScope,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub started_at: OffsetDateTime,
    #[schemars(with = "Option<String>")]
    #[serde(default, with = "time::serde::rfc3339::option")]
    pub finished_at: Option<OffsetDateTime>,
    #[serde(default)]
    pub input: Value,
    #[serde(default)]
    pub output: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<AgentErrorRecord>,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct RunLease {
    pub key: String,
    pub owner: String,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub acquired_at: OffsetDateTime,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub expires_at: OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type", content = "id", rename_all = "snake_case")]
pub enum RunScope {
    Global,
    User(String),
    Tenant(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum AgentErrorKind {
    ValidationError,
    ToolError,
    LlmError,
    Timeout,
    Cancelled,
    ApprovalRequired,
    TransientExternalError,
    InternalError,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct AgentErrorRecord {
    pub kind: AgentErrorKind,
    pub code: String,
    pub message: String,
    pub retryable: bool,
    #[serde(default)]
    pub details: Value,
}

#[derive(Debug, Error)]
#[error("{record:?}")]
pub struct AgentError {
    pub record: AgentErrorRecord,
}

impl AgentError {
    pub fn internal(message: impl Into<String>) -> Self {
        Self {
            record: AgentErrorRecord {
                kind: AgentErrorKind::InternalError,
                code: "internal_error".to_owned(),
                message: message.into(),
                retryable: false,
                details: json!({}),
            },
        }
    }

    pub fn validation(message: impl Into<String>) -> Self {
        Self {
            record: AgentErrorRecord {
                kind: AgentErrorKind::ValidationError,
                code: "validation_error".to_owned(),
                message: message.into(),
                retryable: false,
                details: json!({}),
            },
        }
    }

    pub fn timeout(duration: Duration) -> Self {
        Self {
            record: AgentErrorRecord {
                kind: AgentErrorKind::Timeout,
                code: "timeout".to_owned(),
                message: format!("agent run timed out after {}ms", duration.as_millis()),
                retryable: true,
                details: json!({"timeout_ms": duration.as_millis()}),
            },
        }
    }
}

#[derive(Debug, Error)]
#[error("{message}")]
pub struct StoreError {
    pub message: String,
}

impl StoreError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

#[derive(Debug, Error)]
#[error("{record:?}")]
pub struct ToolError {
    pub record: AgentErrorRecord,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_schema: Option<Value>,
    pub risk: ToolRisk,
    #[serde(default)]
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ToolRisk {
    ReadOnly,
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct AgentRuntimeCatalog {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    #[serde(default = "catalog_version")]
    pub catalog_version: String,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub generated_at: OffsetDateTime,
    #[serde(default)]
    pub active_domains: Vec<String>,
    #[serde(default)]
    pub agents: Vec<AgentSpec>,
    #[serde(default)]
    pub tools: Vec<ToolSpec>,
    #[serde(default)]
    pub proposal_kinds: Vec<ProposalKindSpec>,
    #[serde(default)]
    pub prompt_blocks: Vec<PromptBlockSpec>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SessionRecord {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub session_id: SessionId,
    pub title: String,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub updated_at: OffsetDateTime,
    #[serde(default)]
    pub metadata: Value,
}

impl SessionRecord {
    pub fn new(title: impl Into<String>, metadata: Value) -> Self {
        let now = OffsetDateTime::now_utc();
        Self {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            session_id: SessionId::new_v7(),
            title: title.into(),
            created_at: now,
            updated_at: now,
            metadata,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ThreadRecord {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub thread_id: ThreadId,
    pub session_id: SessionId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_thread_id: Option<ThreadId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[serde(default)]
    pub metadata: Value,
}

impl ThreadRecord {
    pub fn root(session_id: SessionId, title: Option<String>, metadata: Value) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            thread_id: ThreadId::new_v7(),
            session_id,
            parent_thread_id: None,
            title,
            created_at: OffsetDateTime::now_utc(),
            metadata,
        }
    }

    pub fn fork(
        session_id: SessionId,
        parent_thread_id: ThreadId,
        title: Option<String>,
        metadata: Value,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            thread_id: ThreadId::new_v7(),
            session_id,
            parent_thread_id: Some(parent_thread_id),
            title,
            created_at: OffsetDateTime::now_utc(),
            metadata,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum StepKind {
    AgentRun,
    LlmRound,
    ToolCall,
    Proposal,
    Approval,
    StateUpdate,
    Note,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct StepRecord {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub step_id: StepId,
    pub thread_id: ThreadId,
    pub kind: StepKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_id: Option<RunId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(default)]
    pub payload: Value,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
}

impl StepRecord {
    pub fn agent_run(
        thread_id: ThreadId,
        run_id: RunId,
        summary: Option<String>,
        payload: Value,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            step_id: StepId::new_v7(),
            thread_id,
            kind: StepKind::AgentRun,
            run_id: Some(run_id),
            summary,
            payload,
            created_at: OffsetDateTime::now_utc(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ProposalKindSpec {
    pub kind: String,
    pub tool_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ProposalStatus {
    Created,
    PendingApproval,
    Approved,
    Denied,
    Expired,
    Applying,
    Applied,
    ApplyFailed,
    Undoing,
    Undone,
    UndoFailed,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ProposalEnvelope {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub proposal_id: ProposalId,
    pub run_id: RunId,
    pub agent_id: String,
    pub kind: String,
    pub summary: String,
    #[serde(default)]
    pub payload: Value,
    pub status: ProposalStatus,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub created_at: OffsetDateTime,
    #[schemars(with = "Option<String>")]
    #[serde(default, with = "time::serde::rfc3339::option")]
    pub expires_at: Option<OffsetDateTime>,
}

impl ProposalEnvelope {
    pub fn new(
        run_id: RunId,
        agent_id: impl Into<String>,
        kind: impl Into<String>,
        summary: impl Into<String>,
        payload: Value,
    ) -> Self {
        Self {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            proposal_id: ProposalId::new_v7(),
            run_id,
            agent_id: agent_id.into(),
            kind: kind.into(),
            summary: summary.into(),
            payload,
            status: ProposalStatus::PendingApproval,
            created_at: OffsetDateTime::now_utc(),
            expires_at: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ApprovalDecision {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub proposal_id: ProposalId,
    pub decision: ApprovalDecisionKind,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub decided_at: OffsetDateTime,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ApprovalDecisionKind {
    Approve,
    Deny,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct PromptBlockSpec {
    pub index: u32,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct PromptManifest {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub id: String,
    pub version: String,
    pub agent_id: String,
    pub agent_version: String,
    pub catalog_version: String,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub generated_at: OffsetDateTime,
    pub model_family: String,
    pub provider: String,
    pub model: String,
    pub tool_schema_version: String,
    #[serde(default)]
    pub active_domains: Vec<String>,
    #[serde(default)]
    pub blocks: Vec<PromptManifestBlock>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct PromptManifestBlock {
    pub index: u32,
    pub source: String,
    pub content_hash: String,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ToolContext {
    pub run_id: RunId,
    pub agent_id: String,
    pub user: Option<UserContext>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct AgentEvent {
    pub kind: String,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub occurred_at: OffsetDateTime,
    #[serde(default)]
    pub payload: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct TraceEvent {
    pub kind: String,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub occurred_at: OffsetDateTime,
    #[serde(default)]
    pub payload: Value,
}

impl TraceEvent {
    pub fn new(kind: impl Into<String>, payload: Value) -> Self {
        Self {
            kind: kind.into(),
            occurred_at: OffsetDateTime::now_utc(),
            payload,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "PascalCase")]
pub enum HookEventName {
    SessionStart,
    SessionStop,
    RunStart,
    RunStop,
    BeforeAgentStep,
    AfterAgentStep,
    SubagentStart,
    SubagentStop,
    BeforeToolCall,
    AfterToolCall,
    BeforeProposalCreate,
    AfterProposalDecision,
    BeforeStateSave,
    AfterStateSave,
    BeforeCompact,
    AfterCompact,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum HookKind {
    NativeRust,
    Process,
    Server,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum HookInvocationStatus {
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct HookEvent {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub hook_event: HookEventName,
    pub hook_kind: HookKind,
    pub hook_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub command: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_id: Option<RunId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
    pub status: HookInvocationStatus,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub started_at: OffsetDateTime,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub finished_at: OffsetDateTime,
    pub duration_ms: u64,
    #[serde(default)]
    pub input: Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct AgentTrace {
    #[serde(default = "protocol_version")]
    pub protocol_version: String,
    pub runtime_version: String,
    pub run_id: RunId,
    pub agent_id: String,
    pub agent_version: String,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub started_at: OffsetDateTime,
    #[schemars(with = "String")]
    #[serde(with = "time::serde::rfc3339")]
    pub finished_at: OffsetDateTime,
    #[serde(default)]
    pub input: Value,
    #[serde(default)]
    pub output: Value,
    #[serde(default)]
    pub events: Vec<TraceEvent>,
}

#[derive(Clone)]
pub struct AgentContext {
    pub run_id: RunId,
    pub now: OffsetDateTime,
    pub user: Option<UserContext>,
    pub input: Value,
    pub services: Arc<dyn AgentServices>,
    pub cancellation: CancellationToken,
    pub trace: Arc<dyn TraceSink>,
}

#[async_trait]
pub trait Agent: Send + Sync {
    fn spec(&self) -> AgentSpec;
    async fn run(&self, ctx: AgentContext) -> Result<AgentRunResult, AgentError>;
}

#[async_trait]
pub trait AgentServices: Send + Sync {
    async fn call_tool(&self, name: &str, input: Value) -> Result<Value, ToolError>;
    async fn emit_event(&self, event: AgentEvent) -> Result<(), AgentError>;
    async fn load_state(&self, key: &str) -> Result<Option<Value>, AgentError>;
    async fn save_state(&self, key: &str, value: Value) -> Result<(), AgentError>;
    async fn create_proposal(&self, proposal: ProposalEnvelope) -> Result<(), AgentError> {
        let _ = proposal;
        Err(AgentError::validation(
            "proposal creation is not supported by this AgentServices implementation",
        ))
    }
}

#[async_trait]
pub trait AgentRegistry: Send + Sync {
    async fn list_agents(&self) -> Result<Vec<AgentSpec>, AgentError>;
    async fn get_agent(&self, id: &str) -> Result<Option<Arc<dyn Agent>>, AgentError>;
}

#[async_trait]
pub trait AgentRunStore: Send + Sync {
    async fn create_run(&self, run: AgentRunRecord) -> Result<(), StoreError>;
    async fn update_run(&self, run: AgentRunRecord) -> Result<(), StoreError>;
    async fn get_run(&self, run_id: &RunId) -> Result<Option<AgentRunRecord>, StoreError>;
    async fn list_runs(
        &self,
        agent_id: Option<&str>,
        limit: Option<usize>,
    ) -> Result<Vec<AgentRunRecord>, StoreError>;
    async fn last_run(
        &self,
        agent_id: &str,
        scope: &RunScope,
    ) -> Result<Option<AgentRunRecord>, StoreError>;
}

#[async_trait]
pub trait AgentLockStore: Send + Sync {
    async fn acquire(
        &self,
        key: &str,
        owner: &str,
        ttl: Duration,
    ) -> Result<Option<RunLease>, StoreError>;
    async fn renew(&self, lease: &RunLease, ttl: Duration) -> Result<(), StoreError>;
    async fn release(&self, lease: RunLease) -> Result<(), StoreError>;
}

#[async_trait]
pub trait AgentStateStore: Send + Sync {
    async fn load(&self, agent_id: &str, key: &str) -> Result<Option<Value>, StoreError>;
    async fn save(&self, agent_id: &str, key: &str, value: Value) -> Result<(), StoreError>;
}

#[async_trait]
pub trait AgentSessionStore: Send + Sync {
    async fn create_session(&self, session: SessionRecord) -> Result<(), StoreError>;
    async fn list_sessions(&self) -> Result<Vec<SessionRecord>, StoreError>;
    async fn get_session(
        &self,
        session_id: &SessionId,
    ) -> Result<Option<SessionRecord>, StoreError>;
    async fn create_thread(&self, thread: ThreadRecord) -> Result<(), StoreError>;
    async fn list_threads(&self, session_id: &SessionId) -> Result<Vec<ThreadRecord>, StoreError>;
    async fn get_thread(&self, thread_id: &ThreadId) -> Result<Option<ThreadRecord>, StoreError>;
    async fn create_step(&self, step: StepRecord) -> Result<(), StoreError>;
    async fn list_steps(&self, thread_id: &ThreadId) -> Result<Vec<StepRecord>, StoreError>;
}

#[async_trait]
pub trait AgentProposalStore: Send + Sync {
    async fn create_proposal(&self, proposal: ProposalEnvelope) -> Result<(), StoreError>;
    async fn update_proposal(&self, proposal: ProposalEnvelope) -> Result<(), StoreError>;
    async fn get_proposal(
        &self,
        proposal_id: &ProposalId,
    ) -> Result<Option<ProposalEnvelope>, StoreError>;
    async fn list_proposals(
        &self,
        run_id: Option<&RunId>,
    ) -> Result<Vec<ProposalEnvelope>, StoreError>;
}

#[async_trait]
pub trait TraceSink: Send + Sync {
    async fn emit(&self, event: TraceEvent) -> Result<(), AgentError>;
}

#[async_trait]
pub trait ToolRegistry: Send + Sync {
    async fn list_tools(&self) -> Result<Vec<ToolSpec>, ToolError>;
    async fn call(&self, name: &str, input: Value, ctx: ToolContext) -> Result<Value, ToolError>;
}

pub fn protocol_version() -> String {
    PROTOCOL_VERSION.to_owned()
}

pub fn catalog_version() -> String {
    CATALOG_VERSION.to_owned()
}

fn default_trigger() -> TriggerKind {
    TriggerKind::Manual
}
