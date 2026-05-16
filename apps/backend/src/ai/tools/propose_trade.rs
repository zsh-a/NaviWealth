use async_trait::async_trait;
use serde_json::{json, Value};

use super::registry::Tool;
use super::ToolCtx;
use crate::ai::context::{BudgetTier, RiskLevel};
use crate::ai::policy::{Access, AllowedRuntimes, Confirmation, SideEffect, ToolDescriptor};
use crate::ai::proposals;
use crate::error::AppError;

pub struct ProposeTradeTool;

pub(crate) const DESCRIPTION: &str = "提议一笔证券 / 加密交易（买入 / 卖出 / 转入 / 转出 / 估值调整）。\
                          ⚠ 这是只提议、不落库的工具：返回一个 plan，前端会让用户在确认 UI 上点确认后才走 \
                          TradeEntryService.buildPlan + JournalEntryRepository。\
                          - asset 通过 asset_id 或 asset_symbol / asset_name 任一指认；多个匹配会返回 candidates。\
                          - account 同理。\
                          - 缺少字段时优先反问用户，不要硬编值。\
                          - 日期相对值（昨天 / 上周三）请你解析为 ISO-8601 后传入。";

fn input_schema() -> Value {
    json!({
        "type": "object",
        "required": ["type", "quantity"],
        "properties": {
            "type": {
                "type": "string",
                "enum": ["buy", "sell", "transferIn", "transferOut", "valuationAdjust"]
            },
            "asset_id":     { "type": "string" },
            "asset_symbol": { "type": "string", "description": "如 AAPL / 600519 / BTC" },
            "asset_name":   { "type": "string", "description": "如 苹果 / 茅台" },
            "account_id":   { "type": "string" },
            "account_name": { "type": "string" },
            "quantity":     { "type": "number", "minimum": 0 },
            "price":        { "type": "number", "minimum": 0, "description": "成交价。留空时前端会从行情回填，并 warn 用户。" },
            "fee":          { "type": "number", "minimum": 0, "default": 0 },
            "tax":          { "type": "number", "minimum": 0, "default": 0 },
            "currency":     { "type": "string", "description": "ISO 4217；留空时取账户币种" },
            "trade_date":   { "type": "string", "description": "ISO-8601；相对日期请你先解析" },
            "note":         { "type": "string" }
        }
    })
}

#[async_trait(?Send)]
impl Tool for ProposeTradeTool {
    fn descriptor(&self) -> ToolDescriptor {
        ToolDescriptor {
            name: "propose_trade",
            access: Access::Propose,
            risk: RiskLevel::Propose,
            requires_confirmation: Confirmation::OneTap,
            allowed_context_tier: BudgetTier::Standard,
            allowed_runtimes: AllowedRuntimes::CLOUD_ONLY,
            side_effect: SideEffect::DeviceLocalWrite,
            read_model_layer: None,
        }
    }

    fn input_schema(&self) -> Value {
        input_schema()
    }

    async fn invoke(&self, ctx: &ToolCtx<'_>, input: Value) -> Result<Value, AppError> {
        proposals::propose_trade(ctx, &input).await
    }
}
