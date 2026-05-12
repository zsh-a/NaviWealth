//! Per-turn agent session state.

use chrono::Utc;
use serde_json::Value;

use crate::ai::adapters::anthropic::wire::ChatMessage;
use crate::ai::context::BudgetTier;
use crate::ai::guardrails::SYSTEM_PROMPT;

#[derive(Debug, Clone)]
pub struct Session {
    pub messages: Vec<ChatMessage>,
    pub portfolio_snapshot: Option<Value>,
    pub context_tier: Option<BudgetTier>,
    pub system_appendix: Option<String>,
    pub rounds_used: u8,
}

impl Session {
    pub fn new(
        messages: Vec<ChatMessage>,
        portfolio_snapshot: Option<Value>,
        context_tier: Option<BudgetTier>,
        system_appendix: Option<String>,
    ) -> Self {
        Self {
            messages,
            portfolio_snapshot,
            context_tier,
            system_appendix,
            rounds_used: 0,
        }
    }

    pub fn system_prompt(&self) -> String {
        let mut system = format!(
            "{SYSTEM_PROMPT}\n\n当前服务器时间: {}",
            Utc::now().to_rfc3339()
        );
        if let Some(appendix) = &self.system_appendix {
            system.push_str(appendix);
        }
        system
    }
}
