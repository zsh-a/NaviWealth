//! Provider-neutral LLM adapter contract.

use async_trait::async_trait;
use futures_util::stream::BoxStream;
use serde_json::Value;

use crate::ai::runtime::AgentEvent;
use crate::error::AppError;

#[derive(Debug, Clone, Copy)]
pub struct AgentRequest<'a> {
    pub model: &'a str,
    pub max_tokens: u32,
    pub system: &'a str,
    pub messages: &'a [Value],
    pub tools: &'a [Value],
}

#[async_trait(?Send)]
pub trait LlmAdapter {
    async fn stream(&self, req: AgentRequest<'_>) -> Result<BoxStream<'_, AgentEvent>, AppError>;
}
