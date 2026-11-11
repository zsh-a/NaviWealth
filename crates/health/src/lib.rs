//! Health domain: manually captured metrics. No HealthKit / Health
//! Connect integration here — the platform seam stays behind the platform
//! crate's stub.

pub mod error;
pub mod models;
pub mod repos;
pub mod tables;

pub use error::{HealthError, Result};
pub use tables::HEALTH_SCHEMA_VERSION;

#[cfg(test)]
mod tests {
    use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations};
    use lifeos::error::Domain;
    use lifeos::sync::{MutationStamper, outbox};
    use rusqlite::Connection;
    use rust_decimal::Decimal;
    use std::path::PathBuf;
    use std::str::FromStr;

    use crate::models::{MetricKind, NewMetric};
    use crate::repos::metric_repository as metrics;
    use crate::tables::{METRICS_TABLE, migration};

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
    fn migration_applies_version_5() {
        let db = test_db();
        db.call_sync(|conn| {
            let version: i64 = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            assert_eq!(version, crate::HEALTH_SCHEMA_VERSION);
            assert_eq!(crate::HEALTH_SCHEMA_VERSION, 5);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn metric_create_and_recent_list() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let steps = metrics::create(
                conn,
                &st,
                NewMetric {
                    kind: MetricKind::Steps,
                    quantity: Decimal::from(8_432),
                    recorded_at: 1_767_250_000,
                    unit: String::new(),
                    source: None,
                },
            )?;
            assert_eq!(steps.unit, "count");
            let weight = metrics::create(
                conn,
                &st,
                NewMetric {
                    kind: MetricKind::Weight,
                    quantity: Decimal::from_str("72.5").unwrap(),
                    recorded_at: 1_767_258_000,
                    unit: String::new(),
                    source: Some("manual".into()),
                },
            )?;
            assert_eq!(weight.unit, "kg");

            let recent = metrics::list_recent(conn, 10)?;
            assert_eq!(recent.len(), 2);
            assert_eq!(recent[0].kind, MetricKind::Weight);
            // Exact decimal roundtrip, no float drift.
            assert_eq!(recent[0].quantity.to_string(), "72.5");
            assert_eq!(recent[1].quantity.to_string(), "8432");
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn by_kind_and_latest_queries() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            for (at, qty) in [(1_000, "70.0"), (2_000, "71.2"), (3_000, "72.5")] {
                metrics::create(
                    conn,
                    &st,
                    NewMetric {
                        kind: MetricKind::Weight,
                        quantity: Decimal::from_str(qty).unwrap(),
                        recorded_at: at,
                        unit: "kg".into(),
                        source: None,
                    },
                )?;
            }
            metrics::create(
                conn,
                &st,
                NewMetric::now(MetricKind::Steps, Decimal::from(9_000)),
            )?;

            let weights = metrics::list_by_kind(conn, MetricKind::Weight, 10)?;
            assert_eq!(weights.len(), 3);
            assert_eq!(weights[0].quantity.to_string(), "72.5");

            let latest = metrics::latest_by_kind(conn, MetricKind::Weight, 2_500)?;
            assert_eq!(latest.unwrap().quantity.to_string(), "71.2");
            assert!(metrics::latest_by_kind(conn, MetricKind::Weight, 500)?.is_none());
            assert!(metrics::latest_by_kind(conn, MetricKind::Sleep, 9_999)?.is_none());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn negative_quantity_is_refused_and_tombstone_works() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let bad = NewMetric {
                kind: MetricKind::Weight,
                quantity: Decimal::from_str("-1").unwrap(),
                recorded_at: 0,
                unit: "kg".into(),
                source: None,
            };
            assert!(metrics::create(conn, &st, bad).is_err());
            assert_eq!(outbox::count(conn)?, 0);

            let metric = metrics::create(
                conn,
                &st,
                NewMetric::now(MetricKind::Sleep, Decimal::from(420)),
            )?;
            metrics::soft_delete(conn, &st, &metric.id)?;
            assert!(
                metrics::get(conn, &metric.id)?
                    .unwrap()
                    .sync
                    .deleted_at
                    .is_some()
            );
            assert!(metrics::list_recent(conn, 10)?.is_empty());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn sync_registry_and_adapter_roundtrip() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            let registry = crate::tables::sync_registry();
            assert_eq!(registry.adapters().len(), 1);
            assert_eq!(registry.adapters()[0].domain(), Domain::Health);
            assert_eq!(registry.adapters()[0].table(), METRICS_TABLE);

            let metric = metrics::create(
                conn,
                &st,
                NewMetric {
                    kind: MetricKind::Weight,
                    quantity: Decimal::from_str("73.05").unwrap(),
                    recorded_at: 1_767_258_000,
                    unit: "kg".into(),
                    source: Some("manual".into()),
                },
            )?;
            let adapter = registry.adapter(METRICS_TABLE).unwrap();
            let payload = adapter.read_row(conn, &metric.id)?.expect("row exists");
            assert_eq!(payload["kind"], "weight");
            assert_eq!(payload["quantity"], "73.05");
            assert_eq!(payload["unit"], "kg");

            let target = Connection::open_in_memory().unwrap();
            for step in core_migrations().push(migration()).steps() {
                target.execute_batch(step.sql)?;
            }
            adapter.apply_upsert(&target, &payload)?;
            assert_eq!(adapter.read_row(&target, &metric.id)?, Some(payload));

            // Tombstone through the adapter marks the known row deleted.
            adapter.apply_tombstone(&target, &metric.id, "9.0000-other", "device-2")?;
            let roundtripped = adapter.read_row(&target, &metric.id)?.unwrap();
            assert!(!roundtripped["deleted_at"].is_null());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn raw_quantity_column_stays_text() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut Connection| -> lifeos::Result<()> {
            metrics::create(
                conn,
                &st,
                NewMetric {
                    kind: MetricKind::Weight,
                    quantity: Decimal::from_str("72.500").unwrap(),
                    recorded_at: 0,
                    unit: "kg".into(),
                    source: None,
                },
            )?;
            let (typeof_value, stored): (String, String) = conn.query_row(
                &format!(r#"SELECT typeof(quantity), quantity FROM "{METRICS_TABLE}""#),
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )?;
            assert_eq!(typeof_value, "text");
            // Stored verbatim — trailing zeros preserved (no REAL rounding).
            assert_eq!(stored, "72.500");
            Ok(())
        })
        .unwrap();
    }
}
