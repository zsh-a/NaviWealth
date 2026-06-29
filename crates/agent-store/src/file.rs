use agent_core::{
    AgentProposalStore, AgentRunRecord, AgentRunStore, AgentSessionStore, ProposalEnvelope,
    ProposalId, RunId, RunScope, SessionId, SessionRecord, StepRecord, StoreError, ThreadId,
    ThreadRecord,
};
use async_trait::async_trait;
use camino::{Utf8Path, Utf8PathBuf};

use crate::util::{same_scope, sort_and_limit_runs};

pub struct FileRunStore {
    root: Utf8PathBuf,
}

pub struct FileProposalStore {
    root: Utf8PathBuf,
}

pub struct FileSessionStore {
    root: Utf8PathBuf,
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
        read_optional_json(&self.path_for(run_id)).await
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
        read_optional_json(&self.path_for(proposal_id)).await
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

fn map_store_err(err: std::io::Error) -> StoreError {
    StoreError::new(err.to_string())
}

fn map_json_err(err: serde_json::Error) -> StoreError {
    StoreError::new(err.to_string())
}
