use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetMonthlySpendByCategoryTool;

pub(crate) const DESCRIPTION: &str = "返回某月（YYYY-MM）按类目 × 币种聚合的支出。\
                          数据来自 AI Read Model（`monthly_spend_by_category`，Snapshot 层 P0），\
                          首次调用会同步刷新；后续命中缓存。\
                          类目在内置 9 类（food/transport/housing/entertainment/medical/education/shopping/travel/other）。\
                          外部导入数据可能落到自定义 category 字符串。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["year_month"],
        "properties": {
            "year_month": {
                "type": "string",
                "description": "YYYY-MM，例如 '2026-04'",
                "pattern": "^[0-9]{4}-[0-9]{2}$"
            },
            "category": {
                "type": "string",
                "description": "可选；只看某一类目的数字。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetMonthlySpendByCategoryTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_monthly_spend_by_category",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Small,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: Some(crate::ai::policy::ReadModelLayer::Snapshot),
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        impls::get_monthly_spend_by_category(ctx, &input).await
    }
}
