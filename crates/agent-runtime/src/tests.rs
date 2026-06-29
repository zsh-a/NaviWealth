use std::{
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use agent_core::{
    Agent, AgentContext, AgentError, AgentErrorKind, AgentErrorRecord, AgentEvent, AgentRunRecord,
    AgentRunResult, AgentRunStatus, AgentRunStore, AgentServices, AgentSpec, PROTOCOL_VERSION,
    RunId, RunRequest, RunScope, ScheduleSpec, ToolError,
};
use async_trait::async_trait;
use serde_json::{Value, json};
use time::OffsetDateTime;
use tokio::time::sleep;

use super::*;

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
