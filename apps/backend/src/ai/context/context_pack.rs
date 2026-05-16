//! Top-level [`ContextPack`] and its components.
//!
//! Money-shaped values ride as `String` decimal in **minor units** of
//! the relevant currency. Strings preserve exact precision across the
//! Rust ↔ Dart boundary; `f64` is only used for unitless ratios
//! (`progress_fraction`, `score`, `years_remaining_estimate`).

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ContextPackVersion {
    pub major: u32,
    pub minor: u32,
}

pub const CURRENT_CONTEXT_PACK_VERSION: ContextPackVersion =
    ContextPackVersion { major: 1, minor: 0 };

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum BudgetTier {
    Small,
    Standard,
    Large,
}

impl BudgetTier {
    /// Hard JSON byte cap. The planner refuses to admit a pack whose
    /// serialized form exceeds this — code-level, not prompt-level.
    pub const fn byte_cap(self) -> usize {
        match self {
            Self::Small => 4 * 1024,
            Self::Standard => 16 * 1024,
            Self::Large => 64 * 1024,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PrivacyBudget {
    pub tier: BudgetTier,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AnonymizationLevel {
    None,
    Bucket,
    Hash,
    Redact,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Capability {
    Classify,
    Search,
    Summarize,
    Plan,
    Analyze,
    Write,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RiskLevel {
    Info,
    Suggest,
    Propose,
    Commit,
}

/// See `apps/mobile/lib/core/ai/contracts/intent.dart`. `null` for
/// read-only intents; required for `Capability::Write`.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SideEffectScope {
    Local,
    CrossCutting,
    External,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct IntentHint {
    pub capability: Capability,
    pub risk: RiskLevel,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub side_effect: Option<SideEffectScope>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RiskPreference {
    Conservative,
    Moderate,
    Aggressive,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum CashflowTrend {
    Improving,
    Stable,
    Worsening,
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AccountSummary {
    pub total_count: u32,
    /// Bucket count by coarse account kind. `BTreeMap` rather than
    /// `HashMap` so JSON output is order-stable for goldens.
    pub by_kind: BTreeMap<String, u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CashflowSummary {
    pub base_currency: String,
    pub months_covered: u32,
    pub average_inflow_minor: String,
    pub average_outflow_minor: String,
    pub trend: CashflowTrend,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FireGoalSummary {
    pub target_minor: String,
    pub currency: String,
    pub progress_fraction: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub years_remaining_estimate: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BaseContext {
    pub preferred_currency: String,
    pub risk_preference: RiskPreference,
    /// Wave 32 — deprecated. Account aggregates now live in
    /// `holdings_snapshot` / `asset_allocation_snapshot` read models.
    /// Kept on the wire for backward-compat; clients emit empty values.
    /// Will be removed when ContextPack ticks to major v2.
    pub accounts: AccountSummary,
    /// Wave 32 — deprecated. Cashflow aggregates now live in
    /// `cashflow_buckets` / `monthly_spend_by_category` read models.
    /// Kept on the wire for backward-compat; clients emit empty values.
    /// Will be removed when ContextPack ticks to major v2.
    pub cashflow: CashflowSummary,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fire_goal: Option<FireGoalSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RouteContext {
    pub path: String,
    pub area: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SignalKind {
    SpendingSpike,
    SubscriptionPriceUp,
    RefundUnmatched,
    DepositMaturing,
    FireMilestone,
    CashflowAnomaly,
    Other,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SignalSeverity {
    Info,
    Warn,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RecentSignal {
    pub kind: SignalKind,
    pub severity: SignalSeverity,
    pub summary_zh: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detail_ref: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SemanticHit {
    pub source: String,
    pub title: String,
    pub excerpt: String,
    pub score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DateRange {
    pub from_inclusive: String,
    pub to_exclusive: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScopedAggregate {
    pub label: String,
    pub amount_minor: String,
    pub currency: String,
    pub range: DateRange,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub row_count: Option<u32>,
}

/// 端侧主动给云端的 freshness 失效提示。docs/ai-architecture.md §4.2
/// Phase 2 闭环：mobile 检测 stale → 下一次 chat 的 ContextPack 携带
/// 此 hint → routes/ai.rs 在 dispatch 前清掉 freshness_meta → 工具
/// dispatch 调 ensure_fresh 时自然重算。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct FreshnessHint {
    #[serde(default)]
    pub force_refresh_read_models: Vec<String>,
    /// Wave 32 — 端侧此次 chat 时的 localHlc。早期 client 不携带，
    /// `None` 时回落到 `TaskContext::device_hlc` 兼容旧路径。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_local_hlc: Option<String>,
}

/// 端→云单条分析上报（docs/ai-architecture.md §4.3.3 Analytical 层）。
/// `kind` 决定 payload schema —— 'recurring_pattern' / 'anomaly_flag' /
/// 'refund_link' / 'subscription_change' 等。后端按 kind 路由到对应
/// 的 device-sourced read model 表。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AnalyticalUpload {
    pub kind: String,
    pub id: String,
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TaskContext {
    pub route: RouteContext,
    pub intent: IntentHint,
    #[serde(default)]
    pub signals: Vec<RecentSignal>,
    #[serde(default)]
    pub retrieved: Vec<SemanticHit>,
    #[serde(default)]
    pub aggregates: Vec<ScopedAggregate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub freshness_hint: Option<FreshnessHint>,
    /// 端侧 detector 产生的分析记录（recurring/anomaly 等）。后端
    /// 用 `recurring_patterns::ingest` 等镜像到对应 device-sourced
    /// read model。
    #[serde(default)]
    pub analytical_uploads: Vec<AnalyticalUpload>,
    /// 当存在 `analytical_uploads` 时，端侧的 localHlc 作为这批上报
    /// 的 watermark。空字符串 = 无 HLC（早期 client）。
    #[serde(default)]
    pub device_hlc: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ContextPack {
    pub version: ContextPackVersion,
    pub base: BaseContext,
    pub task: TaskContext,
    pub budget: PrivacyBudget,
}

#[derive(Debug, thiserror::Error)]
pub enum ContextPackError {
    #[error("context pack oversize: tier={tier:?}, actual={actual}, cap={cap}")]
    Oversize {
        tier: BudgetTier,
        actual: usize,
        cap: usize,
    },
    #[error("context pack version unsupported: client={client_major}.{client_minor}, server={server_major}.{server_minor}")]
    VersionUnsupported {
        client_major: u32,
        client_minor: u32,
        server_major: u32,
        server_minor: u32,
    },
    #[error("context pack json error: {0}")]
    Json(#[from] serde_json::Error),
}

impl ContextPack {
    /// Major-version compatibility against the running server. Minor
    /// mismatches are accepted (forward-compatible additive fields).
    pub fn assert_version(&self, server: &ContextPackVersion) -> Result<(), ContextPackError> {
        if self.version.major != server.major {
            return Err(ContextPackError::VersionUnsupported {
                client_major: self.version.major,
                client_minor: self.version.minor,
                server_major: server.major,
                server_minor: server.minor,
            });
        }
        Ok(())
    }

    /// Reject packs whose serialized JSON exceeds the budget cap.
    pub fn assert_budget(&self) -> Result<(), ContextPackError> {
        let bytes = serde_json::to_vec(self)?;
        let cap = self.budget.tier.byte_cap();
        if bytes.len() > cap {
            return Err(ContextPackError::Oversize {
                tier: self.budget.tier,
                actual: bytes.len(),
                cap,
            });
        }
        Ok(())
    }
}
