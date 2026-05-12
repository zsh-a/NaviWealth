use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct ReadCategoryWindowTool;

pub(crate) const DESCRIPTION: &str =
    "Scoped Detail 工具：返回某一类目在指定时间窗口内的交易明细（drill-down）。\
                          只在用户问「为什么 / 哪些」需要例证时调用 —— 默认应当先用 \
                          get_monthly_spend_by_category 的聚合结果回答。\
                          硬限额：窗口 ≤ 31 天，limit ≤ 50。明细字段已脱敏：\
                          merchant_hashed（同用户内稳定，跨用户不可逆）+ account_kind（不返名字）。\
                          purpose 必填，用于 AiTrace 审计。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["category", "from", "to", "purpose"],
        "properties": {
            "category": {
                "type": "string",
                "description": "类目（如 food / transport / shopping）"
            },
            "from": {
                "type": "string",
                "description": "ISO 日期或时间，包含；窗口起点"
            },
            "to": {
                "type": "string",
                "description": "ISO 日期或时间，不包含；窗口终点。to - from ≤ 31 天"
            },
            "purpose": {
                "type": "string",
                "enum": [
                    "drill_down_expense", "drill_down_investment",
                    "refund_matching", "anomaly_explain",
                    "recurring_detect", "other"
                ],
                "description": "调用动机；写入 AiTrace 审计"
            },
            "limit": {
                "type": "integer",
                "minimum": 1,
                "maximum": 50,
                "default": 20
            },
            "merchant_substring": {
                "type": "string",
                "description": "可选；按 note 的子串过滤（hash 后明细只能数 distinct 不能搜，所以匹配在原文上做）"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ReadCategoryWindowTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "read_category_window",
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
        impls::read_category_window(ctx, &input).await
    }
}
