//! Decision repository: the only path to `know:decisions`.

use rusqlite::{Connection, OptionalExtension, params};

use lifeos::Result as LifeosResult;
use lifeos::ids::new_id;
use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::error::{KnowledgeError, Result};
use crate::models::{Decision, DecisionStatus};
use crate::tables::DECISIONS_TABLE;

fn insert(conn: &Connection, decision: &Decision) -> LifeosResult<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{DECISIONS_TABLE}" (id, title, context, choice, outcome, status, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)"#
        ),
        params![
            decision.id,
            decision.title,
            decision.context,
            decision.choice,
            decision.outcome,
            decision.status.as_str(),
            decision.created_at,
            decision.sync.owner_user_id,
            decision.sync.updated_at,
            decision.sync.updated_by_device,
            decision.sync.hlc,
            decision.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn row_to_decision(row: &rusqlite::Row<'_>) -> rusqlite::Result<Decision> {
    Ok(Decision {
        id: row.get(0)?,
        title: row.get(1)?,
        context: row.get(2)?,
        choice: row.get(3)?,
        outcome: row.get(4)?,
        status: row
            .get::<_, String>(5)
            .ok()
            .and_then(|s| DecisionStatus::parse(&s))
            .unwrap_or(DecisionStatus::Active),
        created_at: row.get(6)?,
        sync: SyncMeta {
            owner_user_id: row.get(7)?,
            updated_at: row.get(8)?,
            updated_by_device: row.get(9)?,
            hlc: row.get(10)?,
            deleted_at: row.get(11)?,
        },
    })
}

const DECISION_SELECT: &str = r#"SELECT id, title, context, choice, outcome, status, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "know:decisions""#;

pub fn get(conn: &Connection, id: &str) -> Result<Option<Decision>> {
    let mut stmt = conn.prepare_cached(&format!("{DECISION_SELECT} WHERE id = ?1"))?;
    Ok(stmt.query_row(params![id], row_to_decision).optional()?)
}

pub fn get_required(conn: &Connection, id: &str) -> Result<Decision> {
    get(conn, id)?.ok_or_else(|| KnowledgeError::DecisionNotFound(id.to_owned()))
}

/// Newest decisions first.
pub fn list_recent(conn: &Connection, limit: i64) -> Result<Vec<Decision>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{DECISION_SELECT} WHERE deleted_at IS NULL ORDER BY created_at DESC, hlc DESC LIMIT ?1"
    ))?;
    let rows = stmt.query_map(params![limit], row_to_decision)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn create(
    conn: &mut Connection,
    stamper: &MutationStamper,
    new: crate::models::NewDecision,
) -> Result<Decision> {
    if new.title.trim().is_empty() {
        return Err(KnowledgeError::InvalidData(
            "decision title is empty".into(),
        ));
    }
    if new.choice.trim().is_empty() {
        return Err(KnowledgeError::InvalidData(
            "decision choice is empty".into(),
        ));
    }
    let stamp = stamper.stamp(conn)?;
    let decision = Decision {
        id: new_id(),
        title: new.title,
        context: new.context,
        choice: new.choice,
        outcome: new.outcome,
        status: new.status,
        created_at: new.created_at,
        sync: SyncMeta::from_stamp(&stamp),
    };
    let tx = conn.transaction()?;
    insert(&tx, &decision)?;
    outbox::enqueue(&tx, DECISIONS_TABLE, &decision.id)?;
    tx.commit()?;
    Ok(decision)
}

/// Review update: status and (optionally) the recorded outcome in one
/// stamped mutation.
pub fn review(
    conn: &mut Connection,
    stamper: &MutationStamper,
    id: &str,
    status: DecisionStatus,
    outcome: Option<String>,
) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let tx = conn.transaction()?;
    let updated = tx.execute(
        &format!(
            r#"UPDATE "{DECISIONS_TABLE}" SET status = ?2, outcome = ?3, hlc = ?4, updated_by_device = ?5, updated_at = ?6 WHERE id = ?1 AND deleted_at IS NULL"#
        ),
        params![
            id,
            status.as_str(),
            outcome,
            stamp.hlc,
            stamp.device_id,
            stamp.now.div_euclid(1000),
        ],
    )?;
    if updated == 0 {
        return Err(KnowledgeError::DecisionNotFound(id.to_owned()));
    }
    outbox::enqueue(&tx, DECISIONS_TABLE, id)?;
    tx.commit()?;
    Ok(())
}

/// Tombstone delete (sync carries the deletion).
pub fn soft_delete(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let deleted_at = stamp.now.div_euclid(1000);
    let tx = conn.transaction()?;
    tx.execute(
        &format!(
            r#"UPDATE "{DECISIONS_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    outbox::enqueue(&tx, DECISIONS_TABLE, id)?;
    tx.commit()?;
    Ok(())
}
