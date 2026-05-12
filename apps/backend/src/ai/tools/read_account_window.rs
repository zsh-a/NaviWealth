use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct ReadAccountWindowTool;

pub(crate) const DESCRIPTION: &str = "Scoped Detail：返回某账户在指定窗口内的交易明细（drill-down）。\
                          只在用户问「这张卡上花了哪些」需要例证时调用；首选 Snapshot 工具回答聚合性问题。\
                          硬限额：窗口 ≤ 31 天，limit ≤ 50。明细字段已脱敏：merchant_hashed + category。\
                          purpose 必填，用于 AiTrace 审计。可选 category / min_amount_minor / max_amount_minor。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["account_id", "from", "to", "purpose"],
        "properties": {
            "account_id": { "type": "string" },
            "from":       { "type": "string", "description": "ISO 起点（包含）" },
            "to":         { "type": "string", "description": "ISO 终点（不包含），to - from ≤ 31 天" },
            "purpose": {
                "type": "string",
                "enum": [
                    "drill_down_expense", "drill_down_investment",
                    "refund_matching", "anomaly_explain",
                    "recurring_detect", "other"
                ]
            },
            "limit":            { "type": "integer", "minimum": 1, "maximum": 50, "default": 20 },
            "category":         { "type": "string", "description": "可选；按类目二次过滤" },
            "min_amount_minor": { "type": "integer", "description": "可选；最小 signed minor units" },
            "max_amount_minor": { "type": "integer", "description": "可选；最大 signed minor units" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ReadAccountWindowTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "read_account_window",
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
        impls::read_account_window(ctx, &input).await
    }
}
