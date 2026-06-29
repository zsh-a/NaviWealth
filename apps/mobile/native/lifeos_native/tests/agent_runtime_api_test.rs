use lifeos_native::api::agent_runtime::{
    agent_runtime_catalog_summary, agent_runtime_complete_mock_llm,
    agent_runtime_complete_profile_llm, agent_runtime_continue_run_step,
    agent_runtime_protocol_version, agent_runtime_start_profile_turn_step,
    agent_runtime_start_run_step, agent_runtime_validate_llm_request,
    agent_runtime_validate_llm_response, agent_runtime_validate_run_request,
    agent_runtime_validate_trace,
};
use serde_json::Value;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

#[test]
fn exposes_protocol_version() {
    assert_eq!(agent_runtime_protocol_version(), "agent.v1");
}

#[test]
fn summarizes_catalog_contract() {
    let summary_json = agent_runtime_catalog_summary(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
    )
    .expect("catalog should validate");
    let summary: Value = serde_json::from_str(&summary_json).expect("summary should be json");

    assert_eq!(summary["protocol_version"], "agent.v1");
    assert_eq!(summary["catalog_version"], "agent_catalog.v1");
    assert_eq!(summary["agent_count"], 1);
    assert_eq!(summary["tool_count"], 1);
    assert_eq!(summary["proposal_kind_count"], 1);
    assert_eq!(summary["prompt_block_count"], 1);
}

#[test]
fn normalizes_run_request_contract() {
    let normalized = agent_runtime_validate_run_request(
        include_str!("../../../../../fixtures/agent-runtime/run-request.valid.json").to_owned(),
    )
    .expect("run request should validate");
    let request: Value = serde_json::from_str(&normalized).expect("request should be json");

    assert_eq!(request["protocol_version"], "agent.v1");
    assert_eq!(request["trigger"], "manual");
    assert_eq!(request["input"]["message"], "hello runtime");
}

#[test]
fn normalizes_trace_contract() {
    let normalized = agent_runtime_validate_trace(
        include_str!("../../../../../fixtures/agent-runtime/trace.valid.json").to_owned(),
    )
    .expect("trace should validate");
    let trace: Value = serde_json::from_str(&normalized).expect("trace should be json");

    assert_eq!(trace["protocol_version"], "agent.v1");
    assert_eq!(trace["run_id"], "run_018f0000-0000-7000-8000-000000000000");
    assert_eq!(trace["events"][0]["kind"], "run_started");
}

#[test]
fn normalizes_llm_contracts() {
    let request_json = agent_runtime_validate_llm_request(
        include_str!("../../../../../fixtures/agent-runtime/llm-request.valid.json").to_owned(),
    )
    .expect("llm request should validate");
    let request: Value = serde_json::from_str(&request_json).expect("request should be json");
    assert_eq!(request["protocol_version"], "agent.v1");
    assert_eq!(request["provider"], "mock");
    assert_eq!(request["messages"][0]["role"], "user");

    let response_json = agent_runtime_validate_llm_response(
        include_str!("../../../../../fixtures/agent-runtime/llm-response.valid.json").to_owned(),
    )
    .expect("llm response should validate");
    let response: Value = serde_json::from_str(&response_json).expect("response should be json");
    assert_eq!(response["protocol_version"], "agent.v1");
    assert_eq!(response["finish_reason"], "stop");
}

#[test]
fn normalizes_multimodal_tool_llm_request_contract() {
    let request_json = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "anthropic",
          "model": "claude-vision-test",
          "messages": [{
            "role": "user",
            "content": [
              {
                "type": "image",
                "source": {
                  "type": "base64",
                  "media_type": "image/png",
                  "data": "ZmFrZQ=="
                }
              },
              {"type": "text", "text": "Extract transactions."}
            ]
          }],
          "tools": [{
            "name": "emit_parsed_transactions",
            "description": "Emit rows",
            "input_schema": {
              "type": "object",
              "properties": {"transactions": {"type": "array"}},
              "required": ["transactions"]
            },
            "risk": "read_only"
          }],
          "metadata": {"api_key": "sk-test"}
        }"#
        .to_owned(),
    )
    .expect("multimodal llm request should validate");
    let request: Value = serde_json::from_str(&request_json).expect("request should be json");

    assert_eq!(request["messages"][0]["content"][0]["type"], "image");
    assert_eq!(request["tools"][0]["name"], "emit_parsed_transactions");
    assert_eq!(request["tools"][0]["risk"], "read_only");
}

#[tokio::test]
async fn complete_mock_llm_returns_provider_response() {
    let response_json = agent_runtime_complete_mock_llm(
        include_str!("../../../../../fixtures/agent-runtime/llm-request.valid.json").to_owned(),
        "native mock response".to_owned(),
    )
    .await
    .expect("mock llm should complete");
    let response: Value = serde_json::from_str(&response_json).expect("response should be json");

    assert_eq!(response["protocol_version"], "agent.v1");
    assert_eq!(response["provider"], "mock");
    assert_eq!(response["model"], "mock-model");
    assert_eq!(response["content"], "native mock response");
    assert_eq!(response["finish_reason"], "stop");
    assert_eq!(response["metadata"]["mock"], true);
}

#[tokio::test]
async fn complete_profile_llm_requires_profile_api_key() {
    let err = agent_runtime_complete_profile_llm(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "openai",
          "model": "test-model",
          "messages": [{"role": "user", "content": "ping"}],
          "metadata": {}
        }"#
        .to_owned(),
    )
    .await
    .expect_err("profile llm should require metadata api key");

    assert!(err.to_string().contains("metadata.api_key"));
}

#[tokio::test]
async fn complete_profile_llm_calls_openai_compatible_provider() {
    let (base_url, server) = spawn_openai_compatible_server();
    let response_json = agent_runtime_complete_profile_llm(format!(
        r#"{{
          "protocol_version": "agent.v1",
          "provider": "openai",
          "model": "test-model",
          "messages": [{{"role": "user", "content": "ping"}}],
          "metadata": {{
            "api_key": "sk-test",
            "base_url": "{base_url}"
          }}
        }}"#
    ))
    .await
    .expect("profile llm should complete through local provider");
    server.join().expect("server thread should finish");
    let response: Value = serde_json::from_str(&response_json).expect("response should be json");

    assert_eq!(response["protocol_version"], "agent.v1");
    assert_eq!(response["provider"], "openai");
    assert_eq!(response["model"], "test-model");
    assert_eq!(response["content"], "profile response");
    assert_eq!(response["finish_reason"], "stop");
    assert_eq!(response["metadata"]["api"], "openai_chat_completions");
}

#[tokio::test]
async fn start_profile_turn_step_completes_llm_and_starts_native_step() {
    let turn_json = agent_runtime_start_profile_turn_step(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "ping"}],
          "metadata": {"mock_response": "native turn response"}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
        r#"{"surface":"rust_test"}"#.to_owned(),
    )
    .await
    .expect("profile turn step should complete");
    let turn: Value = serde_json::from_str(&turn_json).expect("turn should be json");

    assert_eq!(turn["protocol_version"], "agent.v1");
    assert_eq!(turn["llm_response"]["content"], "native turn response");
    assert_eq!(turn["step"]["agent_id"], "execution_review");
    assert_eq!(turn["step"]["status"], "completed");
    assert_eq!(turn["step"]["output"]["content"], "native turn response");
    assert_eq!(
        turn["step"]["output"]["llm_response"]["content"],
        "native turn response"
    );
}

#[test]
fn start_run_step_requests_catalog_tool_call() {
    let step_json = agent_runtime_start_run_step(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "input": {
            "tool_call": {
              "name": "propose_fake",
              "input": {"value": 7}
            }
          },
          "trigger": "manual",
          "metadata": {}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("start step should validate catalog and request");
    let step: Value = serde_json::from_str(&step_json).expect("step should be json");

    assert_eq!(step["protocol_version"], "agent.v1");
    assert_eq!(step["agent_id"], "execution_review");
    assert_eq!(step["status"], "tool_call_requested");
    assert_eq!(step["tool_call"]["name"], "propose_fake");
    assert_eq!(step["tool_call"]["input"]["value"], 7);
}

#[test]
fn start_run_step_seeds_native_tool_plan_continuation() {
    let step_json = agent_runtime_start_run_step(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "input": {
            "tool_plan": [
              {"name": "propose_fake", "input": {"value": 1}},
              {"name": "propose_fake", "input": {"value": 2}}
            ],
            "llm_response": {"content": "use two tools"}
          },
          "trigger": "manual",
          "metadata": {}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("start step should seed tool plan continuation");
    let step: Value = serde_json::from_str(&step_json).expect("step should be json");

    assert_eq!(step["status"], "tool_call_requested");
    assert_eq!(step["tool_call"]["input"]["value"], 1);
    assert_eq!(step["continuation"]["tool_plan"][0]["input"]["value"], 2);
    assert_eq!(
        step["continuation"]["llm_response"]["content"],
        "use two tools"
    );
}

#[test]
fn continue_run_step_completes_with_tool_result() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "1.0.0",
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 7}
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
        step_json.to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_018f0000-0000-7000-8000-000000000000",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("continue step should accept tool result");
    let next: Value = serde_json::from_str(&next_json).expect("next step should be json");

    assert_eq!(next["protocol_version"], "agent.v1");
    assert_eq!(next["agent_id"], "execution_review");
    assert_eq!(next["status"], "completed");
    assert_eq!(next["output"]["mode"], "frb_tool_step");
    assert_eq!(next["output"]["tool_result"]["accepted"], true);
    assert_eq!(next["output"]["tool_call"]["name"], "propose_fake");
}

#[test]
fn continue_run_step_requests_next_native_tool_plan_item() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "1.0.0",
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 1}
      },
      "continuation": {
        "tool_plan": [
          {"name": "propose_fake", "input": {"value": 2}}
        ],
        "tool_results": [],
        "llm_response": {"content": "use two tools"}
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
        step_json.to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_018f0000-0000-7000-8000-000000000000",
          "result": {"accepted": true, "value": 1}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("continue step should request next planned tool");
    let next: Value = serde_json::from_str(&next_json).expect("next step should be json");

    assert_eq!(next["status"], "tool_call_requested");
    assert_eq!(next["tool_call"]["name"], "propose_fake");
    assert_eq!(next["tool_call"]["input"]["value"], 2);
    assert_eq!(
        next["continuation"]["tool_plan"].as_array().unwrap().len(),
        0
    );
    assert_eq!(
        next["continuation"]["tool_results"][0]["tool_response"]["result"]["value"],
        1
    );
}

#[test]
fn continue_run_step_completes_native_tool_plan_after_last_item() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "1.0.0",
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000001",
        "name": "propose_fake",
        "input": {"value": 2}
      },
      "continuation": {
        "tool_plan": [],
        "tool_results": [
          {
            "tool_call": {"name": "propose_fake", "input": {"value": 1}},
            "tool_response": {"result": {"accepted": true, "value": 1}}
          }
        ]
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
        step_json.to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_018f0000-0000-7000-8000-000000000001",
          "result": {"accepted": true, "value": 2}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("continue step should complete the native tool plan");
    let next: Value = serde_json::from_str(&next_json).expect("next step should be json");

    assert_eq!(next["status"], "completed");
    assert_eq!(next["output"]["mode"], "frb_tool_loop");
    assert_eq!(next["output"]["tool_results"].as_array().unwrap().len(), 2);
    assert_eq!(next["output"]["tool_result"]["value"], 2);
}

#[test]
fn continue_run_step_fails_with_tool_error() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "1.0.0",
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 7}
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!("../../../../../fixtures/agent-runtime/catalog.valid.json").to_owned(),
        step_json.to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_018f0000-0000-7000-8000-000000000000",
          "error": {"code": -32000, "message": "tool failed"}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("continue step should accept tool error");
    let next: Value = serde_json::from_str(&next_json).expect("next step should be json");

    assert_eq!(next["status"], "failed");
    assert_eq!(next["error"]["message"], "tool failed");
    assert_eq!(next["tool_call"]["name"], "propose_fake");
}

fn spawn_openai_compatible_server() -> (String, thread::JoinHandle<()>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind local test server");
    let addr = listener.local_addr().expect("local addr");
    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept provider request");
        let mut request = [0_u8; 4096];
        let read = stream.read(&mut request).expect("read provider request");
        let request = String::from_utf8_lossy(&request[..read]);
        assert!(request.contains("POST /v1/chat/completions HTTP/1.1"));
        assert!(request.contains("authorization: Bearer sk-test"));
        let body = r#"{
          "choices": [{
            "message": {"content": "profile response"},
            "finish_reason": "stop"
          }],
          "usage": {
            "prompt_tokens": 1,
            "completion_tokens": 2,
            "total_tokens": 3
          }
        }"#;
        let response = format!(
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\n\r\n{}",
            body.len(),
            body
        );
        stream
            .write_all(response.as_bytes())
            .expect("write provider response");
    });
    (format!("http://{addr}"), handle)
}
