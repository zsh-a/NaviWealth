//! Freshness 元数据 — 每个 read model 工具返回带的 schema 公约信息。
//!
//! 用于:
//!  1. 端侧 freshness gate: 比对 `source_hlc_watermark` 与本地最新 HLC，
//!     落后则触发 `request_freshness_refresh`（§4.2 兜底通道）。
//!  2. 客户端 / Worker 缓存: 不同 `schema_version` / `calculation_version`
//!     之间的结果不能混用。
//!  3. AiTrace 审计: 把 read model 的版本归档，事后可以回溯当时的算法。

use serde::{Deserialize, Serialize};

/// Wire 形态。每个 read-model 工具的 tool_result 都附带一份。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Freshness {
    pub read_model: String,
    pub source_hlc_watermark: String,
    pub refreshed_at: String,
    pub schema_version: u32,
    pub calculation_version: u32,
}

impl Freshness {
    pub fn new(
        read_model: impl Into<String>,
        source_hlc_watermark: impl Into<String>,
        refreshed_at: impl Into<String>,
        schema_version: u32,
        calculation_version: u32,
    ) -> Self {
        Self {
            read_model: read_model.into(),
            source_hlc_watermark: source_hlc_watermark.into(),
            refreshed_at: refreshed_at.into(),
            schema_version,
            calculation_version,
        }
    }
}
