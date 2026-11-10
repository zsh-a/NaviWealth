//! Device AI runtime embedding. The user owns the key: the `LlmProfile`
//! is stored on device and requests go straight to the provider. AI
//! writes stay behind user confirmation (proposals arrive in phase 4).

use std::sync::Arc;

use agent_chat::{ChatTurnEventKind, ChatTurnRequest, ChatTurnRunner};
use agent_core::run::RunScope;
use agent_core::{AgentStateStore, RunId, ToolContext, ToolError, ToolRegistry, ToolSpec};
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

/// No domain tools yet — they arrive with the domain-tool phase. The
/// registry exists so the chat loop is wired exactly as it will run in
/// production.
pub struct NoTools;

#[async_trait::async_trait]
impl ToolRegistry for NoTools {
    async fn list_tools(&self) -> Result<Vec<ToolSpec>, ToolError> {
        Ok(Vec::new())
    }

    async fn call(
        &self,
        name: &str,
        _input: serde_json::Value,
        _ctx: ToolContext,
    ) -> Result<serde_json::Value, ToolError> {
        Err(ToolError::policy_denied(
            format!("tool {name:?} is not registered in this build"),
            json!({ "tool": name }),
        ))
    }
}

fn services() -> Arc<BasicAgentServices> {
    Arc::new(BasicAgentServices::new(
        "naviwealth",
        RunId::new_v7(),
        None,
        RunScope::Global,
        Arc::new(NoTools),
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

/// Build the turn runner for a profile.
pub fn runner(profile: &LlmProfile) -> Result<ChatTurnRunner, String> {
    Ok(ChatTurnRunner::new(provider(profile)?, services()))
}

/// A one-turn request with the user's message (no multi-turn memory yet —
/// session persistence arrives with the agents phase).
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
        tools: Vec::new(),
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
