use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetRecurringPatternsTool;

pub(crate) const DESCRIPTION: &str = "返回端侧 detector 检测到的周期性支出（月度/周度订阅、定期账单等）。\
                          数据来自 AI Read Model `recurring_patterns`（Analytical 层 P1）—— \
                          这是 device-sourced read model：端侧 recurring_detector 跑启发式产生，\
                          通过 ContextPack.analytical_uploads 镜像到云端表（避免 Dart/Rust 双份漂移）。\
                          典型问题：「我有哪些订阅」「每月定期支出多少」「哪些订阅最近涨价了」（最后这个需配合 subscription_changes，待落）。\
                          可选 currency / cadence 过滤。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "currency": {
                "type": "string",
                "description": "可选；只看某一币种。"
            },
            "cadence": {
                "type": "string",
                "enum": ["weekly", "monthly"],
                "description": "可选；只看某一周期。"
            }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetRecurringPatternsTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_recurring_patterns",
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
        impls::get_recurring_patterns(ctx, &input).await
    }
}
