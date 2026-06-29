use std::{
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    process::{Child, Stdio},
    time::{Duration, Instant},
};

use assert_cmd::Command;
use serde_json::Value;

#[test]
fn catalog_summary_reads_flutter_export_shape() {
    let output = agent_cmd()
        .args([
            "catalog",
            "summary",
            "../../fixtures/agent-runtime/catalog.valid.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let json: Value = serde_json::from_slice(&output).expect("summary is JSON");
    assert_eq!(json["protocol_version"], "agent.v1");
    assert_eq!(json["catalog_version"], "agent_catalog.v1");
    assert_eq!(json["active_domains"], serde_json::json!(["finance"]));
    assert_eq!(json["agent_count"], 1);
    assert_eq!(json["tool_count"], 1);
    assert_eq!(json["proposal_kind_count"], 1);
    assert_eq!(json["prompt_block_count"], 1);
}

#[test]
fn catalog_agents_and_tools_are_printable() {
    let agents = agent_cmd()
        .args([
            "catalog",
            "agents",
            "../../fixtures/agent-runtime/catalog.valid.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let agents: Value = serde_json::from_slice(&agents).expect("agents are JSON");
    assert_eq!(agents[0]["id"], "execution_review");

    let tools = agent_cmd()
        .args([
            "catalog",
            "tools",
            "../../fixtures/agent-runtime/catalog.valid.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let tools: Value = serde_json::from_slice(&tools).expect("tools are JSON");
    assert_eq!(tools[0]["name"], "propose_fake");
    assert_eq!(tools[0]["risk"], "medium");
    assert_eq!(tools[0]["metadata"]["requires_confirmation"], "one_tap");
}

#[test]
fn catalog_prompt_manifest_records_prompt_model_and_block_hashes() {
    let output = agent_cmd()
        .args([
            "catalog",
            "prompt-manifest",
            "../../fixtures/agent-runtime/catalog.valid.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let manifest: Value = serde_json::from_slice(&output).expect("prompt manifest is JSON");
    assert_eq!(manifest["protocol_version"], "agent.v1");
    assert_eq!(manifest["id"], "execution_review_prompt");
    assert_eq!(manifest["version"], "execution_review.prompt.v1");
    assert_eq!(manifest["agent_id"], "execution_review");
    assert_eq!(manifest["model_family"], "openai");
    assert_eq!(manifest["provider"], "openai_compatible");
    assert_eq!(manifest["model"], "gpt-5-mini");
    assert_eq!(manifest["tool_schema_version"], "tool_schema.v1");
    assert_eq!(
        manifest["blocks"][0]["content_hash"],
        "blake3:d838ad239f1e6a938780f02c79833321e8fbf2d5d13800030ed4edc40e687796"
    );
}

#[test]
fn validate_accepts_valid_schema_fixture() {
    let output = agent_cmd()
        .args([
            "validate",
            "../../schemas/agent-runtime/run-request.schema.json",
            "../../fixtures/agent-runtime/run-request.valid.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("validation report is JSON");
    assert_eq!(report["valid"], true);
    assert_eq!(report["errors"], serde_json::json!([]));
}

#[test]
fn validate_rejects_invalid_schema_fixture() {
    let output = agent_cmd()
        .args([
            "validate",
            "../../schemas/agent-runtime/run-request.schema.json",
            "../../fixtures/agent-runtime/run-request.invalid.missing-protocol-version.json",
        ])
        .assert()
        .failure()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("validation report is JSON");
    assert_eq!(report["valid"], false);
    assert!(
        report["errors"]
            .as_array()
            .expect("errors is an array")
            .iter()
            .any(|error| error
                .as_str()
                .unwrap_or_default()
                .contains("protocol_version"))
    );
}

#[test]
fn config_profile_drives_run_defaults() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("configured-run-store");
    let config_path = dir.path().join("agent-runtime.toml");
    let registry = std::path::Path::new("../../examples/agent-runtime/agents.yaml")
        .canonicalize()
        .expect("registry path");
    std::fs::write(
        &config_path,
        format!(
            r#"[runtime]
profile = "ci"
registry = "{}"
store = "{}"

[profiles.ci]
timeout_seconds = 5
"#,
            registry.display(),
            store.display()
        ),
    )
    .expect("config written");

    let shown = agent_cmd()
        .args(["--config", config_path.to_str().unwrap(), "config", "show"])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let shown: Value = serde_json::from_slice(&shown).expect("config is JSON");
    assert_eq!(shown["profile"], "ci");
    assert_eq!(shown["runtime"]["timeout_seconds"], 5);

    let output = agent_cmd()
        .args([
            "--config",
            config_path.to_str().unwrap(),
            "run",
            "echo_agent",
            "--input",
            "../../examples/agent-runtime/fixtures/echo-input.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let output: Value = serde_json::from_slice(&output).expect("run is JSON");
    let run_id = output["run_id"].as_str().expect("run id");
    assert_eq!(output["status"], "completed");
    assert!(store.join("runs").join(format!("{run_id}.json")).exists());
}

#[test]
fn run_can_use_catalog_backed_dry_run_registry() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let trace = dir.path().join("trace.json");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            "../../fixtures/agent-runtime/run-request.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--trace-out",
            trace.to_str().expect("utf8 trace path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let result: Value = serde_json::from_slice(&output).expect("result is JSON");
    assert_eq!(result["agent_id"], "execution_review");
    assert_eq!(result["status"], "completed");
    assert_eq!(result["summary"], "catalog dry-run completed");
    assert_eq!(result["output"]["mode"], "catalog_dry_run");
    assert_eq!(result["output"]["agent"]["id"], "execution_review");
    assert_eq!(result["output"]["input"]["protocol_version"], "agent.v1");

    let trace: Value =
        serde_json::from_slice(&std::fs::read(trace).expect("trace file was written"))
            .expect("trace is JSON");
    assert_eq!(trace["agent_id"], "execution_review");
    assert_eq!(trace["events"][1]["kind"], "catalog_dry_run.agent_selected");
}

#[test]
fn replay_can_execute_from_trace() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let trace_path = dir.path().join("source-trace.json");
    let replay_trace_path = dir.path().join("replay-trace.json");

    agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            "../../fixtures/agent-runtime/run-request.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--trace-out",
            trace_path.to_str().expect("utf8 trace path"),
        ])
        .assert()
        .success();

    let output = agent_cmd()
        .args([
            "replay",
            trace_path.to_str().expect("utf8 trace path"),
            "--execute",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--trace-out",
            replay_trace_path.to_str().expect("utf8 replay trace path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("replay report is JSON");
    assert_eq!(report["mode"], "live");
    assert_eq!(report["agent_id"], "execution_review");
    assert_eq!(report["result"]["status"], "completed");
    assert_eq!(report["output_matches"], true);
    assert_ne!(report["source_run_id"], report["replay_run_id"]);
    assert_eq!(report["trace"]["events"][0]["payload"]["trigger"], "replay");

    let replay_trace = read_json(replay_trace_path);
    assert_eq!(
        replay_trace["events"][1]["kind"],
        "catalog_dry_run.agent_selected"
    );
}

#[test]
fn replay_can_run_deterministically_from_trace_without_writing_store() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let trace_path = dir.path().join("source-trace.json");
    let replay_trace_path = dir.path().join("deterministic-trace.json");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            "../../fixtures/agent-runtime/run-request.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--trace-out",
            trace_path.to_str().expect("utf8 trace path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let run: Value = serde_json::from_slice(&output).expect("run result is JSON");
    let source_run_id = run["run_id"].as_str().expect("source run id");

    let output = agent_cmd()
        .args([
            "replay",
            trace_path.to_str().expect("utf8 trace path"),
            "--mode",
            "deterministic",
            "--trace-out",
            replay_trace_path.to_str().expect("utf8 replay trace path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("replay report is JSON");
    assert_eq!(report["mode"], "deterministic");
    assert_eq!(report["source_run_id"], source_run_id);
    assert_eq!(report["replay_run_id"], source_run_id);
    assert_eq!(report["output_matches"], true);
    assert_eq!(report["result"]["output"], run["output"]);

    let deterministic_trace = read_json(replay_trace_path);
    assert_eq!(deterministic_trace["run_id"], source_run_id);
    let run_files = std::fs::read_dir(store.join("runs"))
        .expect("run dir exists")
        .count();
    assert_eq!(run_files, 1);
}

#[test]
fn inspect_and_debug_bundle_export_use_file_store() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let bundle = dir.path().join("bundle");
    let input_path = dir.path().join("sensitive-input.json");
    std::fs::write(
        &input_path,
        serde_json::to_vec(&serde_json::json!({
            "message": "secret run",
            "api_key": "sk-live",
            "nested": {
                "access_token": "access-123",
                "safe": "visible"
            },
            "tool_call": {
                "name": "echo",
                "input": {
                    "api_key": "tool-secret",
                    "value": 7
                }
            }
        }))
        .expect("input encodes"),
    )
    .expect("input writes");

    let session = agent_cmd()
        .args([
            "session",
            "create",
            "--title",
            "Debug bundle session",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let session: Value = serde_json::from_slice(&session).expect("session is JSON");
    let session_id = session["session"]["session_id"]
        .as_str()
        .expect("session id is string");
    let thread_id = session["thread"]["thread_id"]
        .as_str()
        .expect("thread id is string");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            input_path.to_str().expect("utf8 input path"),
            "--session",
            session_id,
            "--thread",
            thread_id,
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let result: Value = serde_json::from_slice(&output).expect("result is JSON");
    let run_id = result["run_id"].as_str().expect("run_id is string");

    let inspect = agent_cmd()
        .args([
            "inspect",
            run_id,
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let record: Value = serde_json::from_slice(&inspect).expect("record is JSON");
    assert_eq!(record["run_id"], run_id);
    assert!(
        record["idempotency_key"]
            .as_str()
            .is_some_and(|key| key.starts_with("idem_"))
    );
    assert_eq!(record["agent_id"], "execution_review");
    assert_eq!(record["status"], "completed");

    let created_proposal = agent_cmd()
        .args([
            "proposal",
            "create",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--run-id",
            run_id,
            "--agent-id",
            "execution_review",
            "--kind",
            "fake",
            "--summary",
            "Debug bundle proposal",
            "--payload-json",
            r#"{"api_key":"proposal-secret","safe":"visible"}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let created_proposal: Value =
        serde_json::from_slice(&created_proposal).expect("proposal is JSON");
    let proposal_id = created_proposal["proposal_id"]
        .as_str()
        .expect("proposal id is string");

    let manifest = agent_cmd()
        .args([
            "debug-bundle",
            "export",
            run_id,
            "--store",
            store.to_str().expect("utf8 store path"),
            "--out",
            bundle.to_str().expect("utf8 bundle path"),
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let manifest: Value = serde_json::from_slice(&manifest).expect("manifest is JSON");
    assert_eq!(manifest["bundle_version"], "debug_bundle.v1");
    assert_eq!(manifest["run_id"], run_id);
    assert_eq!(manifest["agent_id"], "execution_review");
    assert_eq!(manifest["agent_version"], "0.1.0");
    assert_eq!(manifest["files"]["manifest"], "manifest.json");
    assert_eq!(manifest["files"]["trace"], "trace.json");
    assert_eq!(manifest["files"]["events"], "events.jsonl");
    assert_eq!(manifest["files"]["replay_config"], "replay_config.json");
    assert_eq!(manifest["files"]["agent_spec"], "agent_spec.json");
    assert_eq!(manifest["files"]["prompt_manifest"], "prompt_manifest.json");
    assert_eq!(manifest["files"]["tool_calls"], "tool_calls.jsonl");
    assert_eq!(manifest["files"]["state_snapshot"], "state_snapshot.json");
    assert_eq!(manifest["files"]["redactions"], "redactions.json");

    let bundled_trace = read_json(bundle.join("trace.json"));
    assert_eq!(bundled_trace["run_id"], run_id);
    assert_eq!(
        bundled_trace["events"][1]["kind"],
        "catalog_dry_run.agent_selected"
    );
    assert_eq!(bundled_trace["input"]["api_key"], "[REDACTED]");
    assert_eq!(
        bundled_trace["input"]["nested"]["access_token"],
        "[REDACTED]"
    );
    assert_eq!(bundled_trace["input"]["nested"]["safe"], "visible");
    assert_eq!(bundled_trace["output"]["input"]["api_key"], "[REDACTED]");

    let bundled_events = std::fs::read_to_string(bundle.join("events.jsonl"))
        .expect("events jsonl exists")
        .lines()
        .map(|line| serde_json::from_str::<Value>(line).expect("event line is JSON"))
        .collect::<Vec<_>>();
    assert_eq!(
        bundled_events.len(),
        bundled_trace["events"]
            .as_array()
            .expect("trace events is array")
            .len()
    );
    assert!(
        bundled_events
            .iter()
            .any(|event| event["kind"] == "tool_call_finished")
    );
    assert!(bundled_events.iter().any(|event| {
        event["payload"]["input"]["api_key"]
            .as_str()
            .is_some_and(|value| value == "[REDACTED]")
            || event["payload"]["output"]["echo"]["api_key"]
                .as_str()
                .is_some_and(|value| value == "[REDACTED]")
    }));

    let bundled_request = read_json(bundle.join("run_request.json"));
    assert_eq!(bundled_request["run_id"], run_id);
    assert_eq!(bundled_request["trigger"], "replay");
    assert_eq!(bundled_request["input"]["api_key"], "[REDACTED]");
    assert_eq!(
        bundled_request["input"]["nested"]["access_token"],
        "[REDACTED]"
    );
    assert_eq!(bundled_request["input"]["nested"]["safe"], "visible");
    assert_eq!(
        bundled_request["metadata"]["reconstructed_from"],
        "run_record"
    );

    let replay_config = read_json(bundle.join("replay_config.json"));
    assert_eq!(replay_config["run_id"], run_id);
    assert_eq!(replay_config["agent_id"], "execution_review");
    assert_eq!(replay_config["replay_mode"], "trace_execute");
    assert_eq!(replay_config["assets"]["trace"], "trace.json");
    assert_eq!(replay_config["assets"]["events"], "events.jsonl");
    assert_eq!(replay_config["assets"]["tool_calls"], "tool_calls.jsonl");
    assert_eq!(
        replay_config["assets"]["prompt_manifest"],
        "prompt_manifest.json"
    );
    assert_eq!(replay_config["timeout_seconds"], 60);
    assert_eq!(
        replay_config["run_request"]["input"]["api_key"],
        "[REDACTED]"
    );
    assert!(
        replay_config["replay_command"]
            .as_array()
            .expect("replay command is array")
            .iter()
            .any(|part| part == "--catalog")
    );

    let bundled_result = read_json(bundle.join("run_result.json"));
    assert_eq!(bundled_result["run_id"], run_id);
    assert_eq!(bundled_result["status"], "completed");
    assert_eq!(bundled_result["output"]["input"]["api_key"], "[REDACTED]");
    assert_eq!(
        bundled_result["output"]["tool_result"]["echo"]["api_key"],
        "[REDACTED]"
    );

    let bundled_tool_calls = std::fs::read_to_string(bundle.join("tool_calls.jsonl"))
        .expect("tool calls jsonl exists")
        .lines()
        .map(|line| serde_json::from_str::<Value>(line).expect("tool call line is JSON"))
        .collect::<Vec<_>>();
    assert_eq!(bundled_tool_calls.len(), 1);
    assert!(
        bundled_tool_calls[0]["tool_call_id"]
            .as_str()
            .is_some_and(|id| id.starts_with("tool_"))
    );
    assert_eq!(bundled_tool_calls[0]["tool_name"], "echo");
    assert!(
        bundled_tool_calls[0]["input_hash"]
            .as_str()
            .is_some_and(|hash| hash.starts_with("blake3:"))
    );
    assert_eq!(bundled_tool_calls[0]["status"], "completed");
    assert_eq!(
        bundled_tool_calls[0]["output"]["echo"]["api_key"],
        "[REDACTED]"
    );
    assert_eq!(bundled_tool_calls[0]["output"]["echo"]["value"], 7);

    let state_snapshot = read_json(bundle.join("state_snapshot.json"));
    assert_eq!(state_snapshot["run_id"], run_id);
    assert_eq!(state_snapshot["agent_id"], "execution_review");
    assert_eq!(state_snapshot["run_status"], "completed");
    assert_eq!(state_snapshot["session_id"], session_id);
    assert_eq!(state_snapshot["thread_id"], thread_id);
    assert_eq!(state_snapshot["session"]["session_id"], session_id);
    assert_eq!(state_snapshot["thread"]["thread_id"], thread_id);
    assert_eq!(state_snapshot["steps"][0]["run_id"], run_id);
    assert_eq!(state_snapshot["proposals"][0]["proposal_id"], proposal_id);
    assert_eq!(
        state_snapshot["proposals"][0]["payload"]["api_key"],
        "[REDACTED]"
    );
    assert_eq!(state_snapshot["proposals"][0]["payload"]["safe"], "visible");

    let redactions = read_json(bundle.join("redactions.json"));
    assert_eq!(redactions["policy"], "builtin_sensitive_field_names.v1");
    let redacted_paths = redactions["redacted_paths"]
        .as_array()
        .expect("redacted paths is an array");
    assert!(
        redacted_paths
            .iter()
            .any(|path| path.as_str().is_some_and(|path| path.contains("api_key")))
    );
    assert!(redacted_paths.iter().any(|path| {
        path.as_str()
            .is_some_and(|path| path.contains("access_token"))
    }));

    let agent_spec = read_json(bundle.join("agent_spec.json"));
    assert_eq!(agent_spec["id"], "execution_review");

    let prompt_manifest = read_json(bundle.join("prompt_manifest.json"));
    assert_eq!(prompt_manifest["id"], "execution_review_prompt");
    assert_eq!(prompt_manifest["version"], "execution_review.prompt.v1");
    assert_eq!(prompt_manifest["agent_id"], "execution_review");
    assert_eq!(prompt_manifest["model"], "gpt-5-mini");
    assert_eq!(
        prompt_manifest["blocks"][0]["content_hash"],
        "blake3:d838ad239f1e6a938780f02c79833321e8fbf2d5d13800030ed4edc40e687796"
    );
}

#[test]
fn recover_abandons_stale_running_runs_in_file_store() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let run_dir = store.join("runs");
    std::fs::create_dir_all(&run_dir).expect("run dir created");
    let stale_run = serde_json::json!({
        "protocol_version": "agent.v1",
        "run_id": "run_stale_cli",
        "agent_id": "execution_review",
        "status": "running",
        "scope": {"type": "global"},
        "started_at": "2020-01-01T00:00:00Z",
        "finished_at": null,
        "input": {"message": "stale"},
        "output": {},
        "metadata": {}
    });
    std::fs::write(
        run_dir.join("run_stale_cli.json"),
        serde_json::to_vec_pretty(&stale_run).expect("stale run encodes"),
    )
    .expect("stale run writes");

    let output = agent_cmd()
        .args([
            "recover",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--timeout-seconds",
            "1",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let report: Value = serde_json::from_slice(&output).expect("recovery report is JSON");
    assert_eq!(report["scanned_runs"], 1);
    assert_eq!(report["abandoned_count"], 1);
    assert_eq!(report["recovered_runs"][0]["run_id"], "run_stale_cli");
    assert_eq!(report["recovered_runs"][0]["new_status"], "abandoned");

    let updated = read_json(run_dir.join("run_stale_cli.json"));
    assert_eq!(updated["status"], "abandoned");
    assert_eq!(updated["error"]["code"], "stale_running_run_abandoned");
    assert_eq!(updated["error"]["retryable"], true);
    assert!(updated["finished_at"].is_string());
}

#[test]
fn catalog_dry_run_can_call_process_tool_host() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let input_path = dir.path().join("input.json");
    let trace_path = dir.path().join("trace.json");
    std::fs::write(
        &input_path,
        serde_json::to_vec(&serde_json::json!({
            "tool_call": {
                "name": "echo_external",
                "input": {"value": 7}
            }
        }))
        .expect("input encodes"),
    )
    .expect("input writes");
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            input_path.to_str().expect("utf8 input path"),
            "--trace-out",
            trace_path.to_str().expect("utf8 trace path"),
            "--tool-host",
            agent_bin.to_str().expect("utf8 agent bin"),
            "dev-tool-host",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let result: Value = serde_json::from_slice(&output).expect("result is JSON");
    assert_eq!(result["status"], "completed");
    assert_eq!(result["output"]["tool_result"]["host"], "dev-tool-host");
    assert_eq!(result["output"]["tool_result"]["tool"], "echo_external");
    assert_eq!(result["output"]["tool_result"]["input"]["value"], 7);

    let trace = read_json(trace_path);
    let events = trace["events"].as_array().expect("trace events is array");
    let started = events
        .iter()
        .find(|event| event["kind"] == "tool_call_started")
        .expect("tool start event exists");
    let finished = events
        .iter()
        .find(|event| event["kind"] == "tool_call_finished")
        .expect("tool finish event exists");
    let tool_call_id = started["payload"]["tool_call_id"]
        .as_str()
        .expect("tool call id is string");
    assert!(tool_call_id.starts_with("tool_"));
    assert_eq!(finished["payload"]["tool_call_id"], tool_call_id);
    assert_eq!(started["payload"]["tool_name"], "echo_external");
    assert_eq!(finished["payload"]["tool_name"], "echo_external");
    assert!(
        started["payload"]["input_hash"]
            .as_str()
            .is_some_and(|hash| hash.starts_with("blake3:"))
    );
    assert_eq!(
        finished["payload"]["input_hash"],
        started["payload"]["input_hash"]
    );
    assert_eq!(finished["payload"]["status"], "completed");
    assert!(finished["payload"]["duration_ms"].is_number());
    assert_eq!(finished["payload"]["output"]["input"]["value"], 7);
}

#[test]
fn catalog_dry_run_retries_retryable_process_tool_errors() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let input_path = dir.path().join("input.json");
    let trace_path = dir.path().join("trace.json");
    let fail_once_path = dir.path().join("fail-once.marker");
    std::fs::write(
        &input_path,
        serde_json::to_vec(&serde_json::json!({
            "tool_call": {
                "name": "echo_external",
                "input": {
                    "value": 7,
                    "fail_once_path": fail_once_path,
                }
            }
        }))
        .expect("input encodes"),
    )
    .expect("input writes");
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            input_path.to_str().expect("utf8 input path"),
            "--trace-out",
            trace_path.to_str().expect("utf8 trace path"),
            "--tool-host",
            agent_bin.to_str().expect("utf8 agent bin"),
            "dev-tool-host",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--max-retries",
            "1",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let result: Value = serde_json::from_slice(&output).expect("result is JSON");
    assert_eq!(result["status"], "completed");
    assert_eq!(result["output"]["tool_result"]["host"], "dev-tool-host");
    assert!(fail_once_path.exists());

    let trace = read_json(trace_path);
    let events = trace["events"].as_array().expect("trace events is array");
    assert_eq!(
        events
            .iter()
            .filter(|event| event["kind"] == "run_attempt_started")
            .count(),
        2
    );
    assert!(
        events
            .iter()
            .any(|event| event["kind"] == "tool_call_failed")
    );
    assert!(
        events
            .iter()
            .any(|event| event["kind"] == "run_retry_scheduled")
    );
    let retry = events
        .iter()
        .find(|event| event["kind"] == "run_retry_scheduled")
        .expect("retry event exists");
    assert_eq!(retry["payload"]["next_attempt"], 2);
}

#[test]
fn metrics_summary_counts_runs_tools_and_proposals() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("metrics-store");
    let input_path = dir.path().join("input.json");
    std::fs::write(
        &input_path,
        serde_json::to_vec(&serde_json::json!({
            "tool_call": {
                "name": "echo",
                "input": {"value": 23}
            },
            "proposal": {
                "kind": "fake",
                "summary": "Metrics fake proposal",
                "payload": {"value": 24}
            }
        }))
        .expect("input encodes"),
    )
    .expect("input writes");

    agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            input_path.to_str().expect("utf8 input path"),
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success();

    let output = agent_cmd()
        .args([
            "metrics",
            "summary",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let metrics: Value = serde_json::from_slice(&output).expect("metrics are JSON");
    assert_eq!(metrics["protocol_version"], "agent.v1");
    assert_eq!(metrics["run_count"], 1);
    assert_eq!(metrics["successful_run_count"], 1);
    assert_eq!(metrics["runs_by_status"]["completed"], 1);
    assert_eq!(metrics["tool_call_count"], 1);
    assert_eq!(metrics["failed_tool_call_count"], 0);
    assert!(metrics["average_run_latency_ms"].is_number());
    assert!(metrics["average_tool_call_latency_ms"].is_number());
    assert_eq!(metrics["proposal_count"], 1);
    assert_eq!(metrics["proposal_created_count"], 1);
    assert_eq!(metrics["proposals_by_status"]["pending_approval"], 1);
    assert_eq!(metrics["replay_count"], 0);
    assert_eq!(metrics["llm_total_tokens"], 0);
}

#[test]
fn catalog_dry_run_can_call_mock_tool_from_file() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let input_path = dir.path().join("input.json");
    let mock_path = dir.path().join("mock-output.json");
    std::fs::write(
        &input_path,
        serde_json::to_vec(&serde_json::json!({
            "tool_call": {
                "name": "propose_fake",
                "input": {"value": 9}
            }
        }))
        .expect("input encodes"),
    )
    .expect("input writes");
    std::fs::write(
        &mock_path,
        serde_json::to_vec(&serde_json::json!({
            "mocked": true,
            "decision": "accept"
        }))
        .expect("mock encodes"),
    )
    .expect("mock writes");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            input_path.to_str().expect("utf8 input path"),
            "--mock-tool",
            &format!(
                "propose_fake=@{}",
                mock_path.to_str().expect("utf8 mock path")
            ),
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let result: Value = serde_json::from_slice(&output).expect("result is JSON");
    assert_eq!(result["status"], "completed");
    assert_eq!(result["output"]["tool_result"]["mocked"], true);
    assert_eq!(result["output"]["tool_result"]["decision"], "accept");
}

#[test]
fn tool_cli_lists_catalog_tools_and_calls_process_tool_host() {
    let tools = agent_cmd()
        .args([
            "tool",
            "list",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let tools: Value = serde_json::from_slice(&tools).expect("tools are JSON");
    assert_eq!(tools[0]["name"], "propose_fake");

    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    let output = agent_cmd()
        .args([
            "tool",
            "call",
            "propose_fake",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input-json",
            r#"{"value":42}"#,
            "--tool-host",
            agent_bin.to_str().expect("utf8 agent bin"),
            "dev-tool-host",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let output: Value = serde_json::from_slice(&output).expect("tool output is JSON");
    assert_eq!(output["host"], "dev-tool-host");
    assert_eq!(output["tool"], "propose_fake");
    assert_eq!(output["input"]["value"], 42);
}

#[test]
fn tool_cli_can_call_inline_mock_tool() {
    let output = agent_cmd()
        .args([
            "tool",
            "call",
            "propose_fake",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input-json",
            r#"{"value":42}"#,
            "--mock-tool",
            r#"propose_fake={"mocked":true,"value":123}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let output: Value = serde_json::from_slice(&output).expect("tool output is JSON");
    assert_eq!(output["mocked"], true);
    assert_eq!(output["value"], 123);
}

#[test]
fn tool_cli_lists_and_calls_tool_source_manifest() {
    let dir = tempfile::tempdir().expect("temp dir");
    let source_path = dir.path().join("tool-source.json");
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    std::fs::write(
        &source_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": "tool_source.v1",
            "sources": [{
                "id": "dev",
                "command": agent_bin.to_str().expect("utf8 agent bin"),
                "args": ["dev-tool-host"],
                "tools": [{
                    "name": "sourced_echo",
                    "description": "Echo through a configured tool source.",
                    "input_schema": {"type": "object"},
                    "output_schema": {"type": "object"},
                    "risk": "read_only",
                    "metadata": {"source": "test"}
                }]
            }]
        }))
        .expect("manifest encodes"),
    )
    .expect("manifest writes");

    let tools = agent_cmd()
        .args([
            "tool",
            "list",
            "--tool-source",
            source_path.to_str().expect("utf8 source path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let tools: Value = serde_json::from_slice(&tools).expect("tools are JSON");
    assert!(
        tools
            .as_array()
            .expect("tools array")
            .iter()
            .any(|tool| tool["name"] == "sourced_echo")
    );

    let output = agent_cmd()
        .args([
            "tool",
            "call",
            "sourced_echo",
            "--tool-source",
            source_path.to_str().expect("utf8 source path"),
            "--input-json",
            r#"{"value":77}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let output: Value = serde_json::from_slice(&output).expect("tool output is JSON");
    assert_eq!(output["host"], "dev-tool-host");
    assert_eq!(output["tool"], "sourced_echo");
    assert_eq!(output["input"]["value"], 77);
}

#[test]
fn tool_cli_calls_mcp_stdio_tool_source_manifest() {
    let dir = tempfile::tempdir().expect("temp dir");
    let source_path = dir.path().join("mcp-tool-source.json");
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    std::fs::write(
        &source_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": "tool_source.v1",
            "sources": [{
                "id": "mcp-dev",
                "protocol": "mcp_stdio",
                "command": agent_bin.to_str().expect("utf8 agent bin"),
                "args": ["dev-mcp-server"],
                "tools": [{
                    "name": "mcp_echo",
                    "description": "Echo through a dev MCP server.",
                    "input_schema": {"type": "object"},
                    "output_schema": {"type": "object"},
                    "risk": "read_only",
                    "metadata": {"source": "mcp-dev", "protocol": "mcp_stdio"}
                }]
            }]
        }))
        .expect("manifest encodes"),
    )
    .expect("manifest writes");

    let output = agent_cmd()
        .args([
            "tool",
            "call",
            "mcp_echo",
            "--tool-source",
            source_path.to_str().expect("utf8 source path"),
            "--input-json",
            r#"{"value":91}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let output: Value = serde_json::from_slice(&output).expect("tool output is JSON");
    assert_eq!(output["structuredContent"]["host"], "dev-mcp-server");
    assert_eq!(output["structuredContent"]["tool"], "mcp_echo");
    assert_eq!(output["structuredContent"]["input"]["value"], 91);
    assert_eq!(output["isError"], false);
}

#[test]
fn tool_cli_calls_http_json_tool_source_manifest() {
    let dir = tempfile::tempdir().expect("temp dir");
    let source_path = dir.path().join("http-tool-source.json");
    let (port, request_handle) = spawn_http_tool_source_server();
    std::fs::write(
        &source_path,
        serde_json::to_vec_pretty(&serde_json::json!({
            "version": "tool_source.v1",
            "sources": [{
                "id": "http-dev",
                "protocol": "http_json",
                "endpoint": format!("http://127.0.0.1:{port}/tools/call"),
                "headers": {"x-agent-runtime-source": "http-dev"},
                "tools": [{
                    "name": "http_echo",
                    "description": "Echo through a dev HTTP endpoint.",
                    "input_schema": {"type": "object"},
                    "output_schema": {"type": "object"},
                    "risk": "read_only",
                    "metadata": {"source": "http-dev", "protocol": "http_json"}
                }]
            }]
        }))
        .expect("manifest encodes"),
    )
    .expect("manifest writes");

    let output = agent_cmd()
        .args([
            "tool",
            "call",
            "http_echo",
            "--tool-source",
            source_path.to_str().expect("utf8 source path"),
            "--input-json",
            r#"{"value":64}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let output: Value = serde_json::from_slice(&output).expect("tool output is JSON");
    assert_eq!(output["host"], "http-tool-source");
    assert_eq!(output["tool"], "http_echo");
    assert_eq!(output["input"]["value"], 64);

    let request = request_handle.join().expect("request captured");
    assert!(request.starts_with("POST /tools/call HTTP/1.1"));
    assert!(request.contains("x-agent-runtime-source: http-dev"));
    assert!(request.contains(r#""protocol_version":"agent.v1""#));
    assert!(request.contains(r#""method":"tool.call""#));
    assert!(request.contains(r#""tool":"http_echo""#));
    assert!(request.contains(r#""value":64"#));
}

#[test]
fn tool_cli_rejects_tools_missing_from_catalog() {
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    agent_cmd()
        .args([
            "tool",
            "call",
            "missing_tool",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--tool-host",
            agent_bin.to_str().expect("utf8 agent bin"),
            "dev-tool-host",
        ])
        .assert()
        .failure();
}

#[test]
fn tui_once_renders_catalog_and_trace_snapshot() {
    let output = agent_cmd()
        .args([
            "tui",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--trace",
            "../../fixtures/agent-runtime/trace.valid.json",
            "--once",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let output = String::from_utf8(output).expect("stdout is utf8");
    assert!(output.contains("Agent Runtime"));
    assert!(output.contains("Context"));
    assert!(output.contains("Output"));
    assert!(output.contains("Input"));
    assert!(output.contains("/help commands"));
    assert!(output.contains("agent: echo_agent@0.1.0"));
    assert!(output.contains("run_started"));
}

#[test]
fn stdio_server_handles_catalog_summary_and_agent_run() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("stdio-store");
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    let input = concat!(
        r#"{"jsonrpc":"2.0","id":"summary","method":"catalog.summary","params":{}}"#,
        "\n",
        r#"{"jsonrpc":"2.0","id":"run","method":"agent.run","params":{"agent_id":"execution_review","input":{"message":"via stdio","tool_call":{"name":"stdio_external","input":{"ok":true}}}}}"#,
        "\n"
    );

    let output = agent_cmd()
        .args([
            "serve",
            "--stdio",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--tool-host",
            agent_bin.to_str().expect("utf8 agent bin"),
            "dev-tool-host",
        ])
        .write_stdin(input)
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let lines = String::from_utf8(output).expect("stdout is utf8");
    let responses = lines
        .lines()
        .map(|line| serde_json::from_str::<Value>(line).expect("response JSON"))
        .collect::<Vec<_>>();

    assert_eq!(responses.len(), 2);
    assert_eq!(responses[0]["jsonrpc"], "2.0");
    assert_eq!(responses[0]["id"], "summary");
    assert_eq!(responses[0]["result"]["agent_count"], 1);

    assert_eq!(responses[1]["jsonrpc"], "2.0");
    assert_eq!(responses[1]["id"], "run");
    assert_eq!(responses[1]["result"]["result"]["status"], "completed");
    assert_eq!(
        responses[1]["result"]["result"]["output"]["tool_result"]["tool"],
        "stdio_external"
    );
    assert_eq!(
        responses[1]["result"]["trace"]["events"][1]["kind"],
        "catalog_dry_run.agent_selected"
    );
}

#[test]
fn http_server_handles_catalog_summary_and_agent_run() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("http-store");
    let port = reserve_local_port();
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    let child = std::process::Command::new(agent_bin)
        .args([
            "serve",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "--mock-tool",
            r#"propose_fake={"http_action":true}"#,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("HTTP server starts");
    let _server = ChildGuard(child);
    wait_for_http_server(port);

    let summary = http_json_request(port, "GET", "/catalog/summary", None);
    assert_eq!(summary["protocol_version"], "agent.v1");
    assert_eq!(summary["catalog_version"], "agent_catalog.v1");
    assert_eq!(summary["agent_count"], 1);

    let run = http_json_request(
        port,
        "POST",
        "/agents/execution_review/run",
        Some(r#"{"input":{"message":"via http"}}"#),
    );
    assert_eq!(run["result"]["agent_id"], "execution_review");
    assert_eq!(run["result"]["status"], "completed");
    assert_eq!(run["result"]["output"]["mode"], "catalog_dry_run");
    assert_eq!(
        run["trace"]["events"][1]["kind"],
        "catalog_dry_run.agent_selected"
    );

    let run_id = run["result"]["run_id"].as_str().expect("run_id is string");
    let runs = http_json_request(port, "GET", "/runs?agent_id=execution_review&limit=1", None);
    assert_eq!(runs[0]["run_id"], run_id);
    assert_eq!(runs[0]["agent_id"], "execution_review");

    let inspected_run = http_json_request(port, "GET", &format!("/runs/{run_id}"), None);
    assert_eq!(inspected_run["run_id"], run_id);
    assert_eq!(inspected_run["agent_id"], "execution_review");
    assert_eq!(inspected_run["status"], "completed");

    let inspected_trace = http_json_request(port, "GET", &format!("/runs/{run_id}/trace"), None);
    assert_eq!(inspected_trace["run_id"], run_id);
    assert_eq!(inspected_trace["agent_id"], "execution_review");
    assert_eq!(
        inspected_trace["events"][1]["kind"],
        "catalog_dry_run.agent_selected"
    );

    let events = http_text_request(port, "GET", &format!("/runs/{run_id}/events"), None);
    assert!(events.starts_with("HTTP/1.1 200"));
    assert!(events.contains("content-type: text/event-stream"));
    assert!(events.contains("event: run_started"));
    assert!(events.contains("event: catalog_dry_run.agent_selected"));
    assert!(events.contains(r#""kind":"catalog_dry_run.agent_selected""#));

    let replay = http_json_request(port, "POST", &format!("/runs/{run_id}/replay"), Some("{}"));
    let replay_run_id = replay["replay_run_id"]
        .as_str()
        .expect("replay run id is string");
    assert_eq!(replay["source_run_id"], run_id);
    assert_eq!(replay["agent_id"], "execution_review");
    assert_eq!(replay["result"]["status"], "completed");
    assert_eq!(replay["output_matches"], true);
    assert_ne!(replay_run_id, run_id);
    assert_eq!(replay["trace"]["run_id"], replay_run_id);

    let metrics = http_json_request(port, "GET", "/metrics/summary", None);
    assert_eq!(metrics["run_count"], 2);
    assert_eq!(metrics["successful_run_count"], 2);
    assert_eq!(metrics["replay_count"], 1);
    assert_eq!(metrics["runs_by_status"]["completed"], 2);

    let persisted_trace = store.join("traces").join(format!("{run_id}.trace.json"));
    assert!(
        persisted_trace.exists(),
        "HTTP agent.run persists trace for debug bundle export"
    );
}

#[test]
fn config_profile_drives_http_serve_defaults() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("configured-http-store");
    let config_path = dir.path().join("agent-runtime.toml");
    let catalog = std::path::Path::new("../../fixtures/agent-runtime/catalog.valid.json")
        .canonicalize()
        .expect("catalog path");
    let port = reserve_local_port();
    std::fs::write(
        &config_path,
        format!(
            r#"[runtime]
profile = "local"

[profiles.local]
catalog = "{}"
store = "{}"
host = "127.0.0.1"
port = {}
"#,
            catalog.display(),
            store.display(),
            port
        ),
    )
    .expect("config written");

    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    let child = std::process::Command::new(agent_bin)
        .args(["--config", config_path.to_str().unwrap(), "serve"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("HTTP server starts from config");
    let _server = ChildGuard(child);
    wait_for_http_server(port);

    let summary = http_json_request(port, "GET", "/catalog/summary", None);
    assert_eq!(summary["agent_count"], 1);
    assert!(store.exists());
}

#[test]
fn http_server_lists_and_calls_tools() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("http-tool-store");
    let port = reserve_local_port();
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    let child = std::process::Command::new(&agent_bin)
        .args([
            "serve",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "--tool-host",
            agent_bin.to_str().expect("utf8 agent bin"),
            "dev-tool-host",
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("HTTP server starts");
    let _server = ChildGuard(child);
    wait_for_http_server(port);

    let tools = http_json_request(port, "GET", "/tools", None);
    assert_eq!(tools[0]["name"], "propose_fake");

    let call = http_json_request(
        port,
        "POST",
        "/tools/propose_fake/call",
        Some(r#"{"input":{"value":9}}"#),
    );
    assert_eq!(call["tool"], "propose_fake");
    assert_eq!(call["output"]["host"], "dev-tool-host");
    assert_eq!(call["output"]["input"]["value"], 9);
}

#[test]
fn http_server_persists_and_decides_proposals() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("http-proposal-store");
    let port = reserve_local_port();
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    let child = std::process::Command::new(&agent_bin)
        .args([
            "serve",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
            "--mock-tool",
            r#"propose_fake={"http_action":true}"#,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("HTTP server starts");
    let _server = ChildGuard(child);
    wait_for_http_server(port);

    let run = http_json_request(
        port,
        "POST",
        "/agents/execution_review/run",
        Some(r#"{"input":{"message":"proposal trace seed"}}"#),
    );
    let run_id = run["result"]["run_id"].as_str().expect("run_id is string");

    let created = http_json_request(
        port,
        "POST",
        "/proposals",
        Some(&format!(
            r#"{{"run_id":"{run_id}","agent_id":"execution_review","kind":"fake","summary":"HTTP proposal","payload":{{"value":11}}}}"#
        )),
    );
    let proposal_id = created["proposal_id"]
        .as_str()
        .expect("proposal id is string");
    assert_eq!(created["status"], "pending_approval");
    assert_eq!(created["payload"]["value"], 11);

    let listed = http_json_request(port, "GET", &format!("/proposals?run_id={run_id}"), None);
    assert_eq!(listed[0]["proposal_id"], proposal_id);

    let inspected = http_json_request(port, "GET", &format!("/proposals/{proposal_id}"), None);
    assert_eq!(inspected["proposal_id"], proposal_id);

    let decided = http_json_request(
        port,
        "POST",
        &format!("/proposals/{proposal_id}/decision"),
        Some(r#"{"decision":"approve","comment":"approved over HTTP"}"#),
    );
    assert_eq!(decided["decision"]["decision"], "approve");
    assert_eq!(decided["decision"]["comment"], "approved over HTTP");
    assert_eq!(decided["proposal"]["status"], "approved");

    let stored = read_json(store.join("proposals").join(format!("{proposal_id}.json")));
    assert_eq!(stored["status"], "approved");

    let applied = http_json_request(
        port,
        "POST",
        &format!("/proposals/{proposal_id}/apply"),
        Some("{}"),
    );
    assert_eq!(applied["action"], "apply");
    assert_eq!(applied["tool"], "propose_fake");
    assert_eq!(applied["tool_output"]["http_action"], true);
    assert_eq!(applied["proposal"]["status"], "applied");

    let undone = http_json_request(
        port,
        "POST",
        &format!("/proposals/{proposal_id}/undo"),
        Some("{}"),
    );
    assert_eq!(undone["action"], "undo");
    assert_eq!(undone["tool"], "propose_fake");
    assert_eq!(undone["tool_output"]["http_action"], true);
    assert_eq!(undone["proposal"]["status"], "undone");

    let trace = http_json_request(port, "GET", &format!("/runs/{run_id}/trace"), None);
    let event_kinds = trace["events"]
        .as_array()
        .expect("trace events is array")
        .iter()
        .map(|event| event["kind"].as_str().expect("event kind is string"))
        .collect::<Vec<_>>();
    assert!(event_kinds.contains(&"proposal_created"));
    assert!(event_kinds.contains(&"proposal_decided"));
    assert!(event_kinds.contains(&"proposal_applied"));
    assert!(event_kinds.contains(&"proposal_undone"));

    let metrics = http_json_request(port, "GET", "/metrics/summary", None);
    assert_eq!(metrics["proposal_count"], 1);
    assert_eq!(metrics["proposal_created_count"], 1);
    assert_eq!(metrics["proposal_approved_count"], 1);
    assert_eq!(metrics["proposal_applied_count"], 1);
    assert_eq!(metrics["proposals_by_status"]["undone"], 1);
}

#[test]
fn http_server_persists_sessions_threads_and_steps() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("http-session-store");
    let port = reserve_local_port();
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    let child = std::process::Command::new(&agent_bin)
        .args([
            "serve",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--host",
            "127.0.0.1",
            "--port",
            &port.to_string(),
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("HTTP server starts");
    let _server = ChildGuard(child);
    wait_for_http_server(port);

    let created = http_json_request(
        port,
        "POST",
        "/sessions",
        Some(r#"{"title":"HTTP debug","metadata":{"source":"test"}}"#),
    );
    let session_id = created["session"]["session_id"]
        .as_str()
        .expect("session id is string");
    let thread_id = created["thread"]["thread_id"]
        .as_str()
        .expect("thread id is string");
    assert_eq!(created["session"]["title"], "HTTP debug");
    assert_eq!(created["thread"]["session_id"], session_id);

    let listed = http_json_request(port, "GET", "/sessions", None);
    assert_eq!(listed[0]["session_id"], session_id);

    let run_body = format!(
        r#"{{"session_id":"{session_id}","thread_id":"{thread_id}","input":{{"message":"http session"}}}}"#
    );
    let run = http_json_request(
        port,
        "POST",
        "/agents/execution_review/run",
        Some(&run_body),
    );
    let run_id = run["result"]["run_id"].as_str().expect("run id is string");
    assert_eq!(run["result"]["status"], "completed");

    let shown = http_json_request(port, "GET", &format!("/sessions/{session_id}"), None);
    assert_eq!(shown["session"]["session_id"], session_id);
    assert_eq!(shown["threads"][0]["thread"]["thread_id"], thread_id);
    assert_eq!(shown["threads"][0]["steps"][0]["kind"], "agent_run");
    assert_eq!(shown["threads"][0]["steps"][0]["run_id"], run_id);

    let forked = http_json_request(
        port,
        "POST",
        &format!("/sessions/{session_id}/fork"),
        Some(&format!(
            r#"{{"parent_thread_id":"{thread_id}","title":"Alternative"}}"#
        )),
    );
    assert_eq!(forked["session_id"], session_id);
    assert_eq!(forked["parent_thread_id"], thread_id);
    assert_eq!(forked["thread"]["title"], "Alternative");

    let stored_run = read_json(store.join("runs").join(format!("{run_id}.json")));
    assert!(
        stored_run["idempotency_key"]
            .as_str()
            .is_some_and(|key| key.starts_with("idem_"))
    );
    assert_eq!(stored_run["metadata"]["session_id"], session_id);
    assert_eq!(stored_run["metadata"]["thread_id"], thread_id);
}

#[test]
fn eval_runs_catalog_dry_run_and_checks_expectations() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("eval-store");
    let output = agent_cmd()
        .args([
            "eval",
            "../../evals/agent-runtime/catalog_dry_run.yaml",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("eval report is JSON");
    assert_eq!(report["id"], "catalog_dry_run_basic");
    assert_eq!(report["passed"], true);
    assert_eq!(report["agent_id"], "execution_review");
    assert_eq!(report["status"], "completed");
    assert!(
        report["checked"]
            .as_array()
            .expect("checked is array")
            .iter()
            .any(|value| value == "trace_event:catalog_dry_run.agent_selected")
    );
    assert!(
        report["checked"]
            .as_array()
            .expect("checked is array")
            .iter()
            .any(|value| value == "golden_trace")
    );
    assert!(
        report["checked"]
            .as_array()
            .expect("checked is array")
            .iter()
            .any(|value| value == "prompt_manifest")
    );
}

#[test]
fn eval_checks_expected_tool_call_sequence() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("eval-tool-store");
    let output = agent_cmd()
        .args([
            "eval",
            "../../evals/agent-runtime/tool_call_sequence.yaml",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("eval report is JSON");
    assert_eq!(report["id"], "catalog_dry_run_tool_call_sequence");
    assert_eq!(report["passed"], true);
    assert!(
        report["checked"]
            .as_array()
            .expect("checked is array")
            .iter()
            .any(|value| value == "tool_calls")
    );
}

#[test]
fn eval_checks_expected_proposals() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("eval-proposal-store");
    let output = agent_cmd()
        .args([
            "eval",
            "../../evals/agent-runtime/proposal_expectation.yaml",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("eval report is JSON");
    assert_eq!(report["id"], "catalog_dry_run_proposal_expectation");
    assert_eq!(report["passed"], true);
    assert!(
        report["checked"]
            .as_array()
            .expect("checked is array")
            .iter()
            .any(|value| value == "proposals")
    );

    let proposals_dir = store.join("proposals");
    let proposal_files = std::fs::read_dir(&proposals_dir)
        .expect("proposal dir exists")
        .collect::<Result<Vec<_>, _>>()
        .expect("proposal files read");
    assert_eq!(proposal_files.len(), 1);
    let proposal = read_json(proposal_files[0].path());
    assert_eq!(proposal["kind"], "fake");
    assert_eq!(proposal["status"], "pending_approval");
    assert_eq!(proposal["summary"], "Eval fake proposal");
    assert_eq!(proposal["payload"]["value"], 19);
}

#[test]
fn eval_runs_scoring_hook_and_reports_score() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("eval-score-store");
    let eval_file = dir.path().join("scored.yaml");
    let catalog = std::path::Path::new("../../fixtures/agent-runtime/catalog.valid.json")
        .canonicalize()
        .expect("catalog path");
    let agent_bin = assert_cmd::cargo::cargo_bin("agent");
    std::fs::write(
        &eval_file,
        format!(
            r#"id: scored_eval
agent_id: execution_review
catalog: "{}"
input:
  message: scored fixture
expect:
  status: completed
  agent_id: execution_review
  output_mode: catalog_dry_run
scoring_hook:
  command:
    - "{}"
    - dev-score-hook
  min_score: 0.5
"#,
            catalog.display(),
            agent_bin.display()
        ),
    )
    .expect("scored eval writes");

    let output = agent_cmd()
        .args([
            "eval",
            eval_file.to_str().expect("utf8 eval path"),
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("eval report is JSON");
    assert_eq!(report["id"], "scored_eval");
    assert_eq!(report["passed"], true);
    assert_eq!(report["score"], 1.0);
    assert_eq!(
        report["hooks"][0]["protocol_version"],
        serde_json::json!("agent.v1")
    );
    assert_eq!(
        report["hooks"][0]["hook_event"],
        serde_json::json!("AfterAgentStep")
    );
    assert_eq!(
        report["hooks"][0]["hook_kind"],
        serde_json::json!("process")
    );
    assert_eq!(
        report["hooks"][0]["hook_name"],
        serde_json::json!("eval.scoring_hook")
    );
    assert_eq!(report["hooks"][0]["status"], serde_json::json!("completed"));
    assert_eq!(
        report["hooks"][0]["agent_id"],
        serde_json::json!("execution_review")
    );
    assert_eq!(report["hooks"][0]["output"]["score"], 1.0);
    assert!(
        report["hooks"][0]["duration_ms"]
            .as_u64()
            .is_some_and(|value| value < u64::MAX)
    );
    assert!(
        report["scoring_comment"]
            .as_str()
            .is_some_and(|comment| comment.contains("completed"))
    );
    assert!(
        report["checked"]
            .as_array()
            .expect("checked is array")
            .iter()
            .any(|value| value == "scoring_hook")
    );
}

#[test]
fn eval_can_run_directory_suites() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("eval-suite-store");
    let output = agent_cmd()
        .args([
            "eval",
            "../../evals/agent-runtime",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();

    let report: Value = serde_json::from_slice(&output).expect("suite report is JSON");
    assert_eq!(report["passed"], true);
    assert_eq!(report["total"], 3);
    assert_eq!(report["passed_count"], 3);
    assert_eq!(report["failed_count"], 0);
    let ids = report["reports"]
        .as_array()
        .expect("reports is array")
        .iter()
        .map(|report| report["id"].as_str().expect("report id is string"))
        .collect::<Vec<_>>();
    assert!(ids.contains(&"catalog_dry_run_basic"));
    assert!(ids.contains(&"catalog_dry_run_tool_call_sequence"));
    assert!(ids.contains(&"catalog_dry_run_proposal_expectation"));
}

#[test]
fn eval_create_generates_case_and_golden_trace_from_run_store() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let eval_file = dir.path().join("generated_eval.yaml");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            "../../fixtures/agent-runtime/run-request.valid.json",
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let result: Value = serde_json::from_slice(&output).expect("run result is JSON");
    let run_id = result["run_id"].as_str().expect("run_id is string");

    let create_report = agent_cmd()
        .args([
            "eval",
            "create",
            "--from-run",
            run_id,
            "--store",
            store.to_str().expect("utf8 store path"),
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--out",
            eval_file.to_str().expect("utf8 eval path"),
            "--id",
            "generated_from_run",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let create_report: Value =
        serde_json::from_slice(&create_report).expect("create report is JSON");
    assert_eq!(create_report["id"], "generated_from_run");
    assert_eq!(create_report["run_id"], run_id);
    assert_eq!(create_report["agent_id"], "execution_review");

    let generated = std::fs::read_to_string(&eval_file).expect("eval file exists");
    assert!(generated.contains("id: generated_from_run"));
    assert!(generated.contains("golden_trace: golden/generated_from_run.trace.json"));
    assert!(generated.contains("prompt_manifest:"));
    assert!(generated.contains("id: execution_review_prompt"));
    assert!(generated.contains("version: execution_review.prompt.v1"));
    assert!(generated.contains("tool_schema_version: tool_schema.v1"));
    assert!(
        generated
            .contains("blake3:d838ad239f1e6a938780f02c79833321e8fbf2d5d13800030ed4edc40e687796")
    );
    assert!(
        dir.path()
            .join("golden/generated_from_run.trace.json")
            .exists()
    );

    let eval_report = agent_cmd()
        .args([
            "eval",
            eval_file.to_str().expect("utf8 eval path"),
            "--store",
            dir.path()
                .join("generated-eval-store")
                .to_str()
                .expect("utf8 generated store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let eval_report: Value = serde_json::from_slice(&eval_report).expect("eval report is JSON");
    assert_eq!(eval_report["id"], "generated_from_run");
    assert_eq!(eval_report["passed"], true);
    assert!(
        eval_report["checked"]
            .as_array()
            .expect("checked is array")
            .iter()
            .any(|value| value == "golden_trace")
    );
}

#[test]
fn eval_create_generates_proposal_expectations_from_run_store() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("store");
    let input_file = dir.path().join("proposal-run-request.json");
    let eval_file = dir.path().join("generated_proposal_eval.yaml");
    std::fs::write(
        &input_file,
        r#"{
  "message": "generate proposal expectation",
  "proposal": {
    "kind": "fake",
    "summary": "Generated eval fake proposal",
    "payload": {
      "value": 23
    }
  }
}"#,
    )
    .expect("input file written");

    let output = agent_cmd()
        .args([
            "run",
            "execution_review",
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--input",
            input_file.to_str().expect("utf8 input path"),
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let result: Value = serde_json::from_slice(&output).expect("run result is JSON");
    let run_id = result["run_id"].as_str().expect("run_id is string");

    agent_cmd()
        .args([
            "eval",
            "create",
            "--from-run",
            run_id,
            "--store",
            store.to_str().expect("utf8 store path"),
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--out",
            eval_file.to_str().expect("utf8 eval path"),
            "--id",
            "generated_proposal_from_run",
        ])
        .assert()
        .success();

    let generated = std::fs::read_to_string(&eval_file).expect("eval file exists");
    assert!(generated.contains("id: generated_proposal_from_run"));
    assert!(generated.contains("proposal:"));
    assert!(generated.contains("summary: Generated eval fake proposal"));
    assert!(generated.contains("proposals:"));
    assert!(generated.contains("min_count: 1"));
    assert!(generated.contains("kinds:"));
    assert!(generated.contains("- fake"));
    assert!(generated.contains("statuses:"));
    assert!(generated.contains("- pending_approval"));
    assert!(generated.contains("prompt_manifest:"));

    let eval_report = agent_cmd()
        .args([
            "eval",
            eval_file.to_str().expect("utf8 eval path"),
            "--store",
            dir.path()
                .join("generated-proposal-eval-store")
                .to_str()
                .expect("utf8 generated store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let eval_report: Value = serde_json::from_slice(&eval_report).expect("eval report is JSON");
    assert_eq!(eval_report["id"], "generated_proposal_from_run");
    assert_eq!(eval_report["passed"], true);
    let checked = eval_report["checked"].as_array().expect("checked is array");
    assert!(checked.iter().any(|value| value == "proposals"));
    assert!(checked.iter().any(|value| value == "prompt_manifest"));
}

#[test]
fn proposal_cli_persists_and_decides_proposals() {
    let dir = tempfile::tempdir().expect("temp dir");
    let store = dir.path().join("proposal-store");

    let created = agent_cmd()
        .args([
            "proposal",
            "create",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--run-id",
            "run_test",
            "--agent-id",
            "execution_review",
            "--kind",
            "fake",
            "--summary",
            "Review fake proposal",
            "--payload-json",
            r#"{"value":7}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let created: Value = serde_json::from_slice(&created).expect("proposal is JSON");
    let proposal_id = created["proposal_id"]
        .as_str()
        .expect("proposal_id is string");
    assert_eq!(created["protocol_version"], "agent.v1");
    assert_eq!(created["run_id"], "run_test");
    assert_eq!(created["status"], "pending_approval");
    assert_eq!(created["payload"]["value"], 7);

    let listed = agent_cmd()
        .args([
            "proposal",
            "list",
            "--store",
            store.to_str().expect("utf8 store path"),
            "--run-id",
            "run_test",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let listed: Value = serde_json::from_slice(&listed).expect("proposal list is JSON");
    assert_eq!(listed[0]["proposal_id"], proposal_id);

    let inspected = agent_cmd()
        .args([
            "proposal",
            "inspect",
            proposal_id,
            "--store",
            store.to_str().expect("utf8 store path"),
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let inspected: Value = serde_json::from_slice(&inspected).expect("proposal is JSON");
    assert_eq!(inspected["proposal_id"], proposal_id);

    let decided = agent_cmd()
        .args([
            "proposal",
            "decide",
            proposal_id,
            "--store",
            store.to_str().expect("utf8 store path"),
            "--decision",
            "approve",
            "--comment",
            "approved in test",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let decided: Value = serde_json::from_slice(&decided).expect("decision is JSON");
    assert_eq!(decided["decision"]["decision"], "approve");
    assert_eq!(decided["decision"]["comment"], "approved in test");
    assert_eq!(decided["proposal"]["status"], "approved");

    let applied = agent_cmd()
        .args([
            "proposal",
            "apply",
            proposal_id,
            "--store",
            store.to_str().expect("utf8 store path"),
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--mock-tool",
            r#"propose_fake={"applied":true}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let applied: Value = serde_json::from_slice(&applied).expect("apply response is JSON");
    assert_eq!(applied["action"], "apply");
    assert_eq!(applied["tool"], "propose_fake");
    assert_eq!(applied["tool_output"]["applied"], true);
    assert_eq!(applied["proposal"]["status"], "applied");

    let undone = agent_cmd()
        .args([
            "proposal",
            "undo",
            proposal_id,
            "--store",
            store.to_str().expect("utf8 store path"),
            "--catalog",
            "../../fixtures/agent-runtime/catalog.valid.json",
            "--mock-tool",
            r#"propose_fake={"undone":true}"#,
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let undone: Value = serde_json::from_slice(&undone).expect("undo response is JSON");
    assert_eq!(undone["action"], "undo");
    assert_eq!(undone["tool"], "propose_fake");
    assert_eq!(undone["tool_output"]["undone"], true);
    assert_eq!(undone["proposal"]["status"], "undone");

    let stored = read_json(store.join("proposals").join(format!("{proposal_id}.json")));
    assert_eq!(stored["status"], "undone");
}

#[test]
fn llm_cli_completes_with_mock_provider() {
    let output = agent_cmd()
        .args([
            "llm",
            "complete",
            "--prompt",
            "hello",
            "--model",
            "mock-fast",
            "--mock-response",
            "mocked answer",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let response: Value = serde_json::from_slice(&output).expect("llm response is JSON");
    assert_eq!(response["protocol_version"], "agent.v1");
    assert_eq!(response["provider"], "mock");
    assert_eq!(response["model"], "mock-fast");
    assert_eq!(response["content"], "mocked answer");
    assert_eq!(response["finish_reason"], "stop");
    assert!(
        response["usage"]["total_tokens"]
            .as_u64()
            .expect("usage count")
            > 0
    );
}

#[test]
fn llm_cli_completes_with_openai_compatible_provider() {
    let (port, request_handle) = spawn_openai_compatible_server();
    let output = agent_cmd()
        .env("TEST_OPENAI_API_KEY", "secret-key")
        .args([
            "llm",
            "complete",
            "--provider",
            "openai-compatible",
            "--prompt",
            "hello",
            "--model",
            "gpt-test",
            "--api-base-url",
            &format!("http://127.0.0.1:{port}"),
            "--api-key-env",
            "TEST_OPENAI_API_KEY",
            "--temperature",
            "0.2",
            "--max-output-tokens",
            "64",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let response: Value = serde_json::from_slice(&output).expect("llm response is JSON");
    assert_eq!(response["provider"], "openai-compatible");
    assert_eq!(response["model"], "gpt-test");
    assert_eq!(response["content"], "network answer");
    assert_eq!(response["usage"]["total_tokens"], 6);

    let request = request_handle.join().expect("request captured");
    assert!(request.starts_with("POST /chat/completions HTTP/1.1"));
    assert!(request.contains("authorization: Bearer secret-key"));
    assert!(request.contains(r#""model":"gpt-test""#));
    assert!(request.contains(r#""max_tokens":64"#));
}

#[test]
fn llm_cli_completes_with_anthropic_provider() {
    let (port, request_handle) = spawn_anthropic_server();
    let output = agent_cmd()
        .env("TEST_ANTHROPIC_API_KEY", "anthropic-key")
        .args([
            "llm",
            "complete",
            "--provider",
            "anthropic",
            "--prompt",
            "hello",
            "--model",
            "claude-test",
            "--api-base-url",
            &format!("http://127.0.0.1:{port}"),
            "--api-key-env",
            "TEST_ANTHROPIC_API_KEY",
            "--anthropic-version",
            "2023-06-01",
            "--max-output-tokens",
            "64",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let response: Value = serde_json::from_slice(&output).expect("llm response is JSON");
    assert_eq!(response["provider"], "anthropic");
    assert_eq!(response["model"], "claude-test");
    assert_eq!(response["content"], "anthropic answer");
    assert_eq!(response["usage"]["total_tokens"], 7);

    let request = request_handle.join().expect("request captured");
    assert!(request.starts_with("POST /messages HTTP/1.1"));
    assert!(request.contains("x-api-key: anthropic-key"));
    assert!(request.contains("anthropic-version: 2023-06-01"));
    assert!(request.contains(r#""model":"claude-test""#));
    assert!(request.contains(r#""max_tokens":64"#));
}

#[test]
fn llm_cli_completes_with_ollama_provider() {
    let (port, request_handle) = spawn_ollama_server();
    let output = agent_cmd()
        .args([
            "llm",
            "complete",
            "--provider",
            "ollama",
            "--prompt",
            "hello",
            "--model",
            "llama-test",
            "--api-base-url",
            &format!("http://127.0.0.1:{port}"),
            "--temperature",
            "0.3",
            "--max-output-tokens",
            "32",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let response: Value = serde_json::from_slice(&output).expect("llm response is JSON");
    assert_eq!(response["provider"], "ollama");
    assert_eq!(response["model"], "llama-test");
    assert_eq!(response["content"], "local answer");
    assert_eq!(response["usage"]["total_tokens"], 10);

    let request = request_handle.join().expect("request captured");
    assert!(request.starts_with("POST /api/chat HTTP/1.1"));
    assert!(request.contains(r#""model":"llama-test""#));
    assert!(request.contains(r#""stream":false"#));
    assert!(request.contains(r#""num_predict":32"#));
}

fn agent_cmd() -> Command {
    Command::cargo_bin("agent").expect("agent binary exists")
}

fn read_json(path: impl AsRef<std::path::Path>) -> Value {
    serde_json::from_slice(&std::fs::read(path).expect("JSON file exists")).expect("file is JSON")
}

fn reserve_local_port() -> u16 {
    let listener = TcpListener::bind(("127.0.0.1", 0)).expect("port can be reserved");
    listener.local_addr().expect("local addr").port()
}

fn spawn_openai_compatible_server() -> (u16, std::thread::JoinHandle<String>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).expect("server binds");
    let port = listener.local_addr().expect("local addr").port();
    let handle = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("request accepted");
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .expect("timeout set");
        let request = read_http_request(&mut stream);
        let body = r#"{"choices":[{"message":{"content":"network answer"},"finish_reason":"stop"}],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}"#;
        write!(
            stream,
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .expect("response writes");
        request
    });
    (port, handle)
}

fn spawn_anthropic_server() -> (u16, std::thread::JoinHandle<String>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).expect("server binds");
    let port = listener.local_addr().expect("local addr").port();
    let handle = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("request accepted");
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .expect("timeout set");
        let request = read_http_request(&mut stream);
        let body = r#"{"content":[{"type":"text","text":"anthropic answer"}],"stop_reason":"end_turn","usage":{"input_tokens":4,"output_tokens":3}}"#;
        write!(
            stream,
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .expect("response writes");
        request
    });
    (port, handle)
}

fn spawn_ollama_server() -> (u16, std::thread::JoinHandle<String>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).expect("server binds");
    let port = listener.local_addr().expect("local addr").port();
    let handle = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("request accepted");
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .expect("timeout set");
        let request = read_http_request(&mut stream);
        let body = r#"{"message":{"role":"assistant","content":"local answer"},"done_reason":"stop","prompt_eval_count":6,"eval_count":4}"#;
        write!(
            stream,
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .expect("response writes");
        request
    });
    (port, handle)
}

fn spawn_http_tool_source_server() -> (u16, std::thread::JoinHandle<String>) {
    let listener = TcpListener::bind(("127.0.0.1", 0)).expect("server binds");
    let port = listener.local_addr().expect("local addr").port();
    let handle = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("request accepted");
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .expect("timeout set");
        let request = read_http_request(&mut stream);
        let body =
            r#"{"output":{"host":"http-tool-source","tool":"http_echo","input":{"value":64}}}"#;
        write!(
            stream,
            "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .expect("response writes");
        request
    });
    (port, handle)
}

fn read_http_request(stream: &mut TcpStream) -> String {
    let mut bytes = Vec::new();
    let mut buffer = [0_u8; 1024];
    loop {
        let read = stream.read(&mut buffer).expect("request reads");
        if read == 0 {
            break;
        }
        bytes.extend_from_slice(&buffer[..read]);
        if http_request_complete(&bytes) {
            break;
        }
    }
    String::from_utf8(bytes).expect("request is utf8")
}

fn http_request_complete(bytes: &[u8]) -> bool {
    let Some(header_end) = bytes.windows(4).position(|window| window == b"\r\n\r\n") else {
        return false;
    };
    let header_text = String::from_utf8_lossy(&bytes[..header_end]);
    let content_length = header_text
        .lines()
        .find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("content-length")
                .then(|| value.trim().parse::<usize>().ok())
                .flatten()
        })
        .unwrap_or(0);
    bytes.len() >= header_end + 4 + content_length
}

fn wait_for_http_server(port: u16) {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if try_http_json_request(port, "GET", "/healthz", None).is_ok() {
            return;
        }
        assert!(
            Instant::now() < deadline,
            "HTTP server did not start on port {port}"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn http_json_request(port: u16, method: &str, path: &str, body: Option<&str>) -> Value {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match try_http_json_request(port, method, path, body) {
            Ok(value) => return value,
            Err(err) => {
                assert!(
                    Instant::now() < deadline,
                    "HTTP request {method} {path} did not succeed: {err}"
                );
                std::thread::sleep(Duration::from_millis(25));
            }
        }
    }
}

fn http_text_request(port: u16, method: &str, path: &str, body: Option<&str>) -> String {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match try_http_text_request(port, method, path, body) {
            Ok(value) => return value,
            Err(err) => {
                assert!(
                    Instant::now() < deadline,
                    "HTTP request {method} {path} did not succeed: {err}"
                );
                std::thread::sleep(Duration::from_millis(25));
            }
        }
    }
}

fn try_http_json_request(
    port: u16,
    method: &str,
    path: &str,
    body: Option<&str>,
) -> Result<Value, String> {
    let body = body.unwrap_or("");
    let mut stream =
        TcpStream::connect(("127.0.0.1", port)).map_err(|err| format!("connect: {err}"))?;
    write!(
        stream,
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
        body.len()
    )
    .map_err(|err| format!("write: {err}"))?;

    let mut response = String::new();
    stream
        .read_to_string(&mut response)
        .map_err(|err| format!("read: {err}"))?;
    let (head, body) = response
        .split_once("\r\n\r\n")
        .ok_or_else(|| format!("malformed HTTP response: {response}"))?;
    if !head.starts_with("HTTP/1.1 200") {
        return Err(format!("unexpected HTTP response: {response}"));
    }
    serde_json::from_str(body).map_err(|err| format!("decode JSON: {err}; body: {body}"))
}

fn try_http_text_request(
    port: u16,
    method: &str,
    path: &str,
    body: Option<&str>,
) -> Result<String, String> {
    let body = body.unwrap_or("");
    let mut stream =
        TcpStream::connect(("127.0.0.1", port)).map_err(|err| format!("connect: {err}"))?;
    write!(
        stream,
        "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{body}",
        body.len()
    )
    .map_err(|err| format!("write: {err}"))?;

    let mut response = String::new();
    stream
        .read_to_string(&mut response)
        .map_err(|err| format!("read: {err}"))?;
    if !response.starts_with("HTTP/1.1 200") {
        return Err(format!("unexpected HTTP response: {response}"));
    }
    Ok(response)
}

struct ChildGuard(Child);

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
