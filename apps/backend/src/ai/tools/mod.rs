use serde_json::Value;
use worker::D1Database;

use super::context::BudgetTier;

pub mod compute_net_worth;
pub mod compute_xirr;
pub mod get_anomaly_flags;
pub mod get_asset_allocation;
pub mod get_cashflow_buckets;
pub mod get_geo_breakdown;
pub mod get_holdings;
pub mod get_industry_breakdown;
pub mod get_investment_performance;
pub mod get_journal_entries;
pub mod get_market_cap_breakdown;
pub mod get_monthly_spend_by_category;
pub mod get_net_worth_summary;
pub mod get_recurring_patterns;
pub mod get_refund_links;
pub mod get_risk_alerts;
pub mod get_subscription_changes;
pub mod get_transfer_links;
pub mod get_xirr_summary;
pub(crate) mod impls;
pub mod propose_account_create;
pub mod propose_asset_valuation;
pub mod propose_expense;
pub mod propose_liability_payment;
pub mod propose_trade;
pub mod read_account_window;
pub mod read_asset_window;
pub mod read_category_window;
pub mod registry;
pub mod xirr;

pub struct ToolCtx<'a> {
    pub user_id: &'a str,
    pub db: &'a D1Database,
    pub portfolio_snapshot: Option<&'a Value>,
    pub context_tier: Option<BudgetTier>,
}

pub fn registry() -> registry::ToolRegistry {
    registry::ToolRegistry::new([
        std::sync::Arc::new(get_holdings::GetHoldingsTool) as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_journal_entries::GetJournalEntriesTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(compute_xirr::ComputeXirrTool) as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(compute_net_worth::ComputeNetWorthTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_industry_breakdown::GetIndustryBreakdownTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_geo_breakdown::GetGeoBreakdownTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_market_cap_breakdown::GetMarketCapBreakdownTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_risk_alerts::GetRiskAlertsTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_monthly_spend_by_category::GetMonthlySpendByCategoryTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_net_worth_summary::GetNetWorthSummaryTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_cashflow_buckets::GetCashflowBucketsTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_asset_allocation::GetAssetAllocationTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_xirr_summary::GetXirrSummaryTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_recurring_patterns::GetRecurringPatternsTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_anomaly_flags::GetAnomalyFlagsTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_refund_links::GetRefundLinksTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_transfer_links::GetTransferLinksTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_investment_performance::GetInvestmentPerformanceTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(get_subscription_changes::GetSubscriptionChangesTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(read_category_window::ReadCategoryWindowTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(read_account_window::ReadAccountWindowTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(read_asset_window::ReadAssetWindowTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_trade::ProposeTradeTool) as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_expense::ProposeExpenseTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_liability_payment::ProposeLiabilityPaymentTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_account_create::ProposeAccountCreateTool)
            as std::sync::Arc<dyn registry::Tool>,
        std::sync::Arc::new(propose_asset_valuation::ProposeAssetValuationTool)
            as std::sync::Arc<dyn registry::Tool>,
    ])
}
