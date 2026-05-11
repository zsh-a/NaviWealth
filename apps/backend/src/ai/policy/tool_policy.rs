//! Static tool catalogue with typed metadata.
//!
//! Mirrors `apps/mobile/lib/core/ai/contracts/tool_descriptor.dart` —
//! the device router consults the same axes when deciding whether to
//! invoke a tool. The two sides are kept aligned by review (the
//! descriptor types don't cross the wire).

use crate::ai::context::{BudgetTier, RiskLevel};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Access {
    Read,
    Propose,
    /// Reserved for tools that touch external systems (broker / bank
    /// / outbound webhook). Currently empty — anything in this class
    /// is rejected by [`risk_policy::check_tool_call`].
    ExternalWrite,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Confirmation {
    None,
    OneTap,
    Typed,
}

#[derive(Debug, Clone, Copy)]
pub struct ToolDescriptor {
    pub name: &'static str,
    pub access: Access,
    pub risk: RiskLevel,
    pub requires_confirmation: Confirmation,
    /// Minimum [`BudgetTier`] the device must have sent for this tool
    /// to be admissible. `Small` means the tool is universally
    /// allowed; `Large` reserves it for the user-gestured 'deep
    /// analysis' surfaces.
    pub allowed_context_tier: BudgetTier,
}

const DESCRIPTORS: [ToolDescriptor; 24] = [
    // ── Read-only tools ────────────────────────────────────────
    ToolDescriptor {
        name: "get_holdings",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "get_journal_entries",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "compute_xirr",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "compute_net_worth",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "get_industry_breakdown",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "get_geo_breakdown",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "get_market_cap_breakdown",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "get_risk_alerts",
        access: Access::Read,
        risk: RiskLevel::Suggest,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    // Snapshot-layer read models (docs/ai-architecture.md §4.3.2)
    ToolDescriptor {
        name: "get_monthly_spend_by_category",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "get_net_worth_summary",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "get_cashflow_buckets",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    // Analytical-layer read model (cloud-projected; docs §4.3.3)
    ToolDescriptor {
        name: "get_xirr_summary",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    // Analytical-layer read models (docs/ai-architecture.md §4.3.3, device-sourced)
    ToolDescriptor {
        name: "get_recurring_patterns",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "get_anomaly_flags",
        access: Access::Read,
        risk: RiskLevel::Suggest,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "get_refund_links",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "get_transfer_links",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Small,
    },
    // Scoped Detail tools (docs/ai-architecture.md §4.3.4) — drill-down
    // 仅在 LLM 真正需要明细时调用；要求更高的 ContextPack tier 让常规
    // 路由不轻易触发。
    ToolDescriptor {
        name: "read_category_window",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "read_account_window",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "read_asset_window",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
    },
    // ── Propose tools (FIR-66) ─────────────────────────────────
    ToolDescriptor {
        name: "propose_trade",
        access: Access::Propose,
        risk: RiskLevel::Propose,
        requires_confirmation: Confirmation::OneTap,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "propose_expense",
        access: Access::Propose,
        risk: RiskLevel::Propose,
        requires_confirmation: Confirmation::OneTap,
        allowed_context_tier: BudgetTier::Small,
    },
    ToolDescriptor {
        name: "propose_liability_payment",
        access: Access::Propose,
        risk: RiskLevel::Propose,
        requires_confirmation: Confirmation::OneTap,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "propose_account_create",
        access: Access::Propose,
        risk: RiskLevel::Propose,
        requires_confirmation: Confirmation::OneTap,
        allowed_context_tier: BudgetTier::Standard,
    },
    ToolDescriptor {
        name: "propose_asset_valuation",
        access: Access::Propose,
        risk: RiskLevel::Propose,
        requires_confirmation: Confirmation::OneTap,
        allowed_context_tier: BudgetTier::Standard,
    },
];

/// All known tools. Used by tests to assert dispatch coverage.
pub fn descriptors() -> &'static [ToolDescriptor] {
    &DESCRIPTORS
}

/// Look up the descriptor for a tool by name.
pub fn lookup(name: &str) -> Option<&'static ToolDescriptor> {
    DESCRIPTORS.iter().find(|d| d.name == name)
}
