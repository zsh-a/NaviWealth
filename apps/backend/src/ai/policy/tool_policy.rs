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

/// Wave 20 — which runtimes are allowed to dispatch this tool. Bitset
/// instead of `Vec` so the descriptor stays `Copy` / `const`-able.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AllowedRuntimes(pub u8);

impl AllowedRuntimes {
    pub const DEVICE: u8 = 0b01;
    pub const CLOUD: u8 = 0b10;
    pub const ALL: AllowedRuntimes = AllowedRuntimes(Self::DEVICE | Self::CLOUD);
    pub const CLOUD_ONLY: AllowedRuntimes = AllowedRuntimes(Self::CLOUD);

    pub fn allows_device(self) -> bool {
        self.0 & Self::DEVICE != 0
    }
    pub fn allows_cloud(self) -> bool {
        self.0 & Self::CLOUD != 0
    }
}

/// Wave 20 — side-effect classification (orthogonal to risk level).
/// Lets the dispatcher reject `ExternalCall` in routine chat without
/// a special grant.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SideEffect {
    None,
    /// Creates a device-local write proposal (the user still must confirm).
    DeviceLocalWrite,
    /// Hits a third-party system (broker / bank / outbound webhook).
    ExternalCall,
}

/// Wave 20 — which Read Model layer this tool consumes (or `None` for
/// inline computers / proposals).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReadModelLayer {
    Snapshot,
    Analytical,
    ScopedDetail,
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
    /// Wave 20 — which runtimes may dispatch (device LLM vs cloud
    /// orchestrator). All tools default to `CloudOnly` until the device
    /// LLM runtime ships in Phase 5.
    pub allowed_runtimes: AllowedRuntimes,
    /// Wave 20 — side-effect class. Orthogonal to risk level.
    pub side_effect: SideEffect,
    /// Wave 20 — which Read Model layer this tool consumes. `None` for
    /// inline computers (e.g. `compute_xirr`) and proposals.
    pub read_model_layer: Option<ReadModelLayer>,
}

// Convenience: shorthand for the common "cloud-only, no side effect" case.
const fn read_only(
    name: &'static str,
    risk: RiskLevel,
    tier: BudgetTier,
    layer: Option<ReadModelLayer>,
) -> ToolDescriptor {
    ToolDescriptor {
        name,
        access: Access::Read,
        risk,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: tier,
        allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
        side_effect: SideEffect::None,
        read_model_layer: layer,
    }
}

const fn proposal(name: &'static str, tier: BudgetTier) -> ToolDescriptor {
    ToolDescriptor {
        name,
        access: Access::Propose,
        risk: RiskLevel::Propose,
        requires_confirmation: Confirmation::OneTap,
        allowed_context_tier: tier,
        allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
        side_effect: SideEffect::DeviceLocalWrite,
        read_model_layer: None,
    }
}

const DESCRIPTORS: [ToolDescriptor; 27] = [
    // ── Read tools without a read_model layer (inline computers / legacy) ─
    read_only("get_holdings", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Snapshot)),
    read_only("get_journal_entries", RiskLevel::Info, BudgetTier::Small, None),
    read_only("compute_xirr", RiskLevel::Info, BudgetTier::Standard, None),
    read_only("compute_net_worth", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Snapshot)),
    read_only("get_industry_breakdown", RiskLevel::Info, BudgetTier::Standard, Some(ReadModelLayer::Snapshot)),
    read_only("get_geo_breakdown", RiskLevel::Info, BudgetTier::Standard, Some(ReadModelLayer::Snapshot)),
    read_only("get_market_cap_breakdown", RiskLevel::Info, BudgetTier::Standard, Some(ReadModelLayer::Snapshot)),
    read_only("get_risk_alerts", RiskLevel::Suggest, BudgetTier::Standard, Some(ReadModelLayer::Snapshot)),
    // ── Snapshot-layer read models (docs/ai-architecture.md §4.3.2) ──────
    read_only("get_monthly_spend_by_category", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Snapshot)),
    read_only("get_net_worth_summary", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Snapshot)),
    read_only("get_cashflow_buckets", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Snapshot)),
    read_only("get_asset_allocation", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Snapshot)),
    // ── Analytical-layer (cloud-projected) ──────────────────────────────
    read_only("get_xirr_summary", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Analytical)),
    // ── Analytical-layer (device-sourced) ───────────────────────────────
    read_only("get_recurring_patterns", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Analytical)),
    read_only("get_anomaly_flags", RiskLevel::Suggest, BudgetTier::Small, Some(ReadModelLayer::Analytical)),
    read_only("get_refund_links", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Analytical)),
    read_only("get_transfer_links", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Analytical)),
    read_only("get_investment_performance", RiskLevel::Info, BudgetTier::Small, Some(ReadModelLayer::Analytical)),
    read_only("get_subscription_changes", RiskLevel::Suggest, BudgetTier::Small, Some(ReadModelLayer::Analytical)),
    // ── Scoped Detail (drill-down, higher tier) ─────────────────────────
    read_only("read_category_window", RiskLevel::Info, BudgetTier::Standard, Some(ReadModelLayer::ScopedDetail)),
    read_only("read_account_window", RiskLevel::Info, BudgetTier::Standard, Some(ReadModelLayer::ScopedDetail)),
    read_only("read_asset_window", RiskLevel::Info, BudgetTier::Standard, Some(ReadModelLayer::ScopedDetail)),
    // ── Propose tools (FIR-66) ──────────────────────────────────────────
    proposal("propose_trade", BudgetTier::Standard),
    proposal("propose_expense", BudgetTier::Small),
    proposal("propose_liability_payment", BudgetTier::Standard),
    proposal("propose_account_create", BudgetTier::Standard),
    proposal("propose_asset_valuation", BudgetTier::Standard),
];

/// All known tools. Used by tests to assert dispatch coverage.
pub fn descriptors() -> &'static [ToolDescriptor] {
    &DESCRIPTORS
}

/// Look up the descriptor for a tool by name.
pub fn lookup(name: &str) -> Option<&'static ToolDescriptor> {
    DESCRIPTORS.iter().find(|d| d.name == name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_proposals_are_device_local_writes() {
        for d in descriptors() {
            if matches!(d.access, Access::Propose) {
                assert_eq!(
                    d.side_effect,
                    SideEffect::DeviceLocalWrite,
                    "proposal {} must declare device_local_write side effect",
                    d.name
                );
            }
        }
    }

    #[test]
    fn read_tools_never_have_side_effects() {
        for d in descriptors() {
            if matches!(d.access, Access::Read) {
                assert_eq!(
                    d.side_effect,
                    SideEffect::None,
                    "read tool {} must have no side effect",
                    d.name
                );
            }
        }
    }

    #[test]
    fn scoped_detail_tools_require_standard_tier() {
        for d in descriptors() {
            if matches!(d.read_model_layer, Some(ReadModelLayer::ScopedDetail)) {
                assert!(
                    matches!(d.allowed_context_tier, BudgetTier::Standard | BudgetTier::Large),
                    "scoped detail tool {} must not be Small-tier (drill-down protection)",
                    d.name
                );
            }
        }
    }

    #[test]
    fn every_descriptor_admits_cloud() {
        // Until Phase 5, every tool must be dispatchable from the cloud
        // orchestrator. Device-only tools would currently never get
        // routed.
        for d in descriptors() {
            assert!(
                d.allowed_runtimes.allows_cloud(),
                "{} excludes cloud runtime — would be unreachable today",
                d.name
            );
        }
    }
}
