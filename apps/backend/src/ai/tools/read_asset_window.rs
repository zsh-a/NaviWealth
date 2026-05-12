use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct ReadAssetWindowTool;

pub(crate) const DESCRIPTION: &str = "Scoped Detail：返回某资产在指定窗口内的交易腿（数量变动 + 单价）。\
                          适合「AAPL 这个月有几次买卖」「这只 ETF 最近调仓」之类的 drill-down。\
                          硬限额：窗口 ≤ 31 天，limit ≤ 50。返回 qty_delta（signed）+ side (buy/sell) + cost_per_unit + currency；\
                          天然脱敏（不含 merchant 信息）。purpose 必填。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["asset_id", "from", "to", "purpose"],
        "properties": {
            "asset_id": { "type": "string" },
            "from":     { "type": "string" },
            "to":       { "type": "string" },
            "purpose": {
                "type": "string",
                "enum": [
                    "drill_down_expense", "drill_down_investment",
                    "refund_matching", "anomaly_explain",
                    "recurring_detect", "other"
                ]
            },
            "limit": { "type": "integer", "minimum": 1, "maximum": 50, "default": 20 }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ReadAssetWindowTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "read_asset_window",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Standard,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: Some(crate::ai::policy::ReadModelLayer::ScopedDetail),
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        impls::read_asset_window(ctx, &input).await
    }
}
