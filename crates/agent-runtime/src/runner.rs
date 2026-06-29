use std::sync::Arc;

use agent_core::{
    Agent, AgentContext, AgentError, AgentRegistry, AgentRunRecord, AgentRunResult, AgentRunStatus,
    AgentRunStore, AgentServices, AgentSpec, AgentTrace, PROTOCOL_VERSION, RunId, RunRequest,
    RunScope, TraceEvent, TraceSink,
};
use serde_json::{Value, json};
use time::OffsetDateTime;
use tokio::sync::Semaphore;
use tokio_util::sync::CancellationToken;

use crate::{
    InMemoryLockStore, RUNTIME_VERSION,
    lock::lock_key,
    policy::ExecutionPolicy,
    recovery::{RecoveryReport, recover_stale_runs},
    scheduler::AgentScheduler,
    services::TracedAgentServices,
    trace::MemoryTraceSink,
};

pub struct RunOutcome {
    pub result: AgentRunResult,
    pub trace: AgentTrace,
}

pub struct AgentRunner {
    registry: Arc<dyn AgentRegistry>,
    run_store: Arc<dyn AgentRunStore>,
    services: Arc<dyn AgentServices>,
    scheduler: AgentScheduler,
    policy: ExecutionPolicy,
    concurrency: Arc<Semaphore>,
    lock_store: Arc<dyn agent_core::AgentLockStore>,
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

    pub fn with_lock_store(mut self, lock_store: Arc<dyn agent_core::AgentLockStore>) -> Self {
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

fn result_is_retryable(result: &AgentRunResult) -> bool {
    if matches!(
        result.status,
        AgentRunStatus::Completed | AgentRunStatus::Skipped | AgentRunStatus::Cancelled
    ) {
        return false;
    }
    result.error.as_ref().is_some_and(|error| error.retryable)
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
