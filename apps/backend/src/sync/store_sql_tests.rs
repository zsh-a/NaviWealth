//! Execute the production statements against SQLite, including the exact
//! interleavings that an in-memory fake or a pure LWW comparison cannot test.

use super::*;
use rusqlite::{params, Connection, OpenFlags};
use serde_json::json;

fn migrate(db: &Connection) {
    db.execute_batch(include_str!("../../migrations/0002_sync_schema.sql"))
        .unwrap();
    db.execute_batch(include_str!(
        "../../migrations/0019_sync_domain_generations.sql"
    ))
    .unwrap();
}

fn database() -> Connection {
    let db = Connection::open_in_memory().unwrap();
    migrate(&db);
    db
}

fn change(id: &str, version: &str) -> RowChange {
    RowChange {
        table: "fin:accounts".into(),
        id: id.into(),
        payload: Some(json!({"id": id, "name": version})),
        version: version.into(),
        deleted: false,
        device_id: String::new(),
        seq: 0,
        generation: 0,
    }
}

fn write(db: &Connection, user: &str, device: &str, row: &RowChange) -> usize {
    db.execute(
        APPLY_CHANGE_SQL,
        params![
            user,
            row.table,
            row.id,
            serde_json::to_string(&row.payload).unwrap(),
            row.version,
            device,
            i32::from(row.deleted),
            "2026-10-23T00:00:00Z",
            row.generation,
            domain_for_wire_table(&row.table).unwrap(),
        ],
    )
    .unwrap()
}

fn horizon(db: &Connection, user: &str) -> i64 {
    db.query_row(MAX_SEQ_SQL, [user], |row| row.get::<_, Option<i64>>(0))
        .unwrap()
        .unwrap_or(0)
}

fn rows(
    db: &Connection,
    user: &str,
    device: &str,
    since: i64,
    upper: i64,
    limit: i64,
) -> Vec<DbRow> {
    db.prepare(PULL_ROWS_SQL)
        .unwrap()
        .query_map(
            params![
                user,
                device,
                since.to_string(),
                upper.to_string(),
                limit + 1
            ],
            |row| {
                Ok(DbRow {
                    seq: row.get(0)?,
                    table_name: row.get(1)?,
                    row_id: row.get(2)?,
                    payload: row.get(3)?,
                    version: row.get(4)?,
                    device_id: row.get(5)?,
                    deleted: row.get(6)?,
                    generation: row.get(7)?,
                })
            },
        )
        .unwrap()
        .collect::<rusqlite::Result<Vec<_>>>()
        .unwrap()
}

fn pull_page(db: &Connection, user: &str, device: &str, since: i64, limit: i64) -> PullPage {
    let upper = horizon(db, user);
    build_pull_page(
        rows(db, user, device, since, upper, limit),
        since,
        upper,
        limit,
    )
}

fn reset(db: &mut Connection, user: &str) {
    let tx = db.transaction().unwrap();
    tx.execute(
        RESET_DOMAIN_SQL,
        params![user, "finance", "now", "reset-device"],
    )
    .unwrap();
    tx.execute(CLEAR_DOMAIN_SQL, params![user, "fin:%"])
        .unwrap();
    tx.commit().unwrap();
}

#[test]
fn winning_writes_advance_seq_and_losing_or_idempotent_writes_do_not() {
    let db = database();
    assert_eq!(write(&db, "user", "device-b", &change("row", "001")), 1);
    let first = horizon(&db, "user");
    assert_eq!(write(&db, "user", "device-b", &change("row", "001")), 0);
    assert_eq!(write(&db, "user", "device-a", &change("row", "001")), 0);
    assert_eq!(write(&db, "user", "device-z", &change("row", "000")), 0);
    assert_eq!(horizon(&db, "user"), first);

    assert_eq!(write(&db, "user", "device-c", &change("row", "001")), 1);
    let tied_winner = horizon(&db, "user");
    assert!(tied_winner > first);
    assert_eq!(write(&db, "user", "device-a", &change("row", "002")), 1);
    let page = pull_page(&db, "user", "reader", first, 500);
    assert_eq!(page.changes.len(), 1);
    assert_eq!(page.changes[0].version, "002");
    assert_eq!(page.changes[0].device_id, "device-a");
    assert!(page.changes[0].seq > tied_winner);
}

#[test]
fn a_later_stale_writer_cannot_overwrite_another_connections_newer_commit() {
    let name = format!(
        "file:sync-review-{}?mode=memory&cache=shared",
        uuid::Uuid::new_v4()
    );
    let flags = OpenFlags::SQLITE_OPEN_READ_WRITE
        | OpenFlags::SQLITE_OPEN_CREATE
        | OpenFlags::SQLITE_OPEN_URI;
    let first = Connection::open_with_flags(&name, flags).unwrap();
    let second = Connection::open_with_flags(&name, flags).unwrap();
    migrate(&first);
    write(&first, "user", "original", &change("row", "001"));

    // Both requests can have observed 001. Preparing a write must not freeze
    // that observation or allow a late request to overwrite 003 with 002.
    let mut stale_write = second.prepare(APPLY_CHANGE_SQL).unwrap();
    write(&first, "user", "newer", &change("row", "003"));
    assert_eq!(
        stale_write
            .execute(params![
                "user",
                "fin:accounts",
                "row",
                "{}",
                "002",
                "older",
                0,
                "now",
                0,
                "finance"
            ])
            .unwrap(),
        0,
    );
    assert_eq!(
        pull_page(&first, "user", "reader", 0, 500).changes[0].version,
        "003"
    );
}

#[test]
fn duplicate_keys_in_one_batch_keep_the_highest_version_in_either_order() {
    for versions in [["003", "002"], ["002", "003"]] {
        let mut db = database();
        write(&db, "user", "device", &change("row", "001"));
        let tx = db.transaction().unwrap();
        for version in versions {
            write(&tx, "user", "device", &change("row", version));
        }
        tx.commit().unwrap();
        let page = pull_page(&db, "user", "reader", 0, 500);
        assert_eq!(page.changes.len(), 1);
        assert_eq!(page.changes[0].version, "003");
    }
}

#[test]
fn reset_rejects_stale_generation_even_with_a_higher_version() {
    let mut db = database();
    write(&db, "user", "device", &change("row", "005"));
    let previous_cursor = horizon(&db, "user");
    reset(&mut db, "user");
    assert_eq!(write(&db, "user", "late", &change("row", "999")), 0);
    let empty = pull_page(&db, "user", "reader", previous_cursor, 500);
    assert!(empty.changes.is_empty());
    assert_eq!(empty.high_seq, 0);

    let mut fresh = change("row", "001");
    fresh.generation = 1;
    assert_eq!(write(&db, "user", "device", &fresh), 1);
    let page = pull_page(&db, "user", "reader", empty.high_seq, 500);
    assert_eq!(page.changes.len(), 1);
    assert_eq!(page.changes[0].generation, 1);
    assert!(page.high_seq > previous_cursor);
    assert_eq!(write(&db, "user", "late", &change("row", "999")), 0);
}

#[test]
fn insert_between_horizon_and_page_read_is_returned_by_the_next_pull() {
    let db = database();
    write(&db, "user", "peer", &change("first", "001"));
    let upper = horizon(&db, "user");
    write(&db, "user", "peer", &change("late", "002"));

    let page = build_pull_page(rows(&db, "user", "reader", 0, upper, 500), 0, upper, 500);
    assert_eq!(
        page.changes
            .iter()
            .map(|r| r.id.as_str())
            .collect::<Vec<_>>(),
        ["first"]
    );
    assert_eq!(page.high_seq, upper);
    let next = pull_page(&db, "user", "reader", page.high_seq, 500);
    assert_eq!(
        next.changes
            .iter()
            .map(|r| r.id.as_str())
            .collect::<Vec<_>>(),
        ["late"]
    );
}

#[test]
fn insert_after_page_read_does_not_advance_the_response_cursor() {
    let db = database();
    write(&db, "user", "peer", &change("first", "001"));
    let upper = horizon(&db, "user");
    let read = rows(&db, "user", "reader", 0, upper, 500);
    write(&db, "user", "peer", &change("late", "002"));
    let page = build_pull_page(read, 0, upper, 500);
    assert_eq!(page.high_seq, upper);
    assert_eq!(
        pull_page(&db, "user", "reader", page.high_seq, 500).changes[0].id,
        "late"
    );
}

#[test]
fn replacement_after_horizon_is_deferred_without_losing_the_new_state() {
    let db = database();
    write(&db, "user", "peer", &change("row", "001"));
    let upper = horizon(&db, "user");
    write(&db, "user", "peer", &change("row", "002"));
    let page = build_pull_page(rows(&db, "user", "reader", 0, upper, 500), 0, upper, 500);
    assert!(page.changes.is_empty());
    let next = pull_page(&db, "user", "reader", page.high_seq, 500);
    assert_eq!(next.changes[0].version, "002");
}

#[test]
fn count_limited_pages_advance_only_through_returned_rows() {
    let db = database();
    for id in ["one", "two", "three"] {
        write(&db, "user", "peer", &change(id, "001"));
    }
    let first = pull_page(&db, "user", "reader", 0, 2);
    assert!(first.more);
    assert_eq!(first.changes.len(), 2);
    assert_eq!(first.high_seq, first.changes[1].seq);
    let second = pull_page(&db, "user", "reader", first.high_seq, 2);
    assert!(!second.more);
    assert_eq!(second.changes[0].id, "three");
}

#[test]
fn byte_limited_pages_do_not_skip_the_first_row_that_did_not_fit() {
    let db = database();
    for i in 0..20 {
        let mut row = change(&format!("row-{i}"), "001");
        row.payload = Some(json!({"text": "x".repeat(60 * 1024)}));
        write(&db, "user", "peer", &row);
    }
    let first = pull_page(&db, "user", "reader", 0, 500);
    assert!(first.more);
    assert!(first.changes.len() < 20);
    assert_eq!(first.high_seq, first.changes.last().unwrap().seq);
    let second = pull_page(&db, "user", "reader", first.high_seq, 500);
    assert!(!second.more);
    let ids = first
        .changes
        .into_iter()
        .chain(second.changes)
        .map(|r| r.id)
        .collect::<Vec<_>>();
    assert_eq!(ids, (0..20).map(|i| format!("row-{i}")).collect::<Vec<_>>());
}

#[test]
fn cursor_bindings_keep_numeric_order_above_i32() {
    let db = database();
    write(&db, "user", "peer", &change("first", "001"));
    db.execute(
        "UPDATE sqlite_sequence SET seq = ? WHERE name = 'sync_rows'",
        [i64::from(i32::MAX) + 5],
    )
    .unwrap();
    write(&db, "user", "peer", &change("large", "001"));
    let page = pull_page(&db, "user", "reader", i64::from(i32::MAX), 500);
    assert_eq!(page.changes.len(), 1);
    assert_eq!(page.changes[0].id, "large");
    assert!(page.high_seq > i64::from(i32::MAX));
}

#[test]
fn an_ahead_cursor_returns_to_the_current_horizon() {
    let db = database();
    write(&db, "user", "peer", &change("first", "001"));
    let page = pull_page(&db, "user", "reader", 999, 500);
    assert!(page.changes.is_empty());
    assert!(!page.more);
    assert_eq!(page.high_seq, horizon(&db, "user"));
    write(&db, "user", "peer", &change("next", "001"));
    let next = pull_page(&db, "user", "reader", page.high_seq, 500);
    assert_eq!(next.changes[0].id, "next");
}

#[test]
fn lww_and_pull_are_user_scoped_and_own_device_rows_do_not_echo() {
    let db = database();
    write(&db, "other", "peer", &change("row", "999"));
    assert_eq!(write(&db, "user", "reader", &change("row", "001")), 1);
    assert_eq!(write(&db, "user", "peer", &change("second", "001")), 1);
    let page = pull_page(&db, "user", "reader", 0, 500);
    assert_eq!(page.changes.len(), 1);
    assert_eq!(page.changes[0].id, "second");
    assert_eq!(page.high_seq, horizon(&db, "user"));
}
