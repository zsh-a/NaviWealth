//! Note repository: the only path to `know:notes`.

use rusqlite::{Connection, OptionalExtension, params};

use lifeos::Result as LifeosResult;
use lifeos::ids::new_id;
use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::error::{KnowledgeError, Result};
use crate::models::Note;
use crate::tables::NOTES_TABLE;

fn insert(conn: &Connection, note: &Note) -> LifeosResult<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{NOTES_TABLE}" (id, title, content, source, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)"#
        ),
        params![
            note.id,
            note.title,
            note.content,
            note.source,
            note.created_at,
            note.sync.owner_user_id,
            note.sync.updated_at,
            note.sync.updated_by_device,
            note.sync.hlc,
            note.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn row_to_note(row: &rusqlite::Row<'_>) -> rusqlite::Result<Note> {
    Ok(Note {
        id: row.get(0)?,
        title: row.get(1)?,
        content: row.get(2)?,
        source: row.get(3)?,
        created_at: row.get(4)?,
        sync: SyncMeta {
            owner_user_id: row.get(5)?,
            updated_at: row.get(6)?,
            updated_by_device: row.get(7)?,
            hlc: row.get(8)?,
            deleted_at: row.get(9)?,
        },
    })
}

const NOTE_SELECT: &str = r#"SELECT id, title, content, source, created_at, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "know:notes""#;

pub fn get(conn: &Connection, id: &str) -> Result<Option<Note>> {
    let mut stmt = conn.prepare_cached(&format!("{NOTE_SELECT} WHERE id = ?1"))?;
    Ok(stmt.query_row(params![id], row_to_note).optional()?)
}

pub fn get_required(conn: &Connection, id: &str) -> Result<Note> {
    get(conn, id)?.ok_or_else(|| KnowledgeError::NoteNotFound(id.to_owned()))
}

/// Newest captures first.
pub fn list_recent(conn: &Connection, limit: i64) -> Result<Vec<Note>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{NOTE_SELECT} WHERE deleted_at IS NULL ORDER BY created_at DESC, hlc DESC LIMIT ?1"
    ))?;
    let rows = stmt.query_map(params![limit], row_to_note)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// Create a note and enqueue its outbox pointer in one transaction (one
/// HLC stamp per mutation).
pub fn create(
    conn: &mut Connection,
    stamper: &MutationStamper,
    new: crate::models::NewNote,
) -> Result<Note> {
    if new.title.trim().is_empty() {
        return Err(KnowledgeError::InvalidData("note title is empty".into()));
    }
    let stamp = stamper.stamp(conn)?;
    let note = Note {
        id: new_id(),
        title: new.title,
        content: new.content,
        source: new.source,
        created_at: new.created_at,
        sync: SyncMeta::from_stamp(&stamp),
    };
    let tx = conn.transaction()?;
    insert(&tx, &note)?;
    outbox::enqueue(&tx, NOTES_TABLE, &note.id)?;
    tx.commit()?;
    Ok(note)
}

/// Full-row LWW update (title/content/source together).
pub fn update(conn: &mut Connection, stamper: &MutationStamper, note: &Note) -> Result<()> {
    if note.title.trim().is_empty() {
        return Err(KnowledgeError::InvalidData("note title is empty".into()));
    }
    let stamp = stamper.stamp(conn)?;
    let mut updated = note.clone();
    updated.sync = SyncMeta::from_stamp(&stamp);
    let tx = conn.transaction()?;
    insert(&tx, &updated)?;
    outbox::enqueue(&tx, NOTES_TABLE, &updated.id)?;
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
            r#"UPDATE "{NOTES_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    outbox::enqueue(&tx, NOTES_TABLE, id)?;
    tx.commit()?;
    Ok(())
}
