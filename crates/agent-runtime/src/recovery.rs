use agent_core::{
    AgentError, AgentErrorKind, AgentErrorRecord, AgentRunRecord, AgentRunStatus, AgentRunStore,
    RunId,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use time::OffsetDateTime;

use crate::{lock::lease_duration, policy::ExecutionPolicy};

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
