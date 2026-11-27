//! Local assistant transcripts and owner-approved memories. They share the
//! application's SQLite transaction and encrypted backup boundary; credentials
//! are never part of these records. Persisted proposals remain unapproved
//! after restart and require a fresh, explicit action from the owner.

use std::collections::HashSet;

use rusqlite::{Connection, OptionalExtension, params};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const SCHEMA: &str = "
CREATE TABLE assistant_sessions (
    id TEXT PRIMARY KEY NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    body TEXT NOT NULL
);
CREATE INDEX assistant_sessions_updated ON assistant_sessions(updated_at_ms DESC, id);
CREATE TABLE assistant_memories (
    id TEXT PRIMARY KEY NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    body TEXT NOT NULL
);";

pub const TABLES: &[(&str, &str)] = &[
    ("assistant_sessions", "id, updated_at_ms, body"),
    ("assistant_memories", "id, updated_at_ms, body"),
];

const MAX_SESSION_BYTES: usize = 4 * 1024 * 1024;
// The host currently loads the conversation list with full replay histories.
// Bound that aggregate before materializing rows, not only each conversation.
const MAX_SESSION_TOTAL_BYTES: i64 = 32 * 1024 * 1024;
const MAX_MEMORY_BYTES: usize = 16 * 1024;
const MAX_MESSAGES: usize = 2_000;
const MAX_TEXT_BYTES: usize = 64 * 1024;
const MAX_SESSIONS: i64 = 500;
const MAX_MEMORIES: i64 = 1_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    User,
    Assistant,
    Tool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Message {
    pub id: String,
    pub role: Role,
    pub text: String,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    #[default]
    Idle,
    Running,
    Interrupted,
    Failed,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Session {
    pub id: String,
    pub title: String,
    pub created_at_ms: i64,
    pub updated_at_ms: i64,
    pub messages: Vec<Message>,
    /// Provider-native history, including tool results. It is never interpreted
    /// as a pending instruction when loading or restoring a session.
    pub history: Vec<Value>,
    pub status: Status,
    /// The configured model/protocol fingerprint. Never contains a secret.
    #[serde(default)]
    pub model_target: Option<String>,
    #[serde(default)]
    pub pending: Vec<PendingAction>,
    /// Bounded host-confirmed outcomes sent with a later prompt, so a model
    /// does not mistake a historical tool result for a still-pending proposal.
    #[serde(default)]
    pub action_outcomes: Vec<ActionOutcome>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionOutcome {
    pub proposal_id: String,
    pub status: ActionStatus,
    pub capture_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionStatus {
    Confirmed,
    Dismissed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PendingAction {
    pub id: String,
    pub kind: PendingKind,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum PendingKind {
    Memory {
        text: String,
    },
    /// Legacy text-only proposals remain readable in old chats and backups.
    Capture {
        text: String,
    },
    Records {
        proposal: Value,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Memory {
    pub id: String,
    pub text: String,
    /// Provenance, not a foreign key: deleting a chat does not silently forget
    /// a separately approved fact. The owner can delete memories explicitly.
    pub source_session: Option<String>,
    pub updated_at_ms: i64,
}

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b':'))
}

fn validate_session(session: &Session) -> Result<(), String> {
    let mut ids = HashSet::new();
    let mut outcome_ids = HashSet::new();
    if !valid_id(&session.id)
        || session.title.trim().is_empty()
        || session.title.len() > 512
        || session.created_at_ms < 0
        || session.updated_at_ms < session.created_at_ms
        || session.messages.len() > MAX_MESSAGES
        || session.history.len() > MAX_MESSAGES
        || session.history.iter().any(|message| !message.is_object())
        || session
            .model_target
            .as_ref()
            .is_some_and(|target| target.is_empty() || target.len() > 2048)
        || session.pending.len() > 8
        || session.action_outcomes.len() > 32
        || session.action_outcomes.iter().any(|outcome| {
            !valid_id(&outcome.proposal_id)
                || !outcome_ids.insert(&outcome.proposal_id)
                || outcome
                    .capture_id
                    .as_ref()
                    .is_some_and(|id| !valid_id(id) || outcome.status != ActionStatus::Confirmed)
        })
        || session.pending.iter().any(|proposal| {
            !valid_id(&proposal.id)
                || !ids.insert(&proposal.id)
                || outcome_ids.contains(&proposal.id)
                || match &proposal.kind {
                    PendingKind::Memory { text } | PendingKind::Capture { text } => {
                        text.trim().is_empty() || text.len() > 4_000
                    }
                    PendingKind::Records { proposal } => {
                        crate::domain::assistant_proposal::parse(proposal).is_err()
                    }
                }
        })
        || session.messages.iter().any(|message| {
            !valid_id(&message.id)
                || !ids.insert(&message.id)
                || message.text.len() > MAX_TEXT_BYTES
        })
    {
        return Err("Invalid assistant session".into());
    }
    navi_assistant::validate_history(&session.history)
}

fn validate_memory(memory: &Memory) -> Result<(), String> {
    if !valid_id(&memory.id)
        || memory.text.trim().is_empty()
        || memory.text.len() > 8 * 1024
        || memory.updated_at_ms < 0
        || memory
            .source_session
            .as_ref()
            .is_some_and(|id| !valid_id(id))
    {
        return Err("Invalid assistant memory".into());
    }
    Ok(())
}

fn encode<T: Serialize>(value: &T, limit: usize) -> Result<String, String> {
    let body = serde_json::to_string(value).map_err(|_| "Invalid assistant record")?;
    if body.len() > limit {
        return Err("Assistant record is too large".into());
    }
    Ok(body)
}

fn decode_session(id: String, updated_at_ms: i64, body: String) -> Result<Session, String> {
    if body.len() > MAX_SESSION_BYTES {
        return Err("Assistant session is too large".into());
    }
    let session: Session = serde_json::from_str(&body).map_err(|_| "Invalid assistant session")?;
    validate_session(&session)?;
    if session.id != id || session.updated_at_ms != updated_at_ms {
        return Err("Inconsistent assistant session".into());
    }
    Ok(session)
}

fn decode_memory(id: String, updated_at_ms: i64, body: String) -> Result<Memory, String> {
    if body.len() > MAX_MEMORY_BYTES {
        return Err("Assistant memory is too large".into());
    }
    let memory: Memory = serde_json::from_str(&body).map_err(|_| "Invalid assistant memory")?;
    validate_memory(&memory)?;
    if memory.id != id || memory.updated_at_ms != updated_at_ms {
        return Err("Inconsistent assistant memory".into());
    }
    Ok(memory)
}

/// Newest first. The bounded record count also protects backup validation.
pub fn sessions(connection: &Connection) -> Result<Vec<Session>, String> {
    let oversized: bool = connection
        .query_row(
            "SELECT COALESCE(SUM(length(CAST(body AS BLOB))),0)>?1 FROM assistant_sessions",
            [MAX_SESSION_TOTAL_BYTES],
            |row| row.get(0),
        )
        .map_err(|e| e.to_string())?;
    if oversized {
        return Err("Assistant conversation storage limit exceeded".into());
    }
    let mut query = connection
        .prepare("SELECT id, updated_at_ms, body FROM assistant_sessions ORDER BY updated_at_ms DESC, id LIMIT ?1")
        .map_err(|e| e.to_string())?;
    let rows = query
        .query_map([MAX_SESSIONS + 1], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })
        .map_err(|e| e.to_string())?;
    let mut sessions = Vec::new();
    for row in rows {
        let (id, updated, body) = row.map_err(|e| e.to_string())?;
        sessions.push(decode_session(id, updated, body)?);
        if sessions.len() > MAX_SESSIONS as usize {
            return Err("Too many assistant sessions".into());
        }
    }
    Ok(sessions)
}

pub fn session(connection: &Connection, id: &str) -> Result<Option<Session>, String> {
    connection
        .query_row(
            "SELECT id, updated_at_ms, body FROM assistant_sessions WHERE id=?1",
            [id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()
        .map_err(|e| e.to_string())?
        .map(|(id, updated, body)| decode_session(id, updated, body))
        .transpose()
}

pub fn create_session(connection: &Connection, session: &Session) -> Result<(), String> {
    validate_session(session)?;
    let body = encode(session, MAX_SESSION_BYTES)?;
    let inserted = connection
        .execute(
            "INSERT INTO assistant_sessions (id,updated_at_ms,body)
             SELECT ?1,?2,?3 WHERE (SELECT COUNT(*) FROM assistant_sessions) < ?4
             AND COALESCE((SELECT SUM(length(CAST(body AS BLOB))) FROM assistant_sessions),0)
                 + length(CAST(?3 AS BLOB)) <= ?5",
            params![
                session.id,
                session.updated_at_ms,
                body,
                MAX_SESSIONS,
                MAX_SESSION_TOTAL_BYTES
            ],
        )
        .map_err(|e| e.to_string())?;
    if inserted != 1 {
        return Err("Delete an old conversation before creating another".into());
    }
    Ok(())
}

/// Update only: an old worker cannot resurrect a deleted chat or overwrite a
/// checkpoint with an older timestamp. The host also invalidates its run token
/// before restore or cancellation so same-millisecond updates cannot race.
pub fn save_session(connection: &Connection, session: &Session) -> Result<(), String> {
    validate_session(session)?;
    let body = encode(session, MAX_SESSION_BYTES)?;
    let updated = connection
        .execute(
            "UPDATE assistant_sessions SET updated_at_ms=?2, body=?3
             WHERE id=?1 AND updated_at_ms<=?2
             AND COALESCE((SELECT SUM(length(CAST(body AS BLOB))) FROM assistant_sessions WHERE id<>?1),0)
                 + length(CAST(?3 AS BLOB)) <= ?4",
            params![session.id, session.updated_at_ms, body, MAX_SESSION_TOTAL_BYTES],
        )
        .map_err(|e| e.to_string())?;
    if updated != 1 {
        return Err(
            "Assistant session changed, was deleted, or conversation storage is full".into(),
        );
    }
    Ok(())
}

pub fn delete_session(connection: &Connection, id: &str) -> Result<(), String> {
    connection
        .execute("DELETE FROM assistant_sessions WHERE id=?1", [id])
        .map(|_| ())
        .map_err(|e| e.to_string())
}

pub fn memories(connection: &Connection) -> Result<Vec<Memory>, String> {
    let mut query = connection
        .prepare("SELECT id, updated_at_ms, body FROM assistant_memories ORDER BY updated_at_ms DESC, id LIMIT ?1")
        .map_err(|e| e.to_string())?;
    let rows = query
        .query_map([MAX_MEMORIES + 1], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })
        .map_err(|e| e.to_string())?;
    let mut memories = Vec::new();
    for row in rows {
        let (id, updated, body) = row.map_err(|e| e.to_string())?;
        memories.push(decode_memory(id, updated, body)?);
        if memories.len() > MAX_MEMORIES as usize {
            return Err("Too many assistant memories".into());
        }
    }
    Ok(memories)
}

/// Called only for owner-confirmed additions or edits, never directly by an
/// LLM tool. A proposal belongs to transient host state until confirmation.
pub fn save_memory(connection: &Connection, memory: &Memory) -> Result<(), String> {
    validate_memory(memory)?;
    let body = encode(memory, MAX_MEMORY_BYTES)?;
    let changed = connection
        .execute(
            "INSERT INTO assistant_memories (id,updated_at_ms,body)
             SELECT ?1,?2,?3 WHERE EXISTS(SELECT 1 FROM assistant_memories WHERE id=?1)
               OR (SELECT COUNT(*) FROM assistant_memories) < ?4
             ON CONFLICT(id) DO UPDATE SET updated_at_ms=excluded.updated_at_ms,body=excluded.body
             WHERE assistant_memories.updated_at_ms<=excluded.updated_at_ms",
            params![memory.id, memory.updated_at_ms, body, MAX_MEMORIES],
        )
        .map_err(|e| e.to_string())?;
    if changed != 1 {
        return Err("Memory changed or the memory limit was reached".into());
    }
    Ok(())
}

pub fn delete_memory(connection: &Connection, id: &str) -> Result<(), String> {
    connection
        .execute("DELETE FROM assistant_memories WHERE id=?1", [id])
        .map(|_| ())
        .map_err(|e| e.to_string())
}

/// Interrupted work needs an explicit next user message. Loading never
/// re-executes a model request, tool call, or approval.
pub fn recover(connection: &Connection) -> Result<(), String> {
    let transaction = connection
        .unchecked_transaction()
        .map_err(|e| e.to_string())?;
    for mut session in sessions(&transaction)? {
        if session.status == Status::Running {
            session.status = Status::Interrupted;
            save_session(&transaction, &session)?;
        }
    }
    transaction.commit().map_err(|e| e.to_string())
}

/// Validate a source backup completely before its rows replace live data.
pub fn validate(connection: &Connection) -> Result<(), String> {
    // Refuse oversized text before materializing it in Rust.
    for (table, limit) in [
        ("assistant_sessions", MAX_SESSION_BYTES),
        ("assistant_memories", MAX_MEMORY_BYTES),
    ] {
        let oversized: bool = connection
            .query_row(
                &format!(
                    "SELECT EXISTS(SELECT 1 FROM {table} WHERE length(CAST(body AS BLOB)) > ?1)"
                ),
                [limit as i64],
                |row| row.get(0),
            )
            .map_err(|e| e.to_string())?;
        if oversized {
            return Err("Assistant record is too large".into());
        }
    }
    sessions(connection)?;
    memories(connection)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chat() -> Session {
        Session {
            id: "chat-1".into(),
            title: "Weekly review".into(),
            created_at_ms: 1,
            updated_at_ms: 2,
            messages: vec![Message {
                id: "message-1".into(),
                role: Role::User,
                text: "Review this week".into(),
            }],
            history: vec![
                serde_json::json!({"kind":"user","role":"user","content":"Review this week","timestamp":1}),
            ],
            status: Status::Running,
            model_target: None,
            pending: Vec::new(),
            action_outcomes: Vec::new(),
        }
    }

    #[test]
    fn restart_keeps_history_and_memory_without_resuming_work() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("assistant.sqlite");
        let first = navi_storage::open(&path, &[SCHEMA]).unwrap();
        let chat = chat();
        create_session(&first, &chat).unwrap();
        let fact = Memory {
            id: "memory-1".into(),
            text: "Prefer vegetarian meals".into(),
            source_session: Some(chat.id.clone()),
            updated_at_ms: 3,
        };
        save_memory(&first, &fact).unwrap();
        drop(first);
        let second = navi_storage::open(&path, &[SCHEMA]).unwrap();
        recover(&second).unwrap();
        let resumed = session(&second, &chat.id).unwrap().unwrap();
        assert_eq!(resumed.status, Status::Interrupted);
        assert_eq!(resumed.history, chat.history);
        assert_eq!(resumed.messages, chat.messages);
        assert_eq!(memories(&second).unwrap(), std::slice::from_ref(&fact));
        delete_session(&second, &chat.id).unwrap();
        assert!(save_session(&second, &chat).is_err());
        assert!(session(&second, &chat.id).unwrap().is_none());
        assert_eq!(memories(&second).unwrap(), [fact]);
        delete_memory(&second, "memory-1").unwrap();
        assert!(memories(&second).unwrap().is_empty());
    }

    #[test]
    fn older_checkpoints_and_invalid_records_are_rejected() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut chat = chat();
        create_session(&connection, &chat).unwrap();
        chat.updated_at_ms = 1;
        chat.messages.clear();
        assert!(save_session(&connection, &chat).is_err());
        assert_eq!(sessions(&connection).unwrap()[0].messages.len(), 1);
        connection
            .execute("UPDATE assistant_sessions SET body='{}'", [])
            .unwrap();
        assert!(recover(&connection).is_err());
        assert!(validate(&connection).is_err());
    }

    #[test]
    fn recovery_is_atomic_if_another_session_is_corrupt() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        create_session(&connection, &chat()).unwrap();
        connection
            .execute("INSERT INTO assistant_sessions VALUES('bad',0,'{}')", [])
            .unwrap();
        assert!(recover(&connection).is_err());
        assert_eq!(
            session(&connection, "chat-1").unwrap().unwrap().status,
            Status::Running
        );
    }

    #[test]
    fn pending_proposals_remain_unapproved_and_invalid_shapes_are_refused() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut session = chat();
        session.pending.push(PendingAction {
            id: "proposal-1".into(),
            kind: PendingKind::Memory {
                text: "Prefers vegetarian meals".into(),
            },
        });
        create_session(&connection, &session).unwrap();
        recover(&connection).unwrap();
        assert_eq!(sessions(&connection).unwrap()[0].pending, session.pending);
        assert!(memories(&connection).unwrap().is_empty());
        session.pending.push(session.pending[0].clone());
        assert!(save_session(&connection, &session).is_err());
        session.pending.pop();
        session.pending[0].kind = PendingKind::Capture { text: " ".into() };
        assert!(save_session(&connection, &session).is_err());
    }

    #[test]
    fn failed_confirmation_rolls_back_memory_and_preserves_proposal() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut chat = chat();
        let action = PendingAction {
            id: "proposal-1".into(),
            kind: PendingKind::Memory {
                text: "Vegetarian".into(),
            },
        };
        chat.pending.push(action);
        create_session(&connection, &chat).unwrap();
        {
            let transaction = connection.unchecked_transaction().unwrap();
            save_memory(
                &transaction,
                &Memory {
                    id: "proposal-1".into(),
                    text: "Vegetarian".into(),
                    source_session: Some(chat.id.clone()),
                    updated_at_ms: 3,
                },
            )
            .unwrap();
            let mut invalid = chat.clone();
            invalid.pending.clear();
            invalid.updated_at_ms = 0;
            assert!(save_session(&transaction, &invalid).is_err());
        }
        assert!(memories(&connection).unwrap().is_empty());
        assert_eq!(sessions(&connection).unwrap(), [chat]);
    }

    #[test]
    fn completed_proposal_outcomes_survive_restart_and_cannot_also_be_pending() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut chat = chat();
        chat.action_outcomes.push(ActionOutcome {
            proposal_id: "confirmed-1".into(),
            status: ActionStatus::Confirmed,
            capture_id: Some("capture-1".into()),
        });
        create_session(&connection, &chat).unwrap();
        recover(&connection).unwrap();
        assert_eq!(
            sessions(&connection).unwrap()[0].action_outcomes,
            chat.action_outcomes
        );
        chat.pending.push(PendingAction {
            id: "confirmed-1".into(),
            kind: PendingKind::Capture {
                text: "Lunch 20 CNY".into(),
            },
        });
        assert!(save_session(&connection, &chat).is_err());
    }

    #[test]
    fn aggregate_limit_is_checked_before_loading_or_appending_history() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        create_session(&connection, &chat()).unwrap();
        // Size inspection happens inside SQLite, before Rust allocates or parses
        // these intentionally invalid bodies from an untrusted source database.
        connection.execute_batch(
            "WITH RECURSIVE ids(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM ids WHERE i<9)
             INSERT INTO assistant_sessions SELECT 'oversize-'||i,0,zeroblob(4*1024*1024) FROM ids;"
        ).unwrap();
        assert_eq!(
            sessions(&connection).unwrap_err(),
            "Assistant conversation storage limit exceeded"
        );
        let mut another = chat();
        another.id = "new-chat".into();
        assert!(create_session(&connection, &another).is_err());
        assert!(session(&connection, &another.id).unwrap().is_none());
        let mut update = chat();
        update.title = "Changed title".into();
        assert!(save_session(&connection, &update).is_err());
        assert_eq!(
            session(&connection, "chat-1").unwrap().unwrap().title,
            "Weekly review"
        );
    }
}
