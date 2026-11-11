//! Asset repository: CRUD over `fin:assets` and the append-only price
//! history in `fin:prices`. This is the only path to those tables.

use rusqlite::{Connection, OptionalExtension, params};
use rust_decimal::Decimal;

use lifeos::Result as LifeosResult;
use lifeos::ids::new_id;
use lifeos::sync::{MutationStamper, SyncMeta, outbox};

use crate::error::{FinanceError, Result};
use crate::models::{Asset, AssetKind, AssetPrice, NewAsset, NewAssetPrice};
use crate::tables::{ASSETS_TABLE, PRICES_TABLE};

pub fn insert_asset(conn: &Connection, asset: &Asset) -> LifeosResult<()> {
    conn.execute(
        &format!(
            r#"INSERT OR REPLACE INTO "{ASSETS_TABLE}" (id, kind, name, note, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)"#
        ),
        params![
            asset.id,
            asset.kind.as_str(),
            asset.name,
            asset.note,
            asset.sync.owner_user_id,
            asset.sync.updated_at,
            asset.sync.updated_by_device,
            asset.sync.hlc,
            asset.sync.deleted_at,
        ],
    )?;
    Ok(())
}

fn row_to_asset(row: &rusqlite::Row<'_>) -> rusqlite::Result<Asset> {
    Ok(Asset {
        id: row.get(0)?,
        kind: row
            .get::<_, String>(1)
            .ok()
            .and_then(|s| AssetKind::parse(&s))
            .unwrap_or(AssetKind::Other),
        name: row.get(2)?,
        note: row.get(3)?,
        sync: SyncMeta {
            owner_user_id: row.get(4)?,
            updated_at: row.get(5)?,
            updated_by_device: row.get(6)?,
            hlc: row.get(7)?,
            deleted_at: row.get(8)?,
        },
    })
}

const ASSET_SELECT: &str = r#"SELECT id, kind, name, note, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "fin:assets""#;

pub fn get(conn: &Connection, id: &str) -> Result<Option<Asset>> {
    let mut stmt = conn.prepare_cached(&format!("{ASSET_SELECT} WHERE id = ?1"))?;
    Ok(stmt.query_row(params![id], row_to_asset).optional()?)
}

pub fn get_required(conn: &Connection, id: &str) -> Result<Asset> {
    get(conn, id)?.ok_or_else(|| FinanceError::AssetNotFound(id.to_owned()))
}

/// Non-deleted assets in creation order (stable HLC sort).
pub fn list(conn: &Connection) -> Result<Vec<Asset>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{ASSET_SELECT} WHERE deleted_at IS NULL ORDER BY hlc"
    ))?;
    let rows = stmt.query_map([], row_to_asset)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

pub fn create(conn: &mut Connection, stamper: &MutationStamper, new: NewAsset) -> Result<Asset> {
    if new.name.trim().is_empty() {
        return Err(FinanceError::InvalidData("asset name is empty".into()));
    }
    let stamp = stamper.stamp(conn)?;
    let asset = Asset {
        id: new_id(),
        kind: new.kind,
        name: new.name,
        note: new.note,
        sync: SyncMeta::from_stamp(&stamp),
    };
    let tx = conn.transaction()?;
    insert_asset(&tx, &asset)?;
    outbox::enqueue(&tx, ASSETS_TABLE, &asset.id)?;
    tx.commit()?;
    Ok(asset)
}

pub fn update(conn: &mut Connection, stamper: &MutationStamper, asset: &Asset) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let mut updated = asset.clone();
    updated.sync = SyncMeta::from_stamp(&stamp);
    let tx = conn.transaction()?;
    insert_asset(&tx, &updated)?;
    outbox::enqueue(&tx, ASSETS_TABLE, &updated.id)?;
    tx.commit()?;
    Ok(())
}

/// Tombstone delete (sync carries the deletion). Prices are history rows
/// and stay.
pub fn soft_delete(conn: &mut Connection, stamper: &MutationStamper, id: &str) -> Result<()> {
    let stamp = stamper.stamp(conn)?;
    let deleted_at = stamp.now.div_euclid(1000);
    let tx = conn.transaction()?;
    tx.execute(
        &format!(
            r#"UPDATE "{ASSETS_TABLE}" SET deleted_at = ?2, hlc = ?3, updated_by_device = ?4, updated_at = ?5 WHERE id = ?1"#
        ),
        params![id, deleted_at, stamp.hlc, stamp.device_id, deleted_at],
    )?;
    outbox::enqueue(&tx, ASSETS_TABLE, id)?;
    tx.commit()?;
    Ok(())
}

// ---- Price history ----

pub fn record_price(
    conn: &mut Connection,
    stamper: &MutationStamper,
    new: NewAssetPrice,
) -> Result<AssetPrice> {
    if new.per_unit <= Decimal::ZERO {
        return Err(FinanceError::InvalidData(
            "price per_unit must be positive".into(),
        ));
    }
    lifeos::money::Currency::new(&new.quote_currency)
        .map_err(|e| FinanceError::InvalidData(e.to_string()))?;
    let stamp = stamper.stamp(conn)?;
    let price = AssetPrice {
        id: new_id(),
        unit: new.unit,
        quote_currency: new.quote_currency,
        observed_on: new.observed_on,
        per_unit: new.per_unit,
        source: new.source,
        sync: SyncMeta::from_stamp(&stamp),
    };
    let tx = conn.transaction()?;
    tx.execute(
        &format!(
            r#"INSERT INTO "{PRICES_TABLE}" (id, unit, quote_currency, observed_on, per_unit, source, owner_user_id, updated_at, updated_by_device, hlc, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)"#
        ),
        params![
            price.id,
            price.unit,
            price.quote_currency,
            price.observed_on,
            price.per_unit.to_string(),
            price.source,
            price.sync.owner_user_id,
            price.sync.updated_at,
            price.sync.updated_by_device,
            price.sync.hlc,
            price.sync.deleted_at,
        ],
    )?;
    outbox::enqueue(&tx, PRICES_TABLE, &price.id)?;
    tx.commit()?;
    Ok(price)
}

fn row_to_price(row: &rusqlite::Row<'_>) -> rusqlite::Result<AssetPrice> {
    let per_unit = row.get::<_, String>(4)?;
    let per_unit = Decimal::from_str_exact(&per_unit).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(4, rusqlite::types::Type::Text, Box::new(e))
    })?;
    Ok(AssetPrice {
        id: row.get(0)?,
        unit: row.get(1)?,
        quote_currency: row.get(2)?,
        observed_on: row.get(3)?,
        per_unit,
        source: row.get(5)?,
        sync: SyncMeta {
            owner_user_id: row.get(6)?,
            updated_at: row.get(7)?,
            updated_by_device: row.get(8)?,
            hlc: row.get(9)?,
            deleted_at: row.get(10)?,
        },
    })
}

const PRICE_SELECT: &str = r#"SELECT id, unit, quote_currency, observed_on, per_unit, source, owner_user_id, updated_at, updated_by_device, hlc, deleted_at FROM "fin:prices""#;

/// Full history for one unit, newest observation first.
pub fn list_prices(conn: &Connection, unit: &str) -> Result<Vec<AssetPrice>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{PRICE_SELECT} WHERE deleted_at IS NULL AND unit = ?1 ORDER BY observed_on DESC, hlc DESC"
    ))?;
    let rows = stmt.query_map(params![unit], row_to_price)?;
    Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
}

/// The newest observation at or before `as_of` for the unit in the given
/// quote currency. Prices recorded in other quote currencies are ignored.
pub fn latest_price(
    conn: &Connection,
    unit: &str,
    quote_currency: &str,
    as_of: i64,
) -> Result<Option<AssetPrice>> {
    let mut stmt = conn.prepare_cached(&format!(
        "{PRICE_SELECT} WHERE deleted_at IS NULL AND unit = ?1 AND quote_currency = ?2 AND observed_on <= ?3 ORDER BY observed_on DESC, hlc DESC LIMIT 1"
    ))?;
    Ok(stmt
        .query_row(params![unit, quote_currency, as_of], row_to_price)
        .optional()?)
}

/// Compile-time reminder that this repository belongs to the finance
/// domain.
pub const DOMAIN: lifeos::error::Domain = lifeos::error::Domain::Finance;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::builders;
    use crate::repos::account_repository as accounts;
    use crate::repos::journal_repository;
    use crate::system_accounts;
    use crate::tables::migration;
    use lifeos::db::{Db, DbOpenOptions, migrations::core_migrations};
    use lifeos::error::Domain;
    use rust_decimal::Decimal;
    use std::path::PathBuf;
    use std::str::FromStr;

    pub(crate) fn test_db() -> Db {
        Db::open(DbOpenOptions {
            path: PathBuf::from(":memory:"),
            encryption_key: None,
            migrations: core_migrations()
                .push(migration())
                .push(crate::tables::assets_migration()),
        })
        .unwrap()
    }

    pub(crate) fn stamper() -> MutationStamper {
        MutationStamper::new("user-1", "device-1")
    }

    fn fx() -> impl crate::invariants::FxRateSource {
        |_conn: &Connection, from: &str, to: &str, _: i64| (from == to).then_some(Decimal::ONE)
    }

    #[tokio::test]
    async fn create_list_get_roundtrip() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            let asset = create(conn, &st, NewAsset::new(AssetKind::Stock, "贵州茅台"))?;
            assert_eq!(asset.kind, AssetKind::Stock);

            let listed = list(conn)?;
            assert_eq!(listed.len(), 1);
            assert_eq!(listed[0].name, "贵州茅台");

            let fetched = get_required(conn, &asset.id)?;
            assert_eq!(fetched, asset);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn kind_wire_names_are_snake_case() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            for (kind, wire) in [
                (AssetKind::MutualFund, "mutual_fund"),
                (AssetKind::RealEstate, "real_estate"),
                (AssetKind::Etf, "etf"),
            ] {
                let asset = create(conn, &st, NewAsset::new(kind, wire))?;
                let raw: String = conn
                    .query_row(
                        &format!(r#"SELECT kind FROM "{ASSETS_TABLE}" WHERE id = ?1"#),
                        params![asset.id],
                        |row| row.get(0),
                    )
                    .unwrap();
                assert_eq!(raw, wire);
                assert_eq!(AssetKind::parse(&raw), Some(kind));
            }
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn update_and_tombstone_carry_outbox_pointers() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            let asset = create(conn, &st, NewAsset::new(AssetKind::Vehicle, "家用车"))?;
            let mut renamed = asset.clone();
            renamed.name = "旧家用车".into();
            update(conn, &st, &renamed)?;
            assert_eq!(get_required(conn, &asset.id)?.name, "旧家用车");
            // The outbox dedupes to one pointer per dirty row.
            assert_eq!(outbox::count(conn)?, 1);

            soft_delete(conn, &st, &asset.id)?;
            assert!(get(conn, &asset.id)?.unwrap().sync.deleted_at.is_some());
            assert!(list(conn)?.is_empty());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn price_history_orders_and_picks_latest() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            let asset = create(conn, &st, NewAsset::new(AssetKind::Stock, "AAPL"))?;
            for (day, price) in [(1000, "150.25"), (2000, "151.00"), (3000, "149.50")] {
                record_price(
                    conn,
                    &st,
                    NewAssetPrice {
                        unit: asset.id.clone(),
                        quote_currency: "USD".into(),
                        observed_on: day,
                        per_unit: Decimal::from_str(price).unwrap(),
                        source: Some("manual".into()),
                    },
                )?;
            }

            let history = list_prices(conn, &asset.id)?;
            assert_eq!(history.len(), 3);
            assert_eq!(history[0].observed_on, 3000);
            // Exact decimal, no float drift.
            assert_eq!(history[0].per_unit.to_string(), "149.50");

            let at_2500 = latest_price(conn, &asset.id, "USD", 2500)?;
            assert_eq!(at_2500.unwrap().observed_on, 2000);
            let before_any = latest_price(conn, &asset.id, "USD", 500)?;
            assert!(before_any.is_none());
            // Other quote currencies do not leak in.
            assert!(latest_price(conn, &asset.id, "CNY", 5000)?.is_none());
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn valuation_adjust_cash_and_physical_entries_balance() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            system_accounts::seed_system_accounts(conn, &st)?;
            let equity = accounts::find_system_account(conn, "user-1", "equity:adjustments")?
                .expect("equity:adjustments seeded");

            // Cash-class: quantity 0 books units=1 with the absolute price.
            let cash_build = builders::valuation_adjust(
                1_767_258_000,
                "cash-account",
                &equity.id,
                "CNY",
                Decimal::ZERO,
                Decimal::from_str("88000").unwrap(),
                "CNY",
                None,
                None,
                vec![],
            )?;
            assert_eq!(cash_build.postings[0].units, Decimal::ONE);
            assert_eq!(
                cash_build.postings[0]
                    .price
                    .as_ref()
                    .unwrap()
                    .per_unit
                    .to_string(),
                "88000"
            );
            assert_eq!(cash_build.postings[1].units.to_string(), "-88000");

            // Physical: quantity × per-unit price against the equity hedge.
            let physical = builders::valuation_adjust(
                1_767_258_000,
                "broker-account",
                &equity.id,
                "asset:AAPL",
                Decimal::from(10),
                Decimal::from_str("151.25").unwrap(),
                "USD",
                None,
                None,
                vec![],
            )?;
            assert_eq!(physical.postings[0].units, Decimal::from(10));
            assert_eq!(physical.postings[1].units.to_string(), "-1512.50");
            let tag = format!("asset:{}", "asset:AAPL");
            assert!(physical.entry.tag_ids.contains(&tag));

            // Both balance natively (the price annotation folds the asset leg
            // into the same currency as the equity hedge).
            let conn_fx = |_conn: &Connection, from: &str, to: &str, _: i64| {
                (from == to).then_some(Decimal::ONE)
            };
            for build in [cash_build, physical] {
                let entry = crate::models::JournalEntry {
                    id: "j".into(),
                    date: build.entry.date,
                    settled_on: None,
                    narration: build.entry.narration.clone(),
                    payee: None,
                    flag: crate::models::EntryFlag::Confirmed,
                    tag_ids: build.entry.tag_ids.clone(),
                    sync: lifeos::sync::SyncMeta {
                        owner_user_id: "u".into(),
                        updated_at: 0,
                        updated_by_device: "d".into(),
                        hlc: "1.0000-d".into(),
                        deleted_at: None,
                    },
                };
                let postings: Vec<crate::models::Posting> = build
                    .postings
                    .iter()
                    .map(|d| crate::models::Posting {
                        id: format!("p{}", d.position),
                        journal_entry_id: "j".into(),
                        position: d.position as i64,
                        account_id: d.account_id.clone(),
                        units: d.units,
                        unit: d.unit.clone(),
                        cost: d.cost.clone(),
                        price: d.price.clone(),
                        sync: lifeos::sync::SyncMeta {
                            owner_user_id: "u".into(),
                            updated_at: 0,
                            updated_by_device: "d".into(),
                            hlc: "1.0000-d".into(),
                            deleted_at: None,
                        },
                    })
                    .collect();
                let report = crate::invariants::evaluate_entry_balance(
                    conn, &entry, &postings, &conn_fx, "CNY", None,
                );
                assert!(report.is_balanced(), "{:?}", report.problems);
            }
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn valuation_adjust_write_commits_atomically() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            system_accounts::seed_system_accounts(conn, &st)?;
            let equity = accounts::find_system_account(conn, "user-1", "equity:adjustments")?
                .expect("seeded");
            let broker = accounts::create(
                conn,
                &st,
                accounts::NewAccount::custody(
                    crate::models::AccountCategory::Broker,
                    "券商",
                    "CNY",
                ),
            )?;
            let asset = create(conn, &st, NewAsset::new(AssetKind::Stock, "茅台"))?;

            // A price observation drives the valuation.
            let price = record_price(
                conn,
                &st,
                NewAssetPrice {
                    unit: asset.id.clone(),
                    quote_currency: "CNY".into(),
                    observed_on: 1_767_258_000,
                    per_unit: Decimal::from_str("1712.00").unwrap(),
                    source: Some("manual".into()),
                },
            )?;
            let build = builders::valuation_adjust(
                1_767_258_000,
                &broker.id,
                &equity.id,
                &asset.id,
                Decimal::from_str("2").unwrap(),
                price.per_unit,
                "CNY",
                Some("估值调整"),
                None,
                vec![],
            )?;
            let created = journal_repository::create(conn, &st, &fx(), "CNY", build)?;
            assert_eq!(created.postings.len(), 2);

            // Entry + 2 postings + price + asset + accounts: all in the outbox.
            let pending = outbox::count(conn)?;
            assert!(pending >= 4);
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn non_positive_price_and_valuation_are_refused() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            assert!(
                record_price(
                    conn,
                    &st,
                    NewAssetPrice {
                        unit: "a".into(),
                        quote_currency: "CNY".into(),
                        observed_on: 0,
                        per_unit: Decimal::ZERO,
                        source: None,
                    },
                )
                .is_err()
            );

            let equity = crate::system_accounts::system_account_id("user-1", "equity:adjustments");
            assert!(
                builders::valuation_adjust(
                    0,
                    "a",
                    &equity,
                    "CNY",
                    Decimal::ZERO,
                    Decimal::ZERO,
                    "CNY",
                    None,
                    None,
                    vec![],
                )
                .is_err()
            );
            Ok(())
        })
        .unwrap();
    }

    #[tokio::test]
    async fn sync_registry_carries_asset_families() {
        let registry = crate::tables::sync_registry();
        let tables: Vec<&str> = registry.adapters().iter().map(|a| a.table()).collect();
        assert!(tables.contains(&ASSETS_TABLE));
        assert!(tables.contains(&PRICES_TABLE));
        let domains: Vec<lifeos::error::Domain> =
            registry.adapters().iter().map(|a| a.domain()).collect();
        assert!(domains.iter().all(|d| *d == Domain::Finance));
    }

    #[tokio::test]
    async fn sync_adapter_roundtrips_asset_and_price_rows() {
        let db = test_db();
        let st = stamper();
        db.call_sync(move |conn: &mut rusqlite::Connection| -> LifeosResult<()> {
            let registry = crate::tables::sync_registry();
            let asset = create(conn, &st, NewAsset::new(AssetKind::Crypto, "BTC"))?;
            record_price(
                conn,
                &st,
                NewAssetPrice {
                    unit: asset.id.clone(),
                    quote_currency: "USD".into(),
                    observed_on: 42,
                    per_unit: Decimal::from_str("61234.5").unwrap(),
                    source: None,
                },
            )?;

            let price_id = list_prices(conn, &asset.id)?[0].id.clone();
            for (table, id) in [(ASSETS_TABLE, asset.id.clone()), (PRICES_TABLE, price_id)] {
                let adapter = registry.adapter(table).expect("adapter registered");
                let payload = adapter.read_row(conn, &id)?.expect("row exists");
                // A fresh database with the same schema accepts the payload.
                let target = Connection::open_in_memory().unwrap();
                for step in core_migrations()
                    .push(migration())
                    .push(crate::tables::assets_migration())
                    .steps()
                {
                    target.execute_batch(step.sql)?;
                }
                adapter.apply_upsert(&target, &payload)?;
                let roundtripped = adapter.read_row(&target, &id)?.expect("row copied");
                assert_eq!(payload, roundtripped);
            }
            Ok(())
        })
        .unwrap();
    }
}
