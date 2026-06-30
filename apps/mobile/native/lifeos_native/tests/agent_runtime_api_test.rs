use lifeos_native::api::agent_runtime::{
    agent_runtime_catalog_summary, agent_runtime_complete_mock_llm,
    agent_runtime_complete_profile_llm, agent_runtime_continue_run_step,
    agent_runtime_protocol_version, agent_runtime_start_profile_turn_step,
    agent_runtime_start_run_step, agent_runtime_validate_agent_turn_request,
    agent_runtime_validate_llm_request, agent_runtime_validate_llm_response,
    agent_runtime_validate_run_request, agent_runtime_validate_tool_spec,
    agent_runtime_validate_trace,
};
use serde_json::{Value, json};
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
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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
fn catalog_summary_rejects_mismatched_catalog_contract() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["protocol_version"] = json!("agent.v0");
    let protocol_err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("mismatched catalog protocol should fail");
    assert!(protocol_err.to_string().contains("protocol_version"));

    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["catalog_version"] = json!("agent_catalog.v0");
    let catalog_err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("mismatched catalog version should fail");
    assert!(catalog_err.to_string().contains("catalog_version"));
}

#[test]
fn catalog_summary_rejects_empty_active_domain() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["active_domains"] = json!(["finance", " "]);

    let err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("empty active domain should fail");

    assert!(err.to_string().contains("catalog.active_domains[1]"));
}

#[test]
fn validates_tool_spec_contract() {
    let normalized = agent_runtime_validate_tool_spec(
        r#"{
          "name": "read_task",
          "description": "Read a task",
          "input_schema": {"type": "object"},
          "risk": "read_only",
          "metadata": {}
        }"#
        .to_owned(),
    )
    .expect("tool spec should validate");
    let tool: Value = serde_json::from_str(&normalized).expect("tool should be json");

    assert_eq!(tool["name"], "read_task");
    assert_eq!(tool["risk"], "read_only");
}

#[test]
fn validate_tool_spec_rejects_malformed_contract() {
    let empty_name = agent_runtime_validate_tool_spec(
        r#"{
          "name": "",
          "description": "Read a task",
          "input_schema": {"type": "object"},
          "risk": "read_only"
        }"#
        .to_owned(),
    )
    .expect_err("empty tool name should fail");
    assert!(empty_name.to_string().contains("name"));

    let bad_schema = agent_runtime_validate_tool_spec(
        r#"{
          "name": "read_task",
          "description": "Read a task",
          "input_schema": "bad",
          "risk": "read_only"
        }"#
        .to_owned(),
    )
    .expect_err("non-object input_schema should fail");
    assert!(bad_schema.to_string().contains("input_schema"));
}

#[test]
fn catalog_summary_rejects_malformed_tool_spec() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["tools"][0]["description"] = json!("");

    let err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("catalog with malformed tool spec should fail");

    assert!(err.to_string().contains("catalog.tools[0].description"));
}

#[test]
fn catalog_summary_rejects_malformed_agent_spec() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["agents"][0]["id"] = json!("");

    let err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("catalog with malformed agent spec should fail");

    assert!(err.to_string().contains("catalog.agents[0].id"));
}

#[test]
fn catalog_summary_rejects_malformed_agent_schedule() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["agents"][0]["schedule"] = json!({
        "type": "interval",
        "every_seconds": 0
    });

    let interval_err =
        agent_runtime_catalog_summary(catalog.to_string()).expect_err("zero interval should fail");
    assert!(
        interval_err
            .to_string()
            .contains("catalog.agents[0].schedule.every_seconds")
    );

    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["agents"][0]["schedule"] = json!({
        "type": "interval",
        "every_seconds": 3600,
        "preferred_hour_local": 24
    });

    let hour_err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("out-of-range preferred hour should fail");
    assert!(
        hour_err
            .to_string()
            .contains("catalog.agents[0].schedule.preferred_hour_local")
    );
}

#[test]
fn catalog_summary_rejects_malformed_proposal_kind() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["proposal_kinds"][0]["tool_name"] = json!("");

    let err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("catalog with malformed proposal kind should fail");

    assert!(
        err.to_string()
            .contains("catalog.proposal_kinds[0].tool_name")
    );
}

#[test]
fn catalog_summary_rejects_proposal_kind_without_catalog_tool() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["proposal_kinds"][0]["tool_name"] = json!("missing_tool");

    let err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("proposal kind should reference a catalog tool");

    assert!(
        err.to_string()
            .contains("catalog.proposal_kinds[0].tool_name")
    );
}

#[test]
fn catalog_summary_rejects_duplicate_catalog_entries() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    let duplicate_tool = catalog["tools"][0].clone();
    catalog["tools"]
        .as_array_mut()
        .expect("tools should be array")
        .push(duplicate_tool);
    let tool_err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("duplicate tool name should fail");
    assert!(tool_err.to_string().contains("catalog.tools[1].name"));

    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["prompt_blocks"] = json!([
        {"index": 0, "text": "first"},
        {"index": 0, "text": "duplicate"}
    ]);
    let prompt_err = agent_runtime_catalog_summary(catalog.to_string())
        .expect_err("duplicate prompt block index should fail");
    assert!(
        prompt_err
            .to_string()
            .contains("catalog.prompt_blocks[1].index")
    );
}

#[test]
fn normalizes_run_request_contract() {
    let normalized = agent_runtime_validate_run_request(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/run-request.valid.json"
        )
        .to_owned(),
    )
    .expect("run request should validate");
    let request: Value = serde_json::from_str(&normalized).expect("request should be json");

    assert_eq!(request["protocol_version"], "agent.v1");
    assert_eq!(request["trigger"], "manual");
    assert_eq!(request["input"]["message"], "hello runtime");
}

#[test]
fn normalizes_run_request_default_object_fields() {
    let normalized = agent_runtime_validate_run_request(
        r#"{
          "protocol_version": "agent.v1",
          "user": {"user_id": "user_1"},
          "trigger": "manual"
        }"#
        .to_owned(),
    )
    .expect("run request defaults should normalize");
    let request: Value = serde_json::from_str(&normalized).expect("request should be json");

    assert_eq!(request["input"], json!({}));
    assert_eq!(request["metadata"], json!({}));
    assert_eq!(request["user"]["metadata"], json!({}));
}

#[test]
fn validate_run_request_rejects_mismatched_protocol_version() {
    let err = agent_runtime_validate_run_request(
        r#"{
          "protocol_version": "agent.v0",
          "input": {"message": "hello runtime"},
          "trigger": "manual"
        }"#
        .to_owned(),
    )
    .expect_err("mismatched run request protocol should fail");

    assert!(err.to_string().contains("protocol_version"));
}

#[test]
fn validate_run_request_rejects_malformed_json_object_fields() {
    let input_err = agent_runtime_validate_run_request(
        r#"{
          "protocol_version": "agent.v1",
          "input": "bad",
          "trigger": "manual"
        }"#
        .to_owned(),
    )
    .expect_err("non-object input should fail");
    assert!(input_err.to_string().contains("input"));

    let metadata_err = agent_runtime_validate_run_request(
        r#"{
          "protocol_version": "agent.v1",
          "input": {"message": "hello runtime"},
          "trigger": "manual",
          "metadata": "bad"
        }"#
        .to_owned(),
    )
    .expect_err("non-object metadata should fail");
    assert!(metadata_err.to_string().contains("metadata"));

    let user_err = agent_runtime_validate_run_request(
        r#"{
          "protocol_version": "agent.v1",
          "input": {"message": "hello runtime"},
          "user": {"user_id": ""},
          "trigger": "manual"
        }"#
        .to_owned(),
    )
    .expect_err("malformed user context should fail");
    assert!(user_err.to_string().contains("user.user_id"), "{user_err}");

    let user_metadata_err = agent_runtime_validate_run_request(
        r#"{
          "protocol_version": "agent.v1",
          "input": {"message": "hello runtime"},
          "user": {"user_id": "user_1", "metadata": []},
          "trigger": "manual"
        }"#
        .to_owned(),
    )
    .expect_err("malformed user metadata should fail");
    assert!(user_metadata_err.to_string().contains("user.metadata"));
}

#[test]
fn normalizes_trace_contract() {
    let normalized = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.valid.json"
        )
        .to_owned(),
    )
    .expect("trace should validate");
    let trace: Value = serde_json::from_str(&normalized).expect("trace should be json");

    assert_eq!(trace["protocol_version"], "agent.v1");
    assert_eq!(trace["run_id"], "run_018f0000-0000-7000-8000-000000000000");
    assert_eq!(trace["events"][0]["kind"], "run_started");
    assert_eq!(trace["events"][1]["kind"], "agent_runtime_step");
    assert_eq!(trace["events"][1]["payload"]["tool_name"], "echo");
    assert_eq!(
        trace["events"][1]["payload"]["run_state"]["terminal_reason"],
        "done"
    );
    assert_eq!(
        trace["events"][1]["payload"]["run_state"]["tool_result_count"],
        1
    );
}

#[test]
fn normalizes_closed_early_step_trace_contract() {
    let normalized = agent_runtime_validate_trace(
        include_str!("../../../../../third_party/agent-runtime/fixtures/contracts/trace.valid.closed-early-step.json")
            .to_owned(),
    )
    .expect("closed_early trace should validate");
    let trace: Value = serde_json::from_str(&normalized).expect("trace should be json");

    assert_eq!(trace["agent_id"], "execution_review");
    assert_eq!(trace["events"][1]["payload"]["status"], "closed_early");
    assert_eq!(
        trace["events"][1]["payload"]["run_state"]["terminal_reason"],
        "closed_early"
    );
}

#[test]
fn rejects_invalid_agent_runtime_step_trace_contracts() {
    let missing_run_state = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.missing-step-run-state.json"
        )
        .to_owned(),
    )
    .expect_err("missing run_state should fail native validation")
    .to_string();
    assert!(missing_run_state.contains("payload.run_state"));

    let unknown_terminal_reason = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.unknown-step-terminal-reason.json"
        )
        .to_owned(),
    )
    .expect_err("unknown terminal reason should fail native validation")
    .to_string();
    assert!(unknown_terminal_reason.contains("terminal_reason"));

    let unknown_status = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.unknown-step-status.json"
        )
        .to_owned(),
    )
    .expect_err("unknown status should fail native validation")
    .to_string();
    assert!(unknown_status.contains("status"));

    let non_string_tool_name = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.non-string-step-tool-name.json"
        )
        .to_owned(),
    )
    .expect_err("non-string tool_name should fail native validation")
    .to_string();
    assert!(non_string_tool_name.contains("tool_name"));

    let empty_tool_name = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.empty-step-tool-name.json"
        )
        .to_owned(),
    )
    .expect_err("empty tool_name should fail native validation")
    .to_string();
    assert!(empty_tool_name.contains("tool_name"));

    let mismatched_run_id = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.mismatched-step-run-id.json"
        )
        .to_owned(),
    )
    .expect_err("mismatched run_id should fail native validation")
    .to_string();
    assert!(mismatched_run_id.contains("run_id"));

    let mismatched_agent_id = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.mismatched-step-agent-id.json"
        )
        .to_owned(),
    )
    .expect_err("mismatched agent_id should fail native validation")
    .to_string();
    assert!(mismatched_agent_id.contains("agent_id"));

    let mismatched_step_index = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.mismatched-step-index.json"
        )
        .to_owned(),
    )
    .expect_err("mismatched step_index should fail native validation")
    .to_string();
    assert!(mismatched_step_index.contains("step_index"));

    let mismatched_run_state_status = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.mismatched-step-run-state-status.json"
        )
        .to_owned(),
    )
    .expect_err("mismatched run_state status should fail native validation")
    .to_string();
    assert!(mismatched_run_state_status.contains("status"));

    let mismatched_terminal_status = agent_runtime_validate_trace(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/trace.invalid.mismatched-step-terminal-status.json"
        )
        .to_owned(),
    )
    .expect_err("mismatched terminal status should fail native validation")
    .to_string();
    assert!(mismatched_terminal_status.contains("terminal_reason"));
}

#[test]
fn normalizes_llm_contracts() {
    let request_json = agent_runtime_validate_llm_request(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/llm-request.valid.json"
        )
        .to_owned(),
    )
    .expect("llm request should validate");
    let request: Value = serde_json::from_str(&request_json).expect("request should be json");
    assert_eq!(request["protocol_version"], "agent.v1");
    assert_eq!(request["provider"], "mock");
    assert_eq!(request["messages"][0]["role"], "user");

    let response_json = agent_runtime_validate_llm_response(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/llm-response.valid.json"
        )
        .to_owned(),
    )
    .expect("llm response should validate");
    let response: Value = serde_json::from_str(&response_json).expect("response should be json");
    assert_eq!(response["protocol_version"], "agent.v1");
    assert_eq!(response["finish_reason"], "stop");
}

#[test]
fn normalizes_agent_turn_request_contract() {
    let request_json = agent_runtime_validate_agent_turn_request(
        r#"{
          "protocol_version": "agent.v1",
          "turn_id": "turn_1",
          "surface": "ai_chat",
          "agent_id": "ai_chat",
          "mode": "chat",
          "provider": "openai",
          "model": "gpt-test",
          "messages": [{
            "role": "user",
            "content": [
              {"type": "text", "text": "Extract this receipt."},
              {
                "type": "image",
                "source": {
                  "type": "base64",
                  "media_type": "image/png",
                  "data": "ZmFrZQ=="
                }
              }
            ],
            "metadata": null
          }],
          "tools": [{
            "name": "emit_parsed_transactions",
            "description": "Emit parsed rows",
            "input_schema": {"type": "object"},
            "risk": "read_only"
          }],
          "metadata": {"api_key": "sk-test"}
        }"#
        .to_owned(),
    )
    .expect("agent turn request should normalize");
    let request: Value = serde_json::from_str(&request_json).expect("request should be json");

    assert_eq!(request["protocol_version"], "agent.v1");
    assert_eq!(request["turn_id"], "turn_1");
    assert_eq!(request["messages"][0]["content"][0]["type"], "text");
    assert_eq!(request["messages"][0]["content"][1]["type"], "image");
    assert_eq!(request["messages"][0]["metadata"], json!({}));
    assert_eq!(request["metadata"]["agent_turn"], true);
    assert_eq!(request["metadata"]["surface"], "ai_chat");
    assert_eq!(request["tools"][0]["name"], "emit_parsed_transactions");
}

#[test]
fn validate_agent_turn_request_rejects_malformed_fields() {
    let empty_surface = agent_runtime_validate_agent_turn_request(
        r#"{
          "protocol_version": "agent.v1",
          "surface": "",
          "provider": "openai",
          "model": "gpt-test",
          "messages": [{"role": "user", "content": "hello"}],
          "metadata": {}
        }"#
        .to_owned(),
    )
    .expect_err("empty surface should fail");
    assert!(empty_surface.to_string().contains("surface"));

    let bad_metadata = agent_runtime_validate_agent_turn_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "openai",
          "model": "gpt-test",
          "messages": [{"role": "user", "content": "hello"}],
          "metadata": []
        }"#
        .to_owned(),
    )
    .expect_err("non-object metadata should fail");
    assert!(bad_metadata.to_string().contains("metadata"));
}

#[test]
fn normalizes_llm_request_default_object_fields() {
    let request_json = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}]
        }"#
        .to_owned(),
    )
    .expect("LLM request defaults should normalize");
    let request: Value = serde_json::from_str(&request_json).expect("request should be json");

    assert_eq!(request["metadata"], json!({}));
    assert_eq!(request["messages"][0]["metadata"], json!({}));
}

#[test]
fn validates_llm_request_generation_limits() {
    let request_json = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}],
          "temperature": 0.2,
          "max_output_tokens": 16
        }"#
        .to_owned(),
    )
    .expect("valid generation limits should validate");
    let request: Value = serde_json::from_str(&request_json).expect("request should be json");

    assert_eq!(request["temperature"], 0.2);
    assert_eq!(request["max_output_tokens"], 16);
}

#[test]
fn normalizes_llm_response_default_object_fields() {
    let response_json = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "stop"
        }"#
        .to_owned(),
    )
    .expect("LLM response defaults should normalize");
    let response: Value = serde_json::from_str(&response_json).expect("response should be json");

    assert_eq!(response["metadata"], json!({}));
}

#[test]
fn validates_llm_response_usage_totals() {
    let response_json = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "stop",
          "usage": {
            "input_tokens": 2,
            "output_tokens": 3,
            "total_tokens": 5
          }
        }"#
        .to_owned(),
    )
    .expect("matching usage totals should validate");
    let response: Value = serde_json::from_str(&response_json).expect("response should be json");

    assert_eq!(response["usage"]["total_tokens"], 5);
}

#[test]
fn normalizes_llm_response_tool_metadata() {
    let response_json = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "tool_call",
          "metadata": {
            "tool_plan": [
              {"name": "propose_fake"}
            ],
            "tool_call": {"name": "read_context"}
          }
        }"#
        .to_owned(),
    )
    .expect("LLM response tool metadata should normalize");
    let response: Value = serde_json::from_str(&response_json).expect("response should be json");

    assert_eq!(response["metadata"]["tool_plan"][0]["input"], json!({}));
    assert_eq!(response["metadata"]["tool_call"]["input"], json!({}));
}

#[test]
fn validate_llm_contracts_reject_mismatched_protocol_version() {
    let request_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v0",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}]
        }"#
        .to_owned(),
    )
    .expect_err("mismatched LLM request protocol should fail");
    assert!(request_err.to_string().contains("protocol_version"));

    let response_err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v0",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "stop"
        }"#
        .to_owned(),
    )
    .expect_err("mismatched LLM response protocol should fail");
    assert!(response_err.to_string().contains("protocol_version"));
}

#[test]
fn validate_llm_response_rejects_malformed_required_fields() {
    let provider_err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "stop"
        }"#
        .to_owned(),
    )
    .expect_err("empty response provider should fail");
    assert!(provider_err.to_string().contains("provider"));

    let model_err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "",
          "content": "hello",
          "finish_reason": "stop"
        }"#
        .to_owned(),
    )
    .expect_err("empty response model should fail");
    assert!(model_err.to_string().contains("model"));
}

#[test]
fn validate_llm_response_rejects_malformed_metadata_field() {
    let metadata_err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "stop",
          "metadata": []
        }"#
        .to_owned(),
    )
    .expect_err("non-object response metadata should fail");
    assert!(metadata_err.to_string().contains("metadata"));
}

#[test]
fn validate_llm_response_rejects_malformed_tool_metadata() {
    let plan_err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "tool_call",
          "metadata": {
            "tool_plan": {"name": "propose_fake"}
          }
        }"#
        .to_owned(),
    )
    .expect_err("non-array response tool_plan should fail");
    assert!(plan_err.to_string().contains("metadata.tool_plan"));

    let item_err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "tool_call",
          "metadata": {
            "tool_plan": [
              {"name": "propose_fake", "input": "bad"}
            ]
          }
        }"#
        .to_owned(),
    )
    .expect_err("non-object response tool_plan input should fail");
    assert!(item_err.to_string().contains("metadata.tool_plan[0].input"));

    let call_err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "tool_call",
          "metadata": {
            "tool_call": {"name": "read_context", "input": []}
          }
        }"#
        .to_owned(),
    )
    .expect_err("non-object response tool_call input should fail");
    assert!(call_err.to_string().contains("metadata.tool_call.input"));
}

#[test]
fn validate_llm_response_rejects_mismatched_usage_totals() {
    let err = agent_runtime_validate_llm_response(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "content": "hello",
          "finish_reason": "stop",
          "usage": {
            "input_tokens": 2,
            "output_tokens": 3,
            "total_tokens": 4
          }
        }"#
        .to_owned(),
    )
    .expect_err("mismatched usage totals should fail");

    assert!(err.to_string().contains("usage.total_tokens"));
}

#[test]
fn validate_llm_request_rejects_malformed_required_fields() {
    let provider_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}]
        }"#
        .to_owned(),
    )
    .expect_err("empty provider should fail");
    assert!(provider_err.to_string().contains("provider"));

    let model_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "",
          "messages": [{"role": "user", "content": "hello"}]
        }"#
        .to_owned(),
    )
    .expect_err("empty model should fail");
    assert!(model_err.to_string().contains("model"));

    let messages_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": []
        }"#
        .to_owned(),
    )
    .expect_err("empty messages should fail");
    assert!(messages_err.to_string().contains("messages"));
}

#[test]
fn validate_llm_request_rejects_invalid_generation_limits() {
    let temperature_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}],
          "temperature": -0.1
        }"#
        .to_owned(),
    )
    .expect_err("negative temperature should fail");
    assert!(temperature_err.to_string().contains("temperature"));

    let max_tokens_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}],
          "max_output_tokens": 0
        }"#
        .to_owned(),
    )
    .expect_err("zero max output tokens should fail");
    assert!(max_tokens_err.to_string().contains("max_output_tokens"));
}

#[test]
fn validate_llm_request_rejects_malformed_metadata_fields() {
    let request_metadata_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}],
          "metadata": []
        }"#
        .to_owned(),
    )
    .expect_err("non-object request metadata should fail");
    assert!(request_metadata_err.to_string().contains("metadata"));

    let message_metadata_err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello", "metadata": []}]
        }"#
        .to_owned(),
    )
    .expect_err("non-object message metadata should fail");
    assert!(
        message_metadata_err
            .to_string()
            .contains("messages[0].metadata")
    );
}

#[test]
fn validate_llm_request_rejects_malformed_tool_spec() {
    let err = agent_runtime_validate_llm_request(
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "hello"}],
          "tools": [{
            "name": "emit",
            "description": "",
            "input_schema": {"type": "object"},
            "risk": "read_only"
          }]
        }"#
        .to_owned(),
    )
    .expect_err("LLM request with malformed tool spec should fail");

    assert!(err.to_string().contains("LLM request tools[0].description"));
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
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/llm-request.valid.json"
        )
        .to_owned(),
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
async fn complete_mock_llm_rejects_mismatched_protocol_version() {
    let err = agent_runtime_complete_mock_llm(
        r#"{
          "protocol_version": "agent.v0",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "ping"}]
        }"#
        .to_owned(),
        "pong".to_owned(),
    )
    .await
    .expect_err("mismatched mock LLM request protocol should fail");

    assert!(err.to_string().contains("protocol_version"));
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
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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

#[tokio::test]
async fn start_profile_turn_step_normalizes_null_run_metadata() {
    let turn_json = agent_runtime_start_profile_turn_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "ping"}],
          "metadata": {"mock_response": "native turn response"}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
        "null".to_owned(),
    )
    .await
    .expect("null run metadata should normalize");
    let turn: Value = serde_json::from_str(&turn_json).expect("turn should be json");

    assert_eq!(
        turn["step"]["output"]["llm_response"]["content"],
        "native turn response"
    );
}

#[tokio::test]
async fn start_profile_turn_step_rejects_non_object_run_metadata() {
    let err = agent_runtime_start_profile_turn_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "provider": "mock",
          "model": "mock-model",
          "messages": [{"role": "user", "content": "ping"}],
          "metadata": {"mock_response": "native turn response"}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
        "[]".to_owned(),
    )
    .await
    .expect_err("non-object run metadata should fail");

    assert!(err.to_string().contains("run metadata"));
}

#[test]
fn start_run_step_requests_catalog_tool_call() {
    let step_json = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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
    assert_eq!(step["run_state"]["status"], "tool_call_requested");
    assert_eq!(step["run_state"]["step_index"], 0);
    assert_eq!(step["run_state"]["remaining_tool_count"], 0);
    assert_eq!(step["run_state"]["tool_result_count"], 0);
    assert!(step["run_state"]["terminal_reason"].is_null());
    assert_eq!(step["trace_event"]["status"], "tool_call_requested");
    assert_eq!(step["trace_event"]["tool_name"], "propose_fake");
}

#[test]
fn start_run_step_rejects_empty_tool_call_name() {
    let err = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "input": {
            "tool_call": {
              "name": "",
              "input": {"value": 7}
            }
          },
          "trigger": "manual",
          "metadata": {}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("empty tool call name should fail");

    assert!(err.to_string().contains("tool_call.name"));
}

#[test]
fn start_run_step_rejects_non_object_run_request_input() {
    let err = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "input": "bad",
          "trigger": "manual",
          "metadata": {}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("non-object run request input should fail");

    assert!(err.to_string().contains("run request input"));
}

#[test]
fn start_run_step_rejects_mismatched_run_request_protocol_version() {
    let err = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v0",
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
    .expect_err("mismatched run request protocol should fail");

    assert!(err.to_string().contains("protocol_version"));
}

#[test]
fn start_run_step_rejects_mismatched_catalog_contract() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["protocol_version"] = json!("agent.v0");

    let err = agent_runtime_start_run_step(
        catalog.to_string(),
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
    .expect_err("mismatched catalog protocol should fail");

    assert!(err.to_string().contains("catalog protocol_version"));
}

#[test]
fn start_run_step_seeds_native_tool_plan_continuation() {
    let step_json = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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
    assert_eq!(step["run_state"]["status"], "tool_call_requested");
    assert_eq!(step["run_state"]["remaining_tool_count"], 1);
    assert_eq!(step["run_state"]["tool_result_count"], 0);
    assert!(step["run_state"]["terminal_reason"].is_null());
}

#[test]
fn start_run_step_rejects_non_object_tool_plan_item() {
    let err = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "input": {
            "tool_plan": [
              "bad"
            ]
          },
          "trigger": "manual",
          "metadata": {}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("non-object tool plan item should fail");

    assert!(err.to_string().contains("tool_plan[0]"));
}

#[test]
fn start_run_step_rejects_unknown_remaining_tool_plan_item() {
    let err = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "input": {
            "tool_plan": [
              {"name": "propose_fake", "input": {"value": 1}},
              {"name": "unknown_tool", "input": {"value": 2}}
            ]
          },
          "trigger": "manual",
          "metadata": {}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("unknown remaining tool plan item should fail at start");

    assert!(err.to_string().contains("continuation.tool_plan[0]"));
}

#[test]
fn start_run_step_rejects_non_object_tool_call_input() {
    let err = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "input": {
            "tool_call": {
              "name": "propose_fake",
              "input": "bad"
            }
          },
          "trigger": "manual",
          "metadata": {}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("non-object tool_call input should fail");

    assert!(err.to_string().contains("tool_call.input"));
}

#[test]
fn native_step_trace_events_validate_as_agent_trace_payloads() {
    let first_json = agent_runtime_start_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000123",
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
    let first: Value = serde_json::from_str(&first_json).expect("first step should be json");

    let terminal_json = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        first.to_string(),
        json!({
            "jsonrpc": "2.0",
            "id": first["tool_call"]["tool_call_id"].clone(),
            "result": {"accepted": true}
        })
        .to_string(),
        "execution_review".to_owned(),
    )
    .expect("continue step should accept tool result");
    let terminal: Value =
        serde_json::from_str(&terminal_json).expect("terminal step should be json");

    let trace = json!({
        "protocol_version": "agent.v1",
        "runtime_version": "0.1.0",
        "run_id": "run_018f0000-0000-7000-8000-000000000123",
        "agent_id": "execution_review",
        "agent_version": "0.1.0",
        "started_at": "2026-06-28T09:12:31Z",
        "finished_at": "2026-06-28T09:12:32Z",
        "input": {"tool_call": {"name": "propose_fake", "input": {"value": 7}}},
        "output": terminal["output"].clone(),
        "events": [
            {
                "kind": "run_started",
                "occurred_at": "2026-06-28T09:12:31Z",
                "payload": {"agent_id": "execution_review"}
            },
            {
                "kind": "agent_runtime_step",
                "occurred_at": "2026-06-28T09:12:31Z",
                "payload": first["trace_event"].clone()
            },
            {
                "kind": "agent_runtime_step",
                "occurred_at": "2026-06-28T09:12:32Z",
                "payload": terminal["trace_event"].clone()
            }
        ]
    });

    let normalized = agent_runtime_validate_trace(trace.to_string())
        .expect("native step trace events should satisfy AgentTrace contract");
    let normalized: Value = serde_json::from_str(&normalized).expect("trace should be json");
    assert_eq!(
        normalized["events"][1]["payload"]["status"],
        "tool_call_requested"
    );
    assert_eq!(
        normalized["events"][1]["payload"]["run_state"]["terminal_reason"],
        Value::Null
    );
    assert_eq!(normalized["events"][2]["payload"]["status"], "completed");
    assert_eq!(
        normalized["events"][2]["payload"]["run_state"]["terminal_reason"],
        "done"
    );
}

#[test]
fn continue_run_step_completes_with_tool_result() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 7}
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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
    assert_eq!(next["run_state"]["status"], "completed");
    assert_eq!(next["run_state"]["terminal_reason"], "done");
    assert_eq!(next["run_state"]["remaining_tool_count"], 0);
    assert_eq!(next["run_state"]["tool_result_count"], 1);
    assert_eq!(next["trace_event"]["status"], "completed");
    assert_eq!(next["trace_event"]["tool_name"], "propose_fake");
}

#[test]
fn continue_run_step_rejects_non_object_previous_tool_call_input() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
            "name": "propose_fake",
            "input": "bad"
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_018f0000-0000-7000-8000-000000000000",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("non-object previous tool_call input should fail");

    assert!(err.to_string().contains("previous step tool_call.input"));
}

#[test]
fn continue_run_step_rejects_mismatched_catalog_contract() {
    let mut catalog: Value = serde_json::from_str(include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
    ))
    .expect("catalog fixture should be json");
    catalog["catalog_version"] = json!("agent_catalog.v0");

    let err = agent_runtime_continue_run_step(
        catalog.to_string(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched catalog version should fail");

    assert!(err.to_string().contains("catalog_version"));
}

#[test]
fn continue_run_step_requests_next_native_tool_plan_item() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 1}
      },
      "continuation": {
        "next_step_index": 1,
        "tool_plan": [
          {"name": "propose_fake", "input": {"value": 2}}
        ],
        "tool_results": [],
        "llm_response": {"content": "use two tools"}
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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
    assert_eq!(next["run_state"]["status"], "tool_call_requested");
    assert_eq!(next["run_state"]["step_index"], 1);
    assert_eq!(next["run_state"]["remaining_tool_count"], 0);
    assert_eq!(next["run_state"]["tool_result_count"], 1);
    assert!(next["run_state"]["terminal_reason"].is_null());
    assert_eq!(next["trace_event"]["status"], "tool_call_requested");
    assert_eq!(next["trace_event"]["tool_name"], "propose_fake");
}

#[test]
fn continue_run_step_rejects_unknown_remaining_tool_plan_item() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 1}
      },
      "continuation": {
        "next_step_index": 1,
        "tool_plan": [
          {"name": "propose_fake", "input": {"value": 2}},
          {"name": "unknown_tool", "input": {"value": 3}}
        ],
        "tool_results": []
      }
    }"#
        .to_owned(),
        r#"{
      "jsonrpc": "2.0",
      "id": "tool_018f0000-0000-7000-8000-000000000000",
      "result": {"accepted": true, "value": 1}
    }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("unknown remaining continuation tool plan item should fail");

    assert!(err.to_string().contains("continuation.tool_plan[0]"));
}

#[test]
fn continue_run_step_rejects_invalid_continuation_tool_plan_type() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 1}
      },
      "continuation": {
        "next_step_index": 1,
        "tool_plan": {"name": "propose_fake"},
        "tool_results": []
      }
    }"#
        .to_owned(),
        r#"{
      "jsonrpc": "2.0",
      "id": "tool_018f0000-0000-7000-8000-000000000000",
      "result": {"accepted": true, "value": 1}
    }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("invalid continuation tool_plan should fail");

    assert!(err.to_string().contains("continuation.tool_plan"));
}

#[test]
fn continue_run_step_rejects_missing_next_tool_plan_name() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 1}
      },
      "continuation": {
        "next_step_index": 1,
        "tool_plan": [
          {"input": {"value": 2}}
        ],
        "tool_results": []
      }
    }"#
        .to_owned(),
        r#"{
      "jsonrpc": "2.0",
      "id": "tool_018f0000-0000-7000-8000-000000000000",
      "result": {"accepted": true, "value": 1}
    }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("missing next tool plan name should fail");

    assert!(err.to_string().contains("continuation.tool_plan[0].name"));
}

#[test]
fn continue_run_step_completes_native_tool_plan_after_last_item() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000001",
        "name": "propose_fake",
        "input": {"value": 2}
      },
      "continuation": {
        "next_step_index": 1,
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
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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
    assert_eq!(next["run_state"]["status"], "completed");
    assert_eq!(next["run_state"]["terminal_reason"], "done");
    assert_eq!(next["run_state"]["remaining_tool_count"], 0);
    assert_eq!(next["run_state"]["tool_result_count"], 2);
    assert_eq!(next["trace_event"]["status"], "completed");
    assert_eq!(next["trace_event"]["tool_name"], "propose_fake");
}

#[test]
fn continue_run_step_fails_with_tool_error() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 7}
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
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
    assert_eq!(next["tool_results"].as_array().unwrap().len(), 1);
    assert_eq!(
        next["tool_results"][0]["tool_response"]["error"]["message"],
        "tool failed"
    );
    assert_eq!(next["run_state"]["status"], "failed");
    assert_eq!(next["run_state"]["terminal_reason"], "stream_error");
    assert_eq!(next["run_state"]["tool_result_count"], 1);
    assert_eq!(next["trace_event"]["status"], "failed");
    assert_eq!(next["trace_event"]["tool_name"], "propose_fake");
}

#[test]
fn continue_run_step_rejects_mismatched_tool_response_id() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_wrong",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched tool response id should fail");

    assert!(err.to_string().contains("tool response id"));
}

#[test]
fn continue_run_step_rejects_invalid_tool_response_jsonrpc() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "1.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("invalid JSON-RPC version should fail");

    assert!(err.to_string().contains("jsonrpc"));
}

#[test]
fn continue_run_step_rejects_non_object_tool_response() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#""bad""#.to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("non-object tool response should fail");

    assert!(err.to_string().contains("tool response must be an object"));
}

#[test]
fn continue_run_step_rejects_empty_previous_run_id() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("empty previous run id should fail");

    assert!(err.to_string().contains("run_id"));
}

#[test]
fn continue_run_step_rejects_missing_previous_step_index() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("missing previous step index should fail");

    assert!(err.to_string().contains("step_index"));
}

#[test]
fn continue_run_step_rejects_tool_response_with_result_and_error() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true},
          "error": {"code": -32000, "message": "also failed"}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("ambiguous tool response should fail");

    assert!(err.to_string().contains("both result and error"));
}

#[test]
fn continue_run_step_rejects_jsonrpc_tool_response_with_non_object_error() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "error": "failed"
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("JSON-RPC tool response with non-object error should fail");

    assert!(err.to_string().contains("error must be an object"));
}

#[test]
fn continue_run_step_rejects_jsonrpc_tool_response_error_without_code() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "error": {"message": "failed"}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("JSON-RPC tool response error without code should fail");

    assert!(err.to_string().contains("error.code must be an integer"));
}

#[test]
fn continue_run_step_rejects_jsonrpc_tool_response_error_with_non_integer_code() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "error": {"code": "failed", "message": "failed"}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("JSON-RPC tool response error with non-integer code should fail");

    assert!(err.to_string().contains("error.code must be an integer"));
}

#[test]
fn continue_run_step_rejects_jsonrpc_tool_response_error_without_message() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "error": {"code": -32000}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("JSON-RPC tool response error without message should fail");

    assert!(err.to_string().contains("error.message must be a string"));
}

#[test]
fn continue_run_step_rejects_jsonrpc_tool_response_error_with_non_string_message() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "error": {"code": -32000, "message": 11}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("JSON-RPC tool response error with non-string message should fail");

    assert!(err.to_string().contains("error.message must be a string"));
}

#[test]
fn continue_run_step_rejects_jsonrpc_tool_response_without_id() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("JSON-RPC tool response without id should fail");

    assert!(err.to_string().contains("id is required"));
}

#[test]
fn continue_run_step_rejects_jsonrpc_tool_response_without_result_or_error() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected"
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("JSON-RPC tool response without result or error should fail");

    assert!(err.to_string().contains("result or error"));
}

#[test]
fn continue_run_step_rejects_mismatched_previous_agent() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "other_agent",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched previous agent should fail");

    assert!(err.to_string().contains("previous step agent_id"));
}

#[test]
fn continue_run_step_rejects_missing_previous_protocol_version() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("missing previous protocol version should fail");

    assert!(err.to_string().contains("protocol_version"));
}

#[test]
fn continue_run_step_rejects_mismatched_previous_protocol_version() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v0",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched previous protocol version should fail");

    assert!(err.to_string().contains("protocol_version"));
}

#[test]
fn continue_run_step_rejects_mismatched_previous_agent_version() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "old-version",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched previous agent version should fail");

    assert!(err.to_string().contains("agent_version"));
}

#[test]
fn continue_run_step_rejects_missing_previous_agent_version() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("missing previous agent version should fail");

    assert!(err.to_string().contains("agent_version"));
}

#[test]
fn continue_run_step_rejects_previous_tool_not_in_catalog() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_unknown",
            "name": "unknown_tool",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_unknown",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("unknown previous tool should fail");

    assert!(err.to_string().contains("not present in the catalog"));
}

#[test]
fn continue_run_step_rejects_missing_previous_tool_name() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_missing_name",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_missing_name",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("missing previous tool name should fail");

    assert!(err.to_string().contains("tool_call.name"));
}

#[test]
fn continue_run_step_rejects_missing_previous_tool_call_id() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_missing",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("missing previous tool_call_id should fail");

    assert!(err.to_string().contains("tool_call_id"));
}

#[test]
fn continue_run_step_rejects_empty_previous_tool_call_id() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "",
            "name": "propose_fake",
            "input": {"value": 7}
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_missing",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("empty previous tool_call_id should fail");

    assert!(err.to_string().contains("tool_call_id"));
}

#[test]
fn continue_run_step_rejects_mismatched_previous_run_state() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          },
          "run_state": {
            "status": "completed",
            "step_index": 0,
            "remaining_tool_count": 0,
            "tool_result_count": 0,
            "terminal_reason": "done"
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched previous run_state should fail");

    assert!(err.to_string().contains("run_state"));
}

#[test]
fn continue_run_step_rejects_mismatched_previous_trace_event() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          },
          "trace_event": {
            "kind": "agent_runtime_step",
            "run_id": "run_wrong",
            "agent_id": "execution_review",
            "status": "tool_call_requested",
            "step_index": 0,
            "tool_name": "propose_fake"
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched previous trace_event should fail");

    assert!(err.to_string().contains("run_id"));
}

#[test]
fn continue_run_step_rejects_mismatched_continuation_next_step_index() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 3,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          },
          "continuation": {
            "next_step_index": 2,
            "tool_plan": [
              {"name": "propose_fake", "input": {"value": 8}}
            ],
            "tool_results": []
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched continuation next step index should fail");

    assert!(err.to_string().contains("next_step_index"));
}

#[test]
fn continue_run_step_rejects_invalid_continuation_next_step_index() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 3,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          },
          "continuation": {
            "next_step_index": "4",
            "tool_plan": [
              {"name": "propose_fake", "input": {"value": 8}}
            ],
            "tool_results": []
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("invalid continuation next step index should fail");

    assert!(err.to_string().contains("non-negative integer"));
}

#[test]
fn continue_run_step_rejects_missing_continuation_next_step_index() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          },
          "continuation": {
            "tool_plan": [
              {"name": "propose_fake", "input": {"value": 8}}
            ],
            "tool_results": []
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("missing continuation next step index should fail");

    assert!(err.to_string().contains("next_step_index"));
}

#[test]
fn continue_run_step_rejects_non_object_continuation() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 7}
          },
          "continuation": "bad"
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("non-object continuation should fail");

    assert!(err.to_string().contains("continuation must be an object"));
}

#[test]
fn continue_run_step_rejects_invalid_continuation_tool_result_item() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 2}
          },
          "continuation": {
        "next_step_index": 1,
            "tool_plan": [],
            "tool_results": ["bad"]
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("invalid historical tool result should fail");

    assert!(err.to_string().contains("tool_results[0]"));
}

#[test]
fn continue_run_step_rejects_historical_tool_result_without_response() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 2}
          },
          "continuation": {
        "next_step_index": 1,
            "tool_plan": [],
            "tool_results": [
              {"tool_call": {"name": "propose_fake", "input": {"value": 1}}}
            ]
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("historical tool result without response should fail");

    assert!(err.to_string().contains("tool_response"));
}

#[test]
fn continue_run_step_rejects_historical_tool_response_with_bad_envelope() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 2}
          },
          "continuation": {
        "next_step_index": 1,
            "tool_plan": [],
            "tool_results": [
              {
                "tool_call": {"name": "propose_fake", "input": {"value": 1}},
                "tool_response": {
                  "jsonrpc": "2.0",
                  "id": "historical",
                  "result": {"accepted": true},
                  "error": {"code": -32000, "message": "ambiguous"}
                }
              }
            ]
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("invalid historical tool response envelope should fail");

    assert!(err.to_string().contains("tool_results[0].tool_response"));
    assert!(err.to_string().contains("both result and error"));
}

#[test]
fn continue_run_step_rejects_mismatched_historical_tool_response_id() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 2}
          },
          "continuation": {
        "next_step_index": 1,
            "tool_plan": [],
            "tool_results": [
              {
                "tool_call": {
                  "tool_call_id": "historical_expected",
                  "name": "propose_fake",
                  "input": {"value": 1}
                },
                "tool_response": {
                  "jsonrpc": "2.0",
                  "id": "historical_wrong",
                  "result": {"accepted": true}
                }
              }
            ]
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("mismatched historical tool response id should fail");

    assert!(err.to_string().contains("tool_results[0].tool_response"));
    assert!(err.to_string().contains("tool response id"));
}

#[test]
fn continue_run_step_rejects_historical_tool_not_in_catalog() {
    let err = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        r#"{
          "protocol_version": "agent.v1",
          "run_id": "run_018f0000-0000-7000-8000-000000000000",
          "agent_id": "execution_review",
          "agent_version": "0.1.0",
          "step_index": 0,
          "status": "tool_call_requested",
          "tool_call": {
            "tool_call_id": "tool_expected",
            "name": "propose_fake",
            "input": {"value": 2}
          },
          "continuation": {
        "next_step_index": 1,
            "tool_plan": [],
            "tool_results": [
              {
                "tool_call": {"name": "unknown_tool", "input": {"value": 1}},
                "tool_response": {"result": {"accepted": true}}
              }
            ]
          }
        }"#
        .to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_expected",
          "result": {"accepted": true}
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect_err("historical unknown tool should fail");

    assert!(err.to_string().contains("not present in the catalog"));
}

#[test]
fn continue_run_step_maps_result_payload_policy_denied() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
          "step_index": 0,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000000",
        "name": "propose_fake",
        "input": {"value": 7}
      }
    }"#;
    let next_json = agent_runtime_continue_run_step(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        step_json.to_owned(),
        r#"{
          "jsonrpc": "2.0",
          "id": "tool_018f0000-0000-7000-8000-000000000000",
          "result": {
            "error": {
              "code": "policy_denied",
              "policy": "confirmation_required",
              "tool": "propose_fake",
              "message": "confirmation required"
            },
            "policy_denied": true
          }
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("policy-denied result payload should terminate as policy_denied");
    let next: Value = serde_json::from_str(&next_json).expect("next step should be json");

    assert_eq!(next["status"], "policy_denied");
    assert_eq!(next["error"]["code"], "policy_denied");
    assert_eq!(next["tool_results"].as_array().unwrap().len(), 1);
    assert_eq!(next["run_state"]["status"], "policy_denied");
    assert_eq!(next["run_state"]["terminal_reason"], "policy_denied");
    assert_eq!(next["run_state"]["tool_result_count"], 1);
    assert_eq!(next["trace_event"]["status"], "policy_denied");
    assert_eq!(next["trace_event"]["tool_name"], "propose_fake");
}

#[test]
fn continue_run_step_closes_early_on_tool_budget_exhaustion() {
    let step_json = r#"{
      "protocol_version": "agent.v1",
      "run_id": "run_018f0000-0000-7000-8000-000000000000",
      "agent_id": "execution_review",
      "agent_version": "0.1.0",
      "step_index": 1,
      "status": "tool_call_requested",
      "tool_call": {
        "tool_call_id": "tool_018f0000-0000-7000-8000-000000000001",
        "name": "propose_fake",
        "input": {"value": 2}
      },
      "continuation": {
        "next_step_index": 2,
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
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json"
        )
        .to_owned(),
        step_json.to_owned(),
        r#"{
          "error": {
            "code": "tool_call_budget_exhausted",
            "message": "agent runtime tool-call budget exhausted",
            "max_tool_steps": 1,
            "dispatched_tool_count": 1
          }
        }"#
        .to_owned(),
        "execution_review".to_owned(),
    )
    .expect("budget exhaustion should close the native step early");
    let next: Value = serde_json::from_str(&next_json).expect("next step should be json");

    assert_eq!(next["status"], "closed_early");
    assert_eq!(next["error"]["code"], "tool_call_budget_exhausted");
    assert_eq!(next["tool_results"].as_array().unwrap().len(), 1);
    assert_eq!(next["run_state"]["status"], "closed_early");
    assert_eq!(next["run_state"]["terminal_reason"], "closed_early");
    assert_eq!(next["run_state"]["remaining_tool_count"], 0);
    assert_eq!(next["run_state"]["tool_result_count"], 1);
    assert_eq!(next["trace_event"]["status"], "closed_early");
    assert_eq!(next["trace_event"]["tool_name"], "propose_fake");
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
