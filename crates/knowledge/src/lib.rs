//! Knowledge domain: notes and decisions. Domain code never imports other
//! domains and reaches the database only through repositories over
//! `&mut Connection`.

pub mod error;
pub mod models;
pub mod repos;
pub mod tables;

pub use error::{KnowledgeError, Result};
pub use tables::KNOWLEDGE_SCHEMA_VERSION;

#[cfg(test)]
mod tests {
    use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations};
    use lifeos::error::Domain;
    use lifeos::sync::{MutationStamper, outbox};
    use rusqlite::Connection;
    use std::path::PathBuf;

    use crate::models::{DecisionStatus, NewDecision, NewNote};
    use crate::repos::{decision_repository as decisions, note_repository as notes};
    use crate::tables::{DECISIONS_TABLE, NOTES_TABLE, migration};

    fn test_db() -> Db {
        Db::open(DbOpenOptions {
            path: PathBuf::from(":memory:"),
            encryption_key: None,
            migrations: core_migrations().push(migration()),
        })
        .unwrap()
    }

    fn stamper() -> MutationStamper {
        MutationStamper::new("user-1", "device-1")
    }

    #[test]
    fn migration_applies_version_3() {
        let db = test_db();
        db.call_sync(|conn| {
            let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            assert_eq!(version, crate::KNOWLEDGE_SCHEMA_VERSION);
            assert_eq!(crate::KNOWLEDGE_SCHEMA_VERSION, 3);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn note_create_update_delete_roundtrip() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let note = notes::create(
                conn,
                &st,
                NewNote {
                    title: "复式记账要点".into(),
                    content: "每笔交易必须借贷平衡。".into(),
                    source: Some("beancount 文档".into()),
                    created_at: 1_767_258_000,
                },
            )?;
            assert_eq!(note.created_at, 1_767_258_000);

            let fetched = notes::get_required(conn, &note.id)?;
            assert_eq!(fetched.source.as_deref(), Some("beancount 文档"));

            let mut edited = fetched.clone();
            edited.content = "每笔交易必须借贷平衡（Σweight = 0）。".into();
            notes::update(conn, &st, &edited)?;
            let reloaded = notes::get_required(conn, &note.id)?;
            assert_ne!(reloaded.sync.hlc, note.sync.hlc);
            assert!(reloaded.content.contains("Σweight"));

            notes::soft_delete(conn, &st, &note.id)?;
            assert!(
                notes::get(conn, &note.id)?
                    .unwrap()
                    .sync
                    .deleted_at
                    .is_some()
            );
            assert!(notes::list_recent(conn, 10)?.is_empty());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn note_list_orders_newest_first() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            for (title, at) in [("早", 1_000), ("中", 2_000), ("晚", 3_000)] {
                notes::create(
                    conn,
                    &st,
                    NewNote {
                        title: title.into(),
                        content: String::new(),
                        source: None,
                        created_at: at,
                    },
                )?;
            }
            let listed = notes::list_recent(conn, 10)?;
            let titles: Vec<&str> = listed.iter().map(|n| n.title.as_str()).collect();
            assert_eq!(titles, vec!["晚", "中", "早"]);

            let page = notes::list_recent(conn, 2)?;
            assert_eq!(page.len(), 2);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn note_create_enqueues_outbox_atomically() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            notes::create(conn, &st, NewNote::now("标题", "内容"))?;
            assert_eq!(outbox::count(conn)?, 1);
            let (table, row_id) = outbox::pending(conn, 1)?[0].clone();
            assert_eq!(table, NOTES_TABLE);
            assert!(!row_id.is_empty());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn decision_create_review_roundtrip() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let decision = decisions::create(
                conn,
                &st,
                NewDecision {
                    title: "要不要定投指数".into(),
                    context: "月结余稳定，想长期增值".into(),
                    choice: "每月定投 沪深300".into(),
                    outcome: None,
                    status: DecisionStatus::Active,
                    created_at: 1_767_258_000,
                },
            )?;
            assert_eq!(decision.status, DecisionStatus::Active);

            decisions::review(
                conn,
                &st,
                &decision.id,
                DecisionStatus::Verified,
                Some("三个月跑赢基准".into()),
            )?;
            let reviewed = decisions::get_required(conn, &decision.id)?;
            assert_eq!(reviewed.status, DecisionStatus::Verified);
            assert_eq!(reviewed.outcome.as_deref(), Some("三个月跑赢基准"));

            // Reviewing an unknown decision is a hard error, not a no-op.
            assert!(decisions::review(conn, &st, "missing", DecisionStatus::Paused, None).is_err());

            decisions::soft_delete(conn, &st, &decision.id)?;
            assert!(decisions::list_recent(conn, 10)?.is_empty());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn decision_requires_title_and_choice() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let empty_title = NewDecision {
                title: "  ".into(),
                context: String::new(),
                choice: "选项".into(),
                outcome: None,
                status: DecisionStatus::Draft,
                created_at: 0,
            };
            assert!(decisions::create(conn, &st, empty_title).is_err());

            let empty_choice = NewDecision {
                title: "问题".into(),
                context: String::new(),
                choice: String::new(),
                outcome: None,
                status: DecisionStatus::Draft,
                created_at: 0,
            };
            assert!(decisions::create(conn, &st, empty_choice).is_err());
            assert_eq!(outbox::count(conn)?, 0);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn sync_adapter_roundtrips_note_and_decision_rows() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let registry = crate::tables::sync_registry();
            let note = notes::create(conn, &st, NewNote::now("笔记", "正文"))?;
            let decision = decisions::create(conn, &st, NewDecision::now("问题", "背景", "选择"))?;

            let adapter = registry.adapter(NOTES_TABLE).expect("notes adapter");
            let payload = adapter.read_row(conn, &note.id)?.expect("row exists");
            assert_eq!(payload["title"], "笔记");
            assert!(payload["hlc"].is_string());

            let decision_adapter = registry.adapter(DECISIONS_TABLE).unwrap();
            let decision_payload = decision_adapter
                .read_row(conn, &decision.id)?
                .expect("row exists");
            assert_eq!(decision_payload["status"], "draft");

            // A fresh database with the same schema accepts both payloads.
            let target = Connection::open_in_memory().unwrap();
            for step in core_migrations().push(migration()).steps() {
                target.execute_batch(step.sql)?;
            }
            adapter.apply_upsert(&target, &payload)?;
            decision_adapter.apply_upsert(&target, &decision_payload)?;
            assert_eq!(adapter.read_row(&target, &note.id)?, Some(payload));
            assert_eq!(
                decision_adapter.read_row(&target, &decision.id)?,
                Some(decision_payload)
            );

            // The registered families belong to the knowledge domain.
            for adapter in registry.adapters() {
                assert_eq!(adapter.domain(), Domain::Knowledge);
            }
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn tombstone_pushes_version_and_writes_no_row() {
        // Applying a tombstone through the adapter marks the known row
        // deleted without creating rows for unknown ids.
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let registry = crate::tables::sync_registry();
            let note = notes::create(conn, &st, NewNote::now("笔记", "正文"))?;
            let adapter = registry.adapter(NOTES_TABLE).unwrap();
            adapter.apply_tombstone(conn, &note.id, "9.0000-other", "device-2")?;
            let stored = notes::get(conn, &note.id)?.unwrap();
            assert!(stored.sync.deleted_at.is_some());
            assert_eq!(stored.sync.updated_by_device, "device-2");

            // Unknown rows are skipped silently.
            adapter.apply_tombstone(conn, "ghost", "9.0000-other", "device-2")?;
            Ok(())
        })
        .unwrap();
    }
}
