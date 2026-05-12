//! Anthropic-compatible wire types.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Default model id when neither env vars nor the client override it.
pub const DEFAULT_MODEL: &str = "deepseek-ai/DeepSeek-V4-Flash";

/// Top-level message in the Anthropic Messages API. Roles are `user` or
/// `assistant`; system instructions ride on the request's `system` field.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    /// Either a plain string or an array of typed blocks (`text`, `tool_use`,
    /// `tool_result`).
    pub content: Value,
}

/// Tool schema as Anthropic expects it.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolSchema {
    pub name: String,
    pub description: String,
    pub input_schema: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct AnthropicRequest<'a> {
    pub model: &'a str,
    pub max_tokens: u32,
    pub system: &'a str,
    pub messages: &'a [ChatMessage],
    pub tools: &'a [ToolSchema],
    pub stream: bool,
}

/// Legacy non-streaming response shape kept for compatibility while
/// `routes::ai` still uses `ai::anthropic`.
#[derive(Debug, Clone, Deserialize)]
pub struct AnthropicMessage {
    pub content: Vec<Value>,
    pub stop_reason: Option<String>,
}
