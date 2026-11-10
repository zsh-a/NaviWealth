//! Schema migrations, applied in order against `PRAGMA user_version`.
//! The schema starts at 1 — there is no legacy history to preserve.

/// One migration step. `sql` may contain multiple statements.
#[derive(Debug, Clone)]
pub struct Migration {
    pub version: i64,
    pub name: &'static str,
    pub sql: &'static str,
}

/// An ordered set of migrations. Domain crates append their own steps;
/// versions are shared across the whole database, so domain steps must
/// pick unused version numbers.
#[derive(Debug, Clone, Default)]
pub struct Migrations {
    steps: Vec<Migration>,
}

impl Migrations {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(mut self, step: Migration) -> Self {
        self.steps.push(step);
        self
    }

    pub fn steps(&self) -> &[Migration] {
        &self.steps
    }

    pub fn is_empty(&self) -> bool {
        self.steps.is_empty()
    }
}

/// Core schema shared by every domain: the settings KV and the sync
/// outbox of dirty-row pointers.
pub fn core_migrations() -> Migrations {
    Migrations::new().push(Migration {
        version: 1,
        name: "core",
        sql: CORE_V1,
    })
}

const CORE_V1: &str = r#"
CREATE TABLE settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);

CREATE TABLE op_outbox (
    table_name TEXT NOT NULL,
    row_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (table_name, row_id)
);
"#;
