use agent_core::{
    AgentRunRecord, AgentRunStore, AgentSessionStore, RunId, RunScope, SessionRecord, StepRecord,
    ThreadRecord,
};
use camino::Utf8PathBuf;
use serde_json::json;

use super::*;

#[tokio::test]
async fn file_session_store_round_trips_session_thread_and_step() {
    let temp = tempfile::tempdir().expect("tempdir");
    let root = Utf8PathBuf::from_path_buf(temp.path().to_path_buf()).expect("utf8 temp path");
    let store = FileSessionStore::new(root).await.expect("store opens");

    let session = SessionRecord::new("Debug session", json!({"source": "test"}));
    let thread = ThreadRecord::root(
        session.session_id.clone(),
        Some("Baseline".to_owned()),
        json!({}),
    );
    let step = StepRecord::agent_run(
        thread.thread_id.clone(),
        RunId("run_test".to_owned()),
        Some("completed".to_owned()),
        json!({"agent_id": "echo", "status": "completed"}),
    );

    store
        .create_session(session.clone())
        .await
        .expect("session saved");
    store
        .create_thread(thread.clone())
        .await
        .expect("thread saved");
    store.create_step(step.clone()).await.expect("step saved");

    assert_eq!(
        store
            .get_session(&session.session_id)
            .await
            .expect("session read")
            .expect("session exists")
            .title,
        "Debug session"
    );
    assert_eq!(
        store
            .list_threads(&session.session_id)
            .await
            .expect("threads read")
            .len(),
        1
    );
    assert_eq!(
        store
            .list_steps(&thread.thread_id)
            .await
            .expect("steps read")
            .first()
            .expect("step exists")
            .step_id,
        step.step_id
    );
}

#[tokio::test]
async fn in_memory_run_store_lists_newest_runs_with_filter_and_limit() {
    let store = InMemoryRunStore::default();
    let now = time::OffsetDateTime::now_utc();
    for (idx, agent_id) in ["echo", "other", "echo"].into_iter().enumerate() {
        store
            .create_run(AgentRunRecord {
                protocol_version: agent_core::PROTOCOL_VERSION.to_owned(),
                run_id: RunId(format!("run_{idx}")),
                idempotency_key: Some(format!("idem_{idx}")),
                agent_id: agent_id.to_owned(),
                status: agent_core::AgentRunStatus::Completed,
                scope: RunScope::Global,
                started_at: now + time::Duration::seconds(idx as i64),
                finished_at: Some(now + time::Duration::seconds(idx as i64)),
                input: json!({}),
                output: json!({}),
                error: None,
                metadata: json!({}),
            })
            .await
            .expect("run saved");
    }

    let runs = store
        .list_runs(Some("echo"), Some(1))
        .await
        .expect("runs listed");

    assert_eq!(runs.len(), 1);
    assert_eq!(runs[0].run_id.0, "run_2");
}
