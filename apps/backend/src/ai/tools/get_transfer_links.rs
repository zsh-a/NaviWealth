use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetTransferLinksTool;

pub(crate) const DESCRIPTION: &str = "返回端侧 transferMatcher 检测到的「账户 A → 账户 B」转账配对。\
                          数据来自 AI Read Model `transfer_links`（Analytical P1，device-sourced）。\
                          payload 含 from_txn_id / to_txn_id / amount_minor / currency。\
                          典型问题：「最近转了几笔」「哪些钱在不同账户之间挪动」。\
                          这些配对是端侧启发式匹配（同币种 + ±2 天窗口 + 50 minor 容差）。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "currency": { "type": "string", "description": "可选；只看某一币种。" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetTransferLinksTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_transfer_links",
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
        impls::get_transfer_links(ctx, &input).await
    }
}
