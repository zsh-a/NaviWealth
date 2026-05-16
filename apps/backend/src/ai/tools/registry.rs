use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use futures_util::future::{select, Either};
use gloo_timers::future::TimeoutFuture;
use serde_json::{json, Value};

use super::super::adapters::anthropic::wire::ToolSchema;
use super::super::policy::{check_tool_call, PolicyDecision, PolicyReason, ToolDescriptor};
use super::ToolCtx;
use crate::error::AppError;

#[async_trait(?Send)]
pub trait Tool: Sync {
    fn descriptor(&self) -> ToolDescriptor;
    fn input_schema(&self) -> Value;
    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError>;
}

pub struct ToolRegistry {
    tools: HashMap<&'static str, Arc<dyn Tool>>,
}

impl ToolRegistry {
    pub fn new(tools: impl IntoIterator<Item = Arc<dyn Tool>>) -> Self {
        let tools = tools
            .into_iter()
            .map(|tool| (tool.descriptor().name, tool))
            .collect();
        Self { tools }
    }

    pub fn get(&self, name: &str) -> Option<&dyn Tool> {
        self.tools.get(name).map(Arc::as_ref)
    }

    pub fn descriptors(&self) -> Vec<ToolDescriptor> {
        let mut descriptors: Vec<ToolDescriptor> =
            self.tools.values().map(|tool| tool.descriptor()).collect();
        descriptors.sort_by(|a, b| a.name.cmp(b.name));
        descriptors
    }

    pub fn schemas(&self) -> Vec<ToolSchema> {
        let mut schemas: Vec<ToolSchema> = self
            .tools
            .values()
            .filter_map(|tool| {
                let descriptor = tool.descriptor();
                if descriptor.name == "get_journal_entries" {
                    return None;
                }
                Some(ToolSchema {
                    name: descriptor.name.into(),
                    description: description_for(descriptor.name).into(),
                    input_schema: tool.input_schema(),
                })
            })
            .collect();
        schemas.sort_by(|a, b| a.name.cmp(&b.name));
        schemas
    }

    pub async fn dispatch(&self, ctx: &ToolCtx<'_>, name: &str, input: &Value) -> Value {
        let Some(tool) = self.get(name) else {
            return policy_denied_result(name, &PolicyReason::UnknownTool);
        };
        let descriptor = tool.descriptor();
        match check_tool_call(Some(&descriptor), ctx.context_tier) {
            PolicyDecision::Allowed => {}
            PolicyDecision::Denied(reason) => {
                worker::console_log!(
                    "tool_policy denied: tool={name} reason={reason:?} client_tier={:?}",
                    ctx.context_tier
                );
                return policy_denied_result(name, &reason);
            }
        }

        let work = Box::pin(tool.invoke(ctx, input.clone()));
        let timeout = Box::pin(TimeoutFuture::new(PER_TOOL_TIMEOUT_MS));
        let result = match select(work, timeout).await {
            Either::Left((result, _)) => result,
            Either::Right(_) => {
                return json!({
                    "error":   format!("tool '{name}' timed out after {}ms", PER_TOOL_TIMEOUT_MS),
                    "code":    "tool_timeout",
                    "tool":    name,
                });
            }
        };
        match result {
            Ok(v) => v,
            Err(e) => json!({
                "error": e.to_string(),
                "code":  e.code(),
            }),
        }
    }
}

const PER_TOOL_TIMEOUT_MS: u32 = 15_000;

pub(crate) fn policy_denied_result(tool_name: &str, reason: &PolicyReason) -> Value {
    json!({
        "error": {
            "code":     "policy_denied",
            "policy":   reason.code(),
            "tool":     tool_name,
            "message":  reason.message(),
        },
        "policy_denied": true,
    })
}

fn description_for(name: &str) -> &'static str {
    match name {
        "get_holdings" => super::get_holdings::DESCRIPTION,
        "get_journal_entries" => super::get_journal_entries::DESCRIPTION,
        "compute_xirr" => super::compute_xirr::DESCRIPTION,
        "compute_net_worth" => super::compute_net_worth::DESCRIPTION,
        "get_industry_breakdown" => super::get_industry_breakdown::DESCRIPTION,
        "get_geo_breakdown" => super::get_geo_breakdown::DESCRIPTION,
        "get_market_cap_breakdown" => super::get_market_cap_breakdown::DESCRIPTION,
        "get_risk_alerts" => super::get_risk_alerts::DESCRIPTION,
        "get_monthly_spend_by_category" => super::get_monthly_spend_by_category::DESCRIPTION,
        "get_net_worth_summary" => super::get_net_worth_summary::DESCRIPTION,
        "get_cashflow_buckets" => super::get_cashflow_buckets::DESCRIPTION,
        "get_asset_allocation" => super::get_asset_allocation::DESCRIPTION,
        "get_xirr_summary" => super::get_xirr_summary::DESCRIPTION,
        "get_recurring_patterns" => super::get_recurring_patterns::DESCRIPTION,
        "get_anomaly_flags" => super::get_anomaly_flags::DESCRIPTION,
        "get_refund_links" => super::get_refund_links::DESCRIPTION,
        "get_transfer_links" => super::get_transfer_links::DESCRIPTION,
        "get_investment_performance" => super::get_investment_performance::DESCRIPTION,
        "get_subscription_changes" => super::get_subscription_changes::DESCRIPTION,
        "read_category_window" => super::read_category_window::DESCRIPTION,
        "read_account_window" => super::read_account_window::DESCRIPTION,
        "read_asset_window" => super::read_asset_window::DESCRIPTION,
        "list_payment_accounts" => super::list_payment_accounts::DESCRIPTION,
        "propose_trade" => super::propose_trade::DESCRIPTION,
        "propose_expense" => super::propose_expense::DESCRIPTION,
        "propose_liability_payment" => super::propose_liability_payment::DESCRIPTION,
        "propose_account_create" => super::propose_account_create::DESCRIPTION,
        "propose_asset_valuation" => super::propose_asset_valuation::DESCRIPTION,
        _ => "",
    }
}

#[cfg(test)]
mod tests {
    use crate::ai::context::BudgetTier;
    use crate::ai::policy::{Access, ReadModelLayer, SideEffect};

    #[test]
    fn all_proposals_are_device_local_writes() {
        for d in crate::ai::tools::registry().descriptors() {
            if matches!(d.access, Access::Propose) {
                assert_eq!(d.side_effect, SideEffect::DeviceLocalWrite);
            }
        }
    }

    #[test]
    fn read_tools_never_have_side_effects() {
        for d in crate::ai::tools::registry().descriptors() {
            if matches!(d.access, Access::Read) {
                assert_eq!(d.side_effect, SideEffect::None);
            }
        }
    }

    #[test]
    fn scoped_detail_tools_require_standard_tier() {
        for d in crate::ai::tools::registry().descriptors() {
            if matches!(d.read_model_layer, Some(ReadModelLayer::ScopedDetail)) {
                assert!(matches!(
                    d.allowed_context_tier,
                    BudgetTier::Standard | BudgetTier::Large
                ));
            }
        }
    }

    #[test]
    fn every_descriptor_admits_cloud() {
        for d in crate::ai::tools::registry().descriptors() {
            assert!(
                d.allowed_runtimes.allows_cloud(),
                "{} excludes cloud runtime",
                d.name
            );
        }
    }

    #[test]
    fn registry_lists_all_descriptors_but_hides_deprecated_schema() {
        let registry = crate::ai::tools::registry();
        assert_eq!(registry.descriptors().len(), 28);
        assert_eq!(registry.schemas().len(), 27);
        assert!(registry.get("get_journal_entries").is_some());
        assert!(!registry
            .schemas()
            .iter()
            .any(|schema| schema.name == "get_journal_entries"));
    }
}
