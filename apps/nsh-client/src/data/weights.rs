//! Body weight entries, kept in the database ([`super::db`]) and mirrored
//! in a signal in day order. Pages change them only with [`set`] and
//! [`remove`]; each change is written before the signal moves.

use nsh_core::prelude::*;
use rusqlite::{Connection, OptionalExtension, params};

use super::{body_metrics, clock, db, scale};
use crate::domain::{
    meal::Day,
    weight::{self, Weight},
};

#[derive(Clone, Default, PartialEq)]
struct Weights(Vec<Weight>);

fn weights() -> Signal<Weights> {
    global::<Weights>()
}

/// Reads the kept entries; the root calls it once, after [`db::open`].
pub fn load() {
    let list = db::with(|connection| {
        read_all(connection).unwrap_or_else(|error| {
            log::error!("weights: cannot read the database: {error}");
            Vec::new()
        })
    })
    .unwrap_or_default();
    weights().set(Weights(list));
}

fn read_all(connection: &Connection) -> rusqlite::Result<Vec<Weight>> {
    let mut statement =
        connection.prepare("SELECT day, kg, logged_at_ms FROM weights ORDER BY day")?;
    let rows = statement.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, f64>(1)?,
            row.get::<_, i64>(2)?,
        ))
    })?;
    let mut list = Vec::new();
    for row in rows {
        let (day, kg, logged_at_ms) = row?;
        match day.parse() {
            Ok(date) if weight::valid_kg(kg) => list.push(Weight {
                day: Day(date),
                kg,
                logged_at_ms,
            }),
            _ => log::warn!("weights: dropped unreadable entry for {day}"),
        }
    }
    Ok(list)
}

/// The entry of `day` (tracked).
pub fn on(day: Day) -> Option<Weight> {
    weights().with(|w| w.0.iter().find(|w| w.day == day).copied())
}

/// The latest entry on or before `day` (tracked).
pub fn latest_until(day: Day) -> Option<Weight> {
    weights().with(|w| weight::latest_until(&w.0, day))
}

/// The change over about a week to `latest` (tracked).
pub fn weekly_change(latest: Weight) -> Option<f64> {
    weights().with(|w| weight::trend_change(&w.0, latest.day.plus_days(-7), latest.day))
}

/// Every entry in day order (tracked).
pub fn all() -> Vec<Weight> {
    weights().with(|w| w.0.clone())
}

/// The entries of the `days` days ending on `day` (tracked).
pub fn window(day: Day, days: i32) -> Vec<Weight> {
    weights().with(|w| weight::window(&w.0, day, days))
}

/// Keeps `kg` (rounded to 0.1) as `day`'s weight, replacing its entry.
/// Refuses a weight outside the accepted range.
pub fn set(day: Day, kg: f64) -> bool {
    let kg = weight::rounded(kg);
    if !weight::valid_kg(kg) {
        return false;
    }
    let entry = Weight {
        day,
        kg,
        logged_at_ms: clock::now_ms(),
    };
    let written = db::with(|connection| -> rusqlite::Result<()> {
        let tx = connection.unchecked_transaction()?;
        scale::reconcile_weight_in_transaction(&tx, &day.to_string(), Some(kg))?;
        tx.execute(
            "INSERT INTO weights (day, kg, logged_at_ms) VALUES (?1, ?2, ?3)
             ON CONFLICT (day) DO UPDATE SET kg = excluded.kg, logged_at_ms = excluded.logged_at_ms",
            params![day.to_string(), entry.kg, entry.logged_at_ms],
        )?;
        tx.commit()
    });
    if !matches!(written, Some(Ok(()))) {
        log::error!("weights: could not keep {day}");
        return false;
    }
    load();
    body_metrics::load();
    true
}

/// The removed measurement is held only for the current Undo action.
#[derive(Clone, PartialEq)]
pub(super) struct Removed {
    weight: Weight,
    metric: Option<(String, i64)>,
    provenance: Option<(String, String)>,
    revision: i64,
}
#[derive(Clone, Default, PartialEq)]
struct Removals(Vec<Removed>);
fn removals() -> Signal<Removals> {
    global::<Removals>()
}

/// Removes the day's weight and its associated composition in one transaction.
/// Its Rust-owned Undo snapshot is returned through the unchanged Weight API.
pub fn remove(day: Day) -> Option<Weight> {
    let removed = db::with(|connection| remove_in(connection, day))?.ok()??;
    let weight = removed.weight;
    removals().update(|r| {
        r.0.retain(|r| r.weight.day != day);
        r.0.push(removed);
        if r.0.len() > 16 {
            r.0.remove(0);
        }
    });
    load();
    body_metrics::load();
    Some(weight)
}

fn remove_in(connection: &Connection, day: Day) -> rusqlite::Result<Option<Removed>> {
    let tx = connection.unchecked_transaction()?;
    let Some(mut removed) = snapshot_on(&tx, day)? else {
        return Ok(None);
    };
    scale::reconcile_weight_in_transaction(&tx, &day.to_string(), None)?;
    tx.execute("DELETE FROM weights WHERE day=?1", [day.to_string()])?;
    removed.revision = weight_revision(&tx, day)?;
    tx.commit()?;
    Ok(Some(removed))
}

pub(super) fn weight_revision(c: &Connection, day: Day) -> rusqlite::Result<i64> {
    Ok(c.query_row(
        "SELECT revision FROM weight_revisions WHERE day=?1",
        [day.to_string()],
        |r| r.get(0),
    )
    .optional()?
    .unwrap_or(0))
}

pub(super) fn snapshot_on(connection: &Connection, day: Day) -> rusqlite::Result<Option<Removed>> {
    let weight = connection
        .query_row(
            "SELECT kg, logged_at_ms FROM weights WHERE day=?1",
            [day.to_string()],
            |r| {
                Ok(Weight {
                    day,
                    kg: r.get(0)?,
                    logged_at_ms: r.get(1)?,
                })
            },
        )
        .optional()?;
    let Some(weight) = weight else {
        return Ok(None);
    };
    let metric = connection
        .query_row(
            "SELECT body, fetched_at_ms FROM body_metrics WHERE day=?1",
            [day.to_string()],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    let provenance = connection
        .query_row(
            "SELECT session_id, body FROM scale_measurements WHERE day=?1",
            [day.to_string()],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    Ok(Some(Removed {
        weight,
        metric,
        provenance,
        revision: weight_revision(connection, day)?,
    }))
}

/// Restores exactly a removed weight, composition and provenance, unless another
/// edit has happened since deletion. Never overwrites an intervening measurement.
pub fn restore_removed(weight: Weight) -> bool {
    let Some(removed) =
        removals().with_untracked(|r| r.0.iter().find(|r| r.weight == weight).cloned())
    else {
        return false;
    };
    let restored = db::with(|c| restore_in(c, &removed));
    if !matches!(restored, Some(Ok(true))) {
        return false;
    }
    removals().update(|r| r.0.retain(|r| r.weight != weight));
    load();
    body_metrics::load();
    true
}
fn restore_in(c: &Connection, removed: &Removed) -> rusqlite::Result<bool> {
    let tx = c.unchecked_transaction()?;
    let day = removed.weight.day.to_string();
    let existing: Option<f64> = tx
        .query_row("SELECT kg FROM weights WHERE day=?1", [&day], |r| r.get(0))
        .optional()?;
    let revision: i64 = tx
        .query_row(
            "SELECT revision FROM weight_revisions WHERE day=?1",
            [&day],
            |r| r.get(0),
        )
        .optional()?
        .unwrap_or(0);
    if existing.is_some() || revision != removed.revision {
        return Ok(false);
    }
    insert_snapshot(&tx, removed)?;
    tx.commit()?;
    Ok(true)
}

pub(super) fn insert_snapshot(c: &Connection, removed: &Removed) -> rusqlite::Result<()> {
    let day = removed.weight.day.to_string();
    c.execute(
        "INSERT INTO weights(day,kg,logged_at_ms) VALUES(?1,?2,?3)",
        params![day, removed.weight.kg, removed.weight.logged_at_ms],
    )?;
    if let Some((body, at)) = &removed.metric {
        c.execute(
            "INSERT INTO body_metrics(day,body,fetched_at_ms) VALUES(?1,?2,?3)",
            params![day, body, at],
        )?;
    }
    if let Some((id, body)) = &removed.provenance {
        c.execute(
            "INSERT INTO scale_measurements(day,session_id,body) VALUES(?1,?2,?3)",
            params![day, id, body],
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use navi_health::{bodycomp, scale::UserProfile};
    fn seed() -> (Connection, Day) {
        let mut c = Connection::open_in_memory().unwrap();
        db::migrate(&mut c).unwrap();
        let day: Day = "2026-11-18".parse().unwrap();
        c.execute("INSERT INTO weights VALUES(?1,58.1,1)", [day.to_string()])
            .unwrap();
        let profile = UserProfile {
            height_cm: 170,
            age_years: 23,
            sex: bodycomp::Sex::Male,
        };
        let metrics = bodycomp::estimate(58.05, 170.0, 23, profile.sex, Some(506.0)).unwrap();
        c.execute(
            "INSERT INTO body_metrics VALUES(?1,?2,1)",
            params![day.to_string(), serde_json::to_string(&metrics).unwrap()],
        )
        .unwrap();
        let measurement = navi_health::scale::Measurement {
            weight_grams: 58_050,
            resistance_ohm: Some(506.0),
            raw_impedances: vec![506.0, 465.0],
            metrics: Some(metrics),
            profile,
            algorithm_version: navi_health::scale::ALGORITHM_VERSION.into(),
        };
        let preview = scale::Preview {
            session_id: "1".repeat(32),
            token: "2".repeat(32),
            day,
            measured_at_ms: 1,
            device: scale::Device {
                id: "device".into(),
                name: "AFU-WL".into(),
            },
            measurement,
            existing_kg: None,
        };
        let body = serde_json::json!({"preview":preview,"confirmed_at_ms":2}).to_string();
        c.execute(
            "INSERT INTO scale_measurements VALUES(?1,?2,?3)",
            params![day.to_string(), preview.session_id, body],
        )
        .unwrap();
        assert!(scale::validate_saved(&c).is_ok());
        (c, day)
    }
    fn count(c: &Connection, table: &str) -> i64 {
        c.query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))
            .unwrap()
    }
    #[test]
    fn delete_undo_restores_composition_and_provenance_together() {
        let (c, day) = seed();
        let removed = remove_in(&c, day).unwrap().unwrap();
        for table in ["weights", "body_metrics", "scale_measurements"] {
            assert_eq!(count(&c, table), 0);
        }
        assert!(restore_in(&c, &removed).unwrap());
        for table in ["weights", "body_metrics", "scale_measurements"] {
            assert_eq!(count(&c, table), 1);
        }
        assert!(scale::validate_saved(&c).is_ok());
        assert!(
            !restore_in(&c, &removed).unwrap(),
            "Undo cannot duplicate an entry"
        );
    }
    #[test]
    fn undo_refuses_any_intervening_weight_edit_even_if_then_deleted() {
        let (c, day) = seed();
        let removed = remove_in(&c, day).unwrap().unwrap();
        c.execute("INSERT INTO weights VALUES(?1,80,5)", [day.to_string()])
            .unwrap();
        c.execute("DELETE FROM weights WHERE day=?1", [day.to_string()])
            .unwrap();
        assert!(!restore_in(&c, &removed).unwrap());
        assert_eq!(count(&c, "weights"), 0);
    }
    #[test]
    fn delete_and_undo_roll_back_whole_health_record_on_write_failure() {
        let (c, day) = seed();
        c.execute_batch("CREATE TRIGGER fail_delete BEFORE DELETE ON body_metrics BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
        assert!(remove_in(&c, day).is_err());
        for table in ["weights", "body_metrics", "scale_measurements"] {
            assert_eq!(count(&c, table), 1);
        }
        c.execute_batch("DROP TRIGGER fail_delete").unwrap();
        let removed = remove_in(&c, day).unwrap().unwrap();
        c.execute_batch("CREATE TRIGGER fail_undo BEFORE INSERT ON scale_measurements BEGIN SELECT RAISE(ABORT,'full disk'); END;").unwrap();
        assert!(restore_in(&c, &removed).is_err());
        for table in ["weights", "body_metrics", "scale_measurements"] {
            assert_eq!(count(&c, table), 0);
        }
    }
    #[test]
    fn manual_weight_changes_clear_estimates_but_same_value_keeps_them() {
        let (c, day) = seed();
        scale::reconcile_weight_in_transaction(&c, &day.to_string(), Some(58.1)).unwrap();
        assert_eq!(count(&c, "body_metrics"), 1);
        let tx = c.unchecked_transaction().unwrap();
        scale::reconcile_weight_in_transaction(&tx, &day.to_string(), Some(60.0)).unwrap();
        tx.execute("UPDATE weights SET kg=60", []).unwrap();
        tx.commit().unwrap();
        assert_eq!(count(&c, "body_metrics"), 0);
        assert_eq!(count(&c, "scale_measurements"), 0);
    }
}
