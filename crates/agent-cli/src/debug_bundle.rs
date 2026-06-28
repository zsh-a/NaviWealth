use std::collections::BTreeMap;

use agent_core::{
    AgentProposalStore, AgentRunRecord, AgentRunResult, AgentRunStore, AgentSessionStore,
    PROTOCOL_VERSION, ProposalEnvelope, RunId, RunRequest, SessionId, SessionRecord, StepRecord,
    ThreadId, ThreadRecord, TriggerKind, UserContext,
};
use agent_runtime::RUNTIME_VERSION;
use agent_store::{FileProposalStore, FileRunStore, FileSessionStore};
use camino::{Utf8Path, Utf8PathBuf};
use miette::{IntoDiagnostic, Result, miette};
use serde::Serialize;
use serde_json::{Value, json};
use time::format_description::well_known::Rfc3339;

use crate::catalog::{build_prompt_manifest, read_catalog, string_metadata};

#[derive(Debug, Serialize)]
struct DebugBundleManifest {
    bundle_version: String,
    protocol_version: String,
    runtime_version: String,
    run_id: String,
    agent_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    agent_version: Option<String>,
    created_at: String,
    files: BTreeMap<String, String>,
}

#[derive(Debug, Default, Serialize)]
struct RedactionReport {
    policy: String,
    replacement: String,
    redacted_paths: Vec<String>,
}

#[derive(Debug, Serialize)]
struct DebugStateSnapshot {
    protocol_version: String,
    runtime_version: String,
    captured_at: String,
    store_root: String,
    run_id: String,
    agent_id: String,
    run_status: agent_core::AgentRunStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    thread_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    session: Option<SessionRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    thread: Option<ThreadRecord>,
    #[serde(default)]
    steps: Vec<StepRecord>,
    #[serde(default)]
    proposals: Vec<ProposalEnvelope>,
}

#[derive(Debug, Serialize)]
struct DebugReplayConfig {
    protocol_version: String,
    runtime_version: String,
    run_id: String,
    agent_id: String,
    replay_mode: String,
    source_store: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_trace: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    catalog: Option<String>,
    timeout_seconds: u64,
    assets: BTreeMap<String, String>,
    replay_command: Vec<String>,
    run_request: RunRequest,
}

impl DebugBundleManifest {
    fn new(
        record: &AgentRunRecord,
        agent_version: Option<String>,
        files: BTreeMap<String, String>,
    ) -> Self {
        Self {
            bundle_version: "debug_bundle.v1".to_owned(),
            protocol_version: PROTOCOL_VERSION.to_owned(),
            runtime_version: RUNTIME_VERSION.to_owned(),
            run_id: record.run_id.0.clone(),
            agent_id: record.agent_id.clone(),
            agent_version,
            created_at: time::OffsetDateTime::now_utc()
                .format(&Rfc3339)
                .unwrap_or_else(|_| time::OffsetDateTime::now_utc().to_string()),
            files,
        }
    }
}

pub(crate) async fn export_debug_bundle(
    run_id: String,
    store_path: Utf8PathBuf,
    out: Utf8PathBuf,
    catalog_path: Option<Utf8PathBuf>,
    trace_path: Option<Utf8PathBuf>,
    timeout_seconds: u64,
) -> Result<()> {
    fs_err::tokio::create_dir_all(&out)
        .await
        .into_diagnostic()?;
    let store = FileRunStore::new(store_path.clone())
        .await
        .into_diagnostic()?;
    let run_id = RunId(run_id);
    let record = store
        .get_run(&run_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("run '{}' was not found", run_id.0))?;

    let trace = match &trace_path {
        Some(path) => Some(read_json_file(path.clone()).await?),
        None => read_store_trace(&store_path, &run_id).await?,
    };
    let catalog = match &catalog_path {
        Some(path) => Some(read_catalog(path.clone()).await?),
        None => None,
    };
    let agent_spec = catalog.as_ref().and_then(|catalog| {
        catalog
            .agents
            .iter()
            .find(|spec| spec.id == record.agent_id)
            .cloned()
    });
    let prompt_manifest = match (&catalog, &agent_spec) {
        (Some(catalog), Some(_)) => Some(build_prompt_manifest(catalog, Some(&record.agent_id))?),
        _ => None,
    };

    let run_request = run_request_from_record(&record);
    let run_result = run_result_from_record(&record)?;
    let state_snapshot = build_debug_state_snapshot(&store_path, &record).await?;
    let replay_config = build_debug_replay_config(
        &store_path,
        catalog_path.as_ref(),
        trace_path.as_ref(),
        timeout_seconds,
        prompt_manifest.is_some(),
        &record,
        &run_request,
    );
    let mut files = BTreeMap::new();
    let mut redactions = RedactionReport {
        policy: "builtin_sensitive_field_names.v1".to_owned(),
        replacement: "[REDACTED]".to_owned(),
        redacted_paths: Vec::new(),
    };

    write_redacted_bundle_json(
        &out,
        "run_record.json",
        &record,
        &mut files,
        &mut redactions,
    )
    .await?;
    write_redacted_bundle_json(
        &out,
        "run_request.json",
        &run_request,
        &mut files,
        &mut redactions,
    )
    .await?;
    write_redacted_bundle_json(
        &out,
        "run_result.json",
        &run_result,
        &mut files,
        &mut redactions,
    )
    .await?;
    write_redacted_bundle_json(
        &out,
        "replay_config.json",
        &replay_config,
        &mut files,
        &mut redactions,
    )
    .await?;
    if let Some(trace) = &trace {
        write_redacted_bundle_json(&out, "trace.json", trace, &mut files, &mut redactions).await?;
        let events = event_records_from_trace(trace);
        if !events.is_empty() {
            write_redacted_bundle_jsonl(&out, "events.jsonl", &events, &mut files, &mut redactions)
                .await?;
        }
        let tool_calls = tool_call_records_from_trace(trace);
        if !tool_calls.is_empty() {
            write_redacted_bundle_jsonl(
                &out,
                "tool_calls.jsonl",
                &tool_calls,
                &mut files,
                &mut redactions,
            )
            .await?;
        }
    }
    if let Some(spec) = &agent_spec {
        write_redacted_bundle_json(&out, "agent_spec.json", spec, &mut files, &mut redactions)
            .await?;
    }
    if let Some(manifest) = &prompt_manifest {
        write_redacted_bundle_json(
            &out,
            "prompt_manifest.json",
            manifest,
            &mut files,
            &mut redactions,
        )
        .await?;
    }
    write_redacted_bundle_json(
        &out,
        "state_snapshot.json",
        &state_snapshot,
        &mut files,
        &mut redactions,
    )
    .await?;
    write_bundle_json(&out, "redactions.json", &redactions, &mut files).await?;
    files.insert("manifest".to_owned(), "manifest.json".to_owned());

    let manifest = DebugBundleManifest::new(
        &record,
        agent_spec.as_ref().map(|spec| spec.version.clone()),
        files,
    );
    write_json_file(out.join("manifest.json"), &manifest).await?;
    print_json(&manifest)
}

async fn build_debug_state_snapshot(
    store_path: &Utf8Path,
    record: &AgentRunRecord,
) -> Result<DebugStateSnapshot> {
    let proposal_store = FileProposalStore::new(store_path.to_path_buf())
        .await
        .into_diagnostic()?;
    let proposals = proposal_store
        .list_proposals(Some(&record.run_id))
        .await
        .into_diagnostic()?;

    let session_id = string_metadata(&record.metadata, "session_id");
    let thread_id = string_metadata(&record.metadata, "thread_id");
    let session_store = FileSessionStore::new(store_path.to_path_buf())
        .await
        .into_diagnostic()?;
    let session = match &session_id {
        Some(session_id) => session_store
            .get_session(&SessionId(session_id.clone()))
            .await
            .into_diagnostic()?,
        None => None,
    };
    let thread = match &thread_id {
        Some(thread_id) => session_store
            .get_thread(&ThreadId(thread_id.clone()))
            .await
            .into_diagnostic()?,
        None => None,
    };
    let steps = match &thread {
        Some(thread) => session_store
            .list_steps(&thread.thread_id)
            .await
            .into_diagnostic()?,
        None => Vec::new(),
    };
    let captured_at = time::OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .into_diagnostic()?;

    Ok(DebugStateSnapshot {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        runtime_version: RUNTIME_VERSION.to_owned(),
        captured_at,
        store_root: store_path.to_string(),
        run_id: record.run_id.0.clone(),
        agent_id: record.agent_id.clone(),
        run_status: record.status.clone(),
        session_id,
        thread_id,
        session,
        thread,
        steps,
        proposals,
    })
}

fn build_debug_replay_config(
    store_path: &Utf8Path,
    catalog_path: Option<&Utf8PathBuf>,
    trace_path: Option<&Utf8PathBuf>,
    timeout_seconds: u64,
    include_prompt_manifest: bool,
    record: &AgentRunRecord,
    run_request: &RunRequest,
) -> DebugReplayConfig {
    let mut assets = BTreeMap::new();
    assets.insert("run_request".to_owned(), "run_request.json".to_owned());
    assets.insert("trace".to_owned(), "trace.json".to_owned());
    assets.insert("events".to_owned(), "events.jsonl".to_owned());
    assets.insert("tool_calls".to_owned(), "tool_calls.jsonl".to_owned());
    assets.insert(
        "state_snapshot".to_owned(),
        "state_snapshot.json".to_owned(),
    );
    if include_prompt_manifest {
        assets.insert(
            "prompt_manifest".to_owned(),
            "prompt_manifest.json".to_owned(),
        );
    }

    let mut replay_command = vec![
        "agent".to_owned(),
        "replay".to_owned(),
        "trace.json".to_owned(),
        "--execute".to_owned(),
        "--store".to_owned(),
        store_path.to_string(),
        "--timeout-seconds".to_owned(),
        timeout_seconds.to_string(),
    ];
    if let Some(catalog_path) = catalog_path {
        replay_command.push("--catalog".to_owned());
        replay_command.push(catalog_path.to_string());
    }

    DebugReplayConfig {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        runtime_version: RUNTIME_VERSION.to_owned(),
        run_id: record.run_id.0.clone(),
        agent_id: record.agent_id.clone(),
        replay_mode: "trace_execute".to_owned(),
        source_store: store_path.to_string(),
        source_trace: trace_path.map(ToString::to_string),
        catalog: catalog_path.map(ToString::to_string),
        timeout_seconds,
        assets,
        replay_command,
        run_request: run_request.clone(),
    }
}

fn run_request_from_record(record: &AgentRunRecord) -> RunRequest {
    RunRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        run_id: Some(record.run_id.clone()),
        input: record.input.clone(),
        user: user_from_record(record),
        trigger: TriggerKind::Replay,
        metadata: json!({
            "source": "debug_bundle",
            "reconstructed_from": "run_record"
        }),
    }
}

fn user_from_record(record: &AgentRunRecord) -> Option<UserContext> {
    match &record.scope {
        agent_core::RunScope::User(user_id) => Some(UserContext {
            user_id: user_id.clone(),
            metadata: json!({}),
        }),
        _ => None,
    }
}

fn run_result_from_record(record: &AgentRunRecord) -> Result<AgentRunResult> {
    let finished_at = record.finished_at.unwrap_or(record.started_at);
    Ok(AgentRunResult {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        run_id: record.run_id.clone(),
        agent_id: record.agent_id.clone(),
        status: record.status.clone(),
        started_at: record.started_at,
        finished_at,
        summary: record.error.as_ref().map(|error| error.message.clone()),
        output: record.output.clone(),
        error: record.error.clone(),
    })
}

async fn write_bundle_json(
    out: &Utf8Path,
    name: &str,
    value: &impl Serialize,
    files: &mut BTreeMap<String, String>,
) -> Result<()> {
    write_json_file(out.join(name), value).await?;
    files.insert(bundle_file_key(name), name.to_owned());
    Ok(())
}

async fn write_redacted_bundle_jsonl(
    out: &Utf8Path,
    name: &str,
    values: &[Value],
    files: &mut BTreeMap<String, String>,
    report: &mut RedactionReport,
) -> Result<()> {
    let mut lines = Vec::new();
    for (index, value) in values.iter().enumerate() {
        let mut value = value.clone();
        redact_json_value(
            &mut value,
            &format!("$.{}[{index}]", bundle_file_key(name)),
            report,
        );
        lines.push(serde_json::to_string(&value).into_diagnostic()?);
    }
    fs_err::tokio::write(out.join(name), format!("{}\n", lines.join("\n")))
        .await
        .into_diagnostic()?;
    files.insert(bundle_file_key(name), name.to_owned());
    Ok(())
}

async fn write_redacted_bundle_json(
    out: &Utf8Path,
    name: &str,
    value: &impl Serialize,
    files: &mut BTreeMap<String, String>,
    report: &mut RedactionReport,
) -> Result<()> {
    let mut value = serde_json::to_value(value).into_diagnostic()?;
    redact_json_value(&mut value, "$", report);
    write_bundle_json(out, name, &value, files).await
}

fn bundle_file_key(name: &str) -> String {
    name.trim_end_matches(".json")
        .trim_end_matches(".jsonl")
        .to_owned()
}

fn redact_json_value(value: &mut Value, path: &str, report: &mut RedactionReport) {
    match value {
        Value::Object(map) => {
            for (key, value) in map.iter_mut() {
                let child_path = format!("{path}.{}", json_path_key(key));
                if is_sensitive_key(key) {
                    if !value.is_null() {
                        *value = Value::String(report.replacement.clone());
                        report.redacted_paths.push(child_path);
                    }
                } else {
                    redact_json_value(value, &child_path, report);
                }
            }
        }
        Value::Array(items) => {
            for (index, value) in items.iter_mut().enumerate() {
                redact_json_value(value, &format!("{path}[{index}]"), report);
            }
        }
        _ => {}
    }
}

fn is_sensitive_key(key: &str) -> bool {
    let key = key.to_ascii_lowercase();
    [
        "authorization",
        "password",
        "passwd",
        "secret",
        "token",
        "access_token",
        "refresh_token",
        "api_key",
        "apikey",
        "jwt",
        "credential",
        "private_key",
    ]
    .iter()
    .any(|marker| key == *marker || key.ends_with(marker) || key.contains(&format!("{marker}_")))
}

fn json_path_key(key: &str) -> String {
    if key
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
    {
        key.to_owned()
    } else {
        format!("{key:?}")
    }
}

fn event_records_from_trace(trace: &Value) -> Vec<Value> {
    trace
        .get("events")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn tool_call_records_from_trace(trace: &Value) -> Vec<Value> {
    trace
        .get("events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|event| {
            let kind = event.get("kind").and_then(Value::as_str)?;
            if !matches!(kind, "tool_call_finished" | "tool_call_failed") {
                return None;
            }
            event.get("payload").cloned()
        })
        .collect()
}

async fn read_store_trace(store: &Utf8Path, run_id: &RunId) -> Result<Option<Value>> {
    let path = store_trace_path(store, run_id);
    if !path.exists() {
        return Ok(None);
    }
    read_json_file(path).await.map(Some)
}

fn store_trace_path(store: &Utf8Path, run_id: &RunId) -> Utf8PathBuf {
    store
        .join("traces")
        .join(format!("{}.trace.json", run_id.0))
}

async fn read_json_file(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
}

async fn write_json_file(path: Utf8PathBuf, value: &impl Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    let bytes = serde_json::to_vec_pretty(value).into_diagnostic()?;
    fs_err::tokio::write(&path, bytes)
        .await
        .map_err(|e| miette!("failed to write JSON at {path}: {e}"))
}

fn print_json(value: &impl Serialize) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(value).into_diagnostic()?);
    Ok(())
}
