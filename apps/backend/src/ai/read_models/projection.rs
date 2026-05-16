//! Projection trait + 通用 helpers。
//!
//! 每个 read model 实现 [`Projection`]，工具调用时通过共享逻辑判断是否
//! 需要刷新（lazy refresh）。后续可加 sync / async / nightly 模式 (§4.3.6)，
//! 当前 Phase 1 只用 lazy。

use chrono::Utc;
use serde::Deserialize;
use worker::{D1Database, D1Type};

use crate::error::AppError;

use super::freshness::Freshness;

/// Phase 1 用 Lazy；后续模式预留位以便 ToolDescriptor 可标注期望档位。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)]
pub enum RefreshMode {
    /// 工具调用时检查 watermark，落后则同步重算。
    Lazy,
    /// write 路径触发：journal_entries / postings 写入后立即更新对应行。
    SyncOnWrite,
    /// Worker queue 批量异步重算。
    AsyncQueue,
    /// 夜间 cron 重算。
    Nightly,
}

/// 每个 read model 实现这个 trait。Phase 1 用 lazy refresh，工具调用
/// 时通过 [`ensure_fresh`] 共享逻辑判断是否需要重算。
///
/// 使用原生 async fn in trait（Rust 1.75+）。所有调用都是静态分发
/// （`<P: Projection>`），不需要 dyn 兼容；Worker 单线程 wasm
/// 环境下 future 不需要 `Send`。
pub trait Projection {
    /// 全局唯一名，进 freshness_meta 表 + Freshness wire。
    fn name(&self) -> &'static str;

    fn schema_version(&self) -> u32;
    fn calculation_version(&self) -> u32;

    /// Phase 1 全部 lazy；后续具体 read model override 此方法可声明
    /// SyncOnWrite / AsyncQueue / Nightly。
    #[allow(dead_code)]
    fn refresh_mode(&self) -> RefreshMode {
        RefreshMode::Lazy
    }

    /// 完整重算并写入 read model 表 + freshness_meta。
    /// 实现负责自己的写顺序（D1 在 Workers 下没有真事务，多用
    /// `db.batch(...)` 保证原子性）。
    fn refresh(
        &self,
        db: &D1Database,
        user_id: &str,
    ) -> impl std::future::Future<Output = Result<Freshness, AppError>>;

    /// 当前已记录的 freshness（如果从未刷新过返回 None）。
    fn current_freshness(
        &self,
        db: &D1Database,
        user_id: &str,
    ) -> impl std::future::Future<Output = Result<Option<Freshness>, AppError>> {
        async move { load_freshness_meta(db, user_id, self.name()).await }
    }
}

/// 工具调用时的入口：返回最新的 Freshness（必要时刷新）。
///
/// 简单的 lazy 策略：
///  1. 读 freshness_meta；不存在或版本不匹配 → 调用 `refresh()`。
///  2. 比较 meta.source_hlc_watermark 与 op_log 的最新 HLC；
///     stale → `refresh()`。
///  3. 否则直接返回 meta。
pub async fn ensure_fresh<P: Projection>(
    db: &D1Database,
    user_id: &str,
    proj: &P,
) -> Result<Freshness, AppError> {
    let meta = proj.current_freshness(db, user_id).await?;
    let needs_refresh = match &meta {
        None => true,
        Some(f) => {
            if f.schema_version != proj.schema_version()
                || f.calculation_version != proj.calculation_version()
            {
                true
            } else {
                let head = latest_op_log_hlc(db, user_id).await?;
                match head {
                    Some(h) => h.as_str() > f.source_hlc_watermark.as_str(),
                    None => false,
                }
            }
        }
    };
    if needs_refresh {
        proj.refresh(db, user_id).await
    } else {
        // safe: needs_refresh=false 蕴含 meta.is_some()
        Ok(meta.expect("meta must exist when needs_refresh is false"))
    }
}

/// 读 freshness_meta 中一行。
pub async fn load_freshness_meta(
    db: &D1Database,
    user_id: &str,
    read_model: &str,
) -> Result<Option<Freshness>, AppError> {
    let stmt = db
        .prepare(
            "SELECT source_hlc_watermark, refreshed_at, schema_version, calculation_version
             FROM read_model_freshness_meta
             WHERE user_id = ?1 AND read_model = ?2",
        )
        .bind_refs([&D1Type::Text(user_id), &D1Type::Text(read_model)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let row: Option<MetaRow> = stmt
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?;
    Ok(row.map(|r| {
        Freshness::new(
            read_model.to_string(),
            r.source_hlc_watermark,
            r.refreshed_at,
            r.schema_version,
            r.calculation_version,
        )
    }))
}

/// 主动失效一个 read model 的 freshness_meta —— 下次 `ensure_fresh`
/// 看到无 meta 行即强制走 `refresh()` 路径。
///
/// 由 freshness gate Phase 2 端→云协议触发：mobile 把上一轮 stale 的
/// read_model 名通过 `ContextPack.task.freshness_hint.force_refresh_read_models`
/// 传上来，`routes/ai.rs` 在 `dispatch` 之前调一次。
pub async fn clear_freshness_meta(
    db: &D1Database,
    user_id: &str,
    read_model: &str,
) -> Result<(), AppError> {
    db.prepare(
        "DELETE FROM read_model_freshness_meta
         WHERE user_id = ?1 AND read_model = ?2",
    )
    .bind_refs([&D1Type::Text(user_id), &D1Type::Text(read_model)])
    .map_err(|e| AppError::Internal(format!("bind: {e}")))?
    .run()
    .await
    .map_err(|e| AppError::Internal(format!("run: {e}")))?;
    Ok(())
}

/// 写 freshness_meta（upsert）。Projection.refresh 实现完成后调用。
pub async fn upsert_freshness_meta(
    db: &D1Database,
    user_id: &str,
    freshness: &Freshness,
) -> Result<(), AppError> {
    db.prepare(
        "INSERT INTO read_model_freshness_meta
            (user_id, read_model, source_hlc_watermark, refreshed_at,
             schema_version, calculation_version)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT (user_id, read_model) DO UPDATE SET
            source_hlc_watermark = excluded.source_hlc_watermark,
            refreshed_at         = excluded.refreshed_at,
            schema_version       = excluded.schema_version,
            calculation_version  = excluded.calculation_version",
    )
    .bind_refs([
        &D1Type::Text(user_id),
        &D1Type::Text(&freshness.read_model),
        &D1Type::Text(&freshness.source_hlc_watermark),
        &D1Type::Text(&freshness.refreshed_at),
        &D1Type::Integer(freshness.schema_version as i32),
        &D1Type::Integer(freshness.calculation_version as i32),
    ])
    .map_err(|e| AppError::Internal(format!("bind: {e}")))?
    .run()
    .await
    .map_err(|e| AppError::Internal(format!("run: {e}")))?;
    Ok(())
}

/// 取该用户 op_log 的最高 HLC。lazy 刷新的 staleness 判定依据。
pub async fn latest_op_log_hlc(db: &D1Database, user_id: &str) -> Result<Option<String>, AppError> {
    let stmt = db
        .prepare("SELECT MAX(hlc_text) AS h FROM op_log WHERE user_id = ?1")
        .bind_refs([&D1Type::Text(user_id)])
        .map_err(|e| AppError::Internal(format!("bind: {e}")))?;
    let row: Option<HlcRow> = stmt
        .first(None)
        .await
        .map_err(|e| AppError::Internal(format!("query: {e}")))?;
    Ok(row.and_then(|r| r.h))
}

/// 当前 ISO 时间，refresh 路径里塞进 freshness。
pub fn now_iso() -> String {
    Utc::now().to_rfc3339()
}

#[derive(Deserialize)]
struct MetaRow {
    source_hlc_watermark: String,
    refreshed_at: String,
    schema_version: u32,
    calculation_version: u32,
}

#[derive(Deserialize)]
struct HlcRow {
    h: Option<String>,
}
