use std::{process::Stdio, sync::Arc};

use agent_core::{
    AgentProposalStore, AgentRunRecord, AgentRunStore, HookEvent, HookEventName,
    HookInvocationStatus, HookKind, PROTOCOL_VERSION, PromptManifest, ProposalEnvelope,
    ProposalStatus, RunId, RunRequest, TriggerKind,
};
use agent_runtime::{AgentRunner, RunOutcome};
use agent_store::{FileProposalStore, FileRunStore};
use camino::{Utf8Path, Utf8PathBuf};
use miette::{IntoDiagnostic, Result, miette};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command as TokioCommand;

use crate::catalog::{build_prompt_manifest, read_catalog, registry_from_catalog};
use crate::tools::{CliServices, ToolOverrides};

#[derive(Debug, Deserialize, Serialize)]
struct EvalCase {
    id: String,
    agent_id: String,
    catalog: Utf8PathBuf,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    golden_trace: Option<Utf8PathBuf>,
    #[serde(default)]
    input: Value,
    expect: EvalExpect,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    scoring_hook: Option<EvalScoringHook>,
}

#[derive(Debug, Deserialize, Serialize)]
struct EvalExpect {
    status: agent_core::AgentRunStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    agent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    trace_events: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    tool_calls: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    proposals: Option<EvalProposalExpect>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    prompt_manifest: Option<EvalPromptManifestExpect>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    output_mode: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
struct EvalProposalExpect {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    min_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    kinds: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    statuses: Vec<ProposalStatus>,
}

#[derive(Debug, Deserialize, Serialize)]
struct EvalPromptManifestExpect {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    agent_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model_family: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    provider: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    tool_schema_version: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    block_hashes: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
struct EvalScoringHook {
    command: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    min_score: Option<f64>,
}

#[derive(Debug, Deserialize, Serialize)]
struct EvalScoringResult {
    passed: bool,
    score: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    comment: Option<String>,
}

#[derive(Debug)]
struct EvalScoringHookOutcome {
    result: EvalScoringResult,
    hook_event: HookEvent,
}

#[derive(Debug, Serialize)]
struct EvalReport {
    id: String,
    passed: bool,
    run_id: String,
    agent_id: String,
    status: agent_core::AgentRunStatus,
    checked: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    score: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    scoring_comment: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    hooks: Vec<HookEvent>,
}

#[derive(Debug, Serialize)]
struct EvalSuiteReport {
    passed: bool,
    total: usize,
    passed_count: usize,
    failed_count: usize,
    reports: Vec<EvalReport>,
}

#[derive(Debug, Serialize)]
struct EvalCreateReport {
    id: String,
    run_id: String,
    agent_id: String,
    eval_file: String,
    golden_trace: String,
}

pub(crate) async fn run_eval_path(
    eval_path: Utf8PathBuf,
    store_path: Utf8PathBuf,
    tool_overrides: ToolOverrides,
    update_golden: bool,
) -> Result<Value> {
    if eval_path.is_dir() {
        let mut reports = Vec::new();
        for path in discover_eval_files(&eval_path)? {
            reports.push(
                run_eval(
                    path,
                    store_path.clone(),
                    tool_overrides.clone(),
                    update_golden,
                )
                .await?,
            );
        }
        let total = reports.len();
        let report = EvalSuiteReport {
            passed: true,
            total,
            passed_count: total,
            failed_count: 0,
            reports,
        };
        serde_json::to_value(report).into_diagnostic()
    } else {
        let report = run_eval(eval_path, store_path, tool_overrides, update_golden).await?;
        serde_json::to_value(report).into_diagnostic()
    }
}

pub(crate) async fn create_eval_from_run(
    run_id: String,
    store_path: Utf8PathBuf,
    out: Utf8PathBuf,
    catalog: Utf8PathBuf,
    id: Option<String>,
    golden_trace: Option<Utf8PathBuf>,
) -> Result<Value> {
    let store = FileRunStore::new(store_path.clone())
        .await
        .into_diagnostic()?;
    let run_id = RunId(run_id);
    let record = store
        .get_run(&run_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("run '{}' was not found", run_id.0))?;
    let trace = read_store_trace(&store_path, &run_id)
        .await?
        .ok_or_else(|| miette!("trace for run '{}' was not found", run_id.0))?;
    let catalog_path = absolutize_runtime_path(catalog)?;
    let catalog = read_catalog(catalog_path.clone()).await?;
    let prompt_manifest =
        eval_prompt_manifest_expectation(&build_prompt_manifest(&catalog, Some(&record.agent_id))?);
    let proposal_store = FileProposalStore::new(store_path.clone())
        .await
        .into_diagnostic()?;
    let proposals = proposal_store
        .list_proposals(Some(&run_id))
        .await
        .into_diagnostic()?;

    let eval_id = id.unwrap_or_else(|| default_eval_id(&record));
    let eval_dir = out.parent().unwrap_or_else(|| Utf8Path::new("."));
    let golden_trace =
        golden_trace.unwrap_or_else(|| Utf8PathBuf::from(format!("golden/{eval_id}.trace.json")));
    let golden_trace_abs = absolutize_eval_path(eval_dir, &golden_trace);
    let mut normalized_trace = trace.clone();
    normalize_volatile_json(&mut normalized_trace);
    write_json_file(golden_trace_abs.clone(), &normalized_trace).await?;

    let case = EvalCase {
        id: eval_id.clone(),
        agent_id: record.agent_id.clone(),
        catalog: catalog_path,
        golden_trace: Some(golden_trace.clone()),
        input: record.input.clone(),
        expect: EvalExpect {
            status: record.status.clone(),
            agent_id: Some(record.agent_id.clone()),
            trace_events: trace_event_kinds(&trace),
            tool_calls: tool_call_sequence_from_trace_value(&trace),
            proposals: eval_proposal_expectation(&proposals),
            prompt_manifest: Some(prompt_manifest),
            output_mode: record
                .output
                .get("mode")
                .and_then(Value::as_str)
                .map(str::to_owned),
        },
        scoring_hook: None,
    };

    write_yaml_file(out.clone(), &case).await?;
    let report = EvalCreateReport {
        id: eval_id,
        run_id: run_id.0,
        agent_id: record.agent_id,
        eval_file: out.to_string(),
        golden_trace: golden_trace_abs.to_string(),
    };
    serde_json::to_value(report).into_diagnostic()
}

async fn run_eval(
    eval_file: Utf8PathBuf,
    store_path: Utf8PathBuf,
    tool_overrides: ToolOverrides,
    update_golden: bool,
) -> Result<EvalReport> {
    let bytes = fs_err::tokio::read(&eval_file)
        .await
        .map_err(|e| miette!("failed to read eval at {eval_file}: {e}"))?;
    let case: EvalCase = serde_yaml::from_slice(&bytes)
        .map_err(|e| miette!("failed to parse eval at {eval_file}: {e}"))?;
    let base = eval_file.parent().unwrap_or_else(|| Utf8Path::new("."));
    let catalog_path = absolutize_eval_path(base, &case.catalog);
    let catalog = read_catalog(catalog_path).await?;
    let expected_prompt_manifest = match &case.expect.prompt_manifest {
        Some(_) => Some(build_prompt_manifest(&catalog, Some(&case.agent_id))?),
        None => None,
    };
    let registry = registry_from_catalog(&catalog);
    let trace_store_path = store_path.clone();
    let store = Arc::new(FileRunStore::new(store_path).await.into_diagnostic()?);
    let proposal_store = Arc::new(
        FileProposalStore::new(trace_store_path.clone())
            .await
            .into_diagnostic()?,
    );
    let services = Arc::new(CliServices::with_proposal_store(
        tool_overrides,
        proposal_store.clone(),
    ));
    let runner = AgentRunner::new(registry, store, services);
    let outcome = runner
        .run_once(
            &case.agent_id,
            RunRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                run_id: None,
                input: case.input.clone(),
                user: None,
                trigger: TriggerKind::Manual,
                metadata: json!({"eval_id": case.id}),
            },
        )
        .await
        .into_diagnostic()?;
    write_store_trace(&trace_store_path, &outcome.trace).await?;

    let mut checked = Vec::new();
    if outcome.result.status != case.expect.status {
        return Err(miette!(
            "eval {} expected status {:?}, got {:?}",
            case.id,
            case.expect.status,
            outcome.result.status
        ));
    }
    checked.push("status".to_owned());

    if let Some(expected_agent_id) = &case.expect.agent_id {
        if &outcome.result.agent_id != expected_agent_id {
            return Err(miette!(
                "eval {} expected agent_id {}, got {}",
                case.id,
                expected_agent_id,
                outcome.result.agent_id
            ));
        }
        checked.push("agent_id".to_owned());
    }

    if let Some(expected_mode) = &case.expect.output_mode {
        let actual = outcome.result.output.get("mode").and_then(Value::as_str);
        if actual != Some(expected_mode.as_str()) {
            return Err(miette!(
                "eval {} expected output mode {}, got {:?}",
                case.id,
                expected_mode,
                actual
            ));
        }
        checked.push("output_mode".to_owned());
    }

    if let (Some(expected), Some(manifest)) =
        (&case.expect.prompt_manifest, &expected_prompt_manifest)
    {
        check_prompt_manifest_expectation(&case.id, expected, manifest)?;
        checked.push("prompt_manifest".to_owned());
    }

    for expected_event in &case.expect.trace_events {
        let found = outcome
            .trace
            .events
            .iter()
            .any(|event| &event.kind == expected_event);
        if !found {
            return Err(miette!(
                "eval {} expected trace event {}",
                case.id,
                expected_event
            ));
        }
        checked.push(format!("trace_event:{expected_event}"));
    }

    if !case.expect.tool_calls.is_empty() {
        let actual_tool_calls = tool_call_sequence_from_trace(&outcome.trace);
        if actual_tool_calls != case.expect.tool_calls {
            return Err(miette!(
                "eval {} expected tool calls {:?}, got {:?}",
                case.id,
                case.expect.tool_calls,
                actual_tool_calls
            ));
        }
        checked.push("tool_calls".to_owned());
    }

    if let Some(expected_proposals) = &case.expect.proposals {
        let proposals = proposal_store
            .list_proposals(Some(&outcome.result.run_id))
            .await
            .into_diagnostic()?;
        if let Some(min_count) = expected_proposals.min_count
            && proposals.len() < min_count
        {
            return Err(miette!(
                "eval {} expected at least {} proposals, got {}",
                case.id,
                min_count,
                proposals.len()
            ));
        }
        for kind in &expected_proposals.kinds {
            if !proposals.iter().any(|proposal| &proposal.kind == kind) {
                return Err(miette!("eval {} expected proposal kind {}", case.id, kind));
            }
        }
        for status in &expected_proposals.statuses {
            if !proposals.iter().any(|proposal| &proposal.status == status) {
                return Err(miette!(
                    "eval {} expected proposal status {:?}",
                    case.id,
                    status
                ));
            }
        }
        checked.push("proposals".to_owned());
    }

    if let Some(golden_path) = &case.golden_trace {
        let golden_path = absolutize_eval_path(base, golden_path);
        let actual = normalized_trace_json(&outcome.trace)?;
        if update_golden {
            write_json_file(golden_path, &actual).await?;
            checked.push("golden_trace:updated".to_owned());
        } else {
            let expected = read_json_file(golden_path.clone()).await?;
            if expected != actual {
                return Err(miette!(
                    "eval {} golden trace mismatch at {}",
                    case.id,
                    golden_path
                ));
            }
            checked.push("golden_trace".to_owned());
        }
    }

    let mut score = None;
    let mut scoring_comment = None;
    let mut hooks = Vec::new();
    if let Some(hook) = &case.scoring_hook {
        let hook_outcome = run_eval_scoring_hook(hook, &case, &outcome, &checked).await?;
        let scoring = hook_outcome.result;
        hooks.push(hook_outcome.hook_event);
        if let Some(min_score) = hook.min_score
            && scoring.score < min_score
        {
            return Err(miette!(
                "eval {} scoring hook returned score {} below threshold {}",
                case.id,
                scoring.score,
                min_score
            ));
        }
        if !scoring.passed {
            return Err(miette!(
                "eval {} scoring hook failed: {}",
                case.id,
                scoring.comment.as_deref().unwrap_or("no comment")
            ));
        }
        checked.push("scoring_hook".to_owned());
        score = Some(scoring.score);
        scoring_comment = scoring.comment;
    }

    Ok(EvalReport {
        id: case.id,
        passed: true,
        run_id: outcome.result.run_id.0,
        agent_id: outcome.result.agent_id,
        status: outcome.result.status,
        checked,
        score,
        scoring_comment,
        hooks,
    })
}

async fn run_eval_scoring_hook(
    hook: &EvalScoringHook,
    case: &EvalCase,
    outcome: &RunOutcome,
    checked: &[String],
) -> Result<EvalScoringHookOutcome> {
    let (command, args) = hook
        .command
        .split_first()
        .ok_or_else(|| miette!("eval {} scoring_hook.command cannot be empty", case.id))?;
    let payload = json!({
        "protocol_version": PROTOCOL_VERSION,
        "eval_id": case.id,
        "agent_id": &outcome.result.agent_id,
        "run_id": &outcome.result.run_id,
        "status": &outcome.result.status,
        "checked": checked,
        "result": &outcome.result,
        "trace": &outcome.trace,
    });
    let started_at = time::OffsetDateTime::now_utc();
    let started = std::time::Instant::now();
    let mut child = TokioCommand::new(command)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| miette!("failed to spawn scoring hook {command}: {e}"))?;

    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| miette!("scoring hook stdin missing"))?;
    let mut encoded = serde_json::to_vec(&payload).into_diagnostic()?;
    encoded.push(b'\n');
    stdin.write_all(&encoded).await.into_diagnostic()?;
    drop(stdin);

    let output = child.wait_with_output().await.into_diagnostic()?;
    let finished_at = time::OffsetDateTime::now_utc();
    let duration_ms = u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX);
    if !output.status.success() {
        return Err(miette!(
            "scoring hook exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let result: EvalScoringResult = serde_json::from_slice(&output.stdout)
        .map_err(|e| miette!("failed to parse scoring hook response: {e}"))?;
    let hook_event = HookEvent {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        hook_event: HookEventName::AfterAgentStep,
        hook_kind: HookKind::Process,
        hook_name: "eval.scoring_hook".to_owned(),
        command: Some(hook.command.clone()),
        run_id: Some(outcome.result.run_id.clone()),
        agent_id: Some(outcome.result.agent_id.clone()),
        status: HookInvocationStatus::Completed,
        started_at,
        finished_at,
        duration_ms,
        input: payload,
        output: Some(serde_json::to_value(&result).into_diagnostic()?),
        error: None,
    };
    Ok(EvalScoringHookOutcome { result, hook_event })
}

pub(crate) async fn run_dev_score_hook() -> Result<()> {
    let stdin = BufReader::new(tokio::io::stdin());
    let mut lines = stdin.lines();
    let Some(line) = lines.next_line().await.into_diagnostic()? else {
        return Err(miette!("score hook expected one JSON line on stdin"));
    };
    let request: Value = serde_json::from_str(&line).into_diagnostic()?;
    let status = request.get("status").and_then(Value::as_str);
    let passed = status == Some("completed");
    let score = if passed { 1.0 } else { 0.0 };
    let response = json!({
        "passed": passed,
        "score": score,
        "comment": format!("dev score hook saw status {:?}", status),
    });
    println!("{}", serde_json::to_string(&response).into_diagnostic()?);
    Ok(())
}

fn eval_prompt_manifest_expectation(manifest: &PromptManifest) -> EvalPromptManifestExpect {
    EvalPromptManifestExpect {
        id: Some(manifest.id.clone()),
        version: Some(manifest.version.clone()),
        agent_version: Some(manifest.agent_version.clone()),
        model_family: Some(manifest.model_family.clone()),
        provider: Some(manifest.provider.clone()),
        model: Some(manifest.model.clone()),
        tool_schema_version: Some(manifest.tool_schema_version.clone()),
        block_hashes: manifest
            .blocks
            .iter()
            .map(|block| block.content_hash.clone())
            .collect(),
    }
}

fn eval_proposal_expectation(proposals: &[ProposalEnvelope]) -> Option<EvalProposalExpect> {
    if proposals.is_empty() {
        return None;
    }

    let mut kinds = Vec::new();
    let mut statuses = Vec::new();
    for proposal in proposals {
        if !kinds.contains(&proposal.kind) {
            kinds.push(proposal.kind.clone());
        }
        if !statuses.contains(&proposal.status) {
            statuses.push(proposal.status.clone());
        }
    }

    Some(EvalProposalExpect {
        min_count: Some(proposals.len()),
        kinds,
        statuses,
    })
}

fn check_prompt_manifest_expectation(
    eval_id: &str,
    expected: &EvalPromptManifestExpect,
    manifest: &PromptManifest,
) -> Result<()> {
    check_expected_prompt_field(eval_id, "id", expected.id.as_deref(), &manifest.id)?;
    check_expected_prompt_field(
        eval_id,
        "version",
        expected.version.as_deref(),
        &manifest.version,
    )?;
    check_expected_prompt_field(
        eval_id,
        "agent_version",
        expected.agent_version.as_deref(),
        &manifest.agent_version,
    )?;
    check_expected_prompt_field(
        eval_id,
        "model_family",
        expected.model_family.as_deref(),
        &manifest.model_family,
    )?;
    check_expected_prompt_field(
        eval_id,
        "provider",
        expected.provider.as_deref(),
        &manifest.provider,
    )?;
    check_expected_prompt_field(eval_id, "model", expected.model.as_deref(), &manifest.model)?;
    check_expected_prompt_field(
        eval_id,
        "tool_schema_version",
        expected.tool_schema_version.as_deref(),
        &manifest.tool_schema_version,
    )?;

    if !expected.block_hashes.is_empty() {
        let actual = manifest
            .blocks
            .iter()
            .map(|block| block.content_hash.as_str())
            .collect::<Vec<_>>();
        let expected_hashes = expected
            .block_hashes
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>();
        if actual != expected_hashes {
            return Err(miette!(
                "eval {} expected prompt block hashes {:?}, got {:?}",
                eval_id,
                expected_hashes,
                actual
            ));
        }
    }
    Ok(())
}

fn check_expected_prompt_field(
    eval_id: &str,
    field: &str,
    expected: Option<&str>,
    actual: &str,
) -> Result<()> {
    if let Some(expected) = expected
        && actual != expected
    {
        return Err(miette!(
            "eval {} expected prompt manifest {} {}, got {}",
            eval_id,
            field,
            expected,
            actual
        ));
    }
    Ok(())
}

fn default_eval_id(record: &AgentRunRecord) -> String {
    format!(
        "{}_{}",
        sanitize_eval_id(&record.agent_id),
        sanitize_eval_id(&record.run_id.0)
    )
}

fn sanitize_eval_id(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn trace_event_kinds(trace: &Value) -> Vec<String> {
    trace
        .get("events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|event| event.get("kind").and_then(Value::as_str))
        .map(str::to_owned)
        .collect()
}

fn tool_call_sequence_from_trace(trace: &agent_core::AgentTrace) -> Vec<String> {
    trace
        .events
        .iter()
        .filter(|event| {
            matches!(
                event.kind.as_str(),
                "tool_call_finished" | "tool_call_failed"
            )
        })
        .filter_map(|event| event.payload.get("tool_name").and_then(Value::as_str))
        .map(str::to_owned)
        .collect()
}

fn tool_call_sequence_from_trace_value(trace: &Value) -> Vec<String> {
    trace
        .get("events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|event| {
            event
                .get("kind")
                .and_then(Value::as_str)
                .is_some_and(|kind| matches!(kind, "tool_call_finished" | "tool_call_failed"))
        })
        .filter_map(|event| {
            event
                .get("payload")
                .and_then(|payload| payload.get("tool_name"))
                .and_then(Value::as_str)
        })
        .map(str::to_owned)
        .collect()
}

fn discover_eval_files(root: &Utf8Path) -> Result<Vec<Utf8PathBuf>> {
    let mut paths = Vec::new();
    for entry in walkdir::WalkDir::new(root) {
        let entry = entry.into_diagnostic()?;
        if !entry.file_type().is_file() {
            continue;
        }
        let path = Utf8PathBuf::from_path_buf(entry.path().to_path_buf())
            .map_err(|path| miette!("non-UTF-8 eval path: {}", path.display()))?;
        let Some(ext) = path.extension() else {
            continue;
        };
        if ext == "yaml" || ext == "yml" {
            paths.push(path);
        }
    }
    paths.sort();
    Ok(paths)
}

fn normalized_trace_json(trace: &agent_core::AgentTrace) -> Result<Value> {
    let mut value = serde_json::to_value(trace).into_diagnostic()?;
    normalize_volatile_json(&mut value);
    Ok(value)
}

fn normalize_volatile_json(value: &mut Value) {
    match value {
        Value::Object(map) => {
            for key in [
                "run_id",
                "proposal_id",
                "started_at",
                "created_at",
                "finished_at",
                "occurred_at",
                "expires_at",
                "runtime_version",
            ] {
                map.remove(key);
            }
            for value in map.values_mut() {
                normalize_volatile_json(value);
            }
        }
        Value::Array(items) => {
            for item in items {
                normalize_volatile_json(item);
            }
        }
        _ => {}
    }
}

fn absolutize_eval_path(base: &Utf8Path, path: &Utf8Path) -> Utf8PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        base.join(path)
    }
}

fn absolutize_runtime_path(path: Utf8PathBuf) -> Result<Utf8PathBuf> {
    if path.is_absolute() {
        return Ok(path);
    }
    let cwd = std::env::current_dir().into_diagnostic()?;
    Utf8PathBuf::from_path_buf(cwd.join(path.as_std_path()))
        .map_err(|path| miette!("non-UTF-8 path: {}", path.display()))
}

async fn write_store_trace(store: &Utf8Path, trace: &agent_core::AgentTrace) -> Result<()> {
    write_json_file(store_trace_path(store, &trace.run_id), trace).await
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

async fn write_yaml_file(path: Utf8PathBuf, value: &impl Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    let bytes = serde_yaml::to_string(value).into_diagnostic()?;
    fs_err::tokio::write(&path, bytes)
        .await
        .map_err(|e| miette!("failed to write YAML at {path}: {e}"))
}
