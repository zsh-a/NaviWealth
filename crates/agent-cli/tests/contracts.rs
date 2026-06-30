use std::path::{Path, PathBuf};

use serde_json::Value;

#[test]
fn committed_fixtures_match_json_schemas() {
    assert_valid(
        "schemas/agent-runtime/run-request.schema.json",
        "fixtures/agent-runtime/run-request.valid.json",
    );
    assert_invalid(
        "schemas/agent-runtime/run-request.schema.json",
        "fixtures/agent-runtime/run-request.invalid.missing-protocol-version.json",
    );
    assert_valid(
        "schemas/agent-runtime/run-result.schema.json",
        "fixtures/agent-runtime/run-result.completed.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.valid.closed-early-step.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.missing-step-run-state.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.missing-step-terminal-reason.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.unknown-step-terminal-reason.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.unknown-step-status.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.non-string-step-tool-name.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.empty-step-tool-name.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.mismatched-step-run-state-status.json",
    );
    assert_invalid(
        "schemas/agent-runtime/trace.schema.json",
        "fixtures/agent-runtime/trace.invalid.mismatched-step-terminal-status.json",
    );
    assert_valid(
        "schemas/agent-runtime/catalog.schema.json",
        "fixtures/agent-runtime/catalog.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/debug-bundle-manifest.schema.json",
        "fixtures/agent-runtime/debug-bundle-manifest.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/debug-state-snapshot.schema.json",
        "fixtures/agent-runtime/debug-state-snapshot.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/debug-replay-config.schema.json",
        "fixtures/agent-runtime/debug-replay-config.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/recovery-report.schema.json",
        "fixtures/agent-runtime/recovery-report.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/prompt-manifest.schema.json",
        "fixtures/agent-runtime/prompt-manifest.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/tool-call-record.schema.json",
        "fixtures/agent-runtime/tool-call-record.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/tool-source-manifest.schema.json",
        "fixtures/agent-runtime/tool-source.example.json",
    );
    assert_valid(
        "schemas/agent-runtime/tool-source-manifest.schema.json",
        "fixtures/agent-runtime/mcp-tool-source.example.json",
    );
    assert_valid(
        "schemas/agent-runtime/tool-source-manifest.schema.json",
        "fixtures/agent-runtime/http-tool-source.example.json",
    );
    assert_valid(
        "schemas/agent-runtime/hook-event.schema.json",
        "fixtures/agent-runtime/hook-event.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/proposal-envelope.schema.json",
        "fixtures/agent-runtime/proposal-envelope.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/approval-decision.schema.json",
        "fixtures/agent-runtime/approval-decision.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/llm-request.schema.json",
        "fixtures/agent-runtime/llm-request.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/llm-response.schema.json",
        "fixtures/agent-runtime/llm-response.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/chat-turn-request.schema.json",
        "fixtures/agent-runtime/chat-turn-request.valid.json",
    );
    assert_invalid(
        "schemas/agent-runtime/chat-turn-request.schema.json",
        "fixtures/agent-runtime/chat-turn-request.invalid.missing-messages.json",
    );
    assert_valid(
        "schemas/agent-runtime/chat-turn-state.schema.json",
        "fixtures/agent-runtime/chat-turn-state.requires-tool-results.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/chat-tool-result.schema.json",
        "fixtures/agent-runtime/chat-tool-result.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/chat-turn-event.schema.json",
        "fixtures/agent-runtime/chat-turn-event.round-finished.requires-tool-results.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/session-record.schema.json",
        "fixtures/agent-runtime/session-record.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/thread-record.schema.json",
        "fixtures/agent-runtime/thread-record.valid.json",
    );
    assert_valid(
        "schemas/agent-runtime/step-record.schema.json",
        "fixtures/agent-runtime/step-record.valid.json",
    );
}

#[test]
fn example_registry_agents_match_agent_spec_schema() {
    let schema = read_json("schemas/agent-runtime/agent-spec.schema.json");
    let validator = jsonschema::validator_for(&schema).expect("agent schema compiles");
    let registry: Value = serde_yaml::from_str(&read_text("examples/agent-runtime/agents.yaml"))
        .expect("example registry parses");
    let agents = registry
        .get("agents")
        .and_then(Value::as_array)
        .expect("registry contains agents");
    for agent in agents {
        let mut spec = agent.clone();
        spec.as_object_mut()
            .expect("agent is object")
            .remove("runner");
        assert_json_valid(&validator, &spec);
    }
}

#[test]
fn committed_eval_cases_match_schema() {
    let schema = read_json("schemas/agent-runtime/eval-case.schema.json");
    let validator = jsonschema::validator_for(&schema).expect("eval case schema compiles");
    for path in [
        "evals/agent-runtime/catalog_dry_run.yaml",
        "evals/agent-runtime/tool_call_sequence.yaml",
        "evals/agent-runtime/proposal_expectation.yaml",
    ] {
        let instance: Value =
            serde_yaml::from_str(&read_text(path)).unwrap_or_else(|e| panic!("{path}: {e}"));
        assert_json_valid(&validator, &instance);
    }
}

#[test]
fn openapi_contract_documents_http_server_routes() {
    let openapi: Value = serde_yaml::from_str(&read_text("openapi/agent-runtime-api.yaml"))
        .expect("OpenAPI contract parses");
    assert_eq!(openapi["openapi"], "3.1.0");
    assert!(openapi["paths"]["/healthz"]["get"].is_object());
    assert!(openapi["paths"]["/catalog/summary"]["get"].is_object());
    assert!(openapi["paths"]["/metrics/summary"]["get"].is_object());
    assert!(openapi["paths"]["/tools"]["get"].is_object());
    assert!(openapi["paths"]["/runs"]["get"].is_object());
    assert!(openapi["paths"]["/runs/{run_id}"]["get"].is_object());
    assert!(openapi["paths"]["/runs/{run_id}/trace"]["get"].is_object());
    assert!(openapi["paths"]["/runs/{run_id}/events"]["get"].is_object());
    assert!(openapi["paths"]["/runs/{run_id}/replay"]["post"].is_object());
    assert!(openapi["paths"]["/tools/{tool_name}/call"]["post"].is_object());
    assert!(openapi["paths"]["/proposals"]["get"].is_object());
    assert!(openapi["paths"]["/proposals"]["post"].is_object());
    assert!(openapi["paths"]["/proposals/{proposal_id}"]["get"].is_object());
    assert!(openapi["paths"]["/proposals/{proposal_id}/decision"]["post"].is_object());
    assert!(openapi["paths"]["/proposals/{proposal_id}/apply"]["post"].is_object());
    assert!(openapi["paths"]["/proposals/{proposal_id}/undo"]["post"].is_object());
    assert!(openapi["paths"]["/sessions"]["get"].is_object());
    assert!(openapi["paths"]["/sessions"]["post"].is_object());
    assert!(openapi["paths"]["/sessions/{session_id}"]["get"].is_object());
    assert!(openapi["paths"]["/sessions/{session_id}/fork"]["post"].is_object());
    assert!(openapi["paths"]["/agents/{agent_id}/run"]["post"].is_object());
    assert_eq!(
        openapi["paths"]["/agents/{agent_id}/run"]["post"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/AgentRunResponse"
    );
    assert_eq!(
        openapi["paths"]["/tools/{tool_name}/call"]["post"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/ToolCallResponse"
    );
    assert_eq!(
        openapi["paths"]["/metrics/summary"]["get"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/RuntimeMetricsSummary"
    );
    assert_eq!(
        openapi["components"]["schemas"]["RuntimeMetricsSummary"]["properties"]["tool_call_count"]
            ["minimum"],
        0
    );
    assert_eq!(
        openapi["components"]["schemas"]["HookEvent"]["$ref"],
        "../schemas/agent-runtime/hook-event.schema.json"
    );
    assert_eq!(
        openapi["components"]["schemas"]["PromptManifest"]["$ref"],
        "../schemas/agent-runtime/prompt-manifest.schema.json"
    );
    assert_eq!(
        openapi["paths"]["/runs/{run_id}"]["get"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/AgentRunRecord"
    );
    assert_eq!(
        openapi["paths"]["/runs"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]
            ["items"]["$ref"],
        "#/components/schemas/AgentRunRecord"
    );
    assert_eq!(
        openapi["components"]["schemas"]["AgentRunRecord"]["properties"]["idempotency_key"]["pattern"],
        "^idem_[a-f0-9]{64}$"
    );
    assert_eq!(
        openapi["paths"]["/runs/{run_id}/trace"]["get"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "../schemas/agent-runtime/trace.schema.json"
    );
    assert_eq!(
        openapi["paths"]["/runs/{run_id}/events"]["get"]["responses"]["200"]["content"]["text/event-stream"]
            ["schema"]["description"],
        "Each SSE data frame is a TraceEvent JSON object from trace.schema.json; agent_runtime_step frames include payload.run_state."
    );
    assert_eq!(
        openapi["paths"]["/runs/{run_id}/replay"]["post"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/ReplayExecutionResponse"
    );
    assert_eq!(
        openapi["components"]["schemas"]["ReplayExecutionResponse"]["properties"]["mode"]["enum"],
        serde_json::json!(["view", "deterministic", "live"])
    );
    assert_eq!(
        openapi["paths"]["/proposals/{proposal_id}/decision"]["post"]["responses"]["200"]["content"]
            ["application/json"]["schema"]["$ref"],
        "#/components/schemas/ProposalDecisionResponse"
    );
    assert_eq!(
        openapi["paths"]["/proposals/{proposal_id}/apply"]["post"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/ProposalActionResponse"
    );
    assert_eq!(
        openapi["paths"]["/proposals/{proposal_id}/undo"]["post"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/ProposalActionResponse"
    );
    assert_eq!(
        openapi["paths"]["/sessions"]["post"]["responses"]["200"]["content"]["application/json"]["schema"]
            ["$ref"],
        "#/components/schemas/SessionCreateResponse"
    );
    assert_eq!(
        openapi["paths"]["/sessions/{session_id}"]["get"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/SessionShowResponse"
    );
    assert_eq!(
        openapi["paths"]["/sessions/{session_id}/fork"]["post"]["responses"]["200"]["content"]["application/json"]
            ["schema"]["$ref"],
        "#/components/schemas/ThreadForkResponse"
    );
}

fn assert_valid(schema_path: &str, instance_path: &str) {
    let schema = read_json(schema_path);
    let instance = read_json(instance_path);
    let validator = jsonschema::validator_for(&schema).expect("schema compiles");
    assert_json_valid(&validator, &instance);
}

fn assert_invalid(schema_path: &str, instance_path: &str) {
    let schema = read_json(schema_path);
    let instance = read_json(instance_path);
    let validator = jsonschema::validator_for(&schema).expect("schema compiles");
    assert!(
        !validator.is_valid(&instance),
        "{instance_path} unexpectedly matched {schema_path}"
    );
}

fn assert_json_valid(validator: &jsonschema::Validator, instance: &Value) {
    if validator.is_valid(instance) {
        return;
    }
    let errors = validator
        .iter_errors(instance)
        .map(|error| error.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    panic!("JSON schema validation failed:\n{errors}");
}

fn read_json(path: &str) -> Value {
    serde_json::from_str(&read_text(path)).unwrap_or_else(|e| panic!("{path}: {e}"))
}

fn read_text(path: &str) -> String {
    std::fs::read_to_string(repo_path(path)).unwrap_or_else(|e| panic!("{path}: {e}"))
}

fn repo_path(path: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join(path)
}
