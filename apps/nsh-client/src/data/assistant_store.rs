//! Local assistant transcripts and owner-approved memories. They share the
//! application's SQLite transaction and encrypted backup boundary; credentials
//! are never part of these records. Persisted proposals remain unapproved
//! after restart and require a fresh, explicit action from the owner.

use std::collections::{HashMap, HashSet};

use crate::domain::backup_bundle::is_photo_name;
use crate::domain::capture::{AskAnswer, AskUser, Draft, MAX_ATTACHMENTS, MAX_INPUT, Record, Turn};

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

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    #[default]
    User,
    Assistant,
    Tool,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Message {
    pub id: String,
    pub role: Role,
    pub text: String,
    #[serde(default)]
    pub images: Vec<String>,
    /// Actual image inputs for retry, including context carried from earlier turns.
    #[serde(default)]
    pub request_images: Vec<String>,
    /// Native history length immediately before this submission; retry truncates here.
    #[serde(default)]
    pub history_start: Option<usize>,
    /// Capture proposals/revisions already applied for this submitted owner turn.
    #[serde(default)]
    pub record_targets: Vec<String>,
    #[serde(default)]
    pub capture_id: Option<String>,
    /// The owner-selected revision target for this sent turn, used on retry.
    #[serde(default)]
    pub editing_capture: Option<String>,
    #[serde(default)]
    pub created_at_ms: i64,
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
    /// A model-generated context aid bound to an exact prefix of `history`.
    /// It is never an approved memory, instruction, or action authorization.
    #[serde(default)]
    pub context_summary: Option<navi_assistant::ContextSummary>,
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
    /// Unsent content belongs to this conversation and survives navigation/restart.
    #[serde(default)]
    pub composer: String,
    #[serde(default)]
    pub attachments: Vec<String>,
    #[serde(default)]
    pub editing_capture: Option<String>,
    /// Host-written receipts, separate from untrusted model/tool text.
    #[serde(default)]
    pub record_actions: Vec<RecordAction>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordStatus {
    Saved,
    Discarded,
    Undone,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RecordAction {
    pub capture_id: String,
    pub status: RecordStatus,
    pub records: Vec<Record>,
    pub saved_at_ms: i64,
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
    Questions {
        request: AskUser,
        #[serde(default)]
        answers: Vec<AskAnswer>,
    },
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

fn valid_images(images: &[String]) -> bool {
    let mut seen = HashSet::new();
    images.len() <= MAX_ATTACHMENTS
        && images
            .iter()
            .all(|name| is_photo_name(name) && seen.insert(name))
}

fn valid_records(records: &[Record], confirmed: bool) -> bool {
    records.len() <= 10
        && records.iter().all(|record| match record {
            Record::Money { draft, .. } => draft.valid(),
            Record::Meal {
                estimate,
                source_image,
                ..
            } => {
                (!confirmed || !estimate.foods.is_empty())
                    && estimate.foods.len() <= 100
                    && estimate.foods.iter().all(|food| food.validate().is_ok())
                    && estimate
                        .title
                        .as_ref()
                        .is_none_or(|title| title.len() <= MAX_TEXT_BYTES)
                    && source_image.valid(MAX_ATTACHMENTS)
            }
            Record::Weight { kg, .. } => crate::domain::weight::valid_kg(*kg),
            Record::Trade {
                security,
                kind,
                currency,
                quantity,
                price,
                amount,
                fee,
                cash,
                ..
            } => {
                use navi_finance::{account::AccountKind, holdings::Kind};
                !security.trim().is_empty()
                    && security.len() <= 512
                    && *fee >= 0
                    && (if *kind == Kind::Dividend {
                        *quantity == 0
                            && *price == 0
                            && if confirmed {
                                *amount > *fee
                            } else {
                                *amount >= 0
                            }
                    } else {
                        *quantity > 0 && *price > 0 && *amount == 0
                    })
                    && (*kind != Kind::Opening || (cash.is_none() && *fee == 0))
                    && cash.as_ref().is_none_or(|account| {
                        account.is_cash()
                            && account.kind() == AccountKind::Assets
                            && account.currency() == *currency
                    })
            }
            Record::Balance { account, .. } => account.is_cash(),
            Record::Price {
                security, price, ..
            } => !security.trim().is_empty() && security.len() <= 512 && *price >= 0,
            Record::Note { text, .. } => crate::domain::review::valid_note(text),
        })
}

fn validate_session(session: &Session) -> Result<(), String> {
    let mut ids = HashSet::new();
    let mut outcome_ids = HashSet::new();
    let mut record_ids = HashSet::new();
    if !valid_id(&session.id)
        || session.title.trim().is_empty()
        || session.title.len() > 512
        || session.created_at_ms < 0
        || session.updated_at_ms < session.created_at_ms
        || session.composer.chars().count() > 8000
        || !valid_images(&session.attachments)
        || session
            .editing_capture
            .as_ref()
            .is_some_and(|id| !valid_id(id))
        || session.record_actions.len() > MAX_MESSAGES
        || session.record_actions.iter().any(|action| {
            !valid_id(&action.capture_id)
                || !record_ids.insert(&action.capture_id)
                || action.saved_at_ms < 0
                || action.saved_at_ms > session.updated_at_ms
                || action.records.len() > 10
                || (action.status == RecordStatus::Saved && action.records.is_empty())
                || !valid_records(&action.records, action.status != RecordStatus::Discarded)
        })
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
                    PendingKind::Questions { request, answers } => {
                        AskUser::parse(
                            &request.call_id,
                            &serde_json::json!({"questions": request.questions}),
                            request.blocks.clone(),
                        )
                        .is_err()
                            || request.validate_answers(answers, "staged", false).is_err()
                    }
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
                || !valid_images(&message.images)
                || !valid_images(&message.request_images)
                || message.record_targets.len() > 8
                || message.record_targets.iter().any(|id| !valid_id(id))
                || message.record_targets.iter().collect::<HashSet<_>>().len()
                    != message.record_targets.len()
                || message
                    .history_start
                    .is_some_and(|start| start > MAX_MESSAGES || start > session.history.len())
                || message.capture_id.as_ref().is_some_and(|id| !valid_id(id))
                || message
                    .editing_capture
                    .as_ref()
                    .is_some_and(|id| !valid_id(id))
                || message.created_at_ms < 0
                || message.created_at_ms > session.updated_at_ms
        })
    {
        return Err("Invalid assistant session".into());
    }
    navi_assistant::validate_history(&session.history)?;
    if let Some(summary) = &session.context_summary {
        navi_assistant::validate_context_summary(summary, &session.history)?;
    }
    Ok(())
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

fn capture_ids(session: &Session) -> HashSet<String> {
    session
        .messages
        .iter()
        .filter_map(|message| message.capture_id.clone())
        .chain(session.editing_capture.clone())
        .collect()
}

pub fn linked_capture_ids(connection: &Connection) -> Result<HashSet<String>, String> {
    Ok(sessions(connection)?.iter().flat_map(capture_ids).collect())
}

/// Used within the capture business transaction, so a receipt cannot exist
/// without the write it describes. This function never commits independently.
pub fn record_capture_outcome(
    connection: &Connection,
    capture_id: &str,
    records: &[Record],
    status: RecordStatus,
) -> Result<(), String> {
    if !valid_id(capture_id) || !valid_records(records, status != RecordStatus::Discarded) {
        return Err("Invalid capture outcome".into());
    }
    for mut session in sessions(connection)? {
        if !capture_ids(&session).contains(capture_id) {
            continue;
        }
        let now = super::clock::now_ms().max(session.updated_at_ms);
        if let Some(action) = session
            .record_actions
            .iter_mut()
            .find(|action| action.capture_id == capture_id)
        {
            if action.status == status && (records.is_empty() || action.records == records) {
                continue;
            }
            if action.status != RecordStatus::Saved
                || status != RecordStatus::Undone
                || (!records.is_empty() && action.records != records)
            {
                return Err("Capture already completed".into());
            }
            action.status = status;
            action.saved_at_ms = now;
        } else {
            if status == RecordStatus::Undone
                || (status == RecordStatus::Saved && records.is_empty())
            {
                return Err("Invalid capture outcome transition".into());
            }
            session.record_actions.push(RecordAction {
                capture_id: capture_id.into(),
                status,
                records: records.to_vec(),
                saved_at_ms: now,
            });
        }
        if session.editing_capture.as_deref() == Some(capture_id) {
            session.editing_capture = None;
        }
        session.updated_at_ms = now;
        save_session(connection, &session)?;
    }
    Ok(())
}

pub fn delete_session(connection: &Connection, id: &str) -> Result<(), String> {
    let transaction = connection
        .unchecked_transaction()
        .map_err(|e| e.to_string())?;
    let Some(deleted) = session(&transaction, id)? else {
        return Ok(());
    };
    transaction
        .execute("DELETE FROM assistant_sessions WHERE id=?1", [id])
        .map_err(|e| e.to_string())?;
    let candidates = capture_ids(&deleted);
    if !candidates.is_empty() {
        let remaining = linked_capture_ids(&transaction)?;
        for id in candidates.difference(&remaining) {
            transaction
                .execute("DELETE FROM capture_drafts WHERE id=?1", [id])
                .map_err(|e| e.to_string())?;
        }
    }
    transaction.commit().map_err(|e| e.to_string())
}

/// Only conversation-owned drafts travel with conversations. Unrelated legacy
/// capture drafts remain device-local, including bodies an old app cannot parse.
pub fn prune_unlinked_drafts(connection: &Connection) -> Result<(), String> {
    let linked = linked_capture_ids(connection)?;
    let mut query = connection
        .prepare("SELECT id FROM capture_drafts")
        .map_err(|e| e.to_string())?;
    let ids = query
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;
    for id in ids {
        if !linked.contains(&id) {
            connection
                .execute("DELETE FROM capture_drafts WHERE id=?1", [id])
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

fn linked_drafts(connection: &Connection) -> Result<Vec<Draft>, String> {
    let mut drafts = Vec::new();
    for id in linked_capture_ids(connection)? {
        let row: Option<(i64, String)> = connection
            .query_row(
                "SELECT created_at_ms,body FROM capture_drafts WHERE id=?1",
                [&id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        let Some((created, body)) = row else {
            continue;
        };
        if body.len() > MAX_SESSION_BYTES {
            return Err("Capture draft is too large".into());
        }
        let draft: Draft = serde_json::from_str(&body).map_err(|_| "Invalid conversation draft")?;
        if draft.id != id
            || draft.created_at_ms != created
            || created < 0
            || !valid_id(&id)
            || draft.input.chars().count() > MAX_INPUT
            || draft.correction.chars().count() > MAX_INPUT
            || draft.question.len() > MAX_TEXT_BYTES
            || draft.model.len() > 2048
            || !valid_images(&draft.attachments)
            || !valid_images(&draft.image_names())
            || !valid_records(&draft.records, false)
            || draft.transcript.len() > MAX_MESSAGES
            || draft.answers.len() > 3
            || draft.evidence.len() > 10
        {
            return Err("Invalid conversation draft".into());
        }
        for turn in &draft.transcript {
            let valid = match turn {
                Turn::Owner { text, images, .. } | Turn::ToolAnswer { text, images, .. } => {
                    text.chars().count() <= MAX_INPUT && valid_images(images)
                }
                Turn::Assistant {
                    reply,
                    records,
                    questions,
                    ..
                } => reply.len() <= MAX_TEXT_BYTES && *records <= 10 && questions.len() <= 3,
                Turn::AskUser { request } => AskUser::parse(
                    &request.call_id,
                    &serde_json::json!({"questions": request.questions}),
                    request.blocks.clone(),
                )
                .is_ok(),
            };
            if !valid {
                return Err("Invalid conversation draft transcript".into());
            }
        }
        if draft.records.iter().any(|record| {
            matches!(record,
            Record::Meal { source_image, .. } if !source_image.valid(draft.sent_images().len()))
        }) {
            return Err("Invalid conversation draft image reference".into());
        }
        drafts.push(draft);
    }
    Ok(drafts)
}

pub fn validate_conversation_drafts(connection: &Connection) -> Result<(), String> {
    let drafts: HashSet<_> = linked_drafts(connection)?
        .into_iter()
        .map(|draft| draft.id)
        .collect();
    for session in sessions(connection)? {
        for id in capture_ids(&session) {
            let completed = session
                .record_actions
                .iter()
                .any(|action| action.capture_id == id);
            if !drafts.contains(&id) && !completed {
                return Err("Conversation draft is missing".into());
            }
            if drafts.contains(&id) && completed {
                return Err("Completed conversation still contains a draft".into());
            }
        }
    }
    Ok(())
}

/// All file references owned by a conversation, including unsent attachments.
pub fn photo_names(connection: &Connection) -> Result<HashSet<String>, String> {
    let mut names = HashSet::new();
    for session in sessions(connection)? {
        names.extend(session.attachments);
        for message in session.messages {
            names.extend(message.images);
            names.extend(message.request_images);
        }
    }
    for draft in linked_drafts(connection)? {
        names.extend(draft.image_names());
    }
    Ok(names)
}

/// Rewrite only file references, preserving source-image ordinals and review
/// state. Restoring never sends a model request or approves a draft.
pub fn remap_photos(
    connection: &Connection,
    names: &HashMap<String, String>,
) -> Result<(), String> {
    let remap = |name: &mut String| {
        if let Some(new) = names.get(name) {
            *name = new.clone();
        }
    };
    for mut session in sessions(connection)? {
        for name in &mut session.attachments {
            remap(name);
        }
        for message in &mut session.messages {
            for name in message.images.iter_mut().chain(&mut message.request_images) {
                remap(name);
            }
        }
        save_session(connection, &session)?;
    }
    for mut draft in linked_drafts(connection)? {
        if let Some(name) = &mut draft.photo {
            remap(name);
        }
        for name in &mut draft.attachments {
            remap(name);
        }
        for turn in &mut draft.transcript {
            if let Turn::Owner { images, .. } | Turn::ToolAnswer { images, .. } = turn {
                for name in images {
                    remap(name);
                }
            }
        }
        if draft.status == crate::domain::capture::Status::Analyzing {
            draft.status = crate::domain::capture::Status::Editing;
        }
        connection
            .execute(
                "UPDATE capture_drafts SET body=?1 WHERE id=?2",
                params![
                    serde_json::to_string(&draft).map_err(|e| e.to_string())?,
                    draft.id
                ],
            )
            .map_err(|e| e.to_string())?;
    }
    Ok(())
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
                ..Message::default()
            }],
            history: vec![
                serde_json::json!({"kind":"user","role":"user","content":"Review this week","timestamp":1}),
            ],
            context_summary: None,
            status: Status::Running,
            model_target: None,
            pending: Vec::new(),
            action_outcomes: Vec::new(),
            ..Session::default()
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

    fn summarized_chat() -> Session {
        let mut chat = chat();
        chat.history.push(serde_json::json!({
            "kind":"assistant","role":"assistant","content":[{"type":"text","text":"Review is ready"}],
            "api":"openai-completions","provider":"navi-owned","model":"fixture",
            "usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,
                "cost":{"input":0.0,"output":0.0,"cacheRead":0.0,"cacheWrite":0.0,"total":0.0}},
            "stopReason":"stop","timestamp":2
        }));
        chat.context_summary = Some(
            navi_assistant::ContextSummary::new(
                &chat.history,
                2,
                "The user requested a weekly review. No memory or record was confirmed.".into(),
            )
            .unwrap(),
        );
        chat
    }

    #[test]
    fn context_summary_survives_restart_without_replacing_history_or_becoming_memory() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("assistant.sqlite");
        let first = navi_storage::open(&path, &[SCHEMA]).unwrap();
        let mut chat = summarized_chat();
        chat.pending.push(PendingAction {
            id: "unapproved-memory".into(),
            kind: PendingKind::Memory {
                text: "Prefers vegetarian meals".into(),
            },
        });
        create_session(&first, &chat).unwrap();
        drop(first);
        let second = navi_storage::open(&path, &[SCHEMA]).unwrap();
        recover(&second).unwrap();
        let kept = session(&second, &chat.id).unwrap().unwrap();
        assert_eq!(kept.status, Status::Interrupted);
        assert_eq!(kept.context_summary, chat.context_summary);
        assert_eq!(kept.history, chat.history);
        assert_eq!(kept.pending, chat.pending);
        assert!(memories(&second).unwrap().is_empty());
        // A newly submitted turn preserves the verified prefix and its summary.
        let mut continued = kept.clone();
        continued.history.push(serde_json::json!({
            "kind":"user","role":"user","content":"What about last month?","timestamp":3
        }));
        continued.updated_at_ms += 1;
        save_session(&second, &continued).unwrap();
        assert_eq!(session(&second, &chat.id).unwrap().unwrap(), continued);
    }

    #[test]
    fn context_summary_validation_rejects_stale_prefix_bounds_and_malformed_bodies() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let original = summarized_chat();
        create_session(&connection, &original).unwrap();
        let mut changed_prefix = original.clone();
        changed_prefix.history[0]["content"] = serde_json::json!("A different request");
        let mut invalid_boundary = original.clone();
        invalid_boundary
            .context_summary
            .as_mut()
            .unwrap()
            .covered_messages = 1;
        let mut invalid_hash = original.clone();
        invalid_hash.context_summary.as_mut().unwrap().source_hash = "0".repeat(64);
        let mut invalid_text = original.clone();
        invalid_text.context_summary.as_mut().unwrap().text = " ".into();
        let mut oversized_text = original.clone();
        oversized_text.context_summary.as_mut().unwrap().text = "界".repeat(4_001);
        for invalid in [
            changed_prefix,
            invalid_boundary,
            invalid_hash,
            invalid_text,
            oversized_text,
        ] {
            assert!(save_session(&connection, &invalid).is_err());
            assert_eq!(
                session(&connection, &original.id).unwrap().unwrap(),
                original
            );
        }
        let mut malformed = serde_json::to_value(&original).unwrap();
        malformed["context_summary"]["approved"] = serde_json::json!(true);
        connection
            .execute(
                "UPDATE assistant_sessions SET body=?1",
                [malformed.to_string()],
            )
            .unwrap();
        assert!(validate(&connection).is_err());
        assert!(recover(&connection).is_err());
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
    #[test]
    fn legacy_sessions_default_composer_images_and_receipts() {
        let mut value = serde_json::to_value(chat()).unwrap();
        for name in [
            "composer",
            "attachments",
            "editing_capture",
            "record_actions",
        ] {
            value.as_object_mut().unwrap().remove(name);
        }
        for name in [
            "images",
            "request_images",
            "history_start",
            "record_targets",
            "capture_id",
            "editing_capture",
            "created_at_ms",
        ] {
            value["messages"][0].as_object_mut().unwrap().remove(name);
        }
        let legacy: Session = serde_json::from_value(value).unwrap();
        validate_session(&legacy).unwrap();
        assert!(legacy.composer.is_empty());
        assert!(legacy.attachments.is_empty());
        assert!(legacy.record_actions.is_empty());
        assert!(legacy.messages[0].images.is_empty());
        assert!(legacy.messages[0].request_images.is_empty());
        assert!(legacy.messages[0].history_start.is_none());
        assert!(legacy.messages[0].record_targets.is_empty());
    }

    #[test]
    fn unsent_content_survives_recovery_and_photo_paths_are_validated() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut chat = chat();
        chat.composer = "Tomorrow's lunch".into();
        chat.attachments = vec!["composed.jpg".into()];
        chat.messages[0].images = vec!["sent.jpg".into()];
        chat.messages[0].request_images = vec!["sent.jpg".into(), "carried.jpg".into()];
        create_session(&connection, &chat).unwrap();
        recover(&connection).unwrap();
        let restored = session(&connection, &chat.id).unwrap().unwrap();
        assert_eq!(restored.composer, chat.composer);
        assert_eq!(restored.attachments, chat.attachments);
        assert_eq!(restored.messages, chat.messages);
        chat.messages[0].request_images.push("../secret.jpg".into());
        assert!(save_session(&connection, &chat).is_err());
        chat.messages[0].request_images.pop();
        chat.attachments = vec!["../secret.jpg".into()];
        assert!(save_session(&connection, &chat).is_err());
        chat.attachments = vec!["sent.jpg".into(); 2];
        assert!(save_session(&connection, &chat).is_err());
    }

    #[test]
    fn capture_receipts_commit_with_business_writes_and_terminal_states_are_guarded() {
        let connection = navi_storage::memory(&[
            SCHEMA,
            "CREATE TABLE capture_drafts(id TEXT PRIMARY KEY,created_at_ms INTEGER,body TEXT);
             CREATE TABLE records(id TEXT PRIMARY KEY);",
        ])
        .unwrap();
        let mut chat = chat();
        chat.messages[0].capture_id = Some("capture-1".into());
        chat.editing_capture = Some("capture-1".into());
        create_session(&connection, &chat).unwrap();
        let record = Record::Note {
            day: "2026-11-28".parse().unwrap(),
            text: "Lunch".into(),
        };
        {
            let transaction = connection.unchecked_transaction().unwrap();
            transaction
                .execute("INSERT INTO records VALUES('capture-1')", [])
                .unwrap();
            record_capture_outcome(
                &transaction,
                "capture-1",
                std::slice::from_ref(&record),
                RecordStatus::Saved,
            )
            .unwrap();
            assert_eq!(
                session(&transaction, &chat.id)
                    .unwrap()
                    .unwrap()
                    .record_actions
                    .len(),
                1
            );
            // Simulate a later business validation/write failure.
        }
        assert_eq!(session(&connection, &chat.id).unwrap().unwrap(), chat);
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM records", [], |row| row
                    .get::<_, i64>(0))
                .unwrap(),
            0
        );
        {
            let transaction = connection.unchecked_transaction().unwrap();
            transaction
                .execute("INSERT INTO records VALUES('capture-1')", [])
                .unwrap();
            record_capture_outcome(
                &transaction,
                "capture-1",
                std::slice::from_ref(&record),
                RecordStatus::Saved,
            )
            .unwrap();
            transaction.commit().unwrap();
        }
        record_capture_outcome(
            &connection,
            "capture-1",
            std::slice::from_ref(&record),
            RecordStatus::Saved,
        )
        .unwrap();
        let saved = session(&connection, &chat.id).unwrap().unwrap();
        assert!(saved.editing_capture.is_none());
        assert_eq!(saved.record_actions.len(), 1);
        assert_eq!(
            saved.record_actions[0].records,
            std::slice::from_ref(&record)
        );
        assert!(
            record_capture_outcome(&connection, "capture-1", &[], RecordStatus::Discarded).is_err()
        );
        record_capture_outcome(&connection, "capture-1", &[], RecordStatus::Undone).unwrap();
        let undone = session(&connection, &chat.id).unwrap().unwrap();
        assert_eq!(undone.record_actions[0].status, RecordStatus::Undone);
        assert_eq!(undone.record_actions[0].records, [record]);
        assert!(
            record_capture_outcome(
                &connection,
                "capture-1",
                &undone.record_actions[0].records,
                RecordStatus::Saved
            )
            .is_err()
        );
        delete_session(&connection, &chat.id).unwrap();
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM records", [], |row| row
                    .get::<_, i64>(0))
                .unwrap(),
            1
        );
    }

    #[test]
    fn deleting_chat_removes_only_unshared_capture_drafts() {
        let connection = navi_storage::memory(&[
            SCHEMA,
            "CREATE TABLE capture_drafts(id TEXT PRIMARY KEY,created_at_ms INTEGER,body TEXT);",
        ])
        .unwrap();
        let mut first = chat();
        first.messages[0].capture_id = Some("shared".into());
        first.editing_capture = Some("private".into());
        create_session(&connection, &first).unwrap();
        let mut second = chat();
        second.id = "chat-2".into();
        second.messages[0].capture_id = Some("shared".into());
        create_session(&connection, &second).unwrap();
        connection.execute("INSERT INTO capture_drafts VALUES('shared',0,'{}'),('private',0,'{}'),('unrelated',0,'{}')", []).unwrap();
        delete_session(&connection, &first.id).unwrap();
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM capture_drafts", [], |row| row
                    .get::<_, i64>(0))
                .unwrap(),
            2
        );
        delete_session(&connection, &second.id).unwrap();
        assert_eq!(
            connection
                .query_row("SELECT id FROM capture_drafts", [], |row| row
                    .get::<_, String>(0))
                .unwrap(),
            "unrelated"
        );
    }

    #[test]
    fn staged_question_answers_are_durable_and_reject_stale_option_ids() {
        let input = serde_json::json!({"questions":[{"id":"q1","text":"Which meal?","reason":"Choose a slot","required":true,
            "options":[{"id":"lunch","label":"Lunch","description":"Midday meal"}]}]});
        let request = AskUser::parse("local-question", &input,
            serde_json::json!([{"type":"tool_use","id":"local-question","name":"ask_user","input":input}])).unwrap();
        let mut chat = chat();
        chat.pending.push(PendingAction {
            id: "question-action".into(),
            kind: PendingKind::Questions {
                request,
                answers: Vec::new(),
            },
        });
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        create_session(&connection, &chat).unwrap();
        let PendingKind::Questions { answers, .. } = &mut chat.pending[0].kind else {
            unreachable!()
        };
        answers.push(AskAnswer {
            question_id: "q1".into(),
            option_id: Some("lunch".into()),
            text: String::new(),
        });
        save_session(&connection, &chat).unwrap();
        recover(&connection).unwrap();
        assert_eq!(
            session(&connection, &chat.id).unwrap().unwrap().pending,
            chat.pending
        );
        let PendingKind::Questions { answers, .. } = &mut chat.pending[0].kind else {
            unreachable!()
        };
        answers[0].option_id = Some("dinner".into());
        assert!(save_session(&connection, &chat).is_err());
    }
    #[test]
    fn incomplete_review_can_be_discarded_without_weakening_saved_receipts() {
        use navi_finance::{currency::Currency, holdings::Kind};
        let incomplete = Record::Trade {
            day: "2026-11-28".parse().unwrap(),
            security: "fund".into(),
            currency: Currency::CNY,
            kind: Kind::Dividend,
            quantity: 0,
            price: 0,
            amount: 10,
            fee: 20,
            cash: None,
        };
        assert!(valid_records(std::slice::from_ref(&incomplete), false));
        assert!(!valid_records(std::slice::from_ref(&incomplete), true));
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut chat = chat();
        chat.messages[0].capture_id = Some("incomplete".into());
        create_session(&connection, &chat).unwrap();
        assert!(
            record_capture_outcome(
                &connection,
                "incomplete",
                std::slice::from_ref(&incomplete),
                RecordStatus::Saved
            )
            .is_err()
        );
        record_capture_outcome(
            &connection,
            "incomplete",
            &[incomplete],
            RecordStatus::Discarded,
        )
        .unwrap();
        assert_eq!(
            session(&connection, &chat.id)
                .unwrap()
                .unwrap()
                .record_actions[0]
                .status,
            RecordStatus::Discarded
        );
    }
    #[test]
    fn retry_history_boundary_must_exist_in_the_saved_native_history() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut chat = chat();
        chat.messages[0].history_start = Some(chat.history.len());
        create_session(&connection, &chat).unwrap();
        assert_eq!(session(&connection, &chat.id).unwrap().unwrap(), chat);
        for invalid in [chat.history.len() + 1, MAX_MESSAGES + 1] {
            chat.messages[0].history_start = Some(invalid);
            assert!(save_session(&connection, &chat).is_err());
        }
        chat.messages[0].history_start = Some(0);
        save_session(&connection, &chat).unwrap();
    }
    #[test]
    fn applied_record_targets_are_bounded_unique_historical_references() {
        let connection = navi_storage::memory(&[SCHEMA]).unwrap();
        let mut chat = chat();
        chat.messages[0].record_targets = vec!["completed-capture".into()];
        create_session(&connection, &chat).unwrap();
        assert_eq!(session(&connection, &chat.id).unwrap().unwrap(), chat);
        // Historical markers do not require a still-live draft or business record.
        assert!(linked_capture_ids(&connection).unwrap().is_empty());
        for invalid in [
            vec!["duplicate".into(); 2],
            vec!["../invalid".into()],
            (0..9).map(|index| format!("capture-{index}")).collect(),
        ] {
            chat.messages[0].record_targets = invalid;
            assert!(save_session(&connection, &chat).is_err());
        }
    }
}
