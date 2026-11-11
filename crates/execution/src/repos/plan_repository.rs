//! Plan repository: the only path to `exec:plans`.

use rusqlite::{Connection, OptionalExtension, params};

use lifeos::Result as LifeosResult;
use lifeos::ids::new_id;
use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::error::{ExecutionError, Result};
use crate::models::{Plan, PlanStatus};
use crate::tables::PLANS_TABLE;

fn insert(conn: &Connection, plan: &Plan) -> LifeosResult<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{PLANS_TABLE}" (id, title, kind, period, status, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"#
        ),
        params![
            plan.id,
            plan.title,
            plan.kind.as_str(),
            plan.period.as_str(),
            plan.status.as_str(),
            plan.created_at,
            plan.sync.owner_user_id,
            plan.sync.updated_at,
            plan.sync.updated_by_device,
            plan.sync.hlc,
            plan.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn row_to_plan(row: &rusqlite::Row<'_>) -> rusqlite::Result<Plan> {
    Ok(Plan {
        id: row.get(0)?,
        title: row.get(1)?,
        kind: row
            .get::<_, String>(2)
            .ok()
            .and_then(|s| crate::models::PlanKind::parse(&s))
            .unwrap_or(crate::models::PlanKind::Project),
        period: row
            .get::<_, String>(3)
            .ok()
            .and_then(|s| crate::models::PlanPeriod::parse(&s))
            .unwrap_or(crate::models::PlanPeriod::Open),
        status: row
            .get::<_, String>(4)
            .ok()
            .and_then(|s| PlanStatus::parse(&s))
            .unwrap_or(PlanStatus::Active),
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

const PLAN_SELECT: &str = r#"SELECT id, title, kind, period, status, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "exec:plans""#;

pub fn get(conn: &Connection, id: &str) -> Result<Option<Plan>> {
    let mut stmt = conn.prepare_cached(&format!("{PLAN_SELECT} WHERE id = ?1"))?;
    Ok(stmt.query_row(params![id], row_to_plan).optional()?)
}

pub fn get_required(conn: &Connection, id: &str) -> Result<Plan> {
    get(conn, id)?.ok_or_else(|| ExecutionError::PlanNotFound(id.to_owned()))
}

/// Open plans first (active then paused), then finished ones, each newest
/// first.
pub fn list(conn: &Connection) -> Result<Vec<Plan>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{PLAN_SELECT} WHERE deleted_at IS NULL ORDER BY CASE status WHEN 'active' THEN 0 WHEN 'paused' THEN 1 ELSE 2 END, created_at DESC"
    ))?;
    let rows = stmt.query_map([], row_to_plan)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn create(
    conn: &mut Connection,
    stamper: &MutationStamper,
    new: crate::models::NewPlan,
) -> Result<Plan> {
    if new.title.trim().is_empty() {
        return Err(ExecutionError::InvalidData("plan title is empty".into()));
    }
    let stamp = stamper.stamp(conn)?;
    let plan = Plan {
        id: new_id(),
        title: new.title,
        kind: new.kind,
        period: new.period,
        status: new.status,
        created_at: new.created_at,
        sync: SyncMeta::from_stamp(&stamp),
    };
    let tx = conn.transaction()?;
    insert(&tx, &plan)?;
    outbox::enqueue(&tx, PLANS_TABLE, &plan.id)?;
    tx.commit()?;
    Ok(plan)
}

pub fn update(conn: &mut Connection, stamper: &MutationStamper, plan: &Plan) -> Result<()> {
    if plan.title.trim().is_empty() {
        return Err(ExecutionError::InvalidData("plan title is empty".into()));
    }
    let stamp = stamper.stamp(conn)?;
    let mut updated = plan.clone();
    updated.sync = SyncMeta::from_stamp(&stamp);
    let tx = conn.transaction()?;
    insert(&tx, &updated)?;
    outbox::enqueue(&tx, PLANS_TABLE, &updated.id)?;
    tx.commit()?;
    Ok(())
}

/// Tombstone delete (sync carries the deletion). Actions keep their
/// `plan_id` — the id simply no longer resolves (the Flutter rule "close
/// or delete moves its actions to Inbox" is a UI concern over open
/// actions).
pub fn soft_delete(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let deleted_at = stamp.now.div_euclid(1000);
    let tx = conn.transaction()?;
    tx.execute(
        &format!(
            r#"UPDATE "{PLANS_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    outbox::enqueue(&tx, PLANS_TABLE, id)?;
    tx.commit()?;
    Ok(())
}
