//! Knowledge schema (migration version 3 — the counter is shared across
//! the whole database: 1 = core, 2 = finance) and the sync registration.
//! Sync tables carry no foreign keys on purpose; ordering is the
//! repository's concern.

use std::sync::Arc;

use lifeos::db::migrations::Migration;
use lifeos::error::Domain;
use lifeos::sync::{SqlTableAdapter, SyncRegistry};

pub const KNOWLEDGE_SCHEMA_VERSION: i64 = 3;

pub const NOTES_TABLE: &str = "know:notes";
pub const DECISIONS_TABLE: &str = "know:decisions";

pub const NOTE_COLUMNS: &[&str] = &[
    "id",
    "title",
    "content",
    "source",
    "created_at",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub const DECISION_COLUMNS: &[&str] = &[
    "id",
    "title",
    "context",
    "choice",
    "outcome",
    "status",
    "created_at",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub fn migration() -> Migration {
    Migration {
        version: KNOWLEDGE_SCHEMA_VERSION,
        name: "knowledge",
        sql: KNOWLEDGE_V1,
    }
}

const KNOWLEDGE_V1: &str = r#"
CREATE TABLE "know:notes" (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    content TEXT NOT NULL DEFAULT '',
    source TEXT,
    created_at INTEGER NOT NULL,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_know_notes_created ON "know:notes" (created_at DESC);

CREATE TABLE "know:decisions" (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    context TEXT NOT NULL DEFAULT '',
    choice TEXT NOT NULL,
    outcome TEXT,
    status TEXT NOT NULL DEFAULT 'draft',
    created_at INTEGER NOT NULL,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_know_decisions_created ON "know:decisions" (created_at DESC);
"#;

/// Register the knowledge row families at the sync boundary.
pub fn sync_registry() -> SyncRegistry {
    let mut registry = SyncRegistry::new();
    registry.add(Arc::new(SqlTableAdapter::new(
        NOTES_TABLE,
        Domain::Knowledge,
        NOTE_COLUMNS,
    )));
    registry.add(Arc::new(SqlTableAdapter::new(
        DECISIONS_TABLE,
        Domain::Knowledge,
        DECISION_COLUMNS,
    )));
    registry
}
