//! Action repository: the only path to `exec:actions`. A status
//! transition *is* the progress record for this phase (no separate
//! progress table).

use rusqlite::{Connection, OptionalExtension, params};

use lifeos::Result as LifeosResult;
use lifeos::ids::new_id;
use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::error::{ExecutionError, Result};
use crate::models::{Action, ActionStatus};
use crate::tables::ACTIONS_TABLE;

fn insert(conn: &Connection, action: &Action) -> LifeosResult<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{ACTIONS_TABLE}" (id, plan_id, title, status, due, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"#
        ),
        params![
            action.id,
            action.plan_id,
            action.title,
            action.status.as_str(),
            action.due,
            action.created_at,
            action.sync.owner_user_id,
            action.sync.updated_at,
            action.sync.updated_by_device,
            action.sync.hlc,
            action.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn row_to_action(row: &rusqlite::Row<'_>) -> rusqlite::Result<Action> {
    Ok(Action {
        id: row.get(0)?,
        plan_id: row.get(1)?,
        title: row.get(2)?,
        status: row
            .get::<_, String>(3)
            .ok()
            .and_then(|s| ActionStatus::parse(&s))
            .unwrap_or(ActionStatus::Todo),
        due: row.get(4)?,
        created_at: row.get(5)?,
        sync: SyncMeta {
            owner_user_id: row.get(6)?,
            updated_at: row.get(7)?,
            updated_by_device: row.get(8)?,
            hlc: row.get(9)?,
            deleted_at: row.get(10)?,
        },
    })
}

const ACTION_SELECT: &str = r#"SELECT id, plan_id, title, status, due, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "exec:actions""#;

pub fn get(conn: &Connection, id: &str) -> Result<Option<Action>> {
    let mut stmt = conn.prepare_cached(&format!("{ACTION_SELECT} WHERE id = ?1"))?;
    Ok(stmt.query_row(params![id], row_to_action).optional()?)
}

pub fn get_required(conn: &Connection, id: &str) -> Result<Action> {
    get(conn, id)?.ok_or_else(|| ExecutionError::ActionNotFound(id.to_owned()))
}

/// Open actions first (todo/doing/blocked), then finished ones; within a
/// group the earliest due first, unscheduled last.
pub fn list_by_plan(conn: &Connection, plan_id: &str) -> Result<Vec<Action>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{ACTION_SELECT} WHERE deleted_at IS NULL AND plan_id = ?1 ORDER BY CASE status WHEN 'todo' THEN 0 WHEN 'doing' THEN 1 WHEN 'blocked' THEN 2 ELSE 3 END, due IS NOT NULL DESC, due, created_at"
    ))?;
    let rows = stmt.query_map(params![plan_id], row_to_action)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// Open actions across every plan (a "today" view).
pub fn list_open(conn: &Connection, limit: i64) -> Result<Vec<Action>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{ACTION_SELECT} WHERE deleted_at IS NULL AND status IN ('todo', 'doing', 'blocked') ORDER BY due IS NOT NULL DESC, due, created_at LIMIT ?1"
    ))?;
    let rows = stmt.query_map(params![limit], row_to_action)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn create(
    conn: &mut Connection,
    stamper: &MutationStamper,
    new: crate::models::NewAction,
) -> Result<Action> {
    if new.title.trim().is_empty() {
        return Err(ExecutionError::InvalidData("action title is empty".into()));
    }
    if new.plan_id.trim().is_empty() {
        return Err(ExecutionError::InvalidData(
            "action plan_id is empty".into(),
        ));
    }
    let stamp = stamper.stamp(conn)?;
    let action = Action {
        id: new_id(),
        plan_id: new.plan_id,
        title: new.title,
        status: ActionStatus::Todo,
        due: new.due,
        created_at: new.created_at,
        sync: SyncMeta::from_stamp(&stamp),
    };
    let tx = conn.transaction()?;
    insert(&tx, &action)?;
    outbox::enqueue(&tx, ACTIONS_TABLE, &action.id)?;
    tx.commit()?;
    Ok(action)
}

pub fn update(conn: &mut Connection, stamper: &MutationStamper, action: &Action) -> Result<()> {
    if action.title.trim().is_empty() {
        return Err(ExecutionError::InvalidData("action title is empty".into()));
    }
    let stamp = stamper.stamp(conn)?;
    let mut updated = action.clone();
    updated.sync = SyncMeta::from_stamp(&stamp);
    let tx = conn.transaction()?;
    insert(&tx, &updated)?;
    outbox::enqueue(&tx, ACTIONS_TABLE, &updated.id)?;
    tx.commit()?;
    Ok(())
}

/// Move an action between statuses (`todo → doing → done`, `dropped`,
/// …). The transition is the progress record; nothing else is written.
pub fn set_status(
    conn: &mut Connection,
    stamper: &MutationStamper,
    id: &str,
    status: ActionStatus,
) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let tx = conn.transaction()?;
    let updated = tx.execute(
        &format!(
            r#"UPDATE "{ACTIONS_TABLE}" SET status = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1 AND deleted_at IS NULL"#
        ),
        params![
            id,
            status.as_str(),
            stamp.hlc,
            stamp.device_id,
            stamp.now.div_euclid(1000),
        ],
    )?;
    if updated == 0 {
        return Err(ExecutionError::ActionNotFound(id.to_owned()));
    }
    outbox::enqueue(&tx, ACTIONS_TABLE, id)?;
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
            r#"UPDATE "{ACTIONS_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    outbox::enqueue(&tx, ACTIONS_TABLE, id)?;
    tx.commit()?;
    Ok(())
}
