//! Reactive mirror of committed immutable valuation observations.
use finance_core::valuation::{self, Snapshot};
use nsh_core::prelude::*;
#[derive(Clone, Default, PartialEq)]
struct State(Vec<Snapshot>);
pub fn all() -> Vec<Snapshot> {
    global::<State>().with(|s| s.0.clone())
}
pub fn load() -> Result<(), String> {
    let rows = super::db::with(valuation::load)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    global::<State>().set(State(rows));
    Ok(())
}
/// Automatic captures occur once per local day; manual captures append revisions.
pub fn capture(manual: bool) -> Result<(), String> {
    let now = super::clock::now_ms();
    let day = super::clock::day_of(now).0;
    let saved = super::db::with(|c| -> Result<Option<Snapshot>, valuation::Error> {
        if !manual && valuation::load(c)?.iter().any(|s| s.body.day == day) {
            return Ok(None);
        }
        valuation::record_current(
            c,
            day,
            jiff::Timestamp::from_millisecond(now).map_err(|_| valuation::Error::Invalid)?,
        )
        .map(Some)
    })
    .ok_or("database unavailable")?
    .map_err(|e| e.to_string())?;
    if let Some(saved) = saved {
        global::<State>().update(|s| s.0.push(saved));
    }
    Ok(())
}
