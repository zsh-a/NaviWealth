use agent_core::{AgentSessionStore, SessionId, SessionRecord, StepRecord, ThreadId, ThreadRecord};
use agent_runtime::RunOutcome;
use agent_store::FileSessionStore;
use camino::{Utf8Path, Utf8PathBuf};
use miette::{IntoDiagnostic, Result, miette};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Debug, Serialize)]
pub(crate) struct SessionCreateReport {
    pub(crate) session: SessionRecord,
    pub(crate) thread: ThreadRecord,
}

#[derive(Debug, Serialize)]
pub(crate) struct SessionShowReport {
    pub(crate) session: SessionRecord,
    pub(crate) threads: Vec<ThreadWithSteps>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ThreadWithSteps {
    pub(crate) thread: ThreadRecord,
    pub(crate) steps: Vec<StepRecord>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ThreadForkReport {
    pub(crate) session_id: String,
    pub(crate) parent_thread_id: String,
    pub(crate) thread: ThreadRecord,
}

#[derive(Debug, Serialize)]
pub(crate) struct HttpSessionCreateResponse {
    pub(crate) session: SessionRecord,
    pub(crate) thread: ThreadRecord,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpSessionCreateParams {
    pub(crate) title: String,
    #[serde(default)]
    pub(crate) metadata: Value,
}

#[derive(Debug, Deserialize)]
pub(crate) struct HttpThreadForkParams {
    pub(crate) parent_thread_id: String,
    #[serde(default)]
    pub(crate) title: Option<String>,
    #[serde(default)]
    pub(crate) metadata: Value,
}

pub(crate) async fn create_session(
    store_path: Utf8PathBuf,
    title: String,
) -> Result<SessionCreateReport> {
    let store = FileSessionStore::new(store_path).await.into_diagnostic()?;
    let session = SessionRecord::new(title.clone(), json!({}));
    let thread = ThreadRecord::root(session.session_id.clone(), Some(title), json!({}));
    store
        .create_session(session.clone())
        .await
        .into_diagnostic()?;
    store
        .create_thread(thread.clone())
        .await
        .into_diagnostic()?;
    Ok(SessionCreateReport { session, thread })
}

pub(crate) fn run_metadata(session: Option<&str>, thread: Option<&str>) -> Value {
    json!({
        "session_id": session,
        "thread_id": thread,
    })
}

pub(crate) async fn record_session_step(
    store_path: &Utf8Path,
    thread_id: Option<&str>,
    outcome: &RunOutcome,
) -> Result<()> {
    let Some(thread_id) = thread_id else {
        return Ok(());
    };
    let store = FileSessionStore::new(store_path.to_path_buf())
        .await
        .into_diagnostic()?;
    let thread_id = ThreadId(thread_id.to_owned());
    let thread = store
        .get_thread(&thread_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("thread '{}' was not found", thread_id.0))?;
    let step = StepRecord::agent_run(
        thread.thread_id,
        outcome.result.run_id.clone(),
        outcome.result.summary.clone(),
        json!({
            "agent_id": outcome.result.agent_id.clone(),
            "status": outcome.result.status.clone(),
        }),
    );
    store.create_step(step).await.into_diagnostic()
}

pub(crate) async fn show_session(
    store_path: Utf8PathBuf,
    session_id: SessionId,
) -> Result<SessionShowReport> {
    let store = FileSessionStore::new(store_path).await.into_diagnostic()?;
    let session = store
        .get_session(&session_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
    let mut threads = Vec::new();
    for thread in store
        .list_threads(&session.session_id)
        .await
        .into_diagnostic()?
    {
        let steps = store
            .list_steps(&thread.thread_id)
            .await
            .into_diagnostic()?;
        threads.push(ThreadWithSteps { thread, steps });
    }
    Ok(SessionShowReport { session, threads })
}

pub(crate) async fn fork_thread(
    store_path: Utf8PathBuf,
    session_id: SessionId,
    parent_thread_id: ThreadId,
    title: Option<String>,
) -> Result<ThreadForkReport> {
    let store = FileSessionStore::new(store_path).await.into_diagnostic()?;
    store
        .get_session(&session_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
    let parent = store
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
        title,
        json!({}),
    );
    store
        .create_thread(thread.clone())
        .await
        .into_diagnostic()?;
    Ok(ThreadForkReport {
        session_id: session_id.0,
        parent_thread_id: parent_thread_id.0,
        thread,
    })
}
