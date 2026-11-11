//! Device AI runtime embedding. The user owns the key: the `LlmProfile`
//! is stored on device and requests go straight to the provider. This
//! phase registers the finance read-only tools; AI writes stay behind
//! user confirmation (proposals arrive later).

use std::sync::Arc;

use agent_chat::{ChatTurnEventKind, ChatTurnRequest, ChatTurnRunner};
use agent_core::run::RunScope;
use agent_core::{
    AgentError, AgentStateStore, RunId, ToolContext, ToolError, ToolRegistry, ToolReplayPolicy,
    ToolRisk, ToolSpec,
};
use agent_llm::{
    AnthropicProvider, LlmMessage, LlmProvider, LlmRole, MockLlmProvider, OpenAiCompatibleProvider,
};
use agent_runtime::BasicAgentServices;
use agent_store::InMemoryStateStore;
use serde::{Deserialize, Serialize};
use serde_json::json;

pub const PROTOCOL_VERSION: &str = agent_core::PROTOCOL_VERSION;

/// User-owned on-device model profile.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LlmProfile {
    /// `anthropic` | `openai` | `mock`
    pub provider: String,
    /// API base URL (empty → provider default).
    pub base_url: String,
    pub model: String,
    pub api_key: String,
}

impl LlmProfile {
    pub fn is_complete(&self) -> bool {
        match self.provider.as_str() {
            "anthropic" | "openai" => !self.model.is_empty() && !self.api_key.is_empty(),
            "mock" => true,
            _ => false,
        }
    }
}

pub const TOOL_ACCOUNT_BALANCES: &str = "finance_account_balances";
pub const TOOL_RECENT_ENTRIES: &str = "finance_recent_entries";

fn read_only_spec(name: &str, description: &str, input_schema: serde_json::Value) -> ToolSpec {
    ToolSpec {
        name: name.to_owned(),
        description: description.to_owned(),
        input_schema,
        output_schema: None,
        risk: ToolRisk::ReadOnly,
        replay_policy: ToolReplayPolicy::SafeRetry,
        metadata: json!({ "domain": "finance" }),
    }
}

/// The finance read-only tool specs (attached to every chat turn).
pub fn finance_tool_specs() -> Vec<ToolSpec> {
    vec![
        read_only_spec(
            TOOL_ACCOUNT_BALANCES,
            "列出所有启用的账户及其当前余额（金额为十进制字符串）。",
            json!({
                "type": "object",
                "properties": {},
                "additionalProperties": false
            }),
        ),
        read_only_spec(
            TOOL_RECENT_ENTRIES,
            "按时间倒序返回最近的记账分录（账户名 + 金额），可用 limit 限制条数（默认 10，最大 50）。",
            json!({
                "type": "object",
                "properties": {
                    "limit": { "type": "integer", "minimum": 1, "maximum": 50 }
                },
                "additionalProperties": false
            }),
        ),
    ]
}

/// Domain tools the chat loop may call. This phase ships finance reads
/// only; every other tool name is policy-denied (no write path yet).
pub struct DomainTools {
    services: Arc<crate::state::Services>,
}

impl DomainTools {
    pub fn new(services: Arc<crate::state::Services>) -> Self {
        Self { services }
    }
}

#[async_trait::async_trait]
impl ToolRegistry for DomainTools {
    async fn list_tools(&self) -> Result<Vec<ToolSpec>, ToolError> {
        Ok(finance_tool_specs())
    }

    async fn call(
        &self,
        name: &str,
        input: serde_json::Value,
        _ctx: ToolContext,
    ) -> Result<serde_json::Value, ToolError> {
        match name {
            TOOL_ACCOUNT_BALANCES => {
                let lines = self.services.account_balance_lines().await.map_err(|e| {
                    ToolError::from_agent_error(AgentError::internal(format!(
                        "balances read failed: {e}"
                    )))
                })?;
                Ok(json!({ "accounts": lines }))
            }
            TOOL_RECENT_ENTRIES => {
                let limit = match input.get("limit") {
                    None | Some(serde_json::Value::Null) => 10,
                    Some(value) => {
                        let n = value.as_i64().ok_or_else(|| {
                            ToolError::from_agent_error(AgentError::validation(
                                "limit must be an integer",
                            ))
                        })?;
                        if !(1..=50).contains(&n) {
                            return Err(ToolError::from_agent_error(AgentError::validation(
                                "limit must be between 1 and 50",
                            )));
                        }
                        n
                    }
                };
                let lines = self.services.recent_entry_lines(limit).await.map_err(|e| {
                    ToolError::from_agent_error(AgentError::internal(format!(
                        "entries read failed: {e}"
                    )))
                })?;
                Ok(json!({ "entries": lines }))
            }
            other => Err(ToolError::policy_denied(
                format!(
                    "tool {other:?} is not registered; writes need user confirmation and are not enabled"
                ),
                json!({ "tool": other }),
            )),
        }
    }
}

fn agent_services(services: Arc<crate::state::Services>) -> Arc<BasicAgentServices> {
    Arc::new(BasicAgentServices::new(
        "naviwealth",
        RunId::new_v7(),
        None,
        RunScope::Global,
        Arc::new(DomainTools::new(services)),
        Arc::new(InMemoryStateStore::default()) as Arc<dyn AgentStateStore>,
    ))
}

fn provider(profile: &LlmProfile) -> Result<Arc<dyn LlmProvider>, String> {
    Ok(match profile.provider.as_str() {
        "anthropic" => {
            let base_url = if profile.base_url.is_empty() {
                "https://api.anthropic.com".to_owned()
            } else {
                profile.base_url.clone()
            };
            Arc::new(
                AnthropicProvider::new("anthropic", base_url, &profile.api_key, "2023-06-01")
                    .map_err(|e| e.to_string())?,
            )
        }
        "openai" => {
            let base_url = if profile.base_url.is_empty() {
                "https://api.openai.com/v1".to_owned()
            } else {
                profile.base_url.clone()
            };
            Arc::new(
                OpenAiCompatibleProvider::new("openai", base_url, &profile.api_key)
                    .map_err(|e| e.to_string())?,
            )
        }
        "mock" => Arc::new(MockLlmProvider::new(
            "mock",
            if profile.model.is_empty() {
                "mock-model"
            } else {
                profile.model.as_str()
            },
            "已连接模拟模型（开发模式）。真实模型请在设置中配置自己的 API Key。",
        )),
        other => return Err(format!("unknown provider: {other}")),
    })
}

/// Build the turn runner for a profile over the app services (the tool
/// registry reads through the same DB worker as the UI).
pub fn runner(
    services: &Arc<crate::state::Services>,
    profile: &LlmProfile,
) -> Result<ChatTurnRunner, String> {
    Ok(ChatTurnRunner::new(
        provider(profile)?,
        agent_services(services.clone()),
    ))
}

/// A one-turn request with the user's message and the read-only finance
/// tools attached (no multi-turn memory yet — session persistence arrives
/// with the agents phase).
pub fn turn_request(profile: &LlmProfile, user_text: String) -> ChatTurnRequest {
    ChatTurnRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        turn_id: None,
        surface: Some("naviwealth-client".to_owned()),
        mode: None,
        session_id: None,
        thread_id: None,
        agent_id: None,
        provider: profile.provider.clone(),
        model: profile.model.clone(),
        messages: vec![LlmMessage {
            role: LlmRole::User,
            content: json!(user_text),
            name: None,
            metadata: json!({}),
        }],
        temperature: None,
        max_output_tokens: None,
        tools: finance_tool_specs(),
        context_blocks: Vec::new(),
        metadata: json!({}),
        context_policy: Default::default(),
        max_tool_rounds: 4,
        tool_execution: Default::default(),
    }
}

/// Is this event a content delta?
pub fn delta_text(event: &agent_chat::ChatTurnEvent) -> Option<&str> {
    if event.kind == ChatTurnEventKind::Delta {
        event.content.as_deref()
    } else {
        None
    }
}

/// Error text from an Error-kind event, if any.
pub fn error_text(event: &agent_chat::ChatTurnEvent) -> Option<String> {
    if event.kind == ChatTurnEventKind::Error {
        Some(
            event
                .content
                .clone()
                .unwrap_or_else(|| "unknown error".to_owned()),
        )
    } else {
        None
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::state;
    use rust_decimal::Decimal;
    use std::str::FromStr;

    fn tool_ctx() -> ToolContext {
        ToolContext {
            run_id: RunId::new_v7(),
            agent_id: "test".to_owned(),
            scope: RunScope::Global,
            user: None,
            metadata: json!({}),
        }
    }

    /// The test-mode services (in-memory DB, mock-friendly). The process
    /// global initializes once; `enable_test_mode` must win that race, so
    /// every test calls it before `shared()`.
    fn test_services() -> Arc<state::Services> {
        state::enable_test_mode();
        state::Services::shared()
    }

    #[test]
    fn finance_specs_are_read_only_with_schemas() {
        let specs = finance_tool_specs();
        assert_eq!(specs.len(), 2);
        assert!(specs.iter().all(|s| s.risk == ToolRisk::ReadOnly));
        assert!(specs.iter().all(|s| s.input_schema.is_object()));
        assert!(
            specs.iter().any(|s| s.name == TOOL_ACCOUNT_BALANCES
                && s.replay_policy == ToolReplayPolicy::SafeRetry)
        );
        assert!(specs.iter().any(|s| s.name == TOOL_RECENT_ENTRIES));
    }

    #[tokio::test]
    async fn balances_tool_lists_created_account() {
        let services = test_services();
        let new_account = naviwealth_finance::models::NewAccount::custody(
            naviwealth_finance::models::AccountCategory::Cash,
            "工具测试现金",
            "CNY",
        );
        services
            .create_account(new_account, Some(Decimal::from_str("250.5").unwrap()))
            .await
            .expect("account created");

        let registry = DomainTools::new(services);
        let out = registry
            .call(TOOL_ACCOUNT_BALANCES, json!({}), tool_ctx())
            .await
            .expect("tool call succeeds");
        let accounts = out["accounts"].as_array().expect("accounts array");
        let hit = accounts
            .iter()
            .filter_map(|v| v.as_str())
            .find(|line| line.contains("工具测试现金"))
            .expect("created account listed");
        assert!(hit.contains("250.5 CNY"), "balance line: {hit}");
    }

    #[tokio::test]
    async fn recent_entries_tool_returns_written_entry() {
        let services = test_services();
        let new_account = naviwealth_finance::models::NewAccount::custody(
            naviwealth_finance::models::AccountCategory::Cash,
            "工具测试现金二",
            "CNY",
        );
        let account = services
            .create_account(new_account, Some(Decimal::from(100)))
            .await
            .expect("account created");
        let categories = services
            .expense_categories()
            .await
            .expect("categories seeded");
        let expense_account_id = categories.first().expect("a category exists").0.clone();
        services
            .create_expense(
                lifeos::ids::now_secs(),
                Decimal::from_str("12.5").unwrap(),
                expense_account_id,
                account.id.clone(),
                Some("工具测试".to_owned()),
                None,
            )
            .await
            .expect("expense written");

        let registry = DomainTools::new(services.clone());
        let out = registry
            .call(TOOL_RECENT_ENTRIES, json!({ "limit": 5 }), tool_ctx())
            .await
            .expect("tool call succeeds");
        let entries = out["entries"].as_array().expect("entries array");
        assert!(
            entries
                .iter()
                .filter_map(|v| v.as_str())
                .any(|line| line.contains("工具测试现金二") && line.contains("12.5")),
            "entry line lists account and amount: {entries:?}"
        );

        // Out-of-range and non-integer limits are validation errors.
        assert!(
            registry
                .call(TOOL_RECENT_ENTRIES, json!({ "limit": 0 }), tool_ctx())
                .await
                .is_err()
        );
        assert!(
            registry
                .call(TOOL_RECENT_ENTRIES, json!({ "limit": "x" }), tool_ctx())
                .await
                .is_err()
        );
    }

    #[tokio::test]
    async fn unknown_or_write_tool_is_policy_denied() {
        let services = test_services();
        let registry = DomainTools::new(services);
        let err = registry
            .call("finance_transfer_money", json!({}), tool_ctx())
            .await
            .expect_err("unregistered tool is denied");
        assert!(err.to_string().contains("not registered"));
    }
}
