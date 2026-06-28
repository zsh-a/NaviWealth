use std::{collections::HashMap, sync::Arc};

use agent_core::{
    AgentProposalStore, AgentRunRecord, AgentRunStore, AgentSessionStore, AgentStateStore,
    ProposalEnvelope, ProposalId, RunId, RunScope, SessionId, SessionRecord, StepRecord,
    StoreError, ThreadId, ThreadRecord,
};
use async_trait::async_trait;
use camino::{Utf8Path, Utf8PathBuf};
use tokio::sync::RwLock;

#[derive(Default)]
pub struct InMemoryRunStore {
    runs: RwLock<HashMap<String, AgentRunRecord>>,
}

impl InMemoryRunStore {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }
}

#[async_trait]
impl AgentRunStore for InMemoryRunStore {
    async fn create_run(&self, run: AgentRunRecord) -> Result<(), StoreError> {
        self.runs.write().await.insert(run.run_id.0.clone(), run);
        Ok(())
    }

    async fn update_run(&self, run: AgentRunRecord) -> Result<(), StoreError> {
        self.runs.write().await.insert(run.run_id.0.clone(), run);
        Ok(())
    }

    async fn get_run(&self, run_id: &RunId) -> Result<Option<AgentRunRecord>, StoreError> {
        Ok(self.runs.read().await.get(&run_id.0).cloned())
    }

    async fn list_runs(
        &self,
        agent_id: Option<&str>,
        limit: Option<usize>,
    ) -> Result<Vec<AgentRunRecord>, StoreError> {
        let mut runs = self
            .runs
            .read()
            .await
            .values()
            .filter(|run| agent_id.is_none_or(|agent_id| run.agent_id == agent_id))
            .cloned()
            .collect::<Vec<_>>();
        sort_and_limit_runs(&mut runs, limit);
        Ok(runs)
    }

    async fn last_run(
        &self,
        agent_id: &str,
        scope: &RunScope,
    ) -> Result<Option<AgentRunRecord>, StoreError> {
        let mut runs = self
            .runs
            .read()
            .await
            .values()
            .filter(|run| run.agent_id == agent_id && same_scope(&run.scope, scope))
            .cloned()
            .collect::<Vec<_>>();
        runs.sort_by_key(|run| run.started_at);
        Ok(runs.pop())
    }
}

#[derive(Default)]
pub struct InMemoryStateStore {
    values: RwLock<HashMap<(String, String), serde_json::Value>>,
}

impl InMemoryStateStore {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }
}

#[async_trait]
impl AgentStateStore for InMemoryStateStore {
    async fn load(
        &self,
        agent_id: &str,
        key: &str,
    ) -> Result<Option<serde_json::Value>, StoreError> {
        Ok(self
            .values
            .read()
            .await
            .get(&(agent_id.to_owned(), key.to_owned()))
            .cloned())
    }

    async fn save(
        &self,
        agent_id: &str,
        key: &str,
        value: serde_json::Value,
    ) -> Result<(), StoreError> {
        self.values
            .write()
            .await
            .insert((agent_id.to_owned(), key.to_owned()), value);
        Ok(())
    }
}

#[derive(Default)]
pub struct InMemoryProposalStore {
    proposals: RwLock<HashMap<String, ProposalEnvelope>>,
}

#[derive(Default)]
pub struct InMemorySessionStore {
    sessions: RwLock<HashMap<String, SessionRecord>>,
    threads: RwLock<HashMap<String, ThreadRecord>>,
    steps: RwLock<HashMap<String, StepRecord>>,
}

impl InMemorySessionStore {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }
}

#[async_trait]
impl AgentSessionStore for InMemorySessionStore {
    async fn create_session(&self, session: SessionRecord) -> Result<(), StoreError> {
        self.sessions
            .write()
            .await
            .insert(session.session_id.0.clone(), session);
        Ok(())
    }

    async fn list_sessions(&self) -> Result<Vec<SessionRecord>, StoreError> {
        let mut sessions = self
            .sessions
            .read()
            .await
            .values()
            .cloned()
            .collect::<Vec<_>>();
        sessions.sort_by_key(|session| session.updated_at);
        sessions.reverse();
        Ok(sessions)
    }

    async fn get_session(
        &self,
        session_id: &SessionId,
    ) -> Result<Option<SessionRecord>, StoreError> {
        Ok(self.sessions.read().await.get(&session_id.0).cloned())
    }

    async fn create_thread(&self, thread: ThreadRecord) -> Result<(), StoreError> {
        self.threads
            .write()
            .await
            .insert(thread.thread_id.0.clone(), thread);
        Ok(())
    }

    async fn list_threads(&self, session_id: &SessionId) -> Result<Vec<ThreadRecord>, StoreError> {
        let mut threads = self
            .threads
            .read()
            .await
            .values()
            .filter(|thread| thread.session_id == *session_id)
            .cloned()
            .collect::<Vec<_>>();
        threads.sort_by_key(|thread| thread.created_at);
        Ok(threads)
    }

    async fn get_thread(&self, thread_id: &ThreadId) -> Result<Option<ThreadRecord>, StoreError> {
        Ok(self.threads.read().await.get(&thread_id.0).cloned())
    }

    async fn create_step(&self, step: StepRecord) -> Result<(), StoreError> {
        self.steps
            .write()
            .await
            .insert(step.step_id.0.clone(), step);
        Ok(())
    }

    async fn list_steps(&self, thread_id: &ThreadId) -> Result<Vec<StepRecord>, StoreError> {
        let mut steps = self
            .steps
            .read()
            .await
            .values()
            .filter(|step| step.thread_id == *thread_id)
            .cloned()
            .collect::<Vec<_>>();
        steps.sort_by_key(|step| step.created_at);
        Ok(steps)
    }
}

impl InMemoryProposalStore {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }
}

#[async_trait]
impl AgentProposalStore for InMemoryProposalStore {
    async fn create_proposal(&self, proposal: ProposalEnvelope) -> Result<(), StoreError> {
        self.proposals
            .write()
            .await
            .insert(proposal.proposal_id.0.clone(), proposal);
        Ok(())
    }

    async fn update_proposal(&self, proposal: ProposalEnvelope) -> Result<(), StoreError> {
        self.proposals
            .write()
            .await
            .insert(proposal.proposal_id.0.clone(), proposal);
        Ok(())
    }

    async fn get_proposal(
        &self,
        proposal_id: &ProposalId,
    ) -> Result<Option<ProposalEnvelope>, StoreError> {
        Ok(self.proposals.read().await.get(&proposal_id.0).cloned())
    }

    async fn list_proposals(
        &self,
        run_id: Option<&RunId>,
    ) -> Result<Vec<ProposalEnvelope>, StoreError> {
        let mut proposals = self
            .proposals
            .read()
            .await
            .values()
            .filter(|proposal| match run_id {
                Some(run_id) => proposal.run_id == *run_id,
                None => true,
            })
            .cloned()
            .collect::<Vec<_>>();
        proposals.sort_by_key(|proposal| proposal.created_at);
        Ok(proposals)
    }
}

pub struct FileRunStore {
    root: Utf8PathBuf,
}

pub struct FileProposalStore {
    root: Utf8PathBuf,
}

pub struct FileSessionStore {
    root: Utf8PathBuf,
}

impl FileSessionStore {
    pub async fn new(root: impl Into<Utf8PathBuf>) -> Result<Self, StoreError> {
        let root = root.into();
        for dir in [session_dir(&root), thread_dir(&root), step_dir(&root)] {
            fs_err::tokio::create_dir_all(dir)
                .await
                .map_err(map_store_err)?;
        }
        Ok(Self { root })
    }

    fn session_path_for(&self, session_id: &SessionId) -> Utf8PathBuf {
        session_dir(&self.root).join(format!("{}.json", session_id.0))
    }

    fn thread_path_for(&self, thread_id: &ThreadId) -> Utf8PathBuf {
        thread_dir(&self.root).join(format!("{}.json", thread_id.0))
    }

    fn step_path_for(&self, step: &StepRecord) -> Utf8PathBuf {
        step_dir(&self.root).join(format!("{}.json", step.step_id.0))
    }
}

#[async_trait]
impl AgentSessionStore for FileSessionStore {
    async fn create_session(&self, session: SessionRecord) -> Result<(), StoreError> {
        write_json(&self.session_path_for(&session.session_id), &session).await
    }

    async fn list_sessions(&self) -> Result<Vec<SessionRecord>, StoreError> {
        let mut sessions = read_json_records::<SessionRecord>(&session_dir(&self.root)).await?;
        sessions.sort_by_key(|session| session.updated_at);
        sessions.reverse();
        Ok(sessions)
    }

    async fn get_session(
        &self,
        session_id: &SessionId,
    ) -> Result<Option<SessionRecord>, StoreError> {
        read_optional_json(&self.session_path_for(session_id)).await
    }

    async fn create_thread(&self, thread: ThreadRecord) -> Result<(), StoreError> {
        write_json(&self.thread_path_for(&thread.thread_id), &thread).await
    }

    async fn list_threads(&self, session_id: &SessionId) -> Result<Vec<ThreadRecord>, StoreError> {
        let mut threads = read_json_records::<ThreadRecord>(&thread_dir(&self.root))
            .await?
            .into_iter()
            .filter(|thread| thread.session_id == *session_id)
            .collect::<Vec<_>>();
        threads.sort_by_key(|thread| thread.created_at);
        Ok(threads)
    }

    async fn get_thread(&self, thread_id: &ThreadId) -> Result<Option<ThreadRecord>, StoreError> {
        read_optional_json(&self.thread_path_for(thread_id)).await
    }

    async fn create_step(&self, step: StepRecord) -> Result<(), StoreError> {
        write_json(&self.step_path_for(&step), &step).await
    }

    async fn list_steps(&self, thread_id: &ThreadId) -> Result<Vec<StepRecord>, StoreError> {
        let mut steps = read_json_records::<StepRecord>(&step_dir(&self.root))
            .await?
            .into_iter()
            .filter(|step| step.thread_id == *thread_id)
            .collect::<Vec<_>>();
        steps.sort_by_key(|step| step.created_at);
        Ok(steps)
    }
}

impl FileProposalStore {
    pub async fn new(root: impl Into<Utf8PathBuf>) -> Result<Self, StoreError> {
        let root = root.into();
        fs_err::tokio::create_dir_all(proposal_dir(&root))
            .await
            .map_err(map_store_err)?;
        Ok(Self { root })
    }

    fn path_for(&self, proposal_id: &ProposalId) -> Utf8PathBuf {
        proposal_dir(&self.root).join(format!("{}.json", proposal_id.0))
    }
}

#[async_trait]
impl AgentProposalStore for FileProposalStore {
    async fn create_proposal(&self, proposal: ProposalEnvelope) -> Result<(), StoreError> {
        write_json(&self.path_for(&proposal.proposal_id), &proposal).await
    }

    async fn update_proposal(&self, proposal: ProposalEnvelope) -> Result<(), StoreError> {
        write_json(&self.path_for(&proposal.proposal_id), &proposal).await
    }

    async fn get_proposal(
        &self,
        proposal_id: &ProposalId,
    ) -> Result<Option<ProposalEnvelope>, StoreError> {
        let path = self.path_for(proposal_id);
        if !path.exists() {
            return Ok(None);
        }
        let bytes = fs_err::tokio::read(path).await.map_err(map_store_err)?;
        serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(map_json_err)
    }

    async fn list_proposals(
        &self,
        run_id: Option<&RunId>,
    ) -> Result<Vec<ProposalEnvelope>, StoreError> {
        let mut entries = fs_err::tokio::read_dir(proposal_dir(&self.root))
            .await
            .map_err(map_store_err)?;
        let mut proposals = Vec::new();
        while let Some(entry) = entries.next_entry().await.map_err(map_store_err)? {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let bytes = fs_err::tokio::read(path).await.map_err(map_store_err)?;
            let proposal: ProposalEnvelope =
                serde_json::from_slice(&bytes).map_err(map_json_err)?;
            if match run_id {
                Some(run_id) => proposal.run_id == *run_id,
                None => true,
            } {
                proposals.push(proposal);
            }
        }
        proposals.sort_by_key(|proposal| proposal.created_at);
        Ok(proposals)
    }
}

impl FileRunStore {
    pub async fn new(root: impl Into<Utf8PathBuf>) -> Result<Self, StoreError> {
        let root = root.into();
        fs_err::tokio::create_dir_all(run_dir(&root))
            .await
            .map_err(map_store_err)?;
        Ok(Self { root })
    }

    fn path_for(&self, run_id: &RunId) -> Utf8PathBuf {
        run_dir(&self.root).join(format!("{}.json", run_id.0))
    }
}

#[async_trait]
impl AgentRunStore for FileRunStore {
    async fn create_run(&self, run: AgentRunRecord) -> Result<(), StoreError> {
        write_json(&self.path_for(&run.run_id), &run).await
    }

    async fn update_run(&self, run: AgentRunRecord) -> Result<(), StoreError> {
        write_json(&self.path_for(&run.run_id), &run).await
    }

    async fn get_run(&self, run_id: &RunId) -> Result<Option<AgentRunRecord>, StoreError> {
        let path = self.path_for(run_id);
        if !path.exists() {
            return Ok(None);
        }
        let bytes = fs_err::tokio::read(path).await.map_err(map_store_err)?;
        serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(map_json_err)
    }

    async fn list_runs(
        &self,
        agent_id: Option<&str>,
        limit: Option<usize>,
    ) -> Result<Vec<AgentRunRecord>, StoreError> {
        let mut runs = read_json_records::<AgentRunRecord>(&run_dir(&self.root))
            .await?
            .into_iter()
            .filter(|run| agent_id.is_none_or(|agent_id| run.agent_id == agent_id))
            .collect::<Vec<_>>();
        sort_and_limit_runs(&mut runs, limit);
        Ok(runs)
    }

    async fn last_run(
        &self,
        agent_id: &str,
        scope: &RunScope,
    ) -> Result<Option<AgentRunRecord>, StoreError> {
        let mut entries = fs_err::tokio::read_dir(run_dir(&self.root))
            .await
            .map_err(map_store_err)?;
        let mut runs = Vec::new();
        while let Some(entry) = entries.next_entry().await.map_err(map_store_err)? {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let bytes = fs_err::tokio::read(path).await.map_err(map_store_err)?;
            let run: AgentRunRecord = serde_json::from_slice(&bytes).map_err(map_json_err)?;
            if run.agent_id == agent_id && same_scope(&run.scope, scope) {
                runs.push(run);
            }
        }
        runs.sort_by_key(|run| run.started_at);
        Ok(runs.pop())
    }
}

async fn write_json(path: &Utf8Path, value: &impl serde::Serialize) -> Result<(), StoreError> {
    let bytes = serde_json::to_vec_pretty(value).map_err(map_json_err)?;
    fs_err::tokio::write(path, bytes)
        .await
        .map_err(map_store_err)
}

async fn read_optional_json<T>(path: &Utf8Path) -> Result<Option<T>, StoreError>
where
    T: serde::de::DeserializeOwned,
{
    if !path.exists() {
        return Ok(None);
    }
    let bytes = fs_err::tokio::read(path).await.map_err(map_store_err)?;
    serde_json::from_slice(&bytes)
        .map(Some)
        .map_err(map_json_err)
}

async fn read_json_records<T>(dir: &Utf8Path) -> Result<Vec<T>, StoreError>
where
    T: serde::de::DeserializeOwned,
{
    if !dir.exists() {
        return Ok(vec![]);
    }
    let mut entries = fs_err::tokio::read_dir(dir).await.map_err(map_store_err)?;
    let mut records = Vec::new();
    while let Some(entry) = entries.next_entry().await.map_err(map_store_err)? {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("json") {
            continue;
        }
        let bytes = fs_err::tokio::read(path).await.map_err(map_store_err)?;
        records.push(serde_json::from_slice(&bytes).map_err(map_json_err)?);
    }
    Ok(records)
}

fn run_dir(root: &Utf8Path) -> Utf8PathBuf {
    root.join("runs")
}

fn proposal_dir(root: &Utf8Path) -> Utf8PathBuf {
    root.join("proposals")
}

fn session_dir(root: &Utf8Path) -> Utf8PathBuf {
    root.join("sessions")
}

fn thread_dir(root: &Utf8Path) -> Utf8PathBuf {
    root.join("threads")
}

fn step_dir(root: &Utf8Path) -> Utf8PathBuf {
    root.join("steps")
}

fn same_scope(a: &RunScope, b: &RunScope) -> bool {
    match (a, b) {
        (RunScope::Global, RunScope::Global) => true,
        (RunScope::User(a), RunScope::User(b)) => a == b,
        (RunScope::Tenant(a), RunScope::Tenant(b)) => a == b,
        _ => false,
    }
}

fn sort_and_limit_runs(runs: &mut Vec<AgentRunRecord>, limit: Option<usize>) {
    runs.sort_by_key(|run| run.started_at);
    runs.reverse();
    if let Some(limit) = limit {
        runs.truncate(limit);
    }
}

fn map_store_err(err: std::io::Error) -> StoreError {
    StoreError::new(err.to_string())
}

fn map_json_err(err: serde_json::Error) -> StoreError {
    StoreError::new(err.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_core::{StepRecord, ThreadRecord};
    use serde_json::json;

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
}
