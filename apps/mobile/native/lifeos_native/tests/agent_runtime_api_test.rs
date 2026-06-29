use lifeos_native::api::agent_runtime::{
    agent_runtime_catalog_summary, agent_runtime_protocol_version, agent_runtime_start_run_step,
    agent_runtime_validate_run_request, agent_runtime_validate_trace,
};
use serde_json::Value;

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
