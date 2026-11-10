//! The sync v3 engine: row-state, LWW, accepted acknowledgements and
//! per-domain reset generations over one `POST /sync` endpoint.
//!
//! Cycle: read the cursor and the dirty outbox pointers, re-read current
//! row state (≤ 500 per request), push, apply the pull page in one
//! transaction (skip when the local HLC already wins), clear accepted
//! pointers, adopt the cursor, compare domain generations and run the
//! domain-reset handler on mismatch. `more` pages loop with the advanced
//! cursor.

use std::collections::BTreeMap;
use std::sync::Arc;

use rusqlite::Connection;

use crate::db::Db;
use crate::db::settings;
use crate::error::{LifeosError, Result};

use super::outbox;
use super::registry::SyncRegistry;
use super::stamp::{DEVICE_KEY, MutationStamper, OWNER_KEY};
use super::transport::SyncTransport;
use super::types::{Domain, RowChange, SyncRequest, SyncResponse};

/// Mirrors the backend's push limit (`apps/backend/src/routes/sync.rs`).
pub const MAX_CHANGES: usize = 500;

/// Supplies the bearer token for sync calls.
pub trait AuthTokenProvider: Send + Sync {
    fn bearer_token(&self) -> Result<Option<String>>;
}

/// Reads the stored session from `settings`.
#[derive(Debug, Clone)]
pub struct SettingsTokenProvider {
    db: Db,
}

impl SettingsTokenProvider {
    pub fn new(db: Db) -> Self {
        Self { db }
    }
}

impl AuthTokenProvider for SettingsTokenProvider {
    fn bearer_token(&self) -> Result<Option<String>> {
        self.db.call_sync(|conn| {
            let token = settings::get_setting(conn, "sync.access_token")?;
            Ok(token.filter(|t| !t.is_empty()))
        })
    }
}

/// Runs inside the apply transaction when the server generation for a
/// domain moved: wipe the domain's local rows.
pub type DomainResetHandler = Arc<dyn Fn(&Connection, Domain) -> Result<()> + Send + Sync>;

#[derive(Debug, Clone, Default)]
pub struct SyncOutcome {
    pub pushed: usize,
    pub applied: usize,
    pub cursor: i64,
    pub resets: Vec<Domain>,
}

pub struct SyncEngine {
    db: Db,
    registry: SyncRegistry,
    transport: Arc<dyn SyncTransport>,
    auth: Arc<dyn AuthTokenProvider>,
    stamper: MutationStamper,
    on_domain_reset: BTreeMap<Domain, DomainResetHandler>,
}

impl SyncEngine {
    pub fn new(
        db: Db,
        registry: SyncRegistry,
        transport: Arc<dyn SyncTransport>,
        auth: Arc<dyn AuthTokenProvider>,
        stamper: MutationStamper,
    ) -> Self {
        Self {
            db,
            registry,
            transport,
            auth,
            stamper,
            on_domain_reset: BTreeMap::new(),
        }
    }

    pub fn set_domain_reset_handler(&mut self, domain: Domain, handler: DomainResetHandler) {
        self.on_domain_reset.insert(domain, handler);
    }

    fn device_id(conn: &Connection) -> Result<String> {
        settings::get_setting(conn, DEVICE_KEY)?
            .filter(|v| !v.is_empty())
            .ok_or_else(|| LifeosError::Sync("device id not initialized".into()))
    }

    fn stored_generation(conn: &Connection, domain: Domain) -> Result<i64> {
        Ok(
            settings::get_setting(conn, &format!("sync.gen.{}", domain.as_str()))?
                .and_then(|v| v.parse().ok())
                .unwrap_or(0),
        )
    }

    fn store_generation(conn: &Connection, domain: Domain, generation: i64) -> Result<()> {
        settings::set_setting(
            conn,
            &format!("sync.gen.{}", domain.as_str()),
            &generation.to_string(),
        )
    }

    /// One full sync cycle (with pull pagination).
    pub async fn sync_once(&self) -> Result<SyncOutcome> {
        let mut outcome = SyncOutcome::default();
        let mut since = self.cursor().await;
        let mut first_page = true;

        loop {
            let (device_id, changes) = {
                let registry = self.registry.clone();
                let registry = registry.clone();
                self.db
                    .call(move |conn| {
                        let device_id = Self::device_id(conn)?;
                        let changes =
                            collect_push_changes(&registry, conn, &device_id, MAX_CHANGES)?;
                        Ok((device_id, changes))
                    })
                    .await?
            };
            let pushed = changes.len();

            let request = SyncRequest {
                device_id: device_id.clone(),
                since,
                changes,
            };
            let response = self
                .transport
                .post_sync(request, self.auth.bearer_token()?)
                .await?;

            if response.more && response.seq <= since {
                return Err(LifeosError::SyncCursorStalled);
            }

            // First page: adopt generations before applying, so stale local
            // rows are wiped before current-generation rows land.
            if first_page && !response.domain_generations.is_empty() {
                let registry = self.registry.clone();
                let generations = response.domain_generations.clone();
                outcome.resets = self
                    .db
                    .call(move |conn| adopt_generations(&registry, conn, &generations))
                    .await?;
                first_page = false;
            }

            let applied = {
                let stamper = self.stamper.clone();
                let registry = self.registry.clone();
                let response = response.clone();
                self.db
                    .call(move |conn| {
                        let applied = apply_page(&stamper, &registry, conn, &response)?;
                        settings::set_setting(conn, "sync.cursor", &response.seq.to_string())?;
                        Ok(applied)
                    })
                    .await?
            };

            outcome.pushed += pushed;
            outcome.applied += applied;
            outcome.cursor = response.seq;
            since = response.seq;

            if !response.more {
                break;
            }
        }

        tracing::info!(
            pushed = outcome.pushed,
            applied = outcome.applied,
            cursor = outcome.cursor,
            resets = ?outcome.resets,
            "sync cycle complete"
        );
        Ok(outcome)
    }

    async fn cursor(&self) -> i64 {
        self.db
            .call(|conn| {
                Ok(settings::get_setting(conn, "sync.cursor")?
                    .and_then(|v| v.parse().ok())
                    .unwrap_or(0))
            })
            .await
            .unwrap_or(0)
    }

    /// Server-side domain reset: wipe local rows, adopt the new generation.
    pub async fn reset_domain(&self, domain: Domain) -> Result<i64> {
        let generation = self
            .transport
            .reset_domain(domain, self.auth.bearer_token()?)
            .await?;
        let registry = self.registry.clone();
        self.db
            .call(move |conn| {
                let tx = conn.transaction()?;
                for adapter in registry.adapters_for_domain(domain) {
                    adapter.delete_all(&tx)?;
                    outbox::clear_table(&tx, adapter.table())?;
                }
                Self::store_generation(&tx, domain, generation)?;
                tx.commit()?;
                Ok(())
            })
            .await?;
        Ok(generation)
    }
}

impl std::fmt::Debug for SyncEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SyncEngine").finish_non_exhaustive()
    }
}

fn collect_push_changes(
    registry: &SyncRegistry,
    conn: &Connection,
    device_id: &str,
    limit: usize,
) -> Result<Vec<RowChange>> {
    let pointers = outbox::pending(conn, limit)?;
    let mut changes = Vec::with_capacity(pointers.len());
    for (table, row_id) in pointers {
        let Some(adapter) = registry.adapter(&table) else {
            tracing::warn!(%table, %row_id, "outbox pointer for unregistered table; dropping");
            outbox::clear(conn, &[(table.clone(), row_id)])?;
            continue;
        };
        let Some(payload) = adapter.read_row(conn, &row_id)? else {
            tracing::warn!(%table, %row_id, "dirty row vanished; dropping pointer");
            outbox::clear(conn, &[(table.clone(), row_id)])?;
            continue;
        };
        let version = payload
            .get("hlc")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_owned();
        let deleted = payload
            .get("deleted_at")
            .map(|v| !v.is_null())
            .unwrap_or(false);
        let generation = SyncEngine::stored_generation(conn, adapter.domain())?;
        changes.push(RowChange {
            table,
            id: row_id,
            payload: Some(payload),
            version,
            deleted,
            device_id: device_id.to_owned(),
            seq: 0,
            generation,
        });
    }
    Ok(changes)
}

fn apply_page(
    stamper: &MutationStamper,
    registry: &SyncRegistry,
    conn: &mut Connection,
    response: &SyncResponse,
) -> Result<usize> {
    let tx = conn.transaction()?;
    let mut applied = 0usize;

    for change in &response.changes {
        let domain = Domain::from_table(&change.table).ok_or_else(|| {
            LifeosError::Sync(format!("row table without domain prefix: {}", change.table))
        })?;
        let generation = SyncEngine::stored_generation(&tx, domain)?;
        if change.generation != 0 && generation != 0 && change.generation != generation {
            tracing::debug!(table = %change.table, id = %change.id, "stale generation row skipped");
            continue;
        }

        let Some(adapter) = registry.adapter(&change.table) else {
            tracing::warn!(table = %change.table, "pull for unregistered table skipped");
            continue;
        };

        // LWW: the local row wins when its HLC is not older.
        let local_version = adapter
            .read_row(&tx, &change.id)?
            .and_then(|row| row.get("hlc").and_then(|v| v.as_str()).map(str::to_owned));
        if let Some(local) = local_version
            && local.as_str() >= change.version.as_str()
        {
            continue;
        }

        if change.deleted {
            adapter.apply_tombstone(&tx, &change.id, &change.version, &change.device_id)?;
        } else {
            let payload = change.payload.as_ref().ok_or_else(|| {
                LifeosError::Sync(format!("pull row {} without payload", change.id))
            })?;
            adapter.apply_upsert(&tx, payload)?;
        }
        stamper.merge_remote(&tx, &change.version)?;
        applied += 1;
    }

    let acks: Vec<(String, String)> = response
        .accepted
        .iter()
        .map(|ack| (ack.table.clone(), ack.id.clone()))
        .collect();
    outbox::clear(&tx, &acks)?;

    tx.commit()?;
    Ok(applied)
}

fn adopt_generations(
    registry: &SyncRegistry,
    conn: &mut Connection,
    domain_generations: &BTreeMap<String, i64>,
) -> Result<Vec<Domain>> {
    let tx = conn.transaction()?;
    let mut resets = Vec::new();
    for (domain_str, &generation) in domain_generations {
        let Some(domain) = parse_domain(domain_str) else {
            continue;
        };
        let stored = SyncEngine::stored_generation(&tx, domain)?;
        if stored == generation {
            continue;
        }
        if generation < stored {
            return Err(LifeosError::Sync(format!(
                "server generation for {domain} moved backwards ({stored} -> {generation})"
            )));
        }
        for adapter in registry.adapters_for_domain(domain) {
            adapter.delete_all(&tx)?;
            outbox::clear_table(&tx, adapter.table())?;
        }
        SyncEngine::store_generation(&tx, domain, generation)?;
        resets.push(domain);
    }
    tx.commit()?;
    Ok(resets)
}

fn parse_domain(value: &str) -> Option<Domain> {
    match value {
        "finance" => Some(Domain::Finance),
        "health" => Some(Domain::Health),
        "knowledge" => Some(Domain::Knowledge),
        "execution" => Some(Domain::Execution),
        _ => None,
    }
}

/// Ensure the device/owner rows exist before the first sync.
pub fn ensure_identity(conn: &Connection, owner_user_id: &str, device_id: &str) -> Result<()> {
    settings::set_setting(conn, OWNER_KEY, owner_user_id)?;
    match settings::get_setting(conn, DEVICE_KEY)? {
        Some(existing) if !existing.is_empty() => {
            if existing != device_id {
                tracing::warn!("device id changed; stamps will use the new id");
                settings::set_setting(conn, DEVICE_KEY, device_id)?;
            }
        }
        _ => settings::set_setting(conn, DEVICE_KEY, device_id)?,
    }
    Ok(())
}
