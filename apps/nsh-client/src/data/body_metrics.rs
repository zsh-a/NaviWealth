//! Estimated body composition per day ([`navi_health::bodycomp`]), kept in
//! the database ([`super::db`]) and mirrored in a signal in day order, like
//! [`super::weights`]. Until the scale link exists the table stays empty;
//! nothing here is ever estimated from a manually entered weight.

use nsh_core::prelude::*;
use rusqlite::{Connection, params};

use super::{clock, db};
use crate::domain::meal::Day;
use navi_health::bodycomp::BodyMetrics;

/// One day's composition with when the estimate was kept.
#[derive(Clone, PartialEq)]
pub struct Metric {
    pub day: Day,
    pub metrics: BodyMetrics,
    pub fetched_at_ms: i64,
}

#[derive(Clone, Default, PartialEq)]
struct Metrics(Vec<Metric>);

fn metrics() -> Signal<Metrics> {
    global::<Metrics>()
}

/// Reads the kept estimates; the root calls it once, after [`db::open`].
pub fn load() {
    let list = db::with(|connection| {
        read_all(connection).unwrap_or_else(|error| {
            log::error!("body_metrics: cannot read the database: {error}");
            Vec::new()
        })
    })
    .unwrap_or_default();
    metrics().set(Metrics(list));
}

fn read_all(connection: &Connection) -> rusqlite::Result<Vec<Metric>> {
    let mut statement =
        connection.prepare("SELECT day, body, fetched_at_ms FROM body_metrics ORDER BY day")?;
    let rows = statement.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, i64>(2)?,
        ))
    })?;
    let mut list = Vec::new();
    for row in rows {
        let (day, body, fetched_at_ms) = row?;
        match (day.parse(), serde_json::from_str::<BodyMetrics>(&body)) {
            (Ok(date), Ok(value)) if value.valid() => list.push(Metric {
                day: Day(date),
                metrics: value,
                fetched_at_ms,
            }),
            _ => log::warn!("body_metrics: dropped unreadable entry for {day}"),
        }
    }
    Ok(list)
}

/// The estimate of `day` (tracked).
pub fn on(day: Day) -> Option<Metric> {
    metrics().with(|m| m.0.iter().find(|m| m.day == day).cloned())
}

/// The latest estimate on or before `day` (tracked).
pub fn latest_until(day: Day) -> Option<Metric> {
    metrics().with(|m| m.0.iter().rev().find(|m| m.day <= day).cloned())
}

/// The estimates of the `days` days ending on `day` (tracked).
pub fn window(day: Day, days: i32) -> Vec<Metric> {
    let first = day.plus_days(1 - days);
    metrics().with(|m| {
        m.0.iter()
            .filter(|m| m.day >= first && m.day <= day)
            .cloned()
            .collect()
    })
}

/// Keeps `metrics` as `day`'s estimate, replacing it. Refuses invalid
/// values. Used by the preview seed; real scale readings use scale's atomic
/// confirmation service. Nothing estimates it from a manually entered weight.
pub fn set(day: Day, value: BodyMetrics) -> bool {
    let value = BodyMetrics {
        body_fat_percent: rounded(value.body_fat_percent),
        muscle_percent: rounded(value.muscle_percent),
        water_percent: rounded(value.water_percent),
        resistance_ohm: value.resistance_ohm.map(|r| (r * 100.0).round() / 100.0),
        model: value.model,
    };
    if !value.valid() {
        return false;
    }
    let metric = Metric {
        day,
        metrics: value,
        fetched_at_ms: clock::now_ms(),
    };
    let body = match serde_json::to_string(&metric.metrics) {
        Ok(body) => body,
        Err(error) => {
            log::error!("body_metrics: {day} was not serialised: {error}");
            return false;
        }
    };
    let written = db::with(|connection| -> rusqlite::Result<()> {
        let tx = connection.unchecked_transaction()?;
        // A standalone composition write cannot retain provenance from a
        // different scale estimate. Real measurements use scale::confirm.
        tx.execute(
            "DELETE FROM scale_measurements WHERE day=?1",
            [day.to_string()],
        )?;
        tx.execute(
            "INSERT INTO body_metrics (day, body, fetched_at_ms) VALUES (?1, ?2, ?3)
             ON CONFLICT (day) DO UPDATE SET body = excluded.body, fetched_at_ms = excluded.fetched_at_ms",
            params![day.to_string(), body, metric.fetched_at_ms],
        )?;
        tx.commit()
    });
    if !matches!(written, Some(Ok(_))) {
        log::error!("body_metrics: {day} was not kept");
        return false;
    }
    metrics().update(|m| {
        m.0.retain(|kept| kept.day != day);
        let at = m.0.partition_point(|kept| kept.day < day);
        m.0.insert(at, metric);
    });
    true
}

/// Shares are kept to one decimal, as they are shown.
fn rounded(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}
