use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetInvestmentPerformanceTool;

pub(crate) const DESCRIPTION: &str = "返回 per-asset 当前持仓表现：market_value / cost_basis / unrealized_pnl / weight。\
                          数据来自 AI Read Model `investment_performance`（Analytical P1，device-sourced）—— \
                          端侧 holdingsSnapshotProvider 算出 per-asset 持仓后通过 \
                          ContextPack.analytical_uploads 镜像到云端表，AI 不需要再做计算。\
                          每行: asset_id / asset_currency / base_currency / market_value_base / \
                          cost_basis_base / unrealized_pnl_base / weight / holding_days? / as_of。\
                          典型问题：「我现在赚最多的是哪个标的」「AAPL 持仓现值」「未实现盈亏总计」。\
                          需要全时间窗口 XIRR 走 get_xirr_summary；自定义时间窗 XIRR 走 compute_xirr。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "base_currency": {
                "type": "string",
                "description": "可选；只看某一 base currency（一般用户的整个 portfolio 都是同一个）。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetInvestmentPerformanceTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_investment_performance",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Small,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: Some(crate::ai::policy::ReadModelLayer::Analytical),
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        impls::get_investment_performance(ctx, &input).await
    }
}
