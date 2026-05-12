//! Pure decision function for tool dispatch.
//!
//! The dispatcher hands in the looked-up [`ToolDescriptor`] (or
//! `None` for unknown tools) plus the client's reported
//! [`BudgetTier`] (from the [`ContextPack`], when present). The
//! function decides; the dispatcher chooses what to do with the
//! decision (Phase 2-C: log; Phase 3: deny).

use crate::ai::context::BudgetTier;

use super::tool_policy::{Access, ToolDescriptor};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PolicyDecision {
    Allowed,
    Denied(PolicyReason),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PolicyReason {
    UnknownTool,
    ContextTierTooLow {
        client: BudgetTier,
        required: BudgetTier,
    },
    /// External-side-effect tools always need an explicit user
    /// confirmation; the planner cannot auto-dispatch them.
    ExternalWriteRequiresConsent,
}

impl PolicyReason {
    /// Short, stable identifier the model can branch on without parsing
    /// the human-readable message.
    pub fn code(&self) -> &'static str {
        match self {
            PolicyReason::UnknownTool => "unknown_tool",
            PolicyReason::ContextTierTooLow { .. } => "context_tier_too_low",
            PolicyReason::ExternalWriteRequiresConsent => "external_write_requires_consent",
        }
    }

    /// Human-readable explanation. Goes in the synthesized tool_result
    /// body so the LLM can read it (and so traces are debuggable).
    pub fn message(&self) -> String {
        match self {
            PolicyReason::UnknownTool => {
                "tool is not registered in the descriptor table".into()
            }
            PolicyReason::ContextTierTooLow { client, required } => {
                format!(
                    "context tier {client:?} below required {required:?} — caller must \
                     escalate the ContextPack tier before invoking this tool"
                )
            }
            PolicyReason::ExternalWriteRequiresConsent => {
                "external-write tools require explicit user confirmation; planner cannot \
                 auto-dispatch"
                    .into()
            }
        }
    }
}

pub fn check_tool_call(
    descriptor: Option<&ToolDescriptor>,
    client_tier: Option<BudgetTier>,
) -> PolicyDecision {
    let Some(d) = descriptor else {
        return PolicyDecision::Denied(PolicyReason::UnknownTool);
    };
    if d.access == Access::ExternalWrite {
        return PolicyDecision::Denied(PolicyReason::ExternalWriteRequiresConsent);
    }
    if let Some(client) = client_tier {
        if !tier_at_least(client, d.allowed_context_tier) {
            return PolicyDecision::Denied(PolicyReason::ContextTierTooLow {
                client,
                required: d.allowed_context_tier,
            });
        }
    }
    PolicyDecision::Allowed
}

fn tier_at_least(client: BudgetTier, required: BudgetTier) -> bool {
    rank(client) >= rank(required)
}

fn rank(t: BudgetTier) -> u8 {
    match t {
        BudgetTier::Small => 0,
        BudgetTier::Standard => 1,
        BudgetTier::Large => 2,
    }
}

#[cfg(test)]
mod tests {
    use super::super::tool_policy::{lookup, Access, Confirmation, ToolDescriptor};
    use super::*;
    use crate::ai::context::RiskLevel;

    const READ_STD: ToolDescriptor = ToolDescriptor {
        name: "test_read",
        access: Access::Read,
        risk: RiskLevel::Info,
        requires_confirmation: Confirmation::None,
        allowed_context_tier: BudgetTier::Standard,
        allowed_runtimes: crate::ai::policy::tool_policy::AllowedRuntimes::CLOUD_ONLY,
        side_effect: crate::ai::policy::tool_policy::SideEffect::None,
        read_model_layer: None,
    };

    const PROPOSE_LARGE: ToolDescriptor = ToolDescriptor {
        name: "test_propose",
        access: Access::Propose,
        risk: RiskLevel::Propose,
        requires_confirmation: Confirmation::OneTap,
        allowed_context_tier: BudgetTier::Large,
        allowed_runtimes: crate::ai::policy::tool_policy::AllowedRuntimes::CLOUD_ONLY,
        side_effect: crate::ai::policy::tool_policy::SideEffect::DeviceLocalWrite,
        read_model_layer: None,
    };

    const EXTERNAL: ToolDescriptor = ToolDescriptor {
        name: "test_external",
        access: Access::ExternalWrite,
        risk: RiskLevel::Commit,
        requires_confirmation: Confirmation::Typed,
        allowed_context_tier: BudgetTier::Standard,
        allowed_runtimes: crate::ai::policy::tool_policy::AllowedRuntimes::CLOUD_ONLY,
        side_effect: crate::ai::policy::tool_policy::SideEffect::ExternalCall,
        read_model_layer: None,
    };

    #[test]
    fn unknown_tool_is_denied() {
        let decision = check_tool_call(None, Some(BudgetTier::Large));
        assert_eq!(decision, PolicyDecision::Denied(PolicyReason::UnknownTool));
    }

    #[test]
    fn external_write_is_always_denied() {
        let decision = check_tool_call(Some(&EXTERNAL), Some(BudgetTier::Large));
        assert_eq!(
            decision,
            PolicyDecision::Denied(PolicyReason::ExternalWriteRequiresConsent)
        );
    }

    #[test]
    fn matching_tier_is_allowed() {
        let decision = check_tool_call(Some(&READ_STD), Some(BudgetTier::Standard));
        assert_eq!(decision, PolicyDecision::Allowed);
    }

    #[test]
    fn higher_tier_satisfies_a_lower_requirement() {
        let decision = check_tool_call(Some(&READ_STD), Some(BudgetTier::Large));
        assert_eq!(decision, PolicyDecision::Allowed);
    }

    #[test]
    fn lower_tier_is_denied_with_specifics() {
        let decision = check_tool_call(Some(&PROPOSE_LARGE), Some(BudgetTier::Standard));
        assert_eq!(
            decision,
            PolicyDecision::Denied(PolicyReason::ContextTierTooLow {
                client: BudgetTier::Standard,
                required: BudgetTier::Large,
            })
        );
    }

    #[test]
    fn missing_client_tier_admits_known_tool() {
        // Legacy clients pre-Phase-2-A don't send a ContextPack. The
        // policy is permissive for them: descriptor is consulted only
        // for the access class (which gates external_write).
        let decision = check_tool_call(Some(&READ_STD), None);
        assert_eq!(decision, PolicyDecision::Allowed);
    }

    #[test]
    fn every_dispatch_target_has_a_descriptor() {
        // Sanity: the dispatch table in `tools.rs` and the descriptor
        // table here must move in lockstep. If a future commit adds a
        // tool to dispatch without registering metadata, this test
        // tells us where to look.
        for name in &[
            "get_holdings",
            "get_journal_entries",
            "compute_xirr",
            "compute_net_worth",
            "get_industry_breakdown",
            "get_geo_breakdown",
            "get_market_cap_breakdown",
            "get_risk_alerts",
            "get_monthly_spend_by_category",
            "get_net_worth_summary",
            "get_cashflow_buckets",
            "get_asset_allocation",
            "get_recurring_patterns",
            "get_anomaly_flags",
            "get_refund_links",
            "get_transfer_links",
            "get_investment_performance",
            "get_subscription_changes",
            "get_xirr_summary",
            "read_category_window",
            "read_account_window",
            "read_asset_window",
            "propose_trade",
            "propose_expense",
            "propose_liability_payment",
            "propose_account_create",
            "propose_asset_valuation",
        ] {
            assert!(lookup(name).is_some(), "no descriptor for {name}");
        }
    }
}
