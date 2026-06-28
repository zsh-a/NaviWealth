use std::{collections::HashMap, sync::Arc, time::Duration};

use agent_core::{
    Agent, AgentContext, AgentError, AgentErrorKind, AgentErrorRecord, AgentEvent, AgentLockStore,
    AgentRegistry, AgentRunRecord, AgentRunResult, AgentRunStatus, AgentRunStore, AgentServices,
    AgentSpec, AgentStateStore, AgentTrace, PROTOCOL_VERSION, RunId, RunLease, RunRequest,
    RunScope, ScheduleSpec, StoreError, ToolContext, ToolError, ToolRegistry, TraceEvent,
    TraceSink,
};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use time::OffsetDateTime;
use tokio::sync::{Mutex, Semaphore};
use tokio_util::sync::CancellationToken;

pub const RUNTIME_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Clone)]
pub struct ExecutionPolicy {
    pub timeout: Duration,
    pub max_retries: u32,
    pub retry_backoff: Duration,
    pub max_concurrent_runs: usize,
}

impl Default for ExecutionPolicy {
    fn default() -> Self {
        Self {
            timeout: Duration::from_secs(60),
            max_retries: 0,
            retry_backoff: Duration::ZERO,
            max_concurrent_runs: 1,
        }
    }
}

pub struct RunOutcome {
    pub result: AgentRunResult,
    pub trace: AgentTrace,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoveryReport {
    pub scanned_runs: usize,
    pub abandoned_count: usize,
    pub recovered_runs: Vec<RecoveredRun>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecoveredRun {
    pub run_id: RunId,
    pub agent_id: String,
    pub previous_status: AgentRunStatus,
    pub new_status: AgentRunStatus,
    #[serde(with = "time::serde::rfc3339")]
    pub started_at: OffsetDateTime,
    #[serde(with = "time::serde::rfc3339")]
    pub abandoned_at: OffsetDateTime,
    pub reason: String,
}

pub struct AgentRunner {
    registry: Arc<dyn AgentRegistry>,
    run_store: Arc<dyn AgentRunStore>,
    services: Arc<dyn AgentServices>,
    scheduler: AgentScheduler,
    policy: ExecutionPolicy,
    concurrency: Arc<Semaphore>,
    lock_store: Arc<dyn AgentLockStore>,
}

impl AgentRunner {
    pub fn new(
        registry: Arc<dyn AgentRegistry>,
        run_store: Arc<dyn AgentRunStore>,
        services: Arc<dyn AgentServices>,
    ) -> Self {
        Self {
            registry,
            run_store,
            services,
            scheduler: AgentScheduler,
            policy: ExecutionPolicy::default(),
            concurrency: Arc::new(Semaphore::new(
                ExecutionPolicy::default().max_concurrent_runs,
            )),
            lock_store: Arc::new(InMemoryLockStore::default()),
        }
    }

    pub fn with_policy(mut self, policy: ExecutionPolicy) -> Self {
        self.concurrency = Arc::new(Semaphore::new(policy.max_concurrent_runs.max(1)));
        self.policy = policy;
        self
    }

    pub fn with_lock_store(mut self, lock_store: Arc<dyn AgentLockStore>) -> Self {
        self.lock_store = lock_store;
        self
    }

    pub async fn recover_stale_runs(&self) -> Result<RecoveryReport, AgentError> {
        recover_stale_runs(self.run_store.as_ref(), &self.policy).await
    }

    pub async fn run_once(
        &self,
        agent_id: &str,
        request: RunRequest,
    ) -> Result<RunOutcome, AgentError> {
        let _permit = self
            .concurrency
            .clone()
            .acquire_owned()
            .await
            .map_err(|e| AgentError::internal(format!("run concurrency limiter closed: {e}")))?;
        let agent = self
            .registry
            .get_agent(agent_id)
            .await?
            .ok_or_else(|| AgentError::validation(format!("unknown agent '{agent_id}'")))?;
        let spec = agent.spec();
        let run_id = request.run_id.clone().unwrap_or_else(RunId::new_v7);
        let started_at = OffsetDateTime::now_utc();
        let scope = request
            .user
            .as_ref()
            .map(|u| RunScope::User(u.user_id.clone()))
            .unwrap_or(RunScope::Global);
        let idempotency_key = run_idempotency_key(&spec.id, &scope, &request);
        let lock_key = lock_key(&spec.id, &scope);
        let lease = self
            .lock_store
            .acquire(&lock_key, &run_id.0, self.policy.lease_ttl())
            .await
            .map_err(|e| AgentError::internal(e.to_string()))?;
        let Some(lease) = lease else {
            let reason = format!("run skipped because active lease exists for {lock_key}");
            let result = AgentRunResult::skipped(
                run_id.clone(),
                spec.id.clone(),
                started_at,
                Some(reason.clone()),
            );
            self.run_store
                .create_run(AgentRunRecord {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    run_id: run_id.clone(),
                    idempotency_key: Some(idempotency_key.clone()),
                    agent_id: spec.id.clone(),
                    status: AgentRunStatus::Skipped,
                    scope,
                    started_at,
                    finished_at: Some(result.finished_at),
                    input: request.input.clone(),
                    output: result.output.clone(),
                    error: None,
                    metadata: request.metadata.clone(),
                })
                .await
                .map_err(|e| AgentError::internal(e.to_string()))?;
            let trace_doc = AgentTrace {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                runtime_version: RUNTIME_VERSION.to_owned(),
                run_id,
                agent_id: spec.id,
                agent_version: spec.version,
                started_at,
                finished_at: result.finished_at,
                input: request.input,
                output: result.output.clone(),
                events: vec![TraceEvent::new(
                    "run_skipped",
                    json!({"reason": reason, "lock_key": lock_key}),
                )],
            };
            return Ok(RunOutcome {
                result,
                trace: trace_doc,
            });
        };
        self.run_store
            .create_run(AgentRunRecord {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                run_id: run_id.clone(),
                idempotency_key: Some(idempotency_key.clone()),
                agent_id: spec.id.clone(),
                status: AgentRunStatus::Running,
                scope: scope.clone(),
                started_at,
                finished_at: None,
                input: request.input.clone(),
                output: json!({}),
                error: None,
                metadata: request.metadata.clone(),
            })
            .await
            .map_err(|e| AgentError::internal(e.to_string()))?;

        let trace = Arc::new(MemoryTraceSink::default());
        trace
            .emit(TraceEvent::new(
                "run_started",
                json!({"run_id": run_id.0, "agent_id": spec.id, "trigger": request.trigger}),
            ))
            .await?;

        let mut result = self
            .run_with_retries(
                agent,
                &spec,
                run_id.clone(),
                started_at,
                request.clone(),
                trace.clone(),
            )
            .await?;
        result.finished_at = OffsetDateTime::now_utc();

        trace
            .emit(TraceEvent::new(
                "run_finished",
                json!({"run_id": result.run_id.0, "status": result.status}),
            ))
            .await?;

        self.run_store
            .update_run(AgentRunRecord {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                run_id: result.run_id.clone(),
                idempotency_key: Some(idempotency_key),
                agent_id: result.agent_id.clone(),
                status: result.status.clone(),
                scope,
                started_at,
                finished_at: Some(result.finished_at),
                input: request.input.clone(),
                output: result.output.clone(),
                error: result.error.clone(),
                metadata: request.metadata.clone(),
            })
            .await
            .map_err(|e| AgentError::internal(e.to_string()))?;

        let trace_doc = AgentTrace {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            runtime_version: RUNTIME_VERSION.to_owned(),
            run_id: result.run_id.clone(),
            agent_id: result.agent_id.clone(),
            agent_version: spec.version,
            started_at,
            finished_at: result.finished_at,
            input: request.input,
            output: result.output.clone(),
            events: trace.events().await,
        };

        self.lock_store
            .release(lease)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))?;

        Ok(RunOutcome {
            result,
            trace: trace_doc,
        })
    }

    async fn run_with_retries(
        &self,
        agent: Arc<dyn Agent>,
        spec: &AgentSpec,
        run_id: RunId,
        started_at: OffsetDateTime,
        request: RunRequest,
        trace: Arc<MemoryTraceSink>,
    ) -> Result<AgentRunResult, AgentError> {
        let max_attempts = self.policy.max_retries.saturating_add(1);
        let trace_attempts = self.policy.max_retries > 0;
        let mut attempt = 1_u32;

        loop {
            if trace_attempts {
                trace
                    .emit(TraceEvent::new(
                        "run_attempt_started",
                        json!({
                            "run_id": run_id.0.clone(),
                            "agent_id": spec.id.clone(),
                            "attempt": attempt,
                            "max_attempts": max_attempts,
                        }),
                    ))
                    .await?;
            }

            let ctx = AgentContext {
                run_id: run_id.clone(),
                now: started_at,
                user: request.user.clone(),
                input: request.input.clone(),
                services: Arc::new(TracedAgentServices {
                    inner: self.services.clone(),
                    trace: trace.clone(),
                    run_id: run_id.clone(),
                    agent_id: spec.id.clone(),
                }),
                cancellation: CancellationToken::new(),
                trace: trace.clone(),
            };

            let run_future = agent.run(ctx);
            let mut result = match tokio::time::timeout(self.policy.timeout, run_future).await {
                Ok(Ok(mut result)) => {
                    result.run_id = run_id.clone();
                    result.agent_id = spec.id.clone();
                    result
                }
                Ok(Err(err)) => failure_result(run_id.clone(), &spec.id, started_at, err),
                Err(_) => failure_result(
                    run_id.clone(),
                    &spec.id,
                    started_at,
                    AgentError::timeout(self.policy.timeout),
                ),
            };
            let retryable = result_is_retryable(&result);
            if trace_attempts {
                trace
                    .emit(TraceEvent::new(
                        "run_attempt_finished",
                        json!({
                            "run_id": run_id.0.clone(),
                            "agent_id": spec.id.clone(),
                            "attempt": attempt,
                            "status": result.status.clone(),
                            "retryable": retryable,
                            "error": result.error.clone(),
                        }),
                    ))
                    .await?;
            }

            if !retryable || attempt >= max_attempts {
                if retryable && attempt >= max_attempts {
                    result.error = result.error.map(|mut error| {
                        error.details["attempts"] = json!(attempt);
                        error.details["retry_exhausted"] = json!(true);
                        error
                    });
                }
                return Ok(result);
            }

            let next_attempt = attempt + 1;
            trace
                .emit(TraceEvent::new(
                    "run_retry_scheduled",
                    json!({
                        "run_id": run_id.0.clone(),
                        "agent_id": spec.id.clone(),
                        "attempt": attempt,
                        "next_attempt": next_attempt,
                        "backoff_ms": self.policy.retry_backoff.as_millis(),
                    }),
                ))
                .await?;
            if !self.policy.retry_backoff.is_zero() {
                tokio::time::sleep(self.policy.retry_backoff).await;
            }
            attempt = next_attempt;
        }
    }

    pub async fn tick(&self, request: RunRequest) -> Result<Vec<RunOutcome>, AgentError> {
        let now = OffsetDateTime::now_utc();
        let scope = request
            .user
            .as_ref()
            .map(|u| RunScope::User(u.user_id.clone()))
            .unwrap_or(RunScope::Global);
        let mut outcomes = Vec::new();
        for spec in self.registry.list_agents().await? {
            let last = self
                .run_store
                .last_run(&spec.id, &scope)
                .await
                .map_err(|e| AgentError::internal(e.to_string()))?;
            if self.scheduler.should_fire(&spec, now, last.as_ref()) {
                outcomes.push(self.run_once(&spec.id, request.clone()).await?);
            }
        }
        Ok(outcomes)
    }
}

impl ExecutionPolicy {
    fn lease_ttl(&self) -> Duration {
        let attempts = self.max_retries.saturating_add(1);
        self.timeout
            .saturating_mul(attempts)
            .saturating_add(self.retry_backoff.saturating_mul(self.max_retries))
    }
}

pub async fn recover_stale_runs(
    run_store: &dyn AgentRunStore,
    policy: &ExecutionPolicy,
) -> Result<RecoveryReport, AgentError> {
    let now = OffsetDateTime::now_utc();
    let runs = run_store
        .list_runs(None, None)
        .await
        .map_err(|e| AgentError::internal(e.to_string()))?;
    let scanned_runs = runs.len();
    let mut recovered_runs = Vec::new();

    for mut run in runs {
        if run.status != AgentRunStatus::Running || !is_stale_running_run(&run, now, policy) {
            continue;
        }
        let previous_status = run.status.clone();
        let reason = format!(
            "running run exceeded recovery timeout of {}ms",
            policy.timeout.as_millis()
        );
        run.status = AgentRunStatus::Abandoned;
        run.finished_at = Some(now);
        run.error = Some(AgentErrorRecord {
            kind: AgentErrorKind::Timeout,
            code: "stale_running_run_abandoned".to_owned(),
            message: reason.clone(),
            retryable: true,
            details: json!({
                "timeout_ms": policy.timeout.as_millis(),
                "recovered_at_unix_seconds": now.unix_timestamp(),
            }),
        });
        run_store
            .update_run(run.clone())
            .await
            .map_err(|e| AgentError::internal(e.to_string()))?;
        recovered_runs.push(RecoveredRun {
            run_id: run.run_id,
            agent_id: run.agent_id,
            previous_status,
            new_status: AgentRunStatus::Abandoned,
            started_at: run.started_at,
            abandoned_at: now,
            reason,
        });
    }

    Ok(RecoveryReport {
        scanned_runs,
        abandoned_count: recovered_runs.len(),
        recovered_runs,
    })
}

fn is_stale_running_run(
    run: &AgentRunRecord,
    now: OffsetDateTime,
    policy: &ExecutionPolicy,
) -> bool {
    run.started_at + lease_duration(policy.lease_ttl()) <= now
}

fn result_is_retryable(result: &AgentRunResult) -> bool {
    if matches!(
        result.status,
        AgentRunStatus::Completed | AgentRunStatus::Skipped | AgentRunStatus::Cancelled
    ) {
        return false;
    }
    result.error.as_ref().is_some_and(|error| error.retryable)
}

pub fn run_idempotency_key(agent_id: &str, scope: &RunScope, request: &RunRequest) -> String {
    let scheduled_for = request
        .metadata
        .get("scheduled_for")
        .cloned()
        .unwrap_or(Value::Null);
    let material = json!({
        "agent_id": agent_id,
        "scope": scope,
        "trigger_kind": &request.trigger,
        "scheduled_for": scheduled_for,
    });
    let bytes = serde_json::to_vec(&material).unwrap_or_else(|_| agent_id.as_bytes().to_vec());
    format!("idem_{}", blake3::hash(&bytes).to_hex())
}

#[derive(Default)]
pub struct InMemoryLockStore {
    leases: Mutex<HashMap<String, RunLease>>,
}

#[async_trait]
impl AgentLockStore for InMemoryLockStore {
    async fn acquire(
        &self,
        key: &str,
        owner: &str,
        ttl: Duration,
    ) -> Result<Option<RunLease>, StoreError> {
        let now = OffsetDateTime::now_utc();
        let mut leases = self.leases.lock().await;
        if leases
            .get(key)
            .is_some_and(|lease| lease.expires_at > now && lease.owner != owner)
        {
            return Ok(None);
        }
        let lease = RunLease {
            key: key.to_owned(),
            owner: owner.to_owned(),
            acquired_at: now,
            expires_at: now + lease_duration(ttl),
        };
        leases.insert(key.to_owned(), lease.clone());
        Ok(Some(lease))
    }

    async fn renew(&self, lease: &RunLease, ttl: Duration) -> Result<(), StoreError> {
        let mut leases = self.leases.lock().await;
        if let Some(stored) = leases.get_mut(&lease.key)
            && stored.owner == lease.owner
        {
            stored.expires_at = OffsetDateTime::now_utc() + lease_duration(ttl);
        }
        Ok(())
    }

    async fn release(&self, lease: RunLease) -> Result<(), StoreError> {
        let mut leases = self.leases.lock().await;
        if leases
            .get(&lease.key)
            .is_some_and(|stored| stored.owner == lease.owner)
        {
            leases.remove(&lease.key);
        }
        Ok(())
    }
}

fn lock_key(agent_id: &str, scope: &RunScope) -> String {
    format!("agent:{agent_id}:scope:{}", scope_key(scope))
}

fn scope_key(scope: &RunScope) -> String {
    match scope {
        RunScope::Global => "global".to_owned(),
        RunScope::User(user_id) => format!("user:{user_id}"),
        RunScope::Tenant(tenant_id) => format!("tenant:{tenant_id}"),
    }
}

fn lease_duration(ttl: Duration) -> time::Duration {
    time::Duration::seconds(ttl.as_secs().max(1) as i64)
}

pub struct AgentScheduler;

impl AgentScheduler {
    pub fn should_fire(
        &self,
        spec: &AgentSpec,
        now: OffsetDateTime,
        last_run: Option<&AgentRunRecord>,
    ) -> bool {
        match spec.schedule {
            ScheduleSpec::Manual => false,
            ScheduleSpec::Interval {
                every_seconds,
                preferred_hour_local,
                jitter_seconds,
            } => {
                if let Some(last) = last_run {
                    let elapsed = now - last.started_at;
                    if elapsed.whole_seconds() < every_seconds as i64 {
                        return false;
                    }
                }
                let Some(hour) = preferred_hour_local else {
                    return true;
                };
                let jitter = jitter_seconds.unwrap_or(300) as i64;
                let now_hour = now.hour() as i64;
                let now_minute = now.minute() as i64;
                let seconds_from_target = ((now_hour - hour as i64) * 3600 + now_minute * 60).abs();
                seconds_from_target <= jitter
            }
        }
    }
}

pub struct InMemoryAgentRegistry {
    agents: HashMap<String, Arc<dyn Agent>>,
}

impl InMemoryAgentRegistry {
    pub fn new(agents: Vec<Arc<dyn Agent>>) -> Self {
        Self {
            agents: agents
                .into_iter()
                .map(|agent| (agent.spec().id, agent))
                .collect(),
        }
    }

    pub fn shared(agents: Vec<Arc<dyn Agent>>) -> Arc<Self> {
        Arc::new(Self::new(agents))
    }
}

#[async_trait]
impl AgentRegistry for InMemoryAgentRegistry {
    async fn list_agents(&self) -> Result<Vec<AgentSpec>, AgentError> {
        Ok(self.agents.values().map(|agent| agent.spec()).collect())
    }

    async fn get_agent(&self, id: &str) -> Result<Option<Arc<dyn Agent>>, AgentError> {
        Ok(self.agents.get(id).cloned())
    }
}

#[derive(Default)]
pub struct MemoryTraceSink {
    events: Mutex<Vec<TraceEvent>>,
}

impl MemoryTraceSink {
    pub async fn events(&self) -> Vec<TraceEvent> {
        self.events.lock().await.clone()
    }
}

#[async_trait]
impl TraceSink for MemoryTraceSink {
    async fn emit(&self, event: TraceEvent) -> Result<(), AgentError> {
        self.events.lock().await.push(event);
        Ok(())
    }
}

pub struct BasicAgentServices {
    agent_id: String,
    run_id: RunId,
    user: Option<agent_core::UserContext>,
    tools: Arc<dyn ToolRegistry>,
    state_store: Arc<dyn AgentStateStore>,
}

struct TracedAgentServices {
    inner: Arc<dyn AgentServices>,
    trace: Arc<dyn TraceSink>,
    run_id: RunId,
    agent_id: String,
}

#[async_trait]
impl AgentServices for TracedAgentServices {
    async fn call_tool(&self, name: &str, input: Value) -> Result<Value, ToolError> {
        self.inner.call_tool(name, input).await
    }

    async fn emit_event(&self, event: AgentEvent) -> Result<(), AgentError> {
        self.inner.emit_event(event).await
    }

    async fn load_state(&self, key: &str) -> Result<Option<Value>, AgentError> {
        let started_at = std::time::Instant::now();
        match self.inner.load_state(key).await {
            Ok(value) => {
                let mut payload = json!({
                    "run_id": self.run_id.0.clone(),
                    "agent_id": self.agent_id.clone(),
                    "key": key,
                    "duration_ms": started_at.elapsed().as_millis(),
                    "status": "completed",
                    "found": value.is_some(),
                });
                if let Some(value) = &value {
                    payload["value_hash"] = json!(state_value_hash(value));
                    payload["value"] = value.clone();
                }
                self.trace
                    .emit(TraceEvent::new("state_read", payload))
                    .await?;
                Ok(value)
            }
            Err(error) => {
                self.trace
                    .emit(TraceEvent::new(
                        "state_read_failed",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "key": key,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "status": "failed",
                            "error": error.record.clone(),
                        }),
                    ))
                    .await?;
                Err(error)
            }
        }
    }

    async fn save_state(&self, key: &str, value: Value) -> Result<(), AgentError> {
        let started_at = std::time::Instant::now();
        let value_hash = state_value_hash(&value);
        match self.inner.save_state(key, value.clone()).await {
            Ok(()) => {
                self.trace
                    .emit(TraceEvent::new(
                        "state_write",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "key": key,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "status": "completed",
                            "value_hash": value_hash,
                            "value": value,
                        }),
                    ))
                    .await?;
                Ok(())
            }
            Err(error) => {
                self.trace
                    .emit(TraceEvent::new(
                        "state_write_failed",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "key": key,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "status": "failed",
                            "value_hash": value_hash,
                            "error": error.record.clone(),
                        }),
                    ))
                    .await?;
                Err(error)
            }
        }
    }

    async fn create_proposal(
        &self,
        proposal: agent_core::ProposalEnvelope,
    ) -> Result<(), AgentError> {
        let started_at = std::time::Instant::now();
        match self.inner.create_proposal(proposal.clone()).await {
            Ok(()) => {
                self.trace
                    .emit(TraceEvent::new(
                        "proposal_created",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "proposal_id": proposal.proposal_id.0,
                            "kind": proposal.kind,
                            "summary": proposal.summary,
                            "status": proposal.status,
                            "duration_ms": started_at.elapsed().as_millis(),
                        }),
                    ))
                    .await?;
                Ok(())
            }
            Err(error) => {
                self.trace
                    .emit(TraceEvent::new(
                        "proposal_create_failed",
                        json!({
                            "run_id": self.run_id.0.clone(),
                            "agent_id": self.agent_id.clone(),
                            "kind": proposal.kind,
                            "summary": proposal.summary,
                            "duration_ms": started_at.elapsed().as_millis(),
                            "error": error.record.clone(),
                        }),
                    ))
                    .await?;
                Err(error)
            }
        }
    }
}

fn state_value_hash(value: &Value) -> String {
    let bytes = serde_json::to_vec(value).unwrap_or_default();
    format!("blake3:{}", blake3::hash(&bytes).to_hex())
}

impl BasicAgentServices {
    pub fn new(
        agent_id: impl Into<String>,
        run_id: RunId,
        user: Option<agent_core::UserContext>,
        tools: Arc<dyn ToolRegistry>,
        state_store: Arc<dyn AgentStateStore>,
    ) -> Self {
        Self {
            agent_id: agent_id.into(),
            run_id,
            user,
            tools,
            state_store,
        }
    }
}

#[async_trait]
impl AgentServices for BasicAgentServices {
    async fn call_tool(&self, name: &str, input: Value) -> Result<Value, ToolError> {
        self.tools
            .call(
                name,
                input,
                ToolContext {
                    run_id: self.run_id.clone(),
                    agent_id: self.agent_id.clone(),
                    user: self.user.clone(),
                },
            )
            .await
    }

    async fn emit_event(&self, _event: AgentEvent) -> Result<(), AgentError> {
        Ok(())
    }

    async fn load_state(&self, key: &str) -> Result<Option<Value>, AgentError> {
        self.state_store
            .load(&self.agent_id, key)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))
    }

    async fn save_state(&self, key: &str, value: Value) -> Result<(), AgentError> {
        self.state_store
            .save(&self.agent_id, key, value)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))
    }
}

fn failure_result(
    run_id: RunId,
    agent_id: &str,
    started_at: OffsetDateTime,
    err: AgentError,
) -> AgentRunResult {
    AgentRunResult {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        run_id,
        agent_id: agent_id.to_owned(),
        status: match err.record.kind {
            agent_core::AgentErrorKind::Timeout => AgentRunStatus::TimedOut,
            agent_core::AgentErrorKind::Cancelled => AgentRunStatus::Cancelled,
            _ => AgentRunStatus::Failed,
        },
        started_at,
        finished_at: OffsetDateTime::now_utc(),
        summary: Some(err.record.message.clone()),
        output: json!({}),
        error: Some(err.record),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_core::{AgentRunResult, ScheduleSpec};
    use async_trait::async_trait;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio::time::{Duration, sleep};

    struct EchoAgent;

    #[async_trait]
    impl Agent for EchoAgent {
        fn spec(&self) -> AgentSpec {
            AgentSpec {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                id: "echo".to_owned(),
                name: "Echo".to_owned(),
                description: None,
                version: "0.1.0".to_owned(),
                schedule: ScheduleSpec::Manual,
                capabilities: vec!["debug.echo".to_owned()],
                metadata: json!({}),
            }
        }

        async fn run(&self, ctx: AgentContext) -> Result<AgentRunResult, AgentError> {
            Ok(AgentRunResult::completed(
                ctx.run_id,
                "echo",
                ctx.now,
                ctx.input,
                Some("echoed input".to_owned()),
            ))
        }
    }

    #[tokio::test]
    async fn runner_executes_agent_and_records_trace() {
        let registry = InMemoryAgentRegistry::shared(vec![Arc::new(EchoAgent)]);
        let run_store = agent_store::InMemoryRunStore::shared();
        let state_store = agent_store::InMemoryStateStore::shared();
        let services = Arc::new(NoopServices { state_store });
        let runner = AgentRunner::new(registry, run_store.clone(), services);

        let outcome = runner
            .run_once(
                "echo",
                RunRequest {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    run_id: None,
                    input: json!({"hello": "world"}),
                    user: None,
                    trigger: agent_core::TriggerKind::Manual,
                    metadata: json!({}),
                },
            )
            .await
            .expect("run succeeds");

        assert!(matches!(outcome.result.status, AgentRunStatus::Completed));
        assert_eq!(outcome.result.output, json!({"hello": "world"}));
        assert_eq!(outcome.trace.events.len(), 2);
        let stored = run_store
            .get_run(&outcome.result.run_id)
            .await
            .expect("run store reads")
            .expect("run record exists");
        assert!(
            stored
                .idempotency_key
                .as_deref()
                .is_some_and(|key| key.starts_with("idem_"))
        );
    }

    #[tokio::test]
    async fn runner_traces_state_reads_and_writes() {
        let registry = InMemoryAgentRegistry::shared(vec![Arc::new(StateAgent)]);
        let run_store = agent_store::InMemoryRunStore::shared();
        let state_store = agent_store::InMemoryStateStore::shared();
        let services = Arc::new(NoopServices { state_store });
        let runner = AgentRunner::new(registry, run_store, services);

        let outcome = runner
            .run_once(
                "stateful",
                RunRequest {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    run_id: None,
                    input: json!({"counter": 7}),
                    user: None,
                    trigger: agent_core::TriggerKind::Manual,
                    metadata: json!({}),
                },
            )
            .await
            .expect("stateful run succeeds");

        let write = outcome
            .trace
            .events
            .iter()
            .find(|event| event.kind == "state_write")
            .expect("state write event exists");
        assert_eq!(write.payload["agent_id"], "stateful");
        assert_eq!(write.payload["key"], "last_input");
        assert_eq!(write.payload["status"], "completed");
        assert_eq!(write.payload["value"]["counter"], 7);
        assert!(
            write.payload["value_hash"]
                .as_str()
                .is_some_and(|hash| hash.starts_with("blake3:"))
        );

        let read = outcome
            .trace
            .events
            .iter()
            .find(|event| event.kind == "state_read")
            .expect("state read event exists");
        assert_eq!(read.payload["agent_id"], "stateful");
        assert_eq!(read.payload["key"], "last_input");
        assert_eq!(read.payload["found"], true);
        assert_eq!(read.payload["value"]["counter"], 7);
        assert_eq!(outcome.result.output["loaded"]["counter"], 7);
    }

    #[test]
    fn run_idempotency_key_is_stable_for_retry_material() {
        let scope = RunScope::Global;
        let request = RunRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            run_id: None,
            input: json!({"message": "ignored"}),
            user: None,
            trigger: agent_core::TriggerKind::Scheduled,
            metadata: json!({"scheduled_for": "2026-06-28T09:00:00Z"}),
        };
        let same_retry = RunRequest {
            input: json!({"message": "different input does not affect retry identity"}),
            ..request.clone()
        };
        let different_schedule = RunRequest {
            metadata: json!({"scheduled_for": "2026-06-28T10:00:00Z"}),
            ..request.clone()
        };

        let first = run_idempotency_key("echo", &scope, &request);
        let second = run_idempotency_key("echo", &scope, &same_retry);
        let third = run_idempotency_key("echo", &scope, &different_schedule);

        assert_eq!(first, second);
        assert_ne!(first, third);
        assert_eq!(first.len(), "idem_".len() + 64);
    }

    #[tokio::test]
    async fn runner_respects_max_concurrent_runs_policy() {
        let counters = Arc::new(ConcurrencyCounters::default());
        let registry = InMemoryAgentRegistry::shared(vec![Arc::new(SlowAgent {
            counters: counters.clone(),
        })]);
        let run_store = agent_store::InMemoryRunStore::shared();
        let state_store = agent_store::InMemoryStateStore::shared();
        let services = Arc::new(NoopServices { state_store });
        let runner = Arc::new(AgentRunner::new(registry, run_store, services).with_policy(
            ExecutionPolicy {
                timeout: Duration::from_secs(5),
                max_retries: 0,
                retry_backoff: Duration::ZERO,
                max_concurrent_runs: 1,
            },
        ));

        let first = {
            let runner = runner.clone();
            tokio::spawn(async move { runner.run_once("slow", run_request()).await })
        };
        let second = {
            let runner = runner.clone();
            tokio::spawn(async move { runner.run_once("slow", run_request()).await })
        };

        first
            .await
            .expect("first task joins")
            .expect("first run succeeds");
        second
            .await
            .expect("second task joins")
            .expect("second run succeeds");

        assert_eq!(counters.max_seen.load(Ordering::SeqCst), 1);
        assert_eq!(counters.completed.load(Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn runner_skips_duplicate_agent_scope_when_lease_is_active() {
        let counters = Arc::new(ConcurrencyCounters::default());
        let registry = InMemoryAgentRegistry::shared(vec![Arc::new(SlowAgent {
            counters: counters.clone(),
        })]);
        let run_store = agent_store::InMemoryRunStore::shared();
        let state_store = agent_store::InMemoryStateStore::shared();
        let services = Arc::new(NoopServices { state_store });
        let runner = Arc::new(AgentRunner::new(registry, run_store, services).with_policy(
            ExecutionPolicy {
                timeout: Duration::from_secs(5),
                max_retries: 0,
                retry_backoff: Duration::ZERO,
                max_concurrent_runs: 2,
            },
        ));

        let first = {
            let runner = runner.clone();
            tokio::spawn(async move { runner.run_once("slow", run_request()).await })
        };
        sleep(Duration::from_millis(10)).await;
        let second = runner
            .run_once("slow", run_request())
            .await
            .expect("second run returns skipped outcome");
        let first = first
            .await
            .expect("first task joins")
            .expect("first run succeeds");

        let statuses = [first.result.status, second.result.status];
        assert!(statuses.contains(&AgentRunStatus::Completed));
        assert!(statuses.contains(&AgentRunStatus::Skipped));
        assert_eq!(counters.max_seen.load(Ordering::SeqCst), 1);
        assert_eq!(counters.completed.load(Ordering::SeqCst), 1);
        assert_eq!(second.trace.events[0].kind, "run_skipped");
    }

    #[tokio::test]
    async fn runner_retries_retryable_agent_errors() {
        let attempts = Arc::new(AtomicUsize::new(0));
        let registry = InMemoryAgentRegistry::shared(vec![Arc::new(FlakyAgent {
            attempts: attempts.clone(),
        })]);
        let run_store = agent_store::InMemoryRunStore::shared();
        let state_store = agent_store::InMemoryStateStore::shared();
        let services = Arc::new(NoopServices { state_store });
        let runner =
            AgentRunner::new(registry, run_store.clone(), services).with_policy(ExecutionPolicy {
                timeout: Duration::from_secs(5),
                max_retries: 1,
                retry_backoff: Duration::ZERO,
                max_concurrent_runs: 1,
            });

        let outcome = runner
            .run_once("flaky", run_request())
            .await
            .expect("retryable run eventually succeeds");

        assert_eq!(attempts.load(Ordering::SeqCst), 2);
        assert_eq!(outcome.result.status, AgentRunStatus::Completed);
        assert_eq!(outcome.result.output["attempt"], 2);
        let event_kinds = outcome
            .trace
            .events
            .iter()
            .map(|event| event.kind.as_str())
            .collect::<Vec<_>>();
        assert_eq!(
            event_kinds
                .iter()
                .filter(|kind| **kind == "run_attempt_started")
                .count(),
            2
        );
        assert!(event_kinds.contains(&"run_retry_scheduled"));

        let stored = run_store
            .get_run(&outcome.result.run_id)
            .await
            .expect("run store reads")
            .expect("run record exists");
        assert_eq!(stored.status, AgentRunStatus::Completed);
        assert_eq!(stored.output["attempt"], 2);
    }

    #[tokio::test]
    async fn recovery_abandons_only_stale_running_runs() {
        let store = agent_store::InMemoryRunStore::shared();
        let now = OffsetDateTime::now_utc();
        store
            .create_run(AgentRunRecord {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                run_id: RunId("run_stale".to_owned()),
                idempotency_key: Some("idem_stale".to_owned()),
                agent_id: "echo".to_owned(),
                status: AgentRunStatus::Running,
                scope: RunScope::Global,
                started_at: now - time::Duration::seconds(120),
                finished_at: None,
                input: json!({"message": "old"}),
                output: json!({}),
                error: None,
                metadata: json!({}),
            })
            .await
            .expect("stale run saved");
        store
            .create_run(AgentRunRecord {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                run_id: RunId("run_fresh".to_owned()),
                idempotency_key: Some("idem_fresh".to_owned()),
                agent_id: "echo".to_owned(),
                status: AgentRunStatus::Running,
                scope: RunScope::Global,
                started_at: now,
                finished_at: None,
                input: json!({"message": "fresh"}),
                output: json!({}),
                error: None,
                metadata: json!({}),
            })
            .await
            .expect("fresh run saved");

        let report = recover_stale_runs(
            store.as_ref(),
            &ExecutionPolicy {
                timeout: Duration::from_secs(60),
                max_retries: 0,
                retry_backoff: Duration::ZERO,
                max_concurrent_runs: 1,
            },
        )
        .await
        .expect("recovery succeeds");

        assert_eq!(report.scanned_runs, 2);
        assert_eq!(report.abandoned_count, 1);
        assert_eq!(report.recovered_runs[0].run_id.0, "run_stale");
        let stale = store
            .get_run(&RunId("run_stale".to_owned()))
            .await
            .expect("stale run reads")
            .expect("stale run exists");
        assert_eq!(stale.status, AgentRunStatus::Abandoned);
        assert_eq!(
            stale.error.expect("stale run has error").code,
            "stale_running_run_abandoned"
        );
        let fresh = store
            .get_run(&RunId("run_fresh".to_owned()))
            .await
            .expect("fresh run reads")
            .expect("fresh run exists");
        assert_eq!(fresh.status, AgentRunStatus::Running);
        assert!(fresh.finished_at.is_none());
    }

    struct StateAgent;

    #[async_trait]
    impl Agent for StateAgent {
        fn spec(&self) -> AgentSpec {
            AgentSpec {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                id: "stateful".to_owned(),
                name: "Stateful".to_owned(),
                description: None,
                version: "0.1.0".to_owned(),
                schedule: ScheduleSpec::Manual,
                capabilities: vec!["debug.state".to_owned()],
                metadata: json!({}),
            }
        }

        async fn run(&self, ctx: AgentContext) -> Result<AgentRunResult, AgentError> {
            ctx.services
                .save_state("last_input", ctx.input.clone())
                .await?;
            let loaded = ctx.services.load_state("last_input").await?;
            Ok(AgentRunResult::completed(
                ctx.run_id,
                "stateful",
                ctx.now,
                json!({"loaded": loaded}),
                Some("stateful run completed".to_owned()),
            ))
        }
    }

    struct FlakyAgent {
        attempts: Arc<AtomicUsize>,
    }

    #[async_trait]
    impl Agent for FlakyAgent {
        fn spec(&self) -> AgentSpec {
            AgentSpec {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                id: "flaky".to_owned(),
                name: "Flaky".to_owned(),
                description: None,
                version: "0.1.0".to_owned(),
                schedule: ScheduleSpec::Manual,
                capabilities: vec!["debug.flaky".to_owned()],
                metadata: json!({}),
            }
        }

        async fn run(&self, ctx: AgentContext) -> Result<AgentRunResult, AgentError> {
            let attempt = self.attempts.fetch_add(1, Ordering::SeqCst) + 1;
            if attempt == 1 {
                return Err(AgentError {
                    record: AgentErrorRecord {
                        kind: AgentErrorKind::TransientExternalError,
                        code: "transient_test_error".to_owned(),
                        message: "transient failure".to_owned(),
                        retryable: true,
                        details: json!({"attempt": attempt}),
                    },
                });
            }
            Ok(AgentRunResult::completed(
                ctx.run_id,
                "flaky",
                ctx.now,
                json!({"attempt": attempt}),
                Some("flaky run completed".to_owned()),
            ))
        }
    }

    #[derive(Default)]
    struct ConcurrencyCounters {
        current: AtomicUsize,
        max_seen: AtomicUsize,
        completed: AtomicUsize,
    }

    struct SlowAgent {
        counters: Arc<ConcurrencyCounters>,
    }

    #[async_trait]
    impl Agent for SlowAgent {
        fn spec(&self) -> AgentSpec {
            AgentSpec {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                id: "slow".to_owned(),
                name: "Slow".to_owned(),
                description: None,
                version: "0.1.0".to_owned(),
                schedule: ScheduleSpec::Manual,
                capabilities: vec!["debug.slow".to_owned()],
                metadata: json!({}),
            }
        }

        async fn run(&self, ctx: AgentContext) -> Result<AgentRunResult, AgentError> {
            let current = self.counters.current.fetch_add(1, Ordering::SeqCst) + 1;
            self.counters.max_seen.fetch_max(current, Ordering::SeqCst);
            sleep(Duration::from_millis(100)).await;
            self.counters.current.fetch_sub(1, Ordering::SeqCst);
            self.counters.completed.fetch_add(1, Ordering::SeqCst);
            Ok(AgentRunResult::completed(
                ctx.run_id,
                "slow",
                ctx.now,
                ctx.input,
                Some("slow run completed".to_owned()),
            ))
        }
    }

    fn run_request() -> RunRequest {
        RunRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            run_id: None,
            input: json!({}),
            user: None,
            trigger: agent_core::TriggerKind::Manual,
            metadata: json!({}),
        }
    }

    struct NoopServices {
        state_store: Arc<dyn agent_core::AgentStateStore>,
    }

    #[async_trait]
    impl AgentServices for NoopServices {
        async fn call_tool(&self, _name: &str, _input: Value) -> Result<Value, ToolError> {
            Ok(json!({}))
        }

        async fn emit_event(&self, _event: AgentEvent) -> Result<(), AgentError> {
            Ok(())
        }

        async fn load_state(&self, key: &str) -> Result<Option<Value>, AgentError> {
            self.state_store
                .load("echo", key)
                .await
                .map_err(|e| AgentError::internal(e.to_string()))
        }

        async fn save_state(&self, key: &str, value: Value) -> Result<(), AgentError> {
            self.state_store
                .save("echo", key, value)
                .await
                .map_err(|e| AgentError::internal(e.to_string()))
        }
    }
}
