//! OpenAI adapter placeholder.

use async_trait::async_trait;
use futures_util::stream::BoxStream;

use crate::ai::runtime::{AgentEvent, AgentRequest, LlmAdapter};
use crate::error::AppError;

#[derive(Debug, Clone, Default)]
pub struct OpenAiAdapter;

#[async_trait(?Send)]
impl LlmAdapter for OpenAiAdapter {
    async fn stream(&self, _req: AgentRequest<'_>) -> Result<BoxStream<'_, AgentEvent>, AppError> {
        // TODO(FIR-156): implement with the OpenAI Responses API and native tools.
        Err(AppError::Internal(
            "OpenAI adapter is not implemented yet".into(),
        ))
    }
}
