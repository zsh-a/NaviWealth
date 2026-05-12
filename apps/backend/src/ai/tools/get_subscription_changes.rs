use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetSubscriptionChangesTool;

pub(crate) const DESCRIPTION: &str = "返回端侧 detectSubscriptionChanges 检测到的订阅价格变动\
                          （早窗口 median vs 晚窗口 median 差值超 10% 且 >=$1 等价）。\
                          数据来自 AI Read Model `subscription_changes`（Analytical P1，device-sourced）。\
                          payload 含 merchant_key / cadence / currency / prev_amount_minor / \
                          new_amount_minor / delta_ratio / since。\
                          典型问题：「哪些订阅最近涨价了」「Netflix 涨了多少」。\
                          注意：检测窗口仅限于本次 chat 上报的 expenses，未持久化跨会话状态。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "currency": { "type": "string", "description": "可选；只看某一币种。" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetSubscriptionChangesTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_subscription_changes",
            access: Access::Read,
            risk: RiskLevel::Suggest,
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
        impls::get_subscription_changes(ctx, &input).await
    }
}
