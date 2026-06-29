use agent_core::PROTOCOL_VERSION;
use async_trait::async_trait;
use futures::stream;
use serde_json::{Value, json};

use crate::types::{
    LlmError, LlmEvent, LlmEventKind, LlmEventStream, LlmFinishReason, LlmProvider, LlmRequest,
    LlmResponse,
};
use crate::usage::estimate_usage;

#[derive(Debug, Clone)]
pub struct MockLlmProvider {
    provider: String,
    model: String,
    response_text: String,
}

impl Default for MockLlmProvider {
    fn default() -> Self {
        Self {
            provider: "mock".to_owned(),
            model: "mock-model".to_owned(),
            response_text: "mock response".to_owned(),
        }
    }
}

impl MockLlmProvider {
    pub fn new(
        provider: impl Into<String>,
        model: impl Into<String>,
        response_text: impl Into<String>,
    ) -> Self {
        Self {
            provider: provider.into(),
            model: model.into(),
            response_text: response_text.into(),
        }
    }

    fn response_for(&self, request: &LlmRequest) -> Result<LlmResponse, LlmError> {
        if request.messages.is_empty() {
            return Err(LlmError::validation(
                "llm request requires at least one message",
            ));
        }
        let content = request
            .metadata
            .get("mock_response")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .unwrap_or_else(|| self.response_text.clone());
        Ok(LlmResponse {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: self.provider.clone(),
            model: if request.model.is_empty() {
                self.model.clone()
            } else {
                request.model.clone()
            },
            usage: Some(estimate_usage(request, &content)),
            content,
            finish_reason: LlmFinishReason::Stop,
            metadata: json!({"mock": true}),
        })
    }
}

#[async_trait]
impl LlmProvider for MockLlmProvider {
    async fn complete(&self, request: LlmRequest) -> Result<LlmResponse, LlmError> {
        self.response_for(&request)
    }

    async fn stream(&self, request: LlmRequest) -> Result<LlmEventStream, LlmError> {
        let response = self.response_for(&request)?;
        let events = vec![
            Ok(LlmEvent {
                kind: LlmEventKind::Started,
                content: None,
                response: None,
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                metadata: json!({"provider": response.provider, "model": response.model}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Delta,
                content: Some(response.content.clone()),
                response: None,
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                metadata: json!({}),
            }),
            Ok(LlmEvent {
                kind: LlmEventKind::Finished,
                content: None,
                response: Some(response),
                tool_call_id: None,
                tool_name: None,
                partial_input_json: None,
                tool_input: None,
                metadata: json!({}),
            }),
        ];
        Ok(Box::pin(stream::iter(events)))
    }
}
