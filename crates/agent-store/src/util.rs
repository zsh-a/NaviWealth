use agent_core::{AgentRunRecord, RunScope};

pub(crate) fn same_scope(a: &RunScope, b: &RunScope) -> bool {
    match (a, b) {
        (RunScope::Global, RunScope::Global) => true,
        (RunScope::User(a), RunScope::User(b)) => a == b,
        (RunScope::Tenant(a), RunScope::Tenant(b)) => a == b,
        _ => false,
    }
}

pub(crate) fn sort_and_limit_runs(runs: &mut Vec<AgentRunRecord>, limit: Option<usize>) {
    runs.sort_by_key(|run| run.started_at);
    runs.reverse();
    if let Some(limit) = limit {
        runs.truncate(limit);
    }
}
