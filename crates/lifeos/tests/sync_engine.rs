//! Sync engine tests against a fake transport: push/apply, LWW, accepted
//! acknowledgements, cursor pagination and domain reset generations —
//! the phase-2 contract the backend implements.

use std::sync::Arc;
use std::sync::Mutex;

use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations, settings};
use lifeos::error::Domain;
use lifeos::sync::{
    MutationStamper, RowAck, RowChange, SettingsTokenProvider, SqlTableAdapter, SyncEngine,
    SyncRegistry, SyncRequest, SyncResponse, ensure_identity, outbox,
};

const NOTES_TABLE: &str = "fin:notes";
const NOTE_COLUMNS: &[&str] = &[
    "id",
    "note",
    "owner_user_id",
    "updated_at",
    "updated_by_device",
    "hlc",
    "deleted_at",
];

/// In-memory fake of the backend's row-state store.
struct FakeServer {
    state: Mutex<ServerState>,
    generations: std::collections::BTreeMap<String, i64>,
}

#[derive(Default)]
struct ServerState {
    rows: Vec<RowChange>,
    seq: i64,
    accepted: Vec<RowAck>,
}

impl FakeServer {
    fn lww_insert(state: &mut ServerState, mut change: RowChange) {
        state.seq += 1;
        change.seq = state.seq;
        change.device_id = "device-2".into();
        if let Some(existing) = state
            .rows
            .iter_mut()
            .find(|r| r.id == change.id && r.table == change.table)
        {
            // LWW: greatest (version, device_id) wins.
            let winner =
                (&change.version, &change.device_id) > (&existing.version, &existing.device_id);
            if winner {
                *existing = change;
            }
        } else {
            state.rows.push(change);
        }
    }
}

#[async_trait::async_trait]
impl lifeos::sync::SyncTransport for FakeServer {
    async fn post_sync(
        &self,
        request: SyncRequest,
        _bearer: Option<String>,
    ) -> lifeos::Result<SyncResponse> {
        let mut state = self.state.lock().unwrap();

        // Accept everything pushed at the protocol boundary and LWW-merge it,
        // stamping rows with the domain's current generation (as the real
        // backend does).
        for change in &request.changes {
            state.accepted.push(RowAck {
                table: change.table.clone(),
                id: change.id.clone(),
            });
            let mut stamped = change.clone();
            stamped.generation = *self.generations.get("finance").unwrap_or(&0);
            Self::lww_insert(&mut state, stamped);
        }

        // Pull: current-generation rows with seq > since, up to a page of 2
        // (to exercise `more`).
        let finance_generation = *self.generations.get("finance").unwrap_or(&0);
        let mut changes: Vec<RowChange> = state
            .rows
            .iter()
            .filter(|r| r.seq > request.since && r.generation == finance_generation)
            .cloned()
            .collect();
        changes.sort_by_key(|r| r.seq);
        let more = changes.len() > 2;
        changes.truncate(2);
        let seq = changes.last().map(|r| r.seq).unwrap_or(request.since);

        Ok(SyncResponse {
            seq,
            changes,
            more,
            accepted: state.accepted.clone(),
            domain_generations: self.generations.clone(),
        })
    }

    async fn reset_domain(&self, _domain: Domain, _bearer: Option<String>) -> lifeos::Result<i64> {
        Ok(1)
    }
}

fn registry() -> SyncRegistry {
    let mut registry = SyncRegistry::new();
    registry.add(Arc::new(SqlTableAdapter::new(
        NOTES_TABLE,
        Domain::Finance,
        NOTE_COLUMNS,
    )));
    registry
}

fn test_db() -> Db {
    let db = Db::open(DbOpenOptions {
        path: std::path::PathBuf::from(":memory:"),
        encryption_key: None,
        migrations: core_migrations(),
    })
    .unwrap();
    db.call_sync(|conn| {
        conn.execute_batch(
            r#"CREATE TABLE "fin:notes" (
                id TEXT PRIMARY KEY NOT NULL,
                note TEXT,
                owner_user_id TEXT NOT NULL,
                updated_at INTEGER NOT NULL,
                updated_by_device TEXT NOT NULL,
                hlc TEXT NOT NULL,
                deleted_at INTEGER
            );"#,
        )?;
        Ok(())
    })
    .unwrap();
    db
}

fn insert_note(db: &Db, stamper: &MutationStamper, id: &str, note: &str) -> String {
    let id = id.to_owned();
    let note = note.to_owned();
    db.call_sync({
        let stamper = stamper.clone();
        move |conn| {
            let stamp = stamper.stamp(conn)?;
            conn.execute(
                r#"INSERT INTO "fin:notes" (id, note, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
                   VALUES (?1, ?2, ?3, ?4, ?5, ?6, NULL)"#,
                rusqlite::params![
                    id,
                    note,
                    stamper.owner_user_id,
                    stamp.now / 1000,
                    stamper.device_id,
                    stamp.hlc
                ],
            )?;
            outbox::enqueue(conn, NOTES_TABLE, &id)?;
            Ok(stamp.hlc)
        }
    })
    .unwrap()
}

#[tokio::test]
async fn push_apply_ack_and_cursor() {
    let db = test_db();
    let stamper = MutationStamper::new("user-1", "device-1");
    db.call_sync(|conn| ensure_identity(conn, "user-1", "device-1"))
        .unwrap();

    // Local write: one dirty row.
    let hlc = insert_note(&db, &stamper, "n1", "hello");

    // A remote row from another device (server already has it).
    let server = Arc::new(FakeServer {
        state: Mutex::new(ServerState {
            rows: vec![RowChange {
                table: NOTES_TABLE.into(),
                id: "r1".into(),
                payload: Some(serde_json::json!({
                    "id": "r1", "note": "remote", "owner_user_id": "user-1",
                    "updated_at": 1, "updated_by_device": "device-2",
                    "hlc": "100.0000-device-2", "deleted_at": null
                })),
                version: "100.0000-device-2".into(),
                deleted: false,
                device_id: "device-2".into(),
                seq: 1,
                generation: 0,
            }],
            seq: 1,
            accepted: Vec::new(),
        }),
        generations: Default::default(),
    });

    let engine = SyncEngine::new(
        db.clone(),
        registry(),
        server.clone(),
        Arc::new(SettingsTokenProvider::new(db.clone())),
        stamper.clone(),
    );
    let outcome = engine.sync_once().await.unwrap();

    // Pushed our row, applied the remote one, cursor advanced.
    assert_eq!(outcome.pushed, 1);
    assert_eq!(outcome.applied, 1);
    assert!(outcome.cursor >= 1);

    // Outbox drained (accepted acks).
    let pending = db.call_sync(|conn| outbox::count(conn)).unwrap();
    assert_eq!(pending, 0);

    // The remote row landed; our row is still there.
    let (remote, local) = db
        .call_sync(|conn| {
            let mut stmt = conn.prepare(r#"SELECT note FROM "fin:notes" WHERE id = ?1"#)?;
            let remote: String = stmt
                .query_row(rusqlite::params!["r1"], |r| r.get(0))
                .unwrap();
            let local: String = stmt
                .query_row(rusqlite::params!["n1"], |r| r.get(0))
                .unwrap();
            Ok((remote, local))
        })
        .unwrap();
    assert_eq!(remote, "remote");
    assert_eq!(local, "hello");

    // Cursor persisted.
    let cursor = db
        .call_sync(|conn| {
            Ok(settings::get_setting(conn, "sync.cursor")?
                .and_then(|v| v.parse::<i64>().ok())
                .unwrap_or(0))
        })
        .unwrap();
    assert_eq!(cursor, outcome.cursor);

    // Second cycle: nothing to push, nothing to pull.
    let second = engine.sync_once().await.unwrap();
    assert_eq!(second.pushed, 0);
    assert_eq!(second.applied, 0);
    assert_eq!(second.cursor, outcome.cursor);
    let _ = hlc;
}

#[tokio::test]
async fn lww_local_newer_wins_on_apply() {
    let db = test_db();
    let stamper = MutationStamper::new("user-1", "device-1");
    db.call_sync(|conn| ensure_identity(conn, "user-1", "device-1"))
        .unwrap();
    insert_note(&db, &stamper, "n1", "local-new");

    // Remote row with an OLDER version for the same id.
    let server = Arc::new(FakeServer {
        state: Mutex::new(ServerState {
            rows: vec![RowChange {
                table: NOTES_TABLE.into(),
                id: "n1".into(),
                payload: Some(serde_json::json!({
                    "id": "n1", "note": "remote-old", "owner_user_id": "user-1",
                    "updated_at": 1, "updated_by_device": "device-2",
                    "hlc": "1.0000-device-2", "deleted_at": null
                })),
                version: "1.0000-device-2".into(),
                deleted: false,
                device_id: "device-2".into(),
                seq: 1,
                generation: 0,
            }],
            seq: 1,
            accepted: Vec::new(),
        }),
        generations: Default::default(),
    });

    let engine = SyncEngine::new(
        db.clone(),
        registry(),
        server.clone(),
        Arc::new(SettingsTokenProvider::new(db.clone())),
        stamper.clone(),
    );
    let outcome = engine.sync_once().await.unwrap();
    // The remote row was skipped (local HLC wins).
    assert_eq!(outcome.applied, 0);
    let note: String = db
        .call_sync(|conn| {
            Ok(
                conn.query_row(r#"SELECT note FROM "fin:notes" WHERE id = 'n1'"#, [], |r| {
                    r.get(0)
                })?,
            )
        })
        .unwrap();
    assert_eq!(note, "local-new");
}

#[tokio::test]
async fn tombstone_deletes_known_row() {
    let db = test_db();
    let stamper = MutationStamper::new("user-1", "device-1");
    db.call_sync(|conn| ensure_identity(conn, "user-1", "device-1"))
        .unwrap();
    insert_note(&db, &stamper, "n1", "to-be-deleted");

    let server = Arc::new(FakeServer {
        state: Mutex::new(ServerState {
            rows: vec![RowChange {
                table: NOTES_TABLE.into(),
                id: "n1".into(),
                payload: Some(serde_json::json!({})),
                version: "999.0000-device-2".into(),
                deleted: true,
                device_id: "device-2".into(),
                seq: 2,
                generation: 0,
            }],
            seq: 2,
            accepted: Vec::new(),
        }),
        generations: Default::default(),
    });

    let engine = SyncEngine::new(
        db.clone(),
        registry(),
        server.clone(),
        Arc::new(SettingsTokenProvider::new(db.clone())),
        stamper.clone(),
    );
    engine.sync_once().await.unwrap();
    let deleted_at: Option<i64> = db
        .call_sync(|conn| {
            Ok(conn.query_row(
                r#"SELECT deleted_at FROM "fin:notes" WHERE id = 'n1'"#,
                [],
                |r| r.get(0),
            )?)
        })
        .unwrap();
    assert!(deleted_at.is_some());
}

#[tokio::test]
async fn generation_change_resets_domain() {
    let db = test_db();
    let stamper = MutationStamper::new("user-1", "device-1");
    db.call_sync(|conn| ensure_identity(conn, "user-1", "device-1"))
        .unwrap();
    insert_note(&db, &stamper, "n1", "stale-after-reset");
    // The row was already pushed before the reset: no outbox pointer.
    db.call_sync(|conn| outbox::clear_table(conn, NOTES_TABLE))
        .unwrap();

    // Server bumped the finance generation and wiped its rows.
    let server = Arc::new(FakeServer {
        state: Mutex::new(ServerState::default()),
        generations: [("finance".to_owned(), 7)].into_iter().collect(),
    });

    let engine = SyncEngine::new(
        db.clone(),
        registry(),
        server.clone(),
        Arc::new(SettingsTokenProvider::new(db.clone())),
        stamper.clone(),
    );
    let outcome = engine.sync_once().await.unwrap();
    assert_eq!(outcome.resets, vec![Domain::Finance]);

    // Local rows of the domain were wiped, generation adopted.
    let (rows, generation) = db
        .call_sync(|conn| {
            let count: i64 =
                conn.query_row(r#"SELECT COUNT(*) FROM "fin:notes""#, [], |r| r.get(0))?;
            let generation = settings::get_setting(conn, "sync.gen.finance")?
                .and_then(|v| v.parse::<i64>().ok())
                .unwrap_or(0);
            Ok((count, generation))
        })
        .unwrap();
    assert_eq!(rows, 0);
    assert_eq!(generation, 7);
}
