//! Finance schema (from 1 — no legacy) and the sync-table registration.
//! Sync tables carry no foreign keys on purpose (sync applies rows in any
//! order); referential orderings are enforced by repositories.

use std::sync::Arc;

use lifeos::db::migrations::Migration;
use lifeos::error::Domain;
use lifeos::sync::{SqlTableAdapter, SyncRegistry};

pub const FINANCE_SCHEMA_VERSION: i64 = 2;

pub const ACCOUNTS_TABLE: &str = "fin:accounts";
pub const JOURNAL_ENTRIES_TABLE: &str = "fin:journal_entries";
pub const POSTINGS_TABLE: &str = "fin:postings";
pub const CATEGORIES_TABLE: &str = "fin:categories";

pub const ACCOUNT_COLUMNS: &[&str] = &[
    "id",
    "type",
    "name",
    "currency",
    "institution",
    "account_number",
    "note",
    "archived",
    "category",
    "parent_id",
    "icon",
    "color",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub const JOURNAL_ENTRY_COLUMNS: &[&str] = &[
    "id",
    "date",
    "settled_on",
    "narration",
    "payee",
    "flag",
    "tag_ids_json",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub const POSTING_COLUMNS: &[&str] = &[
    "id",
    "journal_entry_id",
    "position",
    "account_id",
    "units",
    "unit",
    "cost_per_unit",
    "cost_currency",
    "cost_lot_id",
    "cost_acquired_on",
    "price_per_unit",
    "price_currency",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub const CATEGORY_COLUMNS: &[&str] = &[
    "id",
    "name",
    "name_override",
    "system_key",
    "parent_id",
    "ledger_account_id",
    "icon",
    "color",
    "sort_order",
    "archived",
    "merged_into_id",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

pub fn migration() -> Migration {
    Migration {
        version: FINANCE_SCHEMA_VERSION,
        name: "finance",
        sql: FINANCE_V1,
    }
}

const FINANCE_V1: &str = r#"
CREATE TABLE "fin:accounts" (
    id TEXT PRIMARY KEY NOT NULL,
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    currency TEXT NOT NULL,
    institution TEXT,
    account_number TEXT,
    note TEXT,
    archived INTEGER NOT NULL DEFAULT 0,
    category TEXT NOT NULL DEFAULT 'asset',
    parent_id TEXT,
    icon TEXT,
    color TEXT,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_accounts_parent ON "fin:accounts" (parent_id);

CREATE TABLE "fin:journal_entries" (
    id TEXT PRIMARY KEY NOT NULL,
    date INTEGER NOT NULL,
    settled_on INTEGER,
    narration TEXT NOT NULL,
    payee TEXT,
    flag TEXT NOT NULL DEFAULT 'confirmed',
    tag_ids_json TEXT NOT NULL DEFAULT '[]',
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_journal_entries_date ON "fin:journal_entries" (date DESC);

CREATE TABLE "fin:postings" (
    id TEXT PRIMARY KEY NOT NULL,
    journal_entry_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    account_id TEXT NOT NULL,
    units TEXT NOT NULL,
    unit TEXT NOT NULL,
    cost_per_unit TEXT,
    cost_currency TEXT,
    cost_lot_id TEXT,
    cost_acquired_on INTEGER,
    price_per_unit TEXT,
    price_currency TEXT,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_postings_entry ON "fin:postings" (journal_entry_id, position);
CREATE INDEX idx_postings_account ON "fin:postings" (account_id);

CREATE TABLE "fin:categories" (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    name_override TEXT,
    system_key TEXT,
    parent_id TEXT,
    ledger_account_id TEXT NOT NULL,
    icon TEXT,
    color TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    archived INTEGER NOT NULL DEFAULT 0,
    merged_into_id TEXT,
    owner_user_id TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    updated_by_device TEXT NOT NULL,
    hlc TEXT NOT NULL,
    deleted_at INTEGER
);
CREATE INDEX idx_categories_ledger_account ON "fin:categories" (ledger_account_id);

CREATE TABLE currencies (
    code TEXT PRIMARY KEY NOT NULL,
    name TEXT,
    decimals INTEGER NOT NULL DEFAULT 2,
    symbol TEXT
);

CREATE TABLE fx_rates (
    base TEXT NOT NULL,
    quote TEXT NOT NULL,
    as_of INTEGER NOT NULL,
    rate TEXT NOT NULL,
    source TEXT,
    fetched_at INTEGER,
    PRIMARY KEY (base, quote, as_of)
);
"#;

/// Register the finance row families at the sync boundary.
pub fn sync_registry() -> SyncRegistry {
    let mut registry = SyncRegistry::new();
    registry.add(Arc::new(SqlTableAdapter::new(
        ACCOUNTS_TABLE,
        Domain::Finance,
        ACCOUNT_COLUMNS,
    )));
    registry.add(Arc::new(SqlTableAdapter::new(
        JOURNAL_ENTRIES_TABLE,
        Domain::Finance,
        JOURNAL_ENTRY_COLUMNS,
    )));
    registry.add(Arc::new(SqlTableAdapter::new(
        POSTINGS_TABLE,
        Domain::Finance,
        POSTING_COLUMNS,
    )));
    registry.add(Arc::new(SqlTableAdapter::new(
        CATEGORIES_TABLE,
        Domain::Finance,
        CATEGORY_COLUMNS,
    )));
    registry
}
