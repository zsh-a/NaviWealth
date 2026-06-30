use std::sync::Arc;

use agent_chat::{ChatTurnEvent, ChatTurnEventKind, ChatTurnRequest, ChatTurnRunner};
use agent_core::{
    AgentRegistry, AgentRunStore, AgentServices, PROTOCOL_VERSION, RunId, RunRequest, ToolRisk,
    ToolSpec,
};
use agent_llm::{LlmMessage, LlmRole, user_message};
use agent_runtime::AgentRunner;
use agent_store::{FileProposalStore, FileRunStore};
use camino::Utf8PathBuf;
use futures::StreamExt;
use miette::{IntoDiagnostic, Result, miette};
use serde::Serialize;
use serde_json::{Value, json};

use crate::{
    catalog::{load_catalog_registry, read_catalog},
    chat::provider_from_options,
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
    state.push_log(format!("you: {text}"));
    run_chat_turn(state, &agent_id, text).await
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
            agent_id,
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

async fn run_chat_turn(state: &mut TuiState, agent_id: &str, text: &str) -> Result<()> {
    let provider = provider_from_options(&state.options.chat)?;
    let proposal_store = Arc::new(
        FileProposalStore::new(state.options.store_path.clone())
            .await
            .into_diagnostic()?,
    );
    let services = Arc::new(CliServices::with_proposal_store(
        state.options.tool_overrides.clone(),
        proposal_store,
    ));
    let runner = ChatTurnRunner::new(provider, services);
    let user = user_message(text);
    state.chat_messages.push(user.clone());
    let request = ChatTurnRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        turn_id: None,
        surface: Some("agent_tui".to_owned()),
        mode: Some("natural_language".to_owned()),
        session_id: None,
        thread_id: None,
        agent_id: Some(agent_id.to_owned()),
        provider: state.options.chat.provider.clone(),
        model: state.options.chat.model.clone(),
        messages: state.chat_messages.clone(),
        temperature: state.options.chat.temperature,
        max_output_tokens: state.options.chat.max_output_tokens,
        tools: chat_tools(state).await?,
        metadata: json!({
            "source": "agent_tui",
            "surface": "agent_tui",
            "mode": "natural_language",
        }),
        max_tool_rounds: state.options.chat.max_tool_rounds,
    };

    let mut stream = runner.stream(request);
    let mut assistant_text = String::new();
    let mut final_response = None;
    while let Some(event) = stream.next().await {
        let event = event.map_err(|err| miette!(err.record.message))?;
        apply_chat_event_to_tui(state, &event, &mut assistant_text, &mut final_response);
    }
    let assistant_content = final_response
        .as_ref()
        .map(|response: &agent_llm::LlmResponse| response.content.clone())
        .filter(|content| !content.is_empty())
        .unwrap_or(assistant_text);
    if !assistant_content.is_empty() {
        state.chat_messages.push(LlmMessage {
            role: LlmRole::Assistant,
            content: Value::String(assistant_content),
            name: None,
            metadata: json!({}),
        });
    }
    Ok(())
}

fn apply_chat_event_to_tui(
    state: &mut TuiState,
    event: &ChatTurnEvent,
    assistant_text: &mut String,
    final_response: &mut Option<agent_llm::LlmResponse>,
) {
    match event.kind {
        ChatTurnEventKind::Started => {
            let provider = event
                .metadata
                .get("provider")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            let model = event
                .metadata
                .get("model")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            state.push_log(format!("chat started: {provider}/{model}"));
        }
        ChatTurnEventKind::LlmStarted => {
            state.push_log(format!("round {} started", event.round));
        }
        ChatTurnEventKind::Delta => {
            if let Some(content) = &event.content {
                assistant_text.push_str(content);
                state.push_log(format!("agent: {content}"));
            }
        }
        ChatTurnEventKind::ThinkingDelta => {
            if let Some(content) = &event.content {
                state.push_log(format!("thinking: {content}"));
            }
        }
        ChatTurnEventKind::ThinkingSignatureDelta => {}
        ChatTurnEventKind::ToolCallStart => {
            state.push_log(format!(
                "tool start: {} {}",
                event.tool_call_id.as_deref().unwrap_or(""),
                event.tool_name.as_deref().unwrap_or("")
            ));
        }
        ChatTurnEventKind::ToolCallDelta => {
            if let Some(partial) = &event.partial_input_json {
                state.push_log(format!(
                    "tool args {}: {partial}",
                    event.tool_call_id.as_deref().unwrap_or("")
                ));
            }
        }
        ChatTurnEventKind::ToolCallEnd => {
            state.push_log(format!(
                "tool ready: {} {}",
                event.tool_call_id.as_deref().unwrap_or(""),
                event.tool_name.as_deref().unwrap_or("")
            ));
        }
        ChatTurnEventKind::ToolResult => {
            let tool_name = event.tool_name.as_deref().unwrap_or("");
            let output = event.tool_output.as_ref().unwrap_or(&Value::Null);
            if tool_name == "ask_user" {
                if let Some(lines) = decision_request_lines(output) {
                    for line in lines {
                        state.push_log(line);
                    }
                } else {
                    state.push_log(format!("tool result: {tool_name} {}", compact_json(output)));
                }
            } else {
                state.push_log(format!("tool result: {tool_name} {}", compact_json(output)));
            }
        }
        ChatTurnEventKind::Usage => {
            if let Some(usage) = &event.usage {
                state.push_log(format!(
                    "usage: input={} output={} total={}",
                    usage.input_tokens, usage.output_tokens, usage.total_tokens
                ));
            }
        }
        ChatTurnEventKind::RoundFinished => {
            if let Some(response) = &event.response {
                *final_response = Some(response.clone());
                state.push_log(format!(
                    "round {} finished: {:?}",
                    event.round, response.finish_reason
                ));
            }
        }
        ChatTurnEventKind::Error => {
            state.push_log(format!(
                "chat error: {}",
                event.content.as_deref().unwrap_or("unknown error")
            ));
        }
        ChatTurnEventKind::Done => {
            let reason = event
                .metadata
                .get("stop_reason")
                .and_then(Value::as_str)
                .unwrap_or("done");
            state.push_log(format!("done: {reason} in {} round(s)", event.round));
        }
    }
}

async fn chat_tools(state: &TuiState) -> Result<Vec<ToolSpec>> {
    let mut tools = match &state.options.catalog_path {
        Some(path) => read_catalog(path.clone()).await?.tools,
        None => Vec::new(),
    };
    tools.extend(state.options.tool_overrides.source_specs.clone());
    if !tools.iter().any(|tool| tool.name == "echo") {
        tools.push(ToolSpec {
            name: "echo".to_owned(),
            description: "Echo the provided JSON input.".to_owned(),
            input_schema: json!({"type": "object"}),
            output_schema: Some(json!({"type": "object"})),
            risk: ToolRisk::ReadOnly,
            metadata: json!({"source": "agent_cli_builtin"}),
        });
    }
    Ok(tools)
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

fn decision_request_lines(output: &Value) -> Option<Vec<String>> {
    let object = output.as_object()?;
    if object.get("type").and_then(Value::as_str) != Some("decision_request") {
        return None;
    }
    let title = object.get("title").and_then(Value::as_str)?.trim();
    if title.is_empty() {
        return None;
    }
    let options = object.get("options").and_then(Value::as_array)?;
    if options.len() < 2 {
        return None;
    }

    let mut lines = vec![format!("decision: {title}")];
    if let Some(context) = object
        .get("context")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|context| !context.is_empty())
    {
        lines.push(format!("context: {context}"));
    }
    for (index, option) in options.iter().enumerate() {
        let option = option.as_object()?;
        let label = option.get("label").and_then(Value::as_str)?.trim();
        if label.is_empty() {
            return None;
        }
        let description = option
            .get("description")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|description| !description.is_empty());
        let recommended = option
            .get("recommended")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let marker = if recommended { " [recommended]" } else { "" };
        match description {
            Some(description) => {
                lines.push(format!("  {}. {label} - {description}{marker}", index + 1))
            }
            None => lines.push(format!("  {}. {label}{marker}", index + 1)),
        }
    }
    lines.push("reply with your choice to continue".to_owned());
    Some(lines)
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
    use crate::{chat::ChatLlmOptions, tools::ToolOverrides, tui::data::TuiOptions};

    fn temp_store_path(dir: &tempfile::TempDir) -> Utf8PathBuf {
        Utf8PathBuf::from_path_buf(dir.path().join("store")).expect("temp path should be utf8")
    }

    fn test_chat_options(response: &str) -> ChatLlmOptions {
        ChatLlmOptions {
            provider: "mock".to_owned(),
            model: "mock-model".to_owned(),
            mock_response: response.to_owned(),
            api_base_url: None,
            api_key_env: "OPENAI_API_KEY".to_owned(),
            anthropic_version: "2023-06-01".to_owned(),
            temperature: None,
            max_output_tokens: None,
            max_tool_rounds: 4,
        }
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
            chat: test_chat_options("mock response"),
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
            chat: test_chat_options("chat answer"),
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

        assert!(state.trace.is_none());
        assert!(state.recent_runs.is_empty());
        assert_eq!(state.chat_messages.len(), 2);
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
                .any(|line| line.contains("agent: chat answer"))
        );
    }

    #[tokio::test]
    async fn tui_applies_shared_agent_chat_turn_event_fixture() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut state = TuiState::load(TuiOptions {
            catalog_path: None,
            trace_path: None,
            store_path: temp_store_path(&dir),
            registry_path: Utf8PathBuf::from("../../examples/agent-runtime/agents.yaml"),
            tool_overrides: ToolOverrides::default(),
            chat: test_chat_options("unused"),
            timeout_seconds: 60,
            max_retries: 0,
            retry_backoff_ms: 0,
            once: false,
        })
        .await
        .expect("state loads");
        state.clear_log();

        let events: Vec<ChatTurnEvent> = serde_json::from_str(include_str!(
            "../../../../docs/fixtures/agent_chat_turn_events.json"
        ))
        .expect("shared chat turn events fixture");
        let mut assistant_text = String::new();
        let mut final_response = None;
        for event in &events {
            apply_chat_event_to_tui(&mut state, event, &mut assistant_text, &mut final_response);
        }

        assert_eq!(assistant_text, "Checking ");
        assert!(final_response.is_some());
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("tool start: call_1 get_holdings"))
        );
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("usage: input=11 output=7 total=18"))
        );
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("round 1 finished"))
        );
    }

    #[tokio::test]
    async fn tui_renders_shared_ask_user_turn_fixture_as_decision_options() {
        let dir = tempfile::tempdir().expect("temp dir");
        let mut state = TuiState::load(TuiOptions {
            catalog_path: None,
            trace_path: None,
            store_path: temp_store_path(&dir),
            registry_path: Utf8PathBuf::from("../../examples/agent-runtime/agents.yaml"),
            tool_overrides: ToolOverrides::default(),
            chat: test_chat_options("unused"),
            timeout_seconds: 60,
            max_retries: 0,
            retry_backoff_ms: 0,
            once: false,
        })
        .await
        .expect("state loads");
        state.clear_log();

        let events: Vec<ChatTurnEvent> = serde_json::from_str(include_str!(
            "../../../../docs/fixtures/agent_chat_ask_user_turn_events.json"
        ))
        .expect("shared ask_user turn events fixture");
        let mut assistant_text = String::new();
        let mut final_response = None;
        for event in &events {
            apply_chat_event_to_tui(&mut state, event, &mut assistant_text, &mut final_response);
        }

        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("decision: Implementation path"))
        );
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("1. Context transcript"))
        );
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("[recommended]"))
        );
        assert!(
            state
                .log_lines
                .iter()
                .any(|line| line.contains("reply with your choice to continue"))
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
            chat: test_chat_options("mock response"),
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
            chat: test_chat_options("mock response"),
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
