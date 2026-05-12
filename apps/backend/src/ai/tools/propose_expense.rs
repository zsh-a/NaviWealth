use async_trait::async_trait;
use serde_json::{json, Value};

use super::registry::Tool;
use super::ToolCtx;
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::ai::{context::BudgetTier, context::RiskLevel, proposals};
use crate::error::AppError;

pub struct ProposeExpenseTool;

pub(crate) const DESCRIPTION: &str = "提议一笔日常消费 / 支出。返回 plan，前端确认后才写入 journal_entries / postings。\
                          类目从内置 9 类里选：餐饮 / 交通 / 房租 / 娱乐 / 医疗 / 教育 / 购物 / 旅行 / 其它。\
                          类目不在闭集时工具会返回 candidates，请你让用户选一个再重新调用。";

pub fn schema() -> crate::ai::anthropic::ToolSchema {
    crate::ai::anthropic::ToolSchema {
        name: "propose_expense".into(),
        description: DESCRIPTION.into(),
        input_schema: input_schema(),
    }
}

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["amount"],
        "properties": {
            "amount":       { "type": "number", "minimum": 0 },
            "category":     { "type": "string", "description": "中文 label 或 slug，如 餐饮 / food" },
            "account_id":   { "type": "string" },
            "account_name": { "type": "string" },
            "currency":     { "type": "string" },
            "date":         { "type": "string", "description": "ISO-8601" },
            "note":         { "type": "string" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ProposeExpenseTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "propose_expense",
            access: Access::Propose,
            risk: RiskLevel::Propose,
            requires_confirmation: Confirmation::OneTap,
            allowed_context_tier: BudgetTier::Small,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::DeviceLocalWrite,
            read_model_layer: None,
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        proposals::propose_expense(ctx, &input).await
    }
}
