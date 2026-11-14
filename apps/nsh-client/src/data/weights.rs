//! Body weight entries, kept in the database ([`super::db`]) and mirrored
//! in a signal in day order. Pages change them only with [`set`] and
//! [`remove`]; each change is written before the signal moves.

use nsh_core::prelude::*;
use rusqlite::{Connection, params};

use super::{clock, db};
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
    let written = db::with(|connection| {
        connection.execute(
            "INSERT INTO weights (day, kg, logged_at_ms) VALUES (?1, ?2, ?3)
             ON CONFLICT (day) DO UPDATE SET kg = excluded.kg, logged_at_ms = excluded.logged_at_ms",
            params![day.to_string(), entry.kg, entry.logged_at_ms],
        )
    });
    if let Some(Err(error)) = written {
        log::error!("weights: {day} was not kept: {error}");
        return false;
    }
    weights().update(|w| {
        w.0.retain(|kept| kept.day != day);
        let at = w.0.partition_point(|kept| kept.day < day);
        w.0.insert(at, entry);
    });
    true
}

/// Removes `day`'s entry and gives it back (to undo).
pub fn remove(day: Day) -> Option<Weight> {
    let removed = untracked(|| on(day))?;
    let deleted = db::with(|connection| {
        connection.execute(
            "DELETE FROM weights WHERE day = ?1",
            params![day.to_string()],
        )
    });
    if let Some(Err(error)) = deleted {
        log::error!("weights: {day} was not deleted: {error}");
        return None;
    }
    weights().update(|w| w.0.retain(|kept| kept.day != day));
    Some(removed)
}
