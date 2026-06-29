use agent_core::{PROTOCOL_VERSION, ToolSpec};
use axum::{Json, Router, routing::post};
use futures::StreamExt;
use serde_json::{Value, json};
use tokio::net::TcpListener;

use super::*;

#[tokio::test]
async fn mock_provider_completes_and_streams() {
    let provider = MockLlmProvider::new("mock", "mock-fast", "hello");
    let request = LlmRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        provider: "mock".to_owned(),
        model: "mock-fast".to_owned(),
        messages: vec![user_message("ping")],
        temperature: None,
        max_output_tokens: Some(16),
        tools: vec![],
        metadata: json!({}),
    };

    let response = provider
        .complete(request.clone())
        .await
        .expect("mock completes");
    assert_eq!(response.content, "hello");
    assert_eq!(response.finish_reason, LlmFinishReason::Stop);

    let events = provider
        .stream(request)
        .await
        .expect("mock streams")
        .collect::<Vec<_>>()
        .await;
    assert_eq!(events.len(), 3);
    assert!(matches!(
        events[2].as_ref().expect("event ok").kind,
        LlmEventKind::Finished
    ));
}

#[tokio::test]
async fn openai_compatible_provider_completes_against_chat_api() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/chat/completions",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["model"], "gpt-test");
            assert_eq!(body["messages"][0]["role"], "user");
            Json(json!({
                "choices": [{
                    "message": {"content": "provider answer"},
                    "finish_reason": "stop"
                }],
                "usage": {
                    "prompt_tokens": 3,
                    "completion_tokens": 2,
                    "total_tokens": 5
                }
            }))
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider =
        OpenAiCompatibleProvider::new("openai-compatible", format!("http://{addr}"), "test-key")
            .expect("provider builds");
    let response = provider
        .complete(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "openai-compatible".to_owned(),
            model: "gpt-test".to_owned(),
            messages: vec![user_message("ping")],
            temperature: Some(0.2),
            max_output_tokens: Some(32),
            tools: vec![],
            metadata: json!({}),
        })
        .await
        .expect("provider completes");

    assert_eq!(response.provider, "openai-compatible");
    assert_eq!(response.model, "gpt-test");
    assert_eq!(response.content, "provider answer");
    assert_eq!(response.finish_reason, LlmFinishReason::Stop);
    assert_eq!(
        response.usage.expect("usage").total_tokens,
        5,
        "usage maps from provider response"
    );
}

#[tokio::test]
async fn openai_compatible_provider_streams_sse_text_and_usage() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/chat/completions",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["model"], "gpt-stream-test");
            assert_eq!(body["stream"], true);
            assert_eq!(body["stream_options"]["include_usage"], true);
            (
                [("content-type", "text/event-stream")],
                concat!(
                    "data: {\"choices\":[{\"delta\":{\"content\":\"hel\"},\"finish_reason\":null}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":null}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
                    "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":4,\"completion_tokens\":2,\"total_tokens\":6}}\n\n",
                    "data: [DONE]\n\n"
                ),
            )
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider =
        OpenAiCompatibleProvider::new("openai-compatible", format!("http://{addr}"), "test-key")
            .expect("provider builds");
    let events = provider
        .stream(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "openai-compatible".to_owned(),
            model: "gpt-stream-test".to_owned(),
            messages: vec![user_message("ping")],
            temperature: None,
            max_output_tokens: Some(32),
            tools: vec![],
            metadata: json!({}),
        })
        .await
        .expect("provider streams")
        .collect::<Vec<_>>()
        .await
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .expect("stream events ok");

    assert!(matches!(events[0].kind, LlmEventKind::Started));
    assert_eq!(events[1].content.as_deref(), Some("hel"));
    assert_eq!(events[2].content.as_deref(), Some("lo"));
    let finished = events.last().expect("finished event");
    assert!(matches!(finished.kind, LlmEventKind::Finished));
    let response = finished.response.as_ref().expect("response");
    assert_eq!(response.content, "hello");
    assert_eq!(response.finish_reason, LlmFinishReason::Stop);
    assert_eq!(response.usage.as_ref().expect("usage").total_tokens, 6);
    assert_eq!(response.metadata["stream"], true);
}

#[tokio::test]
async fn openai_compatible_provider_streams_reasoning_and_tool_calls() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/chat/completions",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["stream"], true);
            (
                [("content-type", "text/event-stream")],
                concat!(
                    "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"think\"},\"finish_reason\":null}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read_task\",\"arguments\":\"{\\\"\"}}]},\"finish_reason\":null}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"id\\\":\\\"task_1\\\"}\"}}]},\"finish_reason\":null}]}\n\n",
                    "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
                    "data: [DONE]\n\n"
                ),
            )
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider =
        OpenAiCompatibleProvider::new("openai-compatible", format!("http://{addr}"), "test-key")
            .expect("provider builds");
    let events = provider
        .stream(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "openai-compatible".to_owned(),
            model: "gpt-stream-test".to_owned(),
            messages: vec![user_message("ping")],
            temperature: None,
            max_output_tokens: Some(32),
            tools: vec![],
            metadata: json!({}),
        })
        .await
        .expect("provider streams")
        .collect::<Vec<_>>()
        .await
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .expect("stream events ok");

    assert!(matches!(events[1].kind, LlmEventKind::ThinkingDelta));
    assert_eq!(events[1].content.as_deref(), Some("think"));
    assert!(matches!(events[2].kind, LlmEventKind::ToolCallStart));
    assert_eq!(events[2].tool_call_id.as_deref(), Some("call_1"));
    assert_eq!(events[2].tool_name.as_deref(), Some("read_task"));
    assert_eq!(events[3].partial_input_json.as_deref(), Some("{\""));
    assert_eq!(
        events[4].partial_input_json.as_deref(),
        Some("id\":\"task_1\"}")
    );
    assert!(matches!(events[5].kind, LlmEventKind::ToolCallEnd));
    assert_eq!(events[5].tool_input, Some(json!({"id": "task_1"})));
    let response = events
        .last()
        .and_then(|event| event.response.as_ref())
        .unwrap();
    assert_eq!(response.finish_reason, LlmFinishReason::ToolCall);
}

#[tokio::test]
async fn openai_compatible_provider_sends_tools_and_tool_results() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/chat/completions",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["tools"][0]["type"], "function");
            assert_eq!(body["tools"][0]["function"]["name"], "read_task");
            assert_eq!(
                body["tools"][0]["function"]["parameters"]["required"][0],
                "id"
            );
            assert_eq!(body["messages"][1]["role"], "assistant");
            assert_eq!(body["messages"][1]["content"], Value::Null);
            assert_eq!(body["messages"][1]["tool_calls"][0]["id"], "call_1");
            assert_eq!(
                body["messages"][1]["tool_calls"][0]["function"]["arguments"],
                "{\"id\":\"task_1\"}"
            );
            assert_eq!(body["messages"][2]["role"], "tool");
            assert_eq!(body["messages"][2]["tool_call_id"], "call_1");
            assert_eq!(body["messages"][2]["content"], "{\"title\":\"Task\"}");
            Json(json!({
                "choices": [{
                    "message": {"content": "done"},
                    "finish_reason": "stop"
                }]
            }))
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider =
        OpenAiCompatibleProvider::new("openai-compatible", format!("http://{addr}"), "test-key")
            .expect("provider builds");
    let response = provider
        .complete(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "openai-compatible".to_owned(),
            model: "gpt-tool-test".to_owned(),
            messages: vec![
                user_message("read task"),
                LlmMessage {
                    role: LlmRole::Assistant,
                    content: json!([{
                        "type": "tool_use",
                        "id": "call_1",
                        "name": "read_task",
                        "input": {"id": "task_1"}
                    }]),
                    name: None,
                    metadata: json!({}),
                },
                LlmMessage {
                    role: LlmRole::User,
                    content: json!([{
                        "type": "tool_result",
                        "tool_use_id": "call_1",
                        "content": {"title": "Task"}
                    }]),
                    name: None,
                    metadata: json!({}),
                },
            ],
            temperature: None,
            max_output_tokens: Some(32),
            tools: vec![ToolSpec {
                name: "read_task".to_owned(),
                description: "Read a task".to_owned(),
                input_schema: json!({
                    "type": "object",
                    "properties": {"id": {"type": "string"}},
                    "required": ["id"]
                }),
                output_schema: None,
                risk: agent_core::ToolRisk::ReadOnly,
                metadata: json!({}),
            }],
            metadata: json!({}),
        })
        .await
        .expect("provider completes");

    assert_eq!(response.content, "done");
}

#[tokio::test]
async fn anthropic_provider_completes_against_messages_api() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/messages",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["model"], "claude-test");
            assert_eq!(body["max_tokens"], 64);
            assert_eq!(body["system"], "be concise");
            assert_eq!(body["messages"][0]["role"], "user");
            Json(json!({
                "content": [{"type": "text", "text": "anthropic answer"}],
                "stop_reason": "end_turn",
                "usage": {
                    "input_tokens": 5,
                    "output_tokens": 3
                }
            }))
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider = AnthropicProvider::new(
        "anthropic",
        format!("http://{addr}"),
        "test-key",
        "2023-06-01",
    )
    .expect("provider builds");
    let response = provider
        .complete(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "anthropic".to_owned(),
            model: "claude-test".to_owned(),
            messages: vec![
                LlmMessage {
                    role: LlmRole::System,
                    content: json!("be concise"),
                    name: None,
                    metadata: json!({}),
                },
                user_message("ping"),
            ],
            temperature: Some(0.1),
            max_output_tokens: Some(64),
            tools: vec![],
            metadata: json!({}),
        })
        .await
        .expect("provider completes");

    assert_eq!(response.provider, "anthropic");
    assert_eq!(response.model, "claude-test");
    assert_eq!(response.content, "anthropic answer");
    assert_eq!(response.finish_reason, LlmFinishReason::Stop);
    assert_eq!(
        response.usage.expect("usage").total_tokens,
        8,
        "Anthropic usage totals input plus output tokens"
    );
}

#[tokio::test]
async fn anthropic_provider_streams_sse_text_and_usage() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/messages",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["model"], "claude-stream-test");
            assert_eq!(body["stream"], true);
            assert_eq!(body["messages"][0]["role"], "user");
            (
                [("content-type", "text/event-stream")],
                concat!(
                    "event: message_start\n",
                    "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}\n\n",
                    "event: content_block_start\n",
                    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
                    "event: content_block_delta\n",
                    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hel\"}}\n\n",
                    "event: content_block_delta\n",
                    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"lo\"}}\n\n",
                    "event: message_delta\n",
                    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":3}}\n\n",
                    "event: message_stop\n",
                    "data: {\"type\":\"message_stop\"}\n\n"
                ),
            )
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider = AnthropicProvider::new(
        "anthropic",
        format!("http://{addr}"),
        "test-key",
        "2023-06-01",
    )
    .expect("provider builds");
    let events = provider
        .stream(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "anthropic".to_owned(),
            model: "claude-stream-test".to_owned(),
            messages: vec![user_message("ping")],
            temperature: None,
            max_output_tokens: Some(64),
            tools: vec![],
            metadata: json!({}),
        })
        .await
        .expect("provider streams")
        .collect::<Vec<_>>()
        .await
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .expect("stream events ok");

    assert!(matches!(events[0].kind, LlmEventKind::Started));
    assert_eq!(events[1].content.as_deref(), Some("hel"));
    assert_eq!(events[2].content.as_deref(), Some("lo"));
    let finished = events.last().expect("finished event");
    assert!(matches!(finished.kind, LlmEventKind::Finished));
    let response = finished.response.as_ref().expect("response");
    assert_eq!(response.content, "hello");
    assert_eq!(response.finish_reason, LlmFinishReason::Stop);
    let usage = response.usage.as_ref().expect("usage");
    assert_eq!(usage.input_tokens, 5);
    assert_eq!(usage.output_tokens, 3);
    assert_eq!(usage.total_tokens, 8);
    assert_eq!(response.metadata["stream"], true);
}

#[tokio::test]
async fn anthropic_provider_streams_reasoning_signature_and_tool_calls() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/messages",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["stream"], true);
            (
                [("content-type", "text/event-stream")],
                concat!(
                    "event: message_start\n",
                    "data: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":0}}}\n\n",
                    "event: content_block_start\n",
                    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"plan\",\"signature\":\"sig_1\"}}\n\n",
                    "event: content_block_delta\n",
                    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\" more\"}}\n\n",
                    "event: content_block_delta\n",
                    "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"signature_delta\",\"signature\":\"sig_2\"}}\n\n",
                    "event: content_block_start\n",
                    "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"read_task\",\"input\":{}}}\n\n",
                    "event: content_block_delta\n",
                    "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"\"}}\n\n",
                    "event: content_block_delta\n",
                    "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"id\\\":\\\"task_1\\\"}\"}}\n\n",
                    "event: content_block_stop\n",
                    "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
                    "event: message_delta\n",
                    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":3}}\n\n",
                    "event: message_stop\n",
                    "data: {\"type\":\"message_stop\"}\n\n"
                ),
            )
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider = AnthropicProvider::new(
        "anthropic",
        format!("http://{addr}"),
        "test-key",
        "2023-06-01",
    )
    .expect("provider builds");
    let events = provider
        .stream(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "anthropic".to_owned(),
            model: "claude-stream-test".to_owned(),
            messages: vec![user_message("ping")],
            temperature: None,
            max_output_tokens: Some(64),
            tools: vec![],
            metadata: json!({}),
        })
        .await
        .expect("provider streams")
        .collect::<Vec<_>>()
        .await
        .into_iter()
        .collect::<Result<Vec<_>, _>>()
        .expect("stream events ok");

    assert!(matches!(events[1].kind, LlmEventKind::ThinkingDelta));
    assert_eq!(events[1].content.as_deref(), Some("plan"));
    assert!(matches!(
        events[2].kind,
        LlmEventKind::ThinkingSignatureDelta
    ));
    assert_eq!(events[2].content.as_deref(), Some("sig_1"));
    assert!(matches!(events[3].kind, LlmEventKind::ThinkingDelta));
    assert_eq!(events[3].content.as_deref(), Some(" more"));
    assert!(matches!(
        events[4].kind,
        LlmEventKind::ThinkingSignatureDelta
    ));
    assert_eq!(events[4].content.as_deref(), Some("sig_2"));
    assert!(matches!(events[5].kind, LlmEventKind::ToolCallStart));
    assert_eq!(events[5].tool_call_id.as_deref(), Some("toolu_1"));
    assert_eq!(events[5].tool_name.as_deref(), Some("read_task"));
    assert_eq!(events[6].partial_input_json.as_deref(), Some("{\""));
    assert_eq!(
        events[7].partial_input_json.as_deref(),
        Some("id\":\"task_1\"}")
    );
    assert!(matches!(events[8].kind, LlmEventKind::ToolCallEnd));
    assert_eq!(events[8].tool_input, Some(json!({"id": "task_1"})));
    let response = events
        .last()
        .and_then(|event| event.response.as_ref())
        .unwrap();
    assert_eq!(response.finish_reason, LlmFinishReason::ToolCall);
}

#[tokio::test]
async fn anthropic_provider_preserves_multimodal_content_tools_and_raw_blocks() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/messages",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["model"], "claude-vision-test");
            assert_eq!(body["messages"][0]["role"], "user");
            assert_eq!(body["messages"][0]["content"][0]["type"], "image");
            assert_eq!(
                body["messages"][0]["content"][0]["source"]["media_type"],
                "image/png"
            );
            assert_eq!(body["tools"][0]["name"], "emit_parsed_transactions");
            assert_eq!(
                body["tools"][0]["input_schema"]["required"][0],
                "transactions"
            );
            Json(json!({
                "content": [{
                    "type": "tool_use",
                    "id": "toolu_1",
                    "name": "emit_parsed_transactions",
                    "input": {
                        "transactions": [{
                            "description": "Coffee",
                            "amount_minor": -450,
                            "currency": "USD",
                            "occurred_at": "2026-06-01"
                        }]
                    }
                }],
                "stop_reason": "tool_use",
                "usage": {
                    "input_tokens": 7,
                    "output_tokens": 5
                }
            }))
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider = AnthropicProvider::new(
        "anthropic",
        format!("http://{addr}"),
        "test-key",
        "2023-06-01",
    )
    .expect("provider builds");
    let response = provider
        .complete(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "anthropic".to_owned(),
            model: "claude-vision-test".to_owned(),
            messages: vec![LlmMessage {
                role: LlmRole::User,
                content: json!([
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/png",
                            "data": "ZmFrZQ=="
                        }
                    },
                    {
                        "type": "text",
                        "text": "Extract transactions."
                    }
                ]),
                name: None,
                metadata: json!({}),
            }],
            temperature: None,
            max_output_tokens: Some(1024),
            tools: vec![ToolSpec {
                name: "emit_parsed_transactions".to_owned(),
                description: "Emit rows".to_owned(),
                input_schema: json!({
                    "type": "object",
                    "properties": {"transactions": {"type": "array"}},
                    "required": ["transactions"]
                }),
                output_schema: None,
                risk: agent_core::ToolRisk::ReadOnly,
                metadata: json!({}),
            }],
            metadata: json!({}),
        })
        .await
        .expect("provider completes");

    assert_eq!(response.content, "");
    assert_eq!(response.finish_reason, LlmFinishReason::ToolCall);
    assert_eq!(
        response.metadata["anthropic_content"][0]["name"],
        "emit_parsed_transactions"
    );
    assert_eq!(
        response.metadata["anthropic_content"][0]["input"]["transactions"][0]["description"],
        "Coffee"
    );
}

#[tokio::test]
async fn ollama_provider_completes_against_chat_api() {
    let listener = TcpListener::bind(("127.0.0.1", 0))
        .await
        .expect("listener binds");
    let addr = listener.local_addr().expect("local addr");
    let app = Router::new().route(
        "/api/chat",
        post(|Json(body): Json<Value>| async move {
            assert_eq!(body["model"], "llama-test");
            assert_eq!(body["stream"], false);
            assert_eq!(body["messages"][0]["role"], "user");
            assert_eq!(body["options"]["num_predict"], 32);
            Json(json!({
                "message": {"role": "assistant", "content": "local answer"},
                "done_reason": "stop",
                "prompt_eval_count": 6,
                "eval_count": 4
            }))
        }),
    );
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("test server runs");
    });

    let provider =
        OllamaProvider::new("ollama", format!("http://{addr}")).expect("provider builds");
    let response = provider
        .complete(LlmRequest {
            protocol_version: PROTOCOL_VERSION.to_owned(),
            provider: "ollama".to_owned(),
            model: "llama-test".to_owned(),
            messages: vec![user_message("ping")],
            temperature: Some(0.3),
            max_output_tokens: Some(32),
            tools: vec![],
            metadata: json!({}),
        })
        .await
        .expect("provider completes");

    assert_eq!(response.provider, "ollama");
    assert_eq!(response.model, "llama-test");
    assert_eq!(response.content, "local answer");
    assert_eq!(response.finish_reason, LlmFinishReason::Stop);
    assert_eq!(response.usage.expect("usage").total_tokens, 10);
}
