//! Isolates the agent-runtime embedding from the UI: does the mock
//! provider stream a full turn on the app-level tokio runtime?

use agent_chat::{ChatTurnEventKind, ChatTurnRunner};
use agent_core::run::RunScope;
use agent_core::stores::AgentStateStore;
use agent_core::{RunId, ToolContext, ToolError, ToolRegistry};
use agent_llm::MockLlmProvider;
use agent_runtime::BasicAgentServices;
use agent_store::InMemoryStateStore;
use futures::StreamExt;
use std::sync::Arc;

struct NoTools;

#[async_trait::async_trait]
impl ToolRegistry for NoTools {
    async fn list_tools(&self) -> Result<Vec<agent_core::ToolSpec>, ToolError> {
        Ok(Vec::new())
    }

    async fn call(
        &self,
        _name: &str,
        _input: serde_json::Value,
        _ctx: ToolContext,
    ) -> Result<serde_json::Value, ToolError> {
        unreachable!()
    }
}

#[tokio::test]
async fn mock_provider_streams_a_full_turn() {
    let services = Arc::new(BasicAgentServices::new(
        "naviwealth",
        RunId::new_v7(),
        None,
        RunScope::Global,
        Arc::new(NoTools),
        Arc::new(InMemoryStateStore::default()) as Arc<dyn AgentStateStore>,
    ));
    let runner = ChatTurnRunner::new(
        Arc::new(MockLlmProvider::new(
            "mock",
            "mock-model",
            "mock reply text",
        )),
        services,
    );
    let request = agent_chat::ChatTurnRequest {
        protocol_version: agent_core::PROTOCOL_VERSION.to_owned(),
        turn_id: None,
        surface: None,
        mode: None,
        session_id: None,
        thread_id: None,
        agent_id: None,
        provider: "mock".to_owned(),
        model: "mock-model".to_owned(),
        messages: vec![agent_llm::LlmMessage {
            role: agent_llm::LlmRole::User,
            content: serde_json::json!("hi"),
            name: None,
            metadata: serde_json::json!({}),
        }],
        temperature: None,
        max_output_tokens: None,
        tools: Vec::new(),
        context_blocks: Vec::new(),
        metadata: serde_json::json!({}),
        context_policy: Default::default(),
        max_tool_rounds: 4,
        tool_execution: Default::default(),
    };

    let mut stream = runner.stream(request);
    let mut deltas = 0;
    let mut saw_done = false;
    let mut first_error: Option<String> = None;
    while let Some(event) = stream.next().await {
        match event {
            Ok(event) => {
                if event.kind == ChatTurnEventKind::Delta {
                    deltas += 1;
                }
                if event.kind == ChatTurnEventKind::Done {
                    saw_done = true;
                    break;
                }
                if event.kind == ChatTurnEventKind::Error {
                    first_error = event.content.clone();
                    break;
                }
            }
            Err(e) => {
                first_error = Some(e.to_string());
                break;
            }
        }
    }
    assert!(saw_done, "turn never finished: {first_error:?}");
    assert!(deltas > 0, "no deltas streamed");
}
