use super::chat::{
    ChatTurnEnvelope, chat_turn_error_event, chat_turn_event_from_llm_event,
    chat_turn_finished_events,
};
use super::contracts::normalize_llm_event_contract;
use super::*;

fn catalog_json() -> String {
    json!({
        "protocol_version": "agent.v1",
        "catalog_version": "agent_catalog.v1",
        "generated_at": "2026-06-29T00:00:00Z",
        "agents": [
            {
                "protocol_version": "agent.v1",
                "id": "execution_review",
                "name": "Execution Review",
                "version": "0.1.0",
                "schedule": {"type": "manual"},
                "capabilities": ["scheduled_agent"],
                "metadata": {"domain": "execution"}
            }
        ],
        "tools": [
            {
                "name": "read_first",
                "description": "Read first",
                "input_schema": {"type": "object"},
                "risk": "read_only",
                "metadata": {}
            },
            {
                "name": "read_second",
                "description": "Read second",
                "input_schema": {"type": "object"},
                "risk": "read_only",
                "metadata": {}
            }
        ],
        "proposal_kinds": [],
        "prompt_blocks": []
    })
    .to_string()
}

#[test]
fn chat_turn_event_wraps_llm_event_with_envelope() {
    let envelope = ChatTurnEnvelope {
        turn_id: Some("turn_1".to_owned()),
        session_id: Some("session_1".to_owned()),
        thread_id: Some("thread_1".to_owned()),
        surface: Some("ai_chat".to_owned()),
        agent_id: Some("ai_chat".to_owned()),
        mode: Some("chat".to_owned()),
    };
    let event = LlmEvent {
        kind: agent_llm::LlmEventKind::Delta,
        content: Some("done".to_owned()),
        response: None,
        tool_call_id: None,
        tool_name: None,
        partial_input_json: None,
        tool_input: None,
        metadata: json!({"stream": true}),
    };

    let value = chat_turn_event_from_llm_event(&envelope, event).expect("event wraps");

    assert_eq!(value["protocol_version"], "agent.v1");
    assert_eq!(value["turn_id"], "turn_1");
    assert_eq!(value["session_id"], "session_1");
    assert_eq!(value["thread_id"], "thread_1");
    assert_eq!(value["surface"], "ai_chat");
    assert_eq!(value["agent_id"], "ai_chat");
    assert_eq!(value["mode"], "chat");
    assert_eq!(value["kind"], "delta");
    assert_eq!(value["round"], 1);
    assert_eq!(value["content"], "done");
}

#[test]
fn chat_turn_finished_event_expands_to_chat_turn_events() {
    let envelope = ChatTurnEnvelope {
        turn_id: Some("turn_1".to_owned()),
        session_id: Some("session_1".to_owned()),
        thread_id: Some("thread_1".to_owned()),
        surface: Some("ai_chat".to_owned()),
        agent_id: Some("ai_chat".to_owned()),
        mode: Some("chat".to_owned()),
    };
    let event = LlmEvent {
        kind: agent_llm::LlmEventKind::Finished,
        content: None,
        response: Some(LlmResponse {
            protocol_version: protocol_version(),
            provider: "mock".to_owned(),
            model: "mock-model".to_owned(),
            content: "done".to_owned(),
            finish_reason: agent_llm::LlmFinishReason::Stop,
            object: None,
            usage: Some(agent_llm::LlmUsage {
                input_tokens: 1,
                output_tokens: 2,
                total_tokens: 3,
            }),
            metadata: json!({}),
        }),
        tool_call_id: None,
        tool_name: None,
        partial_input_json: None,
        tool_input: None,
        metadata: json!({"stream": true}),
    };

    let values = chat_turn_finished_events(&envelope, event).expect("event expands");

    assert_eq!(values.len(), 3);
    assert_eq!(values[0]["kind"], "usage");
    assert_eq!(values[0]["usage"]["total_tokens"], 3);
    assert_eq!(values[1]["kind"], "round_finished");
    assert_eq!(values[1]["response"]["content"], "done");
    assert_eq!(values[2]["kind"], "done");
    assert_eq!(values[2]["metadata"]["stop_reason"], "end_turn");
}

#[test]
fn chat_turn_error_event_wraps_error_metadata() {
    let envelope = ChatTurnEnvelope {
        turn_id: Some("turn_1".to_owned()),
        session_id: None,
        thread_id: None,
        surface: None,
        agent_id: None,
        mode: None,
    };

    let value = chat_turn_error_event(
        &envelope,
        json!({"code": "provider_error", "message": "bad key"}),
    );

    assert_eq!(value["protocol_version"], "agent.v1");
    assert_eq!(value["turn_id"], "turn_1");
    assert_eq!(value["kind"], "error");
    assert_eq!(value["metadata"]["code"], "provider_error");
}

#[test]
fn native_effect_plan_steps_own_step_index_and_trace_events() {
    let request_json = json!({
        "protocol_version": "agent.v1",
        "run_id": "run_native_trace",
        "input": {
            "effects": [
                {"kind": "tool", "name": "read_first", "input": {"id": "first"}},
                {"kind": "tool", "name": "read_second", "input": {"id": "second"}}
            ]
        },
        "trigger": "manual",
        "metadata": {}
    })
    .to_string();

    let first: Value = serde_json::from_str(
        &agent_runtime_start_run_step(catalog_json(), request_json, "execution_review".to_owned())
            .expect("start step"),
    )
    .expect("first step json");
    assert_eq!(first["status"], "effect_requested");
    assert_eq!(first["step_index"], 0);
    assert_eq!(first["effect"]["kind"], "tool");
    assert_eq!(first["effect"]["name"], "read_first");
    assert_eq!(first["trace_event"]["kind"], "agent_runtime_step");
    assert_eq!(first["trace_event"]["step_index"], 0);
    assert_eq!(first["trace_event"]["effect_kind"], "tool");
    assert_eq!(first["trace_event"]["tool_name"], "read_first");
    assert_eq!(
        first["trace_event"]["run_state"]["remaining_effect_count"],
        1
    );
    assert_eq!(first["trace_event"]["run_state"]["effect_result_count"], 0);
    assert_eq!(first["run_state"]["remaining_effect_count"], 1);
    assert_eq!(first["run_state"]["effect_result_count"], 0);
    assert_eq!(first["run_state"]["terminal_reason"], Value::Null);
    let first_effect_id = first["effect"]["effect_id"]
        .as_str()
        .expect("first effect_id")
        .to_owned();

    let second: Value = serde_json::from_str(
        &agent_runtime_continue_run_step(
            catalog_json(),
            first.to_string(),
            json!({"jsonrpc": "2.0", "id": first_effect_id, "result": {"ok": true}}).to_string(),
            "execution_review".to_owned(),
        )
        .expect("second step"),
    )
    .expect("second step json");
    assert_eq!(second["status"], "effect_requested");
    assert_eq!(second["step_index"], 1);
    assert_eq!(second["effect"]["kind"], "tool");
    assert_eq!(second["effect"]["name"], "read_second");
    assert_eq!(second["trace_event"]["step_index"], 1);
    assert_eq!(second["trace_event"]["effect_kind"], "tool");
    assert_eq!(second["trace_event"]["tool_name"], "read_second");
    assert_eq!(
        second["trace_event"]["run_state"]["remaining_effect_count"],
        0
    );
    assert_eq!(second["trace_event"]["run_state"]["effect_result_count"], 1);
    assert_eq!(second["run_state"]["remaining_effect_count"], 0);
    assert_eq!(second["run_state"]["effect_result_count"], 1);
    assert_eq!(second["run_state"]["terminal_reason"], Value::Null);
    let second_effect_id = second["effect"]["effect_id"]
        .as_str()
        .expect("second effect_id")
        .to_owned();

    let terminal: Value = serde_json::from_str(
        &agent_runtime_continue_run_step(
            catalog_json(),
            second.to_string(),
            json!({"jsonrpc": "2.0", "id": second_effect_id, "result": {"done": true}}).to_string(),
            "execution_review".to_owned(),
        )
        .expect("terminal step"),
    )
    .expect("terminal step json");
    assert_eq!(terminal["status"], "completed");
    assert_eq!(terminal["step_index"], 2);
    assert_eq!(terminal["trace_event"]["step_index"], 2);
    assert_eq!(terminal["trace_event"]["tool_name"], "read_second");
    assert_eq!(
        terminal["trace_event"]["run_state"]["terminal_reason"],
        "done"
    );
    assert_eq!(
        terminal["trace_event"]["run_state"]["effect_result_count"],
        2
    );
    assert_eq!(terminal["output"]["mode"], "frb_effect_loop");
    assert_eq!(terminal["run_state"]["remaining_effect_count"], 0);
    assert_eq!(terminal["run_state"]["effect_result_count"], 2);
    assert_eq!(terminal["run_state"]["terminal_reason"], "done");
}

#[test]
fn native_effect_response_errors_set_stream_error_terminal_reason() {
    let request_json = json!({
        "protocol_version": "agent.v1",
        "run_id": "run_native_error_trace",
        "input": {
            "effects": [
                {"kind": "tool", "name": "read_first", "input": {"id": "first"}}
            ]
        },
        "trigger": "manual",
        "metadata": {}
    })
    .to_string();

    let first: Value = serde_json::from_str(
        &agent_runtime_start_run_step(catalog_json(), request_json, "execution_review".to_owned())
            .expect("start step"),
    )
    .expect("first step json");
    let first_effect_id = first["effect"]["effect_id"]
        .as_str()
        .expect("first effect_id")
        .to_owned();

    let failed: Value = serde_json::from_str(
        &agent_runtime_continue_run_step(
            catalog_json(),
            first.to_string(),
            json!({
                "jsonrpc": "2.0",
                "id": first_effect_id,
                "error": {"code": -32000, "message": "no"}
            })
            .to_string(),
            "execution_review".to_owned(),
        )
        .expect("failed step"),
    )
    .expect("failed step json");

    assert_eq!(failed["status"], "failed");
    assert_eq!(failed["trace_event"]["status"], "failed");
    assert_eq!(
        failed["trace_event"]["run_state"]["terminal_reason"],
        "stream_error"
    );
    assert_eq!(failed["trace_event"]["run_state"]["effect_result_count"], 1);
    assert_eq!(failed["run_state"]["terminal_reason"], "stream_error");
}

#[test]
fn llm_stream_event_contract_normalizes_metadata() {
    let mut event = LlmEvent {
        kind: agent_llm::LlmEventKind::Delta,
        content: Some("hello".to_owned()),
        response: None,
        tool_call_id: None,
        tool_name: None,
        partial_input_json: None,
        tool_input: None,
        metadata: Value::Null,
    };

    normalize_llm_event_contract(&mut event).expect("event should normalize");

    assert_eq!(event.metadata, json!({}));
}

#[test]
fn llm_stream_event_contract_validates_finished_response() {
    let mut event = LlmEvent {
        kind: agent_llm::LlmEventKind::Finished,
        content: None,
        response: Some(LlmResponse {
            protocol_version: protocol_version(),
            provider: "mock".to_owned(),
            model: "mock-model".to_owned(),
            content: "hello".to_owned(),
            finish_reason: agent_llm::LlmFinishReason::Stop,
            object: None,
            usage: Some(agent_llm::LlmUsage {
                input_tokens: 2,
                output_tokens: 3,
                total_tokens: 4,
            }),
            metadata: json!({}),
        }),
        tool_call_id: None,
        tool_name: None,
        partial_input_json: None,
        tool_input: None,
        metadata: json!({}),
    };

    let err = normalize_llm_event_contract(&mut event)
        .expect_err("mismatched finished usage should fail");

    assert!(err.to_string().contains("usage.total_tokens"));
}
