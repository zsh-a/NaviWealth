//! Health schema (migration version 5 — the counter is shared across the
//! whole database: 1 = core, 2 = finance, 3 = knowledge, 4 = execution)
//! and the sync registration. No platform integration here — the HealthKit
//! / Health Connect seam stays behind the platform stub.

use std::sync::Arc;

use lifeos::db::migrations::Migration;
use lifeos::error::Domain;
use lifeos::sync::{SqlTableAdapter, SyncRegistry};

pub const HEALTH_SCHEMA_VERSION: i64 = 5;

pub const METRICS_TABLE: &str = "health:metrics";

pub const METRIC_COLUMNS: &[&str] = &[
    "id",
    "kind",
    "quantity",
    "recorded_at",
    "unit",
    "source",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub fn migration() -> Migration {
    Migration {
        version: HEALTH_SCHEMA_VERSION,
        name: "health",
        sql: HEALTH_V1,
    }
}

// `quantity` is TEXT: exact decimal, never REAL/NUMERIC.
const HEALTH_V1: &str = r#"
CREATE TABLE "health:metrics" (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL,
    quantity TEXT NOT NULL,
    recorded_at INTEGER NOT NULL,
    unit TEXT NOT NULL,
    source TEXT,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_health_metrics_recorded ON "health:metrics" (recorded_at DESC);
CREATE INDEX idx_health_metrics_kind ON "health:metrics" (kind, recorded_at DESC);
"#;

/// Register the health row family at the sync boundary.
pub fn sync_registry() -> SyncRegistry {
    let mut registry = SyncRegistry::new();
    registry.add(Arc::new(SqlTableAdapter::new(
        METRICS_TABLE,
        Domain::Health,
        METRIC_COLUMNS,
    )));
    registry
}
