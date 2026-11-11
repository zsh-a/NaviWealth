//! Execution domain: plans and actions. Domain code never imports other
//! domains and reaches the database only through repositories over
//! `&mut Connection`.

pub mod error;
pub mod models;
pub mod repos;
pub mod tables;

pub use error::{ExecutionError, Result};
pub use tables::EXECUTION_SCHEMA_VERSION;

#[cfg(test)]
mod tests {
    use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations};
    use lifeos::error::Domain;
    use lifeos::sync::{MutationStamper, outbox};
    use rusqlite::Connection;
    use std::path::PathBuf;

    use crate::models::{ActionStatus, NewAction, NewPlan, PlanKind, PlanPeriod, PlanStatus};
    use crate::repos::{action_repository as actions, plan_repository as plans};
    use crate::tables::{ACTIONS_TABLE, PLANS_TABLE, migration};

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
    fn migration_applies_version_4() {
        let db = test_db();
        db.call_sync(|conn| {
            let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            assert_eq!(version, crate::EXECUTION_SCHEMA_VERSION);
            assert_eq!(crate::EXECUTION_SCHEMA_VERSION, 4);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn plan_create_list_update_roundtrip() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let plan = plans::create(
                conn,
                &st,
                NewPlan::now("装修阳台", PlanKind::Project, PlanPeriod::Month),
            )?;
            assert_eq!(plan.status, PlanStatus::Active);
            assert_eq!(plan.kind, PlanKind::Project);

            plans::create(
                conn,
                &st,
                NewPlan::now("保持运动", PlanKind::Focus, PlanPeriod::Open),
            )?;
            let listed = plans::list(conn)?;
            assert_eq!(listed.len(), 2);

            let mut paused = plans::get_required(conn, &plan.id)?;
            paused.status = PlanStatus::Paused;
            plans::update(conn, &st, &paused)?;
            assert_eq!(
                plans::get_required(conn, &plan.id)?.status,
                PlanStatus::Paused
            );

            // Open plans (active/paused) sort before finished ones.
            let mut completed = paused;
            completed.status = PlanStatus::Completed;
            plans::update(conn, &st, &completed)?;
            let first = plans::list(conn)?.remove(0);
            assert_eq!(first.title, "保持运动");
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn plan_tombstone_leaves_actions_orphaned_by_design() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let plan = plans::create(
                conn,
                &st,
                NewPlan::now("搬家", PlanKind::Project, PlanPeriod::Quarter),
            )?;
            let action = actions::create(conn, &st, NewAction::now(&plan.id, "找中介"))?;
            plans::soft_delete(conn, &st, &plan.id)?;
            assert!(
                plans::get(conn, &plan.id)?
                    .unwrap()
                    .sync
                    .deleted_at
                    .is_some()
            );
            // The action survives; the plan id just stops resolving as an
            // open plan (moving open actions to Inbox is a UI concern).
            assert_eq!(actions::get_required(conn, &action.id)?.plan_id, plan.id);
            assert_eq!(actions::list_by_plan(conn, &plan.id)?.len(), 1);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn action_create_and_status_transitions() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let plan = plans::create(
                conn,
                &st,
                NewPlan::now("体检", PlanKind::Project, PlanPeriod::Week),
            )?;
            let action = actions::create(
                conn,
                &st,
                NewAction {
                    plan_id: plan.id.clone(),
                    title: "预约体检".into(),
                    due: Some(1_800_000_000),
                    created_at: 1_767_258_000,
                },
            )?;
            assert_eq!(action.status, ActionStatus::Todo);

            // todo → doing → done is the progress trail.
            actions::set_status(conn, &st, &action.id, ActionStatus::Doing)?;
            actions::set_status(conn, &st, &action.id, ActionStatus::Done)?;
            let done = actions::get_required(conn, &action.id)?;
            assert_eq!(done.status, ActionStatus::Done);
            assert!(!done.status.is_open());

            // Transitions are stamped mutations; the outbox dedupes the
            // same rows to one dirty pointer each (plan + action).
            assert_eq!(outbox::count(conn)?, 2);

            // Unknown ids are hard errors.
            assert!(actions::set_status(conn, &st, "missing", ActionStatus::Dropped).is_err());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn action_listing_orders_open_first_and_by_due() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let plan = plans::create(
                conn,
                &st,
                NewPlan::now("周计划", PlanKind::Project, PlanPeriod::Week),
            )?;
            let mk = |title: &str, due: Option<i64>| NewAction {
                plan_id: plan.id.clone(),
                title: title.into(),
                due,
                created_at: 1_767_258_000,
            };
            let a = actions::create(conn, &st, mk("无期限", None))?;
            let b = actions::create(conn, &st, mk("明天", Some(2_000)))?;
            let c = actions::create(conn, &st, mk("今天", Some(1_000)))?;
            let _d = actions::create(conn, &st, mk("已完成", None))?;
            actions::set_status(conn, &st, &_d.id, ActionStatus::Done)?;

            let listed = actions::list_by_plan(conn, &plan.id)?;
            let titles: Vec<&str> = listed.iter().map(|x| x.title.as_str()).collect();
            // Open first, earliest due first, unscheduled last, done after.
            assert_eq!(titles, vec!["今天", "明天", "无期限", "已完成"]);
            let _ = (a, b, c);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn open_actions_view_spans_plans() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let p1 = plans::create(
                conn,
                &st,
                NewPlan::now("计划一", PlanKind::Project, PlanPeriod::Week),
            )?;
            let p2 = plans::create(
                conn,
                &st,
                NewPlan::now("计划二", PlanKind::Focus, PlanPeriod::Open),
            )?;
            let x = actions::create(conn, &st, NewAction::now(&p1.id, "任务 X"))?;
            let y = actions::create(conn, &st, NewAction::now(&p2.id, "任务 Y"))?;
            let open = actions::list_open(conn, 10)?;
            assert_eq!(open.len(), 2);
            actions::set_status(conn, &st, &x.id, ActionStatus::Dropped)?;
            let open = actions::list_open(conn, 10)?;
            assert_eq!(open.len(), 1);
            assert_eq!(open[0].id, y.id);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn sync_adapter_roundtrips_plan_and_action_rows() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let registry = crate::tables::sync_registry();
            let plan = plans::create(
                conn,
                &st,
                NewPlan::now("计划", PlanKind::Focus, PlanPeriod::Quarter),
            )?;
            let action = actions::create(conn, &st, NewAction::now(&plan.id, "动作"))?;

            let plan_adapter = registry.adapter(PLANS_TABLE).expect("plans adapter");
            let payload = plan_adapter.read_row(conn, &plan.id)?.expect("row exists");
            assert_eq!(payload["kind"], "focus");
            assert_eq!(payload["period"], "quarter");

            let action_adapter = registry.adapter(ACTIONS_TABLE).unwrap();
            let action_payload = action_adapter
                .read_row(conn, &action.id)?
                .expect("row exists");
            assert_eq!(action_payload["status"], "todo");
            assert!(action_payload["due"].is_null());

            let target = Connection::open_in_memory().unwrap();
            for step in core_migrations().push(migration()).steps() {
                target.execute_batch(step.sql)?;
            }
            plan_adapter.apply_upsert(&target, &payload)?;
            action_adapter.apply_upsert(&target, &action_payload)?;
            assert_eq!(plan_adapter.read_row(&target, &plan.id)?, Some(payload));
            assert_eq!(
                action_adapter.read_row(&target, &action.id)?,
                Some(action_payload)
            );

            for adapter in registry.adapters() {
                assert_eq!(adapter.domain(), Domain::Execution);
            }
            Ok(())
        })
        .unwrap();
    }
}
