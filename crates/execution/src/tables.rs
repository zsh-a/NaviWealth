//! Execution schema (migration version 4 — the counter is shared across
//! the whole database: 1 = core, 2 = finance, 3 = knowledge) and the sync
//! registration. Progress is not a table here: an action's status
//! transitions *are* the progress record for this phase.

use std::sync::Arc;

use lifeos::db::migrations::Migration;
use lifeos::error::Domain;
use lifeos::sync::{SqlTableAdapter, SyncRegistry};

pub const EXECUTION_SCHEMA_VERSION: i64 = 4;

pub const PLANS_TABLE: &str = "exec:plans";
pub const ACTIONS_TABLE: &str = "exec:actions";

pub const PLAN_COLUMNS: &[&str] = &[
    "id",
    "title",
    "kind",
    "period",
    "status",
    "created_at",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub const ACTION_COLUMNS: &[&str] = &[
    "id",
    "plan_id",
    "title",
    "status",
    "due",
    "created_at",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub fn migration() -> Migration {
    Migration {
        version: EXECUTION_SCHEMA_VERSION,
        name: "execution",
        sql: EXECUTION_V1,
    }
}

const EXECUTION_V1: &str = r#"
CREATE TABLE "exec:plans" (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'project',
    period TEXT NOT NULL DEFAULT 'open',
    status TEXT NOT NULL DEFAULT 'active',
    created_at INTEGER NOT NULL,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);

CREATE TABLE "exec:actions" (
    id TEXT PRIMARY KEY NOT NULL,
    plan_id TEXT NOT NULL,
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'todo',
    due INTEGER,
    created_at INTEGER NOT NULL,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_exec_actions_plan ON "exec:actions" (plan_id, status);
"#;

/// Register the execution row families at the sync boundary.
pub fn sync_registry() -> SyncRegistry {
    let mut registry = SyncRegistry::new();
    registry.add(Arc::new(SqlTableAdapter::new(
        PLANS_TABLE,
        Domain::Execution,
        PLAN_COLUMNS,
    )));
    registry.add(Arc::new(SqlTableAdapter::new(
        ACTIONS_TABLE,
        Domain::Execution,
        ACTION_COLUMNS,
    )));
    registry
}
