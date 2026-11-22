//! The owner's review notes: one line kept on a day, in the database's
//! `review_notes` table (in backups), mirrored in a private signal. The
//! Review tab shows the notes of its period; an empty line removes one.

use nsh_core::prelude::*;
use rusqlite::params;

use super::{clock, db};
use crate::domain::meal::Day;

pub use crate::domain::review::{MAX_NOTE_CHARS as MAX_CHARS, valid_note as valid};

#[derive(Clone, Default, PartialEq)]
struct Notes(Vec<(Day, String)>);

fn notes() -> Signal<Notes> {
    global::<Notes>()
}

/// Reads the kept notes; the root calls it once, after [`db::open`].
pub fn load() {
    let list = db::with(|connection| -> rusqlite::Result<Vec<(Day, String)>> {
        let mut statement =
            connection.prepare("SELECT day, text FROM review_notes ORDER BY day")?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        Ok(rows
            .flatten()
            .filter_map(|(day, text)| Some((day.parse().ok()?, text)))
            .collect())
    })
    .and_then(|read| {
        read.map_err(|error| log::error!("notes: cannot read the database: {error}"))
            .ok()
    })
    .unwrap_or_default();
    notes().set(Notes(list));
}

/// The notes of the days from `first` to `last`, in day order (tracked).
pub fn between(first: Day, last: Day) -> Vec<(Day, String)> {
    notes().with(|n| {
        n.0.iter()
            .filter(|(day, _)| *day >= first && *day <= last)
            .cloned()
            .collect()
    })
}

/// Keeps `text` (trimmed) as `day`'s note; an empty one removes it.
pub fn set(day: Day, text: &str) -> bool {
    let text = text.trim().replace(['\n', '\r'], " ");
    if text.chars().count() > MAX_CHARS {
        return false;
    }
    let written = db::with(|connection| {
        if text.is_empty() {
            connection.execute(
                "DELETE FROM review_notes WHERE day = ?1",
                params![day.to_string()],
            )
        } else {
            connection.execute(
                "INSERT INTO review_notes (day, text, updated_at_ms) VALUES (?1, ?2, ?3)
                 ON CONFLICT (day) DO UPDATE SET
                    text = excluded.text, updated_at_ms = excluded.updated_at_ms",
                params![day.to_string(), text, clock::now_ms()],
            )
        }
    });
    match written {
        Some(Ok(_)) => {}
        other => {
            log::error!("notes: {day} was not kept: {other:?}");
            return false;
        }
    }
    notes().update(|n| {
        n.0.retain(|(kept, _)| *kept != day);
        if !text.is_empty() {
            let at = n.0.partition_point(|(kept, _)| *kept < day);
            n.0.insert(at, (day, text));
        }
    });
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_note_is_one_short_line() {
        assert!(valid("Dinners stayed light."));
        assert!(!valid("  "));
        assert!(!valid("two\nlines"));
        assert!(!valid(&"x".repeat(MAX_CHARS + 1)));
    }
}
