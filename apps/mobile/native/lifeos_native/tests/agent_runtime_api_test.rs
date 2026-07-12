use lifeos_native::api::agent_runtime::{
    agent_runtime_cancel_run_snapshot, agent_runtime_catalog_summary,
    agent_runtime_complete_mock_llm, agent_runtime_continue_run_snapshot,
    agent_runtime_protocol_version, agent_runtime_resume_parent_from_subagent_snapshot,
    agent_runtime_start_profile_turn_snapshot, agent_runtime_start_requested_subagent_snapshot,
    agent_runtime_start_run_snapshot, agent_runtime_validate_chat_turn_request,
    agent_runtime_validate_llm_request, agent_runtime_validate_llm_response,
    agent_runtime_validate_run_request, agent_runtime_validate_tool_spec,
    agent_runtime_validate_trace,
};
use serde_json::{Value, json};

fn catalog_json() -> String {
    include_str!("../../../../../third_party/agent-runtime/fixtures/contracts/catalog.valid.json")
        .to_owned()
}

fn run_request(input: Value) -> String {
    json!({
        "protocol_version": "agent.v1",
        "run_id": "run_native_test",
        "input": input,
        "metadata": {},
    })
    .to_string()
}

fn requested_effect(snapshot: &Value) -> &Value {
    &snapshot["step"]["effect"]
}

fn continue_snapshot(snapshot: &Value, result: Value) -> Value {
    let response = json!({
        "jsonrpc": "2.0",
        "id": requested_effect(snapshot)["effect_id"],
        "result": result,
    });
    let value = agent_runtime_continue_run_snapshot(
        catalog_json(),
        snapshot.to_string(),
        response.to_string(),
        "ai_chat".to_owned(),
    )
    .expect("snapshot continues");
    serde_json::from_str(&value).expect("snapshot json")
}

#[test]
fn exposes_protocol_and_catalog_summary() {
    assert_eq!(agent_runtime_protocol_version(), "agent.v1");
    let summary: Value = serde_json::from_str(
        &agent_runtime_catalog_summary(catalog_json()).expect("catalog summary"),
    )
    .expect("summary json");
    assert_eq!(summary["protocol_version"], "agent.v1");
    assert_eq!(summary["catalog_version"], "agent_catalog.v1");
    assert_eq!(summary["agent_count"], 1);
    assert_eq!(summary["tool_count"], 1);
}

#[test]
fn validates_shared_contract_fixtures() {
    let request = include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/run-request.valid.json"
    );
    let normalized =
        agent_runtime_validate_run_request(request.to_owned()).expect("run request validates");
    assert_eq!(
        serde_json::from_str::<Value>(&normalized).expect("request json")["protocol_version"],
        "agent.v1"
    );

    let catalog: Value = serde_json::from_str(&catalog_json()).expect("catalog json");
    agent_runtime_validate_tool_spec(catalog["tools"][0].to_string()).expect("tool validates");

    let trace = include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/trace.valid.closed-early-step.json"
    );
    agent_runtime_validate_trace(trace.to_owned()).expect("trace validates");
}

#[test]
fn rejects_invalid_protocol_and_contract_shapes() {
    let error = agent_runtime_validate_run_request(
        json!({"protocol_version": "agent.v0", "input": {}}).to_string(),
    )
    .expect_err("old protocol is rejected");
    assert!(error.to_string().contains("protocol_version"));

    let error = agent_runtime_catalog_summary(
        json!({
            "protocol_version": "agent.v1",
            "catalog_version": "agent_catalog.v0",
            "generated_at": "2026-01-01T00:00:00Z",
            "active_domains": [],
            "agents": [],
            "tools": [],
            "proposal_kinds": [],
            "prompt_blocks": [],
        })
        .to_string(),
    )
    .expect_err("old catalog is rejected");
    assert!(error.to_string().contains("catalog_version"));
}

#[test]
fn validates_llm_and_chat_contracts() {
    let llm_request = include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/llm-request.valid.json"
    );
    agent_runtime_validate_llm_request(llm_request.to_owned()).expect("llm request validates");

    let llm_response = include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/llm-response.valid.json"
    );
    agent_runtime_validate_llm_response(llm_response.to_owned()).expect("llm response validates");

    let chat_request = include_str!(
        "../../../../../third_party/agent-runtime/fixtures/contracts/chat-turn-request.valid.json"
    );
    agent_runtime_validate_chat_turn_request(chat_request.to_owned())
        .expect("chat request validates");
}

#[tokio::test]
async fn completes_mock_llm() {
    let response = agent_runtime_complete_mock_llm(
        include_str!(
            "../../../../../third_party/agent-runtime/fixtures/contracts/llm-request.valid.json"
        )
        .to_owned(),
        "native mock response".to_owned(),
    )
    .await
    .expect("mock completion");
    let response: Value = serde_json::from_str(&response).expect("response json");
    assert_eq!(response["content"], "native mock response");
    assert_eq!(response["finish_reason"], "stop");
}

#[tokio::test]
async fn profile_turn_returns_only_runtime_owned_snapshot() {
    let turn = agent_runtime_start_profile_turn_snapshot(
        catalog_json(),
        json!({
            "protocol_version": "agent.v1",
            "provider": "mock",
            "model": "mock-model",
            "messages": [{"role": "user", "content": "ping"}],
            "metadata": {"mock_response": "snapshot turn response"},
        })
        .to_string(),
        "ai_chat".to_owned(),
        json!({"surface": "rust_test"}).to_string(),
        3,
        2,
    )
    .await
    .expect("profile snapshot starts");
    let turn: Value = serde_json::from_str(&turn).expect("turn json");
    assert_eq!(turn["llm_response"]["content"], "snapshot turn response");
    assert_eq!(turn["snapshot"]["snapshot_version"], 1);
    assert_eq!(turn["snapshot"]["limits"]["max_effect_steps"], 3);
    assert!(turn.get("step").is_none());
}

#[test]
fn snapshot_runs_typed_tool_plan() {
    let snapshot = agent_runtime_start_run_snapshot(
        catalog_json(),
        run_request(json!({
            "effects": [
                {"kind": "tool", "name": "propose_fake", "input": {"value": 1}},
                {"kind": "tool", "name": "propose_fake", "input": {"value": 2}}
            ]
        })),
        "ai_chat".to_owned(),
        4,
        2,
    )
    .expect("snapshot starts");
    let first: Value = serde_json::from_str(&snapshot).expect("snapshot json");
    assert_eq!(first["step"]["status"], "effect_requested");
    assert_eq!(requested_effect(&first)["risk"], "medium");
    assert_eq!(requested_effect(&first)["metadata"]["domain"], "finance");

    let second = continue_snapshot(&first, json!({"ok": 1}));
    assert_eq!(second["step"]["step_index"], 1);
    assert_eq!(second["step"]["run_state"]["effect_result_count"], 1);

    let terminal = continue_snapshot(&second, json!({"ok": 2}));
    assert_eq!(terminal["step"]["status"], "completed");
    assert_eq!(terminal["progress"]["dispatched_effect_count"], 2);
    assert_eq!(
        terminal["step"]["effect_results"].as_array().unwrap().len(),
        2
    );
}

#[test]
fn snapshot_budget_is_closed_by_runtime() {
    let snapshot = agent_runtime_start_run_snapshot(
        catalog_json(),
        run_request(json!({
            "effect": {"kind": "tool", "name": "propose_fake", "input": {}}
        })),
        "ai_chat".to_owned(),
        0,
        1,
    )
    .expect("snapshot closes");
    let snapshot: Value = serde_json::from_str(&snapshot).expect("snapshot json");
    assert_eq!(snapshot["step"]["status"], "closed_early");
    assert_eq!(snapshot["step"]["error"]["code"], "effect_budget_exhausted");
    assert_eq!(snapshot["progress"]["dispatched_effect_count"], 0);
}

#[test]
fn snapshot_cancellation_is_terminal_without_dispatch() {
    let snapshot = agent_runtime_start_run_snapshot(
        catalog_json(),
        run_request(json!({
            "effect": {"kind": "tool", "name": "propose_fake", "input": {}}
        })),
        "ai_chat".to_owned(),
        2,
        1,
    )
    .expect("snapshot starts");
    let cancelled = agent_runtime_cancel_run_snapshot(
        catalog_json(),
        snapshot,
        "ai_chat".to_owned(),
        "user stopped".to_owned(),
    )
    .expect("snapshot cancels");
    let cancelled: Value = serde_json::from_str(&cancelled).expect("snapshot json");
    assert_eq!(cancelled["step"]["status"], "cancelled");
    assert_eq!(cancelled["step"]["error"]["code"], "user_cancel");
    assert_eq!(cancelled["progress"]["dispatched_effect_count"], 0);
}

#[test]
fn snapshot_runs_and_resumes_subagent() {
    let mut catalog: Value = serde_json::from_str(&catalog_json()).expect("catalog json");
    let child = json!({
        "protocol_version": "agent.v1",
        "id": "child",
        "name": "Child",
        "version": "1.0.0",
        "schedule": {"type": "manual"},
        "capabilities": ["propose_fake"],
        "metadata": {}
    });
    catalog["agents"].as_array_mut().unwrap().push(child);
    let catalog_json = catalog.to_string();
    let parent = agent_runtime_start_run_snapshot(
        catalog_json.clone(),
        run_request(json!({
            "effect": {
                "kind": "subagent",
                "agent_id": "child",
                "input": {
                    "effect": {"kind": "tool", "name": "propose_fake", "input": {}}
                },
                "metadata": {}
            }
        })),
        "ai_chat".to_owned(),
        4,
        2,
    )
    .expect("parent starts");
    let child =
        agent_runtime_start_requested_subagent_snapshot(catalog_json.clone(), parent.clone())
            .expect("child starts");
    let child: Value = serde_json::from_str(&child).expect("child json");
    let response = json!({
        "jsonrpc": "2.0",
        "id": requested_effect(&child)["effect_id"],
        "result": {"ok": true}
    });
    let child = agent_runtime_continue_run_snapshot(
        catalog_json.clone(),
        child.to_string(),
        response.to_string(),
        "child".to_owned(),
    )
    .expect("child completes");
    let parent = agent_runtime_resume_parent_from_subagent_snapshot(catalog_json, parent, child)
        .expect("parent resumes");
    let parent: Value = serde_json::from_str(&parent).expect("parent json");
    assert_eq!(parent["step"]["status"], "completed");
    assert_eq!(parent["progress"]["dispatched_effect_count"], 2);
}
