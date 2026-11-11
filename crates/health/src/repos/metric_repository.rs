//! Metric repository: the only path to `health:metrics`.

use rusqlite::{Connection, OptionalExtension, params};
use rust_decimal::Decimal;

use lifeos::Result as LifeosResult;
use lifeos::ids::new_id;
use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::error::{HealthError, Result};
use crate::models::{Metric, MetricKind, NewMetric};
use crate::tables::METRICS_TABLE;

fn insert(conn: &Connection, metric: &Metric) -> LifeosResult<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{METRICS_TABLE}" (id, kind, quantity, recorded_at, unit, source, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"#
        ),
        params![
            metric.id,
            metric.kind.as_str(),
            metric.quantity.to_string(),
            metric.recorded_at,
            metric.unit,
            metric.source,
            metric.sync.owner_user_id,
            metric.sync.updated_at,
            metric.sync.updated_by_device,
            metric.sync.hlc,
            metric.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn row_to_metric(row: &rusqlite::Row<'_>) -> rusqlite::Result<Metric> {
    let quantity = row.get::<_, String>(2)?;
    let quantity = Decimal::from_str_exact(&quantity).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(2, rusqlite::types::Type::Text, Box::new(e))
    })?;
    Ok(Metric {
        id: row.get(0)?,
        kind: row
            .get::<_, String>(1)
            .ok()
            .and_then(|s| MetricKind::parse(&s))
            .unwrap_or(MetricKind::Steps),
        quantity,
        recorded_at: row.get(3)?,
        unit: row.get(4)?,
        source: row.get(5)?,
        sync: SyncMeta {
            owner_user_id: row.get(6)?,
            updated_at: row.get(7)?,
            updated_by_device: row.get(8)?,
            hlc: row.get(9)?,
            deleted_at: row.get(10)?,
        },
    })
}

const METRIC_SELECT: &str = r#"SELECT id, kind, quantity, recorded_at, unit, source, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "health:metrics""#;

pub fn get(conn: &Connection, id: &str) -> Result<Option<Metric>> {
    let mut stmt = conn.prepare_cached(&format!("{METRIC_SELECT} WHERE id = ?1"))?;
    Ok(stmt.query_row(params![id], row_to_metric).optional()?)
}

pub fn get_required(conn: &Connection, id: &str) -> Result<Metric> {
    get(conn, id)?.ok_or_else(|| HealthError::MetricNotFound(id.to_owned()))
}

/// Newest measurements first.
pub fn list_recent(conn: &Connection, limit: i64) -> Result<Vec<Metric>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{METRIC_SELECT} WHERE deleted_at IS NULL ORDER BY recorded_at DESC, hlc DESC LIMIT ?1"
    ))?;
    let rows = stmt.query_map(params![limit], row_to_metric)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// Newest measurements of one kind first.
pub fn list_by_kind(conn: &Connection, kind: MetricKind, limit: i64) -> Result<Vec<Metric>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{METRIC_SELECT} WHERE deleted_at IS NULL AND kind = ?1 ORDER BY recorded_at DESC, hlc DESC LIMIT ?2"
    ))?;
    let rows = stmt.query_map(params![kind.as_str(), limit], row_to_metric)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// The newest measurement of one kind at or before `as_of`.
pub fn latest_by_kind(conn: &Connection, kind: MetricKind, as_of: i64) -> Result<Option<Metric>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{METRIC_SELECT} WHERE deleted_at IS NULL AND kind = ?1 AND recorded_at <= ?2 ORDER BY recorded_at DESC, hlc DESC LIMIT 1"
    ))?;
    Ok(stmt
        .query_row(params![kind.as_str(), as_of], row_to_metric)
        .optional()?)
}

pub fn create(conn: &mut Connection, stamper: &MutationStamper, new: NewMetric) -> Result<Metric> {
    if new.quantity.is_sign_negative() {
        return Err(HealthError::InvalidData(
            "metric quantity must be non-negative".into(),
        ));
    }
    let unit = if new.unit.trim().is_empty() {
        new.kind.default_unit().to_owned()
    } else {
        new.unit.trim().to_owned()
    };
    let stamp = stamper.stamp(conn)?;
    let metric = Metric {
        id: new_id(),
        kind: new.kind,
        quantity: new.quantity,
        recorded_at: new.recorded_at,
        unit,
        source: new.source,
        sync: SyncMeta::from_stamp(&stamp),
    };
    let tx = conn.transaction()?;
    insert(&tx, &metric)?;
    outbox::enqueue(&tx, METRICS_TABLE, &metric.id)?;
    tx.commit()?;
    Ok(metric)
}

/// Tombstone delete (sync carries the deletion).
pub fn soft_delete(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let deleted_at = stamp.now.div_euclid(1000);
    let tx = conn.transaction()?;
    tx.execute(
        &format!(
            r#"UPDATE "{METRICS_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    outbox::enqueue(&tx, METRICS_TABLE, id)?;
    tx.commit()?;
    Ok(())
}
