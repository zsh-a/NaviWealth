//! Snapshots stay in SQLite. Invalidate open history views after committed writes or restore.
use navi_finance::valuation;
use nsh_core::prelude::*;

#[derive(Default, Clone, PartialEq)]
struct Revision(u64);

pub fn watch() {
    global::<Revision>().with(|_| ());
}
pub fn invalidate() {
    global::<Revision>().update(|r| r.0 = r.0.wrapping_add(1));
}
pub fn read<T>(
    query: impl FnOnce(&rusqlite::Connection) -> Result<T, valuation::Error>,
) -> Result<T, String> {
    super::db::with(query)
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())
}
pub fn capture() -> Result<(), String> {
    let now = super::clock::now_ms();
    let day = super::clock::day_of(now).0;
    let at = jiff::Timestamp::from_millisecond(now).map_err(|e| e.to_string())?;
    let saved = read(|c| valuation::record_if_absent(c, day, at))?;
    if saved {
        invalidate();
    }
    Ok(())
}
