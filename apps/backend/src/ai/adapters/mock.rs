//! Scripted adapter for runtime tests.

use async_trait::async_trait;
use futures_util::stream::{self, BoxStream, StreamExt};

use crate::ai::runtime::{AgentEvent, AgentRequest, LlmAdapter};
use crate::error::AppError;

#[derive(Debug, Clone, Default)]
pub struct MockAdapter {
    events: Vec<AgentEvent>,
}

impl MockAdapter {
    pub fn new(events: Vec<AgentEvent>) -> Self {
        Self { events }
    }
}

#[async_trait(?Send)]
impl LlmAdapter for MockAdapter {
    async fn stream(&self, _req: AgentRequest<'_>) -> Result<BoxStream<'_, AgentEvent>, AppError> {
        Ok(stream::iter(self.events.clone()).boxed())
    }
}
