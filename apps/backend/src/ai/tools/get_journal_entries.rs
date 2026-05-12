use async_trait::async_trait;
use serde_json::{json, Value};

use super::impls;
use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::error::AppError;

pub struct GetJournalEntriesTool;

pub(crate) const DESCRIPTION: &str = "已废弃的兼容工具：按时间 / 币种 / 账户过滤 journal_entries，返回最新交易与 postings。新对话不再向 LLM 暴露。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "unit": { "type": "string", "description": "可选；按 posting unit / currency 过滤" },
            "account_id": { "type": "string", "description": "可选；按账户过滤" },
            "from": { "type": "string", "description": "ISO-8601 lower bound" },
            "to": { "type": "string", "description": "ISO-8601 upper bound" },
            "limit": { "type": "integer", "minimum": 1, "maximum": 200, "default": 50 }
        }
    })
}

#[async_trait(?Send)]
impl Tool for GetJournalEntriesTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "get_journal_entries",
            access: Access::Read,
            risk: RiskLevel::Info,
            requires_confirmation: Confirmation::None,
            allowed_context_tier: BudgetTier::Small,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::None,
            read_model_layer: None,
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        impls::get_journal_entries(ctx, &input).await
    }
}
