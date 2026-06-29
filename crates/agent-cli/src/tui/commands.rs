use std::sync::Arc;

use agent_core::{
    AgentRegistry, AgentRunStore, AgentServices, PROTOCOL_VERSION, RunId, RunRequest,
};
use agent_runtime::AgentRunner;
use agent_store::{FileProposalStore, FileRunStore};
use camino::Utf8PathBuf;
use miette::{IntoDiagnostic, Result, miette};
use serde::Serialize;
use serde_json::{Value, json};

use crate::{
    catalog::{load_catalog_registry, read_catalog},
    config::execution_policy,
    registry::load_registry,
    tools::CliServices,
    trace_store::write_store_trace,
};

use super::data::{TuiState, read_trace};

pub(super) async fn execute_command(state: &mut TuiState, input: &str) -> Result<()> {
    let input = input.trim();
    if input.is_empty() {
        return Ok(());
    }
    let Some(command) = input.strip_prefix('/') else {
        return run_natural_language_command(state, input).await;
    };
    execute_slash_command(state, command.trim()).await
}

async fn execute_slash_command(state: &mut TuiState, input: &str) -> Result<()> {
    let (verb, rest) = split_once(input);
    match verb {
        "help" | "?" => show_help(state),
        "clear" => state.clear_log(),
        "refresh" => {
            state.refresh().await?;
            state.push_log("refreshed catalog/trace/store");
        }
        "run" => run_agent_command(state, rest).await?,
        "tool" | "call" => tool_call_command(state, rest).await?,
        "trace" | "replay" => load_trace_command(state, rest).await?,
        "inspect" => inspect_run_command(state, rest).await?,
        other => state.push_log(format!(
            "unknown command '/{other}'. Try: /help, /run, /tool, /replay, /inspect, /refresh, /clear"
        )),
    }
    Ok(())
}

fn show_help(state: &mut TuiState) {
    state.push_log("Type natural language and press Enter to run the default agent.");
    state.push_log("Slash commands:");
    state.push_log("  /run <agent_id> [json|text]  run a specific agent");
    state.push_log("  /tool <name> [json]          call a tool through active CLI services");
    state.push_log("  /replay <trace_path>         load a trace into the Trace panel");
    state.push_log("  /inspect <run_id>            load a persisted run record summary");
    state.push_log("  /refresh                     reload catalog, trace, and recent runs");
    state.push_log("  /clear                       clear the output panel");
}

async fn run_natural_language_command(state: &mut TuiState, text: &str) -> Result<()> {
    let agent_id = default_agent_id(state).await?;
    let input = json!({
        "message": text,
        "surface": "agent_tui",
        "mode": "natural_language"
    });
    state.push_log(format!("you: {text}"));
    run_agent_with_input(state, &agent_id, input, "natural_language").await
}

async fn run_agent_command(state: &mut TuiState, rest: &str) -> Result<()> {
    let (agent_id, json_input) = split_name_and_json(rest, "agent id")?;
    let input = parse_run_input(json_input)?;
    state.push_log(format!("/run {agent_id} {}", compact_json(&input)));
    run_agent_with_input(state, &agent_id, input, "slash_command").await
}

async fn run_agent_with_input(
    state: &mut TuiState,
    agent_id: &str,
    input: Value,
    input_mode: &str,
) -> Result<()> {
    let registry = load_active_registry(state).await?;
    let store_path = state.options.store_path.clone();
    let store = Arc::new(
        FileRunStore::new(store_path.clone())
            .await
            .into_diagnostic()?,
    );
    let proposal_store = Arc::new(
        FileProposalStore::new(store_path.clone())
            .await
            .into_diagnostic()?,
    );
    let services = Arc::new(CliServices::with_proposal_store(
        state.options.tool_overrides.clone(),
        proposal_store,
    ));
    let runner = AgentRunner::new(registry, store, services).with_policy(execution_policy(
        state.options.timeout_seconds,
        state.options.max_retries,
        state.options.retry_backoff_ms,
    ));
    let outcome = runner
        .run_once(
            &agent_id,
            RunRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                run_id: None,
                input,
                user: None,
                trigger: agent_core::TriggerKind::Manual,
                metadata: json!({
                    "source": "agent_tui",
                    "input_mode": input_mode,
                    "surface": "agent_tui"
                }),
            },
        )
        .await
        .into_diagnostic()?;
    write_store_trace(&store_path, &outcome.trace).await?;
    state.set_trace(
        format!("latest run {}", outcome.result.run_id.0),
        outcome.trace,
    );
    state.refresh_runs().await?;
    state.push_log(format!(
        "run {} {} {:?}",
        outcome.result.run_id.0, outcome.result.agent_id, outcome.result.status
    ));
    if let Some(summary) = outcome.result.summary {
        state.push_log(format!("summary: {summary}"));
    }
    push_agent_output(state, &outcome.result.output);
    Ok(())
}

async fn tool_call_command(state: &mut TuiState, rest: &str) -> Result<()> {
    let (name, json_input) = split_name_and_json(rest, "tool name")?;
    let input = parse_json_or_default(json_input, "tool input")?;
    state.push_log(format!("/tool {name} {}", compact_json(&input)));
    let services = CliServices::new(state.options.tool_overrides.clone());
    let output = services
        .call_tool(&name, input)
        .await
        .map_err(|err| miette!(err.record.message))?;
    state.push_log(pretty_json(&output));
    Ok(())
}

async fn load_trace_command(state: &mut TuiState, rest: &str) -> Result<()> {
    let path = rest.trim();
    if path.is_empty() {
        return Err(miette!("trace path is required"));
    }
    let path = Utf8PathBuf::from(path);
    let trace = read_trace(path.clone()).await?;
    state.set_trace(path.to_string(), trace);
    state.push_log(format!("loaded trace {path}"));
    Ok(())
}

async fn inspect_run_command(state: &mut TuiState, rest: &str) -> Result<()> {
    let run_id = rest.trim();
    if run_id.is_empty() {
        return Err(miette!("run id is required"));
    }
    let store = FileRunStore::new(state.options.store_path.clone())
        .await
        .into_diagnostic()?;
    let record = store
        .get_run(&RunId(run_id.to_owned()))
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("run '{run_id}' was not found"))?;
    state.push_log(format!(
        "run {} {} {:?}",
        run_id, record.agent_id, record.status
    ));
    state.push_log(pretty_json(&record));
    Ok(())
}

fn split_once(input: &str) -> (&str, &str) {
    input
        .trim()
        .split_once(char::is_whitespace)
        .map(|(head, tail)| (head, tail.trim()))
        .unwrap_or((input.trim(), ""))
}

fn split_name_and_json<'a>(input: &'a str, label: &str) -> Result<(String, &'a str)> {
    let input = input.trim();
    if input.is_empty() {
        return Err(miette!("{label} is required"));
    }
    let (name, rest) = split_once(input);
    if name.trim().is_empty() {
        return Err(miette!("{label} is required"));
    }
    Ok((name.to_owned(), rest))
}

fn parse_json_or_default(input: &str, label: &str) -> Result<Value> {
    if input.trim().is_empty() {
        return Ok(json!({}));
    }
    serde_json::from_str(input).map_err(|e| miette!("failed to parse {label} as JSON: {e}"))
}

fn parse_run_input(input: &str) -> Result<Value> {
    let input = input.trim();
    if input.is_empty() {
        return Ok(json!({}));
    }
    match serde_json::from_str(input) {
        Ok(value) => Ok(value),
        Err(_) => Ok(json!({"message": input})),
    }
}

async fn default_agent_id(state: &TuiState) -> Result<String> {
    let agents = match &state.options.catalog_path {
        Some(path) => read_catalog(path.clone()).await?.agents,
        None => load_registry(state.options.registry_path.clone())
            .await?
            .list_specs(),
    };
    agents
        .into_iter()
        .next()
        .map(|agent| agent.id)
        .ok_or_else(|| miette!("no default agent is available"))
}

async fn load_active_registry(state: &TuiState) -> Result<Arc<dyn AgentRegistry>> {
    match &state.options.catalog_path {
        Some(path) => {
            let registry: Arc<dyn AgentRegistry> = load_catalog_registry(path.clone()).await?;
            Ok(registry)
        }
        None => {
            let registry: Arc<dyn AgentRegistry> =
                load_registry(state.options.registry_path.clone())
                    .await?
                    .into_agent_registry();
            Ok(registry)
        }
    }
}

fn push_agent_output(state: &mut TuiState, output: &Value) {
    if let Some(message) = output.get("message").and_then(Value::as_str) {
        state.push_log(format!("agent: {message}"));
    } else if let Some(content) = output.get("content").and_then(Value::as_str) {
        state.push_log(format!("agent: {content}"));
    } else {
        state.push_log(pretty_json(output));
    }
}

fn pretty_json(value: &impl Serialize) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| "<unprintable json>".to_owned())
}

fn compact_json(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "{}".to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{tools::ToolOverrides, tui::data::TuiOptions};

    fn temp_store_path(dir: &tempfile::TempDir) -> Utf8PathBuf {
        Utf8PathBuf::from_path_buf(dir.path().join("store")).expect("temp path should be utf8")
    }

    #[tokio::test]
    async fn run_command_executes_agent_and_loads_trace() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut state = TuiState::load(TuiOptions {
            catalog_path: None,
            trace_path: None,
            store_path: temp_store_path(&dir),
            registry_path: Utf8PathBuf::from("../../examples/agent-runtime/agents.yaml"),
            tool_overrides: ToolOverrides::default(),
            timeout_seconds: 60,
            max_retries: 0,
            retry_backoff_ms: 0,
            once: false,
        })
        .await
        .expect("state loads");

        execute_command(
            &mut state,
            r#"/run echo_agent {"message":"from interactive tui"}"#,
        )
        .await
        .expect("run command succeeds");

        assert!(state.trace.is_some());
        assert_eq!(state.recent_runs.len(), 1);
        assert_eq!(state.recent_runs[0].agent_id, "echo_agent");
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("from interactive tui"))
        );
    }

    #[tokio::test]
    async fn natural_language_input_runs_default_agent() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut state = TuiState::load(TuiOptions {
            catalog_path: None,
            trace_path: None,
            store_path: temp_store_path(&dir),
            registry_path: Utf8PathBuf::from("../../examples/agent-runtime/agents.yaml"),
            tool_overrides: ToolOverrides::default(),
            timeout_seconds: 60,
            max_retries: 0,
            retry_backoff_ms: 0,
            once: false,
        })
        .await
        .expect("state loads");

        execute_command(&mut state, "Summarize my day")
            .await
            .expect("natural input runs");

        assert!(state.trace.is_some());
        assert_eq!(state.recent_runs.len(), 1);
        assert_eq!(state.recent_runs[0].agent_id, "echo_agent");
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("you: Summarize my day"))
        );
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("agent: Summarize my day"))
        );
    }

    #[tokio::test]
    async fn run_command_accepts_text_input() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut state = TuiState::load(TuiOptions {
            catalog_path: None,
            trace_path: None,
            store_path: temp_store_path(&dir),
            registry_path: Utf8PathBuf::from("../../examples/agent-runtime/agents.yaml"),
            tool_overrides: ToolOverrides::default(),
            timeout_seconds: 60,
            max_retries: 0,
            retry_backoff_ms: 0,
            once: false,
        })
        .await
        .expect("state loads");

        execute_command(&mut state, "/run echo_agent hello tui")
            .await
            .expect("text run command succeeds");

        assert!(state.trace.is_some());
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("agent: hello tui"))
        );
    }

    #[tokio::test]
    async fn tool_command_calls_active_services() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut state = TuiState::load(TuiOptions {
            catalog_path: None,
            trace_path: None,
            store_path: temp_store_path(&dir),
            registry_path: Utf8PathBuf::from("../../examples/agent-runtime/agents.yaml"),
            tool_overrides: ToolOverrides::default(),
            timeout_seconds: 60,
            max_retries: 0,
            retry_backoff_ms: 0,
            once: false,
        })
        .await
        .expect("state loads");

        execute_command(&mut state, r#"/tool echo {"value":42}"#)
            .await
            .expect("tool command succeeds");

        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains(r#""value": 42"#))
        );
    }
}
