use std::{collections::HashMap, time::Duration};

use agent_core::{AgentLockStore, RunLease, RunScope, StoreError};
use async_trait::async_trait;
use time::OffsetDateTime;
use tokio::sync::Mutex;

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

pub(crate) fn lock_key(agent_id: &str, scope: &RunScope) -> String {
    format!("agent:{agent_id}:scope:{}", scope_key(scope))
}

fn scope_key(scope: &RunScope) -> String {
    match scope {
        RunScope::Global => "global".to_owned(),
        RunScope::User(user_id) => format!("user:{user_id}"),
        RunScope::Tenant(tenant_id) => format!("tenant:{tenant_id}"),
    }
}

pub(crate) fn lease_duration(ttl: Duration) -> time::Duration {
    time::Duration::seconds(ttl.as_secs().max(1) as i64)
}
