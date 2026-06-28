use std::{
    collections::BTreeMap,
    convert::Infallible,
    io::{self, Stdout},
    net::SocketAddr,
    process::Stdio,
    sync::Arc,
    time::Duration,
};

use agent_core::{
    Agent, AgentContext, AgentError, AgentProposalStore, AgentRunRecord, AgentRunResult,
    AgentRunStore, AgentRuntimeCatalog, AgentServices, AgentSessionStore, AgentSpec,
    AgentStateStore, ApprovalDecision, ApprovalDecisionKind, HookEvent, HookEventName,
    HookInvocationStatus, HookKind, PROTOCOL_VERSION, PromptManifest, PromptManifestBlock,
    ProposalEnvelope, ProposalId, ProposalStatus, RunId, RunRequest, SessionId, SessionRecord,
    StepRecord, ThreadId, ThreadRecord, ToolCallId, ToolError, ToolRisk, ToolSpec, TraceEvent,
    TriggerKind, UserContext,
};
use agent_llm::{
    AnthropicProvider, LlmProvider, LlmRequest, MockLlmProvider, OllamaProvider,
    OpenAiCompatibleProvider, user_message,
};
use agent_runtime::{
    AgentRunner, ExecutionPolicy, InMemoryAgentRegistry, RUNTIME_VERSION, recover_stale_runs,
};
use agent_store::{FileProposalStore, FileRunStore, FileSessionStore, InMemoryStateStore};
use async_trait::async_trait;
use axum::{
    Json, Router,
    extract::{Path, Query, State},
    http::StatusCode,
    response::{
        IntoResponse, Response,
        sse::{Event, Sse},
    },
    routing::{get, post},
};
use camino::{Utf8Path, Utf8PathBuf};
use clap::{Parser, Subcommand, ValueEnum};
use futures::stream;
use miette::{IntoDiagnostic, Result, miette};
use ratatui::{
    Frame, Terminal,
    backend::{CrosstermBackend, TestBackend},
    buffer::Buffer,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use time::format_description::well_known::Rfc3339;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::process::Command as TokioCommand;

mod config;

use config::{
    configured_path, configured_paths, configured_string, configured_u16, configured_u32,
    configured_u64, execution_policy, load_agent_config,
};

const DEFAULT_REGISTRY: &str = "examples/agent-runtime/agents.yaml";
const DEFAULT_STORE: &str = ".agent-runtime/store";
const DEFAULT_EVAL_STORE: &str = ".agent-runtime/eval-store";
const DEFAULT_HOST: &str = "127.0.0.1";
const DEFAULT_PORT: u16 = 8765;
const DEFAULT_TIMEOUT_SECONDS: u64 = 60;

#[derive(Debug, Parser)]
#[command(name = "agent")]
#[command(about = "Schema-first Rust agent runtime CLI")]
struct Cli {
    #[arg(long, env = "AGENT_RUNTIME_CONFIG")]
    config: Option<Utf8PathBuf>,
    #[arg(long, env = "AGENT_RUNTIME_PROFILE")]
    profile: Option<String>,
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    List {
        #[arg(long, default_value = DEFAULT_REGISTRY)]
        registry: Utf8PathBuf,
    },
    Run {
        agent_id: String,
        #[arg(long, default_value = DEFAULT_REGISTRY)]
        registry: Utf8PathBuf,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
        #[arg(long)]
        input: Option<Utf8PathBuf>,
        #[arg(long)]
        trace_out: Option<Utf8PathBuf>,
        #[arg(long)]
        session: Option<String>,
        #[arg(long)]
        thread: Option<String>,
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
        #[arg(long, default_value_t = DEFAULT_TIMEOUT_SECONDS)]
        timeout_seconds: u64,
        #[arg(long, default_value_t = 0)]
        max_retries: u32,
        #[arg(long, default_value_t = 0)]
        retry_backoff_ms: u64,
    },
    Tick {
        #[arg(long, default_value = DEFAULT_REGISTRY)]
        registry: Utf8PathBuf,
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
    },
    Replay {
        trace_file: Utf8PathBuf,
        #[arg(long, value_enum)]
        mode: Option<ReplayMode>,
        #[arg(long)]
        execute: bool,
        #[arg(long, default_value = DEFAULT_REGISTRY)]
        registry: Utf8PathBuf,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
        #[arg(long)]
        trace_out: Option<Utf8PathBuf>,
        #[arg(long, default_value_t = DEFAULT_TIMEOUT_SECONDS)]
        timeout_seconds: u64,
        #[arg(long, default_value_t = 0)]
        max_retries: u32,
        #[arg(long, default_value_t = 0)]
        retry_backoff_ms: u64,
    },
    Inspect {
        run_id: String,
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
    },
    Validate {
        schema: Utf8PathBuf,
        instance: Utf8PathBuf,
    },
    DebugBundle {
        #[command(subcommand)]
        command: DebugBundleCommand,
    },
    Metrics {
        #[command(subcommand)]
        command: MetricsCommand,
    },
    Tool {
        #[command(subcommand)]
        command: ToolCommand,
    },
    Proposal {
        #[command(subcommand)]
        command: ProposalCommand,
    },
    Session {
        #[command(subcommand)]
        command: SessionCommand,
    },
    Llm {
        #[command(subcommand)]
        command: LlmCommand,
    },
    Catalog {
        #[command(subcommand)]
        command: CatalogCommand,
    },
    Config {
        #[command(subcommand)]
        command: ConfigCommand,
    },
    Recover {
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
        #[arg(long, default_value_t = DEFAULT_TIMEOUT_SECONDS)]
        timeout_seconds: u64,
    },
    Cmd {
        #[command(subcommand)]
        command: CmdCommand,
    },
    Serve {
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
        #[arg(long)]
        stdio: bool,
        #[arg(long, default_value = DEFAULT_HOST)]
        host: String,
        #[arg(long, default_value_t = DEFAULT_PORT)]
        port: u16,
    },
    Tui {
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        trace: Option<Utf8PathBuf>,
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
        #[arg(long)]
        once: bool,
    },
    Eval {
        eval_path: Utf8PathBuf,
        #[arg(long, default_value = DEFAULT_EVAL_STORE)]
        store: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
        #[arg(long)]
        update_golden: bool,
        #[arg(long)]
        from_run: Option<String>,
        #[arg(long)]
        out: Option<Utf8PathBuf>,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        id: Option<String>,
        #[arg(long)]
        golden_trace: Option<Utf8PathBuf>,
    },
    #[command(hide = true)]
    DevToolHost,
    #[command(hide = true)]
    DevMcpServer,
    #[command(hide = true)]
    DevScoreHook,
}

#[derive(Debug, Subcommand)]
enum CatalogCommand {
    Summary {
        catalog: Utf8PathBuf,
    },
    Agents {
        catalog: Utf8PathBuf,
    },
    Tools {
        catalog: Utf8PathBuf,
    },
    ProposalKinds {
        catalog: Utf8PathBuf,
    },
    PromptBlocks {
        catalog: Utf8PathBuf,
    },
    PromptManifest {
        catalog: Utf8PathBuf,
        #[arg(long)]
        agent_id: Option<String>,
    },
}

#[derive(Debug, Subcommand)]
enum ConfigCommand {
    Show,
}

#[derive(Debug, Subcommand)]
enum CmdCommand {
    Create {
        #[arg(long)]
        from_run: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        out: Utf8PathBuf,
        #[arg(long)]
        description: Option<String>,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        registry: Option<Utf8PathBuf>,
    },
    Run {
        command_file: Utf8PathBuf,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        registry: Option<Utf8PathBuf>,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
        #[arg(long)]
        trace_out: Option<Utf8PathBuf>,
        #[arg(long, default_value_t = 60)]
        timeout_seconds: u64,
        #[arg(long, default_value_t = 0)]
        max_retries: u32,
        #[arg(long, default_value_t = 0)]
        retry_backoff_ms: u64,
    },
}

#[derive(Debug, Subcommand)]
enum DebugBundleCommand {
    Export {
        run_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        out: Utf8PathBuf,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        trace: Option<Utf8PathBuf>,
        #[arg(long, default_value_t = DEFAULT_TIMEOUT_SECONDS)]
        timeout_seconds: u64,
    },
}

#[derive(Debug, Subcommand)]
enum MetricsCommand {
    Summary {
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
    },
}

#[derive(Debug, Subcommand)]
enum ToolCommand {
    List {
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
    },
    Call {
        name: String,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
        #[arg(long)]
        input: Option<Utf8PathBuf>,
        #[arg(long)]
        input_json: Option<String>,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
    },
}

#[derive(Debug, Subcommand)]
enum ProposalCommand {
    Create {
        #[arg(long)]
        run_id: String,
        #[arg(long)]
        agent_id: String,
        #[arg(long)]
        kind: String,
        #[arg(long)]
        summary: String,
        #[arg(long)]
        payload: Option<Utf8PathBuf>,
        #[arg(long)]
        payload_json: Option<String>,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    List {
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        run_id: Option<String>,
    },
    Inspect {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    Decide {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        decision: String,
        #[arg(long)]
        comment: Option<String>,
    },
    Apply {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        catalog: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
    },
    Undo {
        proposal_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
        #[arg(long)]
        catalog: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
    },
}

#[derive(Debug, Subcommand)]
enum SessionCommand {
    Create {
        #[arg(long)]
        title: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    List {
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    Show {
        session_id: String,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
    Fork {
        session_id: String,
        parent_thread_id: String,
        #[arg(long)]
        title: Option<String>,
        #[arg(long, default_value = ".agent-runtime/store")]
        store: Utf8PathBuf,
    },
}

#[derive(Debug, Subcommand)]
enum LlmCommand {
    Complete {
        #[arg(long)]
        prompt: String,
        #[arg(long, env = "AGENT_LLM_PROVIDER", default_value = "mock")]
        provider: String,
        #[arg(long, default_value = "mock-model")]
        model: String,
        #[arg(long, default_value = "mock response")]
        mock_response: String,
        #[arg(long, env = "OPENAI_BASE_URL")]
        api_base_url: Option<String>,
        #[arg(long, default_value = "OPENAI_API_KEY")]
        api_key_env: String,
        #[arg(long)]
        temperature: Option<f32>,
        #[arg(long)]
        max_output_tokens: Option<u32>,
        #[arg(long, default_value = "2023-06-01")]
        anthropic_version: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .without_time()
        .try_init()
        .ok();

    let cli = Cli::parse();
    let config = load_agent_config(cli.config.clone(), cli.profile.as_deref()).await?;

    match cli.command {
        Command::List { registry } => {
            let registry =
                configured_path(registry, DEFAULT_REGISTRY, config.runtime.registry.as_ref());
            let registry = load_registry(registry).await?;
            let specs = registry.list_specs();
            println!(
                "{}",
                serde_json::to_string_pretty(&specs).into_diagnostic()?
            );
        }
        Command::Run {
            agent_id,
            registry,
            catalog,
            tool_host,
            mock_tool,
            tool_source,
            input,
            trace_out,
            session,
            thread,
            store,
            timeout_seconds,
            max_retries,
            retry_backoff_ms,
        } => {
            let catalog = catalog.or_else(|| config.runtime.catalog.clone());
            let registry =
                configured_path(registry, DEFAULT_REGISTRY, config.runtime.registry.as_ref());
            let tool_source = configured_paths(tool_source, config.runtime.tool_sources.as_ref());
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            let timeout_seconds = configured_u64(
                timeout_seconds,
                DEFAULT_TIMEOUT_SECONDS,
                config.runtime.timeout_seconds,
            );
            let max_retries = configured_u32(max_retries, 0, config.runtime.max_retries);
            let retry_backoff_ms =
                configured_u64(retry_backoff_ms, 0, config.runtime.retry_backoff_ms);
            let input = match input {
                Some(path) => read_json(path).await?,
                None => json!({}),
            };
            let registry = match catalog {
                Some(path) => load_catalog_registry(path).await?,
                None => load_registry(registry).await?.into_agent_registry(),
            };
            let store_path = store;
            let run_metadata = run_metadata(session.as_deref(), thread.as_deref());
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
                tool_overrides(tool_host, mock_tool, tool_source).await?,
                proposal_store,
            ));
            let runner = AgentRunner::new(registry, store, services).with_policy(execution_policy(
                timeout_seconds,
                max_retries,
                retry_backoff_ms,
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
                        metadata: run_metadata.clone(),
                    },
                )
                .await
                .into_diagnostic()?;
            record_session_step(&store_path, thread.as_deref(), &outcome).await?;
            write_store_trace(&store_path, &outcome.trace).await?;
            if let Some(path) = trace_out {
                write_json(path, &outcome.trace).await?;
            }
            println!(
                "{}",
                serde_json::to_string_pretty(&outcome.result).into_diagnostic()?
            );
        }
        Command::Tick { registry, store } => {
            let registry =
                configured_path(registry, DEFAULT_REGISTRY, config.runtime.registry.as_ref());
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            let registry = load_registry(registry).await?;
            let store_path = store;
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
                ToolOverrides::default(),
                proposal_store,
            ));
            let runner = AgentRunner::new(registry.into_agent_registry(), store, services);
            let outcomes = runner
                .tick(RunRequest {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    run_id: None,
                    input: json!({}),
                    user: None,
                    trigger: agent_core::TriggerKind::Scheduled,
                    metadata: json!({}),
                })
                .await
                .into_diagnostic()?;
            for outcome in &outcomes {
                write_store_trace(&store_path, &outcome.trace).await?;
            }
            let results = outcomes
                .into_iter()
                .map(|outcome| outcome.result)
                .collect::<Vec<_>>();
            println!(
                "{}",
                serde_json::to_string_pretty(&results).into_diagnostic()?
            );
        }
        Command::Replay {
            trace_file,
            mode,
            execute,
            registry,
            catalog,
            tool_host,
            mock_tool,
            tool_source,
            store,
            trace_out,
            timeout_seconds,
            max_retries,
            retry_backoff_ms,
        } => {
            let catalog = catalog.or_else(|| config.runtime.catalog.clone());
            let registry =
                configured_path(registry, DEFAULT_REGISTRY, config.runtime.registry.as_ref());
            let tool_source = configured_paths(tool_source, config.runtime.tool_sources.as_ref());
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            let timeout_seconds = configured_u64(
                timeout_seconds,
                DEFAULT_TIMEOUT_SECONDS,
                config.runtime.timeout_seconds,
            );
            let max_retries = configured_u32(max_retries, 0, config.runtime.max_retries);
            let retry_backoff_ms =
                configured_u64(retry_backoff_ms, 0, config.runtime.retry_backoff_ms);
            let mode = if execute {
                match mode {
                    Some(ReplayMode::View | ReplayMode::Deterministic) => {
                        return Err(miette!("--execute is only compatible with --mode live"));
                    }
                    Some(ReplayMode::Live) | None => ReplayMode::Live,
                }
            } else {
                mode.unwrap_or(ReplayMode::View)
            };
            match mode {
                ReplayMode::Live | ReplayMode::Deterministic => {
                    replay_trace(ReplayTraceOptions {
                        trace_file,
                        mode,
                        registry,
                        catalog,
                        tool_host,
                        mock_tool,
                        tool_source,
                        store,
                        trace_out,
                        timeout_seconds,
                        max_retries,
                        retry_backoff_ms,
                    })
                    .await?;
                }
                ReplayMode::View => {
                    let trace = read_json(trace_file).await?;
                    println!(
                        "{}",
                        serde_json::to_string_pretty(&trace).into_diagnostic()?
                    );
                }
            }
        }
        Command::Inspect { run_id, store } => {
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            let store = FileRunStore::new(store).await.into_diagnostic()?;
            let record = store
                .get_run(&RunId(run_id.clone()))
                .await
                .into_diagnostic()?
                .ok_or_else(|| miette!("run '{run_id}' was not found"))?;
            print_json(&record)?;
        }
        Command::Validate { schema, instance } => {
            let report = validate_json(schema, instance).await?;
            print_json(&report)?;
            if !report.valid {
                return Err(miette!("JSON instance failed schema validation"));
            }
        }
        Command::DebugBundle { command } => match command {
            DebugBundleCommand::Export {
                run_id,
                store,
                out,
                catalog,
                trace,
                timeout_seconds,
            } => {
                export_debug_bundle(run_id, store, out, catalog, trace, timeout_seconds).await?;
            }
        },
        Command::Metrics { command } => match command {
            MetricsCommand::Summary { store } => {
                let run_store = FileRunStore::new(store.clone()).await.into_diagnostic()?;
                let proposal_store = FileProposalStore::new(store.clone())
                    .await
                    .into_diagnostic()?;
                let summary = build_metrics_summary(&store, &run_store, &proposal_store).await?;
                print_json(&summary)?;
            }
        },
        Command::Tool { command } => match command {
            ToolCommand::List {
                catalog,
                tool_source,
            } => {
                let mut tools = match catalog {
                    Some(path) => read_catalog(path).await?.tools,
                    None => builtin_tools(),
                };
                tools.extend(load_tool_source_specs(tool_source).await?);
                print_json(&tools)?;
            }
            ToolCommand::Call {
                name,
                catalog,
                tool_source,
                input,
                input_json,
                tool_host,
                mock_tool,
            } => {
                let input = read_command_input(input, input_json).await?;
                let sources = load_tool_sources(tool_source.clone()).await?;
                let has_catalog = catalog.is_some();
                let in_catalog = match catalog {
                    Some(path) => read_catalog(path)
                        .await?
                        .tools
                        .iter()
                        .any(|tool| tool.name == name),
                    None => false,
                };
                let in_sources = source_has_tool(&sources, &name);
                if !in_catalog && !in_sources && (has_catalog || !sources.is_empty()) {
                    return Err(miette!(
                        "tool '{name}' is not present in the active catalog or configured tool sources"
                    ));
                }
                let services =
                    CliServices::new(tool_overrides(tool_host, mock_tool, tool_source).await?);
                let output = services
                    .call_tool(&name, input)
                    .await
                    .map_err(|err| miette!(err.record.message))?;
                print_json(&output)?;
            }
        },
        Command::Proposal { command } => match command {
            ProposalCommand::Create {
                run_id,
                agent_id,
                kind,
                summary,
                payload,
                payload_json,
                store,
            } => {
                let payload = read_command_input(payload, payload_json).await?;
                let proposal =
                    ProposalEnvelope::new(RunId(run_id), agent_id, kind, summary, payload);
                let store_path = store;
                let store = FileProposalStore::new(store_path.clone())
                    .await
                    .into_diagnostic()?;
                store
                    .create_proposal(proposal.clone())
                    .await
                    .into_diagnostic()?;
                append_proposal_created_trace_event(&store_path, &proposal).await?;
                print_json(&proposal)?;
            }
            ProposalCommand::List { store, run_id } => {
                let store = FileProposalStore::new(store).await.into_diagnostic()?;
                let run_id = run_id.map(RunId);
                let proposals = store
                    .list_proposals(run_id.as_ref())
                    .await
                    .into_diagnostic()?;
                print_json(&proposals)?;
            }
            ProposalCommand::Inspect { proposal_id, store } => {
                let store = FileProposalStore::new(store).await.into_diagnostic()?;
                let proposal = store
                    .get_proposal(&ProposalId(proposal_id.clone()))
                    .await
                    .into_diagnostic()?
                    .ok_or_else(|| miette!("proposal '{proposal_id}' was not found"))?;
                print_json(&proposal)?;
            }
            ProposalCommand::Decide {
                proposal_id,
                store,
                decision,
                comment,
            } => {
                let store_path = store;
                let store = FileProposalStore::new(store_path.clone())
                    .await
                    .into_diagnostic()?;
                let proposal_id = ProposalId(proposal_id);
                let mut proposal = store
                    .get_proposal(&proposal_id)
                    .await
                    .into_diagnostic()?
                    .ok_or_else(|| miette!("proposal '{}' was not found", proposal_id.0))?;
                let decision = parse_approval_decision(&decision)?;
                proposal.status = match decision {
                    ApprovalDecisionKind::Approve => ProposalStatus::Approved,
                    ApprovalDecisionKind::Deny => ProposalStatus::Denied,
                };
                store
                    .update_proposal(proposal.clone())
                    .await
                    .into_diagnostic()?;
                let response = ProposalDecisionResponse {
                    decision: ApprovalDecision {
                        protocol_version: PROTOCOL_VERSION.to_owned(),
                        proposal_id,
                        decision,
                        decided_at: time::OffsetDateTime::now_utc(),
                        comment,
                    },
                    proposal,
                };
                append_proposal_decision_trace_event(&store_path, &response).await?;
                print_json(&response)?;
            }
            ProposalCommand::Apply {
                proposal_id,
                store,
                catalog,
                tool_host,
                mock_tool,
                tool_source,
            } => {
                let response = execute_proposal_action(
                    ProposalId(proposal_id),
                    store,
                    catalog,
                    tool_overrides(tool_host, mock_tool, tool_source).await?,
                    ProposalAction::Apply,
                )
                .await?;
                print_json(&response)?;
            }
            ProposalCommand::Undo {
                proposal_id,
                store,
                catalog,
                tool_host,
                mock_tool,
                tool_source,
            } => {
                let response = execute_proposal_action(
                    ProposalId(proposal_id),
                    store,
                    catalog,
                    tool_overrides(tool_host, mock_tool, tool_source).await?,
                    ProposalAction::Undo,
                )
                .await?;
                print_json(&response)?;
            }
        },
        Command::Session { command } => match command {
            SessionCommand::Create { title, store } => {
                let report = create_session(store, title).await?;
                print_json(&report)?;
            }
            SessionCommand::List { store } => {
                let store = FileSessionStore::new(store).await.into_diagnostic()?;
                let sessions = store.list_sessions().await.into_diagnostic()?;
                print_json(&sessions)?;
            }
            SessionCommand::Show { session_id, store } => {
                let report = show_session(store, SessionId(session_id)).await?;
                print_json(&report)?;
            }
            SessionCommand::Fork {
                session_id,
                parent_thread_id,
                title,
                store,
            } => {
                let report = fork_thread(
                    store,
                    SessionId(session_id),
                    ThreadId(parent_thread_id),
                    title,
                )
                .await?;
                print_json(&report)?;
            }
        },
        Command::Llm { command } => match command {
            LlmCommand::Complete {
                prompt,
                provider,
                model,
                mock_response,
                api_base_url,
                api_key_env,
                temperature,
                max_output_tokens,
                anthropic_version,
            } => {
                let request = LlmRequest {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    provider: provider.clone(),
                    model: model.clone(),
                    messages: vec![user_message(prompt)],
                    temperature,
                    max_output_tokens,
                    tools: vec![],
                    metadata: json!({"mock_response": mock_response}),
                };
                let response = match provider.as_str() {
                    "mock" => MockLlmProvider::new("mock", model, "mock response")
                        .complete(request)
                        .await,
                    "openai-compatible" | "openai" => {
                        let base_url = api_base_url.ok_or_else(|| {
                            miette!(
                                "--api-base-url or OPENAI_BASE_URL is required for provider '{provider}'"
                            )
                        })?;
                        let api_key = std::env::var(&api_key_env).map_err(|_| {
                            miette!(
                                "environment variable {api_key_env} is required for provider '{provider}'"
                            )
                        })?;
                        OpenAiCompatibleProvider::new(provider.clone(), base_url, api_key)
                            .map_err(|err| miette!(err.record.message))?
                            .complete(request)
                            .await
                    }
                    "anthropic" => {
                        let base_url = api_base_url
                            .or_else(|| std::env::var("ANTHROPIC_BASE_URL").ok())
                            .unwrap_or_else(|| "https://api.anthropic.com/v1".to_owned());
                        let key_env = if api_key_env == "OPENAI_API_KEY" {
                            "ANTHROPIC_API_KEY".to_owned()
                        } else {
                            api_key_env
                        };
                        let api_key = std::env::var(&key_env).map_err(|_| {
                            miette!(
                                "environment variable {key_env} is required for provider '{provider}'"
                            )
                        })?;
                        AnthropicProvider::new(provider.clone(), base_url, api_key, anthropic_version)
                            .map_err(|err| miette!(err.record.message))?
                            .complete(request)
                            .await
                    }
                    "ollama" | "local" => {
                        let base_url = api_base_url
                            .or_else(|| std::env::var("OLLAMA_BASE_URL").ok())
                            .unwrap_or_else(|| "http://127.0.0.1:11434".to_owned());
                        OllamaProvider::new(provider.clone(), base_url)
                            .map_err(|err| miette!(err.record.message))?
                            .complete(request)
                            .await
                    }
                    other => Err(agent_llm::LlmError::validation(format!(
                        "unsupported LLM provider '{other}'"
                    ))),
                }
                .map_err(|err| miette!(err.record.message))?;
                print_json(&response)?;
            }
        },
        Command::Catalog { command } => match command {
            CatalogCommand::Summary { catalog } => {
                let catalog = read_catalog(catalog).await?;
                let summary = CatalogSummary::from_catalog(&catalog);
                print_json(&summary)?;
            }
            CatalogCommand::Agents { catalog } => {
                let catalog = read_catalog(catalog).await?;
                print_json(&catalog.agents)?;
            }
            CatalogCommand::Tools { catalog } => {
                let catalog = read_catalog(catalog).await?;
                print_json(&catalog.tools)?;
            }
            CatalogCommand::ProposalKinds { catalog } => {
                let catalog = read_catalog(catalog).await?;
                print_json(&catalog.proposal_kinds)?;
            }
            CatalogCommand::PromptBlocks { catalog } => {
                let catalog = read_catalog(catalog).await?;
                print_json(&catalog.prompt_blocks)?;
            }
            CatalogCommand::PromptManifest { catalog, agent_id } => {
                let catalog = read_catalog(catalog).await?;
                let manifest = build_prompt_manifest(&catalog, agent_id.as_deref())?;
                print_json(&manifest)?;
            }
        },
        Command::Config { command } => match command {
            ConfigCommand::Show => {
                print_json(&config)?;
            }
        },
        Command::Recover {
            store,
            timeout_seconds,
        } => {
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            let timeout_seconds = configured_u64(
                timeout_seconds,
                DEFAULT_TIMEOUT_SECONDS,
                config.runtime.timeout_seconds,
            );
            let store = FileRunStore::new(store).await.into_diagnostic()?;
            let report = recover_stale_runs(
                &store,
                &ExecutionPolicy {
                    timeout: Duration::from_secs(timeout_seconds),
                    max_retries: 0,
                    retry_backoff: Duration::ZERO,
                    max_concurrent_runs: 1,
                },
            )
            .await
            .into_diagnostic()?;
            print_json(&report)?;
        }
        Command::Cmd { command } => match command {
            CmdCommand::Create {
                from_run,
                store,
                out,
                description,
                catalog,
                registry,
            } => {
                let report =
                    create_command_from_run(from_run, store, out, description, catalog, registry)
                        .await?;
                print_json(&report)?;
            }
            CmdCommand::Run {
                command_file,
                catalog,
                registry,
                store,
                tool_host,
                mock_tool,
                tool_source,
                trace_out,
                timeout_seconds,
                max_retries,
                retry_backoff_ms,
            } => {
                let report = run_command_template(CommandRunOptions {
                    command_file,
                    catalog,
                    registry,
                    store,
                    tool_host,
                    mock_tool,
                    tool_source,
                    trace_out,
                    timeout_seconds,
                    max_retries,
                    retry_backoff_ms,
                })
                .await?;
                print_json(&report)?;
            }
        },
        Command::Serve {
            catalog,
            store,
            tool_host,
            mock_tool,
            tool_source,
            stdio,
            host,
            port,
        } => {
            let catalog = catalog
                .or_else(|| config.runtime.catalog.clone())
                .ok_or_else(|| miette!("--catalog or runtime.catalog in config is required"))?;
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            let tool_source = configured_paths(tool_source, config.runtime.tool_sources.as_ref());
            let stdio = stdio || config.runtime.stdio.unwrap_or(false);
            let host = configured_string(host, DEFAULT_HOST, config.runtime.host.as_ref());
            let port = configured_u16(port, DEFAULT_PORT, config.runtime.port);
            let server = RuntimeServer::new(
                catalog,
                store,
                tool_overrides(tool_host, mock_tool, tool_source).await?,
            )
            .await?;
            if stdio {
                serve_stdio(server).await?;
            } else {
                serve_http(server, host, port).await?;
            }
        }
        Command::Tui {
            catalog,
            trace,
            store,
            once,
        } => {
            let catalog = catalog.or_else(|| config.runtime.catalog.clone());
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            run_tui(catalog, trace, store, once).await?;
        }
        Command::Eval {
            eval_path,
            store,
            tool_host,
            mock_tool,
            tool_source,
            update_golden,
            from_run,
            out,
            catalog,
            id,
            golden_trace,
        } => {
            let store = if store == Utf8PathBuf::from(DEFAULT_EVAL_STORE) {
                config
                    .runtime
                    .eval_store
                    .clone()
                    .or_else(|| config.runtime.store.clone())
                    .unwrap_or(store)
            } else {
                store
            };
            let catalog = catalog.or_else(|| config.runtime.catalog.clone());
            let tool_source = configured_paths(tool_source, config.runtime.tool_sources.as_ref());
            let result = if eval_path.as_str() == "create" || from_run.is_some() {
                create_eval_from_run(
                    from_run.ok_or_else(|| miette!("--from-run is required"))?,
                    store,
                    out.ok_or_else(|| miette!("--out is required"))?,
                    catalog.ok_or_else(|| miette!("--catalog is required"))?,
                    id,
                    golden_trace,
                )
                .await?
            } else {
                run_eval_path(
                    eval_path,
                    store,
                    tool_overrides(tool_host, mock_tool, tool_source).await?,
                    update_golden,
                )
                .await?
            };
            print_json(&result)?;
        }
        Command::DevToolHost => run_dev_tool_host().await?,
        Command::DevMcpServer => run_dev_mcp_server().await?,
        Command::DevScoreHook => run_dev_score_hook().await?,
    }
    Ok(())
}

#[derive(Debug, Serialize)]
struct CatalogSummary {
    protocol_version: String,
    catalog_version: String,
    generated_at: String,
    active_domains: Vec<String>,
    agent_count: usize,
    tool_count: usize,
    proposal_kind_count: usize,
    prompt_block_count: usize,
}

#[derive(Debug, Serialize)]
struct ValidationReport {
    schema: String,
    instance: String,
    valid: bool,
    errors: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ValueEnum)]
#[serde(rename_all = "snake_case")]
enum ReplayMode {
    View,
    Deterministic,
    Live,
}

#[derive(Debug, Serialize)]
struct ReplayExecutionReport {
    mode: ReplayMode,
    source_run_id: RunId,
    replay_run_id: RunId,
    agent_id: String,
    result: AgentRunResult,
    trace: agent_core::AgentTrace,
    output_matches: bool,
}

struct ReplayTraceOptions {
    trace_file: Utf8PathBuf,
    mode: ReplayMode,
    registry: Utf8PathBuf,
    catalog: Option<Utf8PathBuf>,
    tool_host: Vec<String>,
    mock_tool: Vec<String>,
    tool_source: Vec<Utf8PathBuf>,
    store: Utf8PathBuf,
    trace_out: Option<Utf8PathBuf>,
    timeout_seconds: u64,
    max_retries: u32,
    retry_backoff_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
struct ToolSourceManifest {
    #[serde(default)]
    version: Option<String>,
    #[serde(default)]
    sources: Vec<ToolSourceDefinition>,
}

#[derive(Debug, Clone, Deserialize)]
struct ToolSourceDefinition {
    id: String,
    #[serde(default)]
    protocol: ToolSourceProtocol,
    #[serde(default)]
    command: Option<String>,
    #[serde(default)]
    args: Vec<String>,
    #[serde(default)]
    endpoint: Option<String>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    headers: BTreeMap<String, String>,
    #[serde(default)]
    tools: Vec<ToolSpec>,
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
#[serde(rename_all = "snake_case")]
enum ToolSourceProtocol {
    #[default]
    JsonlToolCall,
    McpStdio,
    HttpJson,
}

#[derive(Debug)]
struct TuiState {
    catalog_path: Option<Utf8PathBuf>,
    trace_path: Option<Utf8PathBuf>,
    store_path: Utf8PathBuf,
    catalog_summary: Option<CatalogSummary>,
    trace: Option<agent_core::AgentTrace>,
    recent_runs: Vec<AgentRunRecord>,
    status: String,
}

#[derive(Clone)]
struct RuntimeServer {
    catalog: Arc<AgentRuntimeCatalog>,
    runner: Arc<AgentRunner>,
    services: Arc<CliServices>,
    run_store: Arc<FileRunStore>,
    proposal_store: Arc<FileProposalStore>,
    session_store: Arc<FileSessionStore>,
    store_path: Utf8PathBuf,
}

#[derive(Debug, Serialize)]
struct AgentRunResponse {
    result: AgentRunResult,
    trace: agent_core::AgentTrace,
}

#[derive(Debug, Serialize)]
struct HttpErrorBody {
    code: String,
    message: String,
}

#[derive(Debug, Serialize)]
struct ToolCallResponse {
    tool: String,
    output: Value,
}

#[derive(Debug, Serialize)]
struct ProposalDecisionResponse {
    decision: ApprovalDecision,
    proposal: ProposalEnvelope,
}

#[derive(Debug, Serialize)]
struct ProposalActionResponse {
    action: String,
    tool: String,
    tool_output: Value,
    proposal: ProposalEnvelope,
}

#[derive(Debug, Serialize)]
struct HttpSessionCreateResponse {
    session: SessionRecord,
    thread: ThreadRecord,
}

#[derive(Debug, Clone, Copy)]
enum ProposalAction {
    Apply,
    Undo,
}

impl ProposalAction {
    fn as_str(self) -> &'static str {
        match self {
            Self::Apply => "apply",
            Self::Undo => "undo",
        }
    }

    fn required_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::Approved,
            Self::Undo => ProposalStatus::Applied,
        }
    }

    fn in_progress_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::Applying,
            Self::Undo => ProposalStatus::Undoing,
        }
    }

    fn success_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::Applied,
            Self::Undo => ProposalStatus::Undone,
        }
    }

    fn failure_status(self) -> ProposalStatus {
        match self {
            Self::Apply => ProposalStatus::ApplyFailed,
            Self::Undo => ProposalStatus::UndoFailed,
        }
    }
}

#[derive(Debug, Deserialize)]
struct HttpProposalCreateParams {
    run_id: String,
    agent_id: String,
    kind: String,
    summary: String,
    #[serde(default)]
    payload: Value,
}

#[derive(Debug, Deserialize)]
struct HttpProposalListParams {
    #[serde(default)]
    run_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct HttpRunListParams {
    #[serde(default)]
    agent_id: Option<String>,
    #[serde(default)]
    limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct HttpProposalDecisionParams {
    decision: String,
    #[serde(default)]
    comment: Option<String>,
}

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
struct RuntimeMetricsSummary {
    protocol_version: String,
    runtime_version: String,
    generated_at: String,
    store_root: String,
    run_count: usize,
    runs_by_status: BTreeMap<String, usize>,
    successful_run_count: usize,
    skipped_run_count: usize,
    failed_run_count: usize,
    timeout_count: usize,
    total_run_latency_ms: u64,
    average_run_latency_ms: Option<f64>,
    tool_call_count: usize,
    failed_tool_call_count: usize,
    total_tool_call_latency_ms: u64,
    average_tool_call_latency_ms: Option<f64>,
    replay_count: usize,
    proposal_count: usize,
    proposals_by_status: BTreeMap<String, usize>,
    proposal_created_count: usize,
    proposal_approved_count: usize,
    proposal_denied_count: usize,
    proposal_applied_count: usize,
    llm_total_tokens: u64,
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

#[derive(Debug, Deserialize)]
struct StdioRequest {
    #[serde(default)]
    jsonrpc: Option<String>,
    #[serde(default)]
    id: Option<Value>,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Serialize)]
struct StdioResponse {
    jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<StdioError>,
}

#[derive(Debug, Serialize)]
struct StdioError {
    code: i32,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<Value>,
}

#[derive(Debug, Deserialize)]
struct AgentRunParams {
    agent_id: String,
    #[serde(default)]
    input: Value,
    #[serde(default)]
    session_id: Option<String>,
    #[serde(default)]
    thread_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct HttpAgentRunParams {
    #[serde(default)]
    input: Value,
    #[serde(default)]
    session_id: Option<String>,
    #[serde(default)]
    thread_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct HttpToolCallParams {
    #[serde(default)]
    input: Value,
}

#[derive(Debug, Deserialize)]
struct HttpSessionCreateParams {
    title: String,
    #[serde(default)]
    metadata: Value,
}

#[derive(Debug, Deserialize)]
struct HttpThreadForkParams {
    parent_thread_id: String,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    metadata: Value,
}

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

#[derive(Debug, Serialize)]
struct CommandCreateReport {
    id: String,
    run_id: String,
    agent_id: String,
    command_file: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct CommandFrontmatter {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    agent: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    catalog: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    registry: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source_run_status: Option<agent_core::AgentRunStatus>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    created_at: Option<String>,
}

struct CommandTemplate {
    frontmatter: CommandFrontmatter,
    input: Value,
}

struct CommandRunOptions {
    command_file: Utf8PathBuf,
    catalog: Option<Utf8PathBuf>,
    registry: Option<Utf8PathBuf>,
    store: Utf8PathBuf,
    tool_host: Vec<String>,
    mock_tool: Vec<String>,
    tool_source: Vec<Utf8PathBuf>,
    trace_out: Option<Utf8PathBuf>,
    timeout_seconds: u64,
    max_retries: u32,
    retry_backoff_ms: u64,
}

#[derive(Debug, Serialize)]
struct CommandRunReport {
    command_file: String,
    agent_id: String,
    result: AgentRunResult,
    trace: agent_core::AgentTrace,
}

#[derive(Debug, Serialize)]
struct SessionCreateReport {
    session: SessionRecord,
    thread: ThreadRecord,
}

#[derive(Debug, Serialize)]
struct SessionShowReport {
    session: SessionRecord,
    threads: Vec<ThreadWithSteps>,
}

#[derive(Debug, Serialize)]
struct ThreadWithSteps {
    thread: ThreadRecord,
    steps: Vec<StepRecord>,
}

#[derive(Debug, Serialize)]
struct ThreadForkReport {
    session_id: String,
    parent_thread_id: String,
    thread: ThreadRecord,
}

#[derive(Debug)]
enum CommandRegistryPath {
    Catalog(Utf8PathBuf),
    Registry(Utf8PathBuf),
}

#[derive(Debug, Deserialize)]
struct ToolHostRequest {
    #[serde(default)]
    id: Option<Value>,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Deserialize)]
struct ToolCallParams {
    name: String,
    #[serde(default)]
    input: Value,
}

impl CatalogSummary {
    fn from_catalog(catalog: &AgentRuntimeCatalog) -> Self {
        Self {
            protocol_version: catalog.protocol_version.clone(),
            catalog_version: catalog.catalog_version.clone(),
            generated_at: catalog
                .generated_at
                .format(&Rfc3339)
                .unwrap_or_else(|_| catalog.generated_at.to_string()),
            active_domains: catalog.active_domains.clone(),
            agent_count: catalog.agents.len(),
            tool_count: catalog.tools.len(),
            proposal_kind_count: catalog.proposal_kinds.len(),
            prompt_block_count: catalog.prompt_blocks.len(),
        }
    }
}

impl RuntimeServer {
    async fn new(
        catalog_path: Utf8PathBuf,
        store_path: Utf8PathBuf,
        tool_overrides: ToolOverrides,
    ) -> Result<Self> {
        let mut catalog = read_catalog(catalog_path).await?;
        catalog.tools.extend(tool_overrides.source_specs.clone());
        let catalog = Arc::new(catalog);
        let registry = registry_from_catalog(&catalog);
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
            tool_overrides,
            proposal_store.clone(),
        ));
        let runner = Arc::new(AgentRunner::new(registry, store.clone(), services.clone()));
        let session_store = Arc::new(
            FileSessionStore::new(store_path.clone())
                .await
                .into_diagnostic()?,
        );
        Ok(Self {
            catalog,
            runner,
            services,
            run_store: store,
            proposal_store,
            session_store,
            store_path,
        })
    }

    async fn run_agent(
        &self,
        agent_id: String,
        input: Value,
        session_id: Option<String>,
        thread_id: Option<String>,
    ) -> Result<AgentRunResponse> {
        let outcome = self
            .runner
            .run_once(
                &agent_id,
                RunRequest {
                    protocol_version: PROTOCOL_VERSION.to_owned(),
                    run_id: None,
                    input,
                    user: None,
                    trigger: agent_core::TriggerKind::Manual,
                    metadata: run_metadata(session_id.as_deref(), thread_id.as_deref()),
                },
            )
            .await
            .into_diagnostic()?;
        record_session_step(&self.store_path, thread_id.as_deref(), &outcome).await?;
        write_store_trace(&self.store_path, &outcome.trace).await?;
        Ok(AgentRunResponse {
            result: outcome.result,
            trace: outcome.trace,
        })
    }

    async fn call_tool(&self, name: String, input: Value) -> Result<ToolCallResponse> {
        ensure_catalog_has_tool(&self.catalog, &name)?;
        let output = self
            .services
            .call_tool(&name, input)
            .await
            .map_err(|err| miette!(err.record.message))?;
        Ok(ToolCallResponse { tool: name, output })
    }

    async fn get_run(&self, run_id: RunId) -> Result<AgentRunRecord> {
        self.run_store
            .get_run(&run_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("run '{}' was not found", run_id.0))
    }

    async fn list_runs(
        &self,
        agent_id: Option<String>,
        limit: Option<usize>,
    ) -> Result<Vec<AgentRunRecord>> {
        self.run_store
            .list_runs(agent_id.as_deref(), limit)
            .await
            .into_diagnostic()
    }

    async fn get_run_trace(&self, run_id: RunId) -> Result<Value> {
        read_store_trace(&self.store_path, &run_id)
            .await?
            .ok_or_else(|| miette!("trace for run '{}' was not found", run_id.0))
    }

    async fn replay_run(&self, run_id: RunId) -> Result<ReplayExecutionReport> {
        let trace_value = self.get_run_trace(run_id.clone()).await?;
        let source_trace: agent_core::AgentTrace = serde_json::from_value(trace_value)
            .map_err(|e| miette!("failed to parse trace for run '{}': {e}", run_id.0))?;
        replay_source_trace(
            self.runner.as_ref(),
            &self.store_path,
            source_trace,
            ReplayMode::Live,
        )
        .await
    }

    async fn metrics_summary(&self) -> Result<RuntimeMetricsSummary> {
        build_metrics_summary(
            &self.store_path,
            self.run_store.as_ref(),
            self.proposal_store.as_ref(),
        )
        .await
    }

    async fn create_proposal(&self, params: HttpProposalCreateParams) -> Result<ProposalEnvelope> {
        let proposal = ProposalEnvelope::new(
            RunId(params.run_id),
            params.agent_id,
            params.kind,
            params.summary,
            params.payload,
        );
        self.proposal_store
            .create_proposal(proposal.clone())
            .await
            .into_diagnostic()?;
        append_proposal_created_trace_event(&self.store_path, &proposal).await?;
        Ok(proposal)
    }

    async fn list_proposals(&self, run_id: Option<String>) -> Result<Vec<ProposalEnvelope>> {
        let run_id = run_id.map(RunId);
        self.proposal_store
            .list_proposals(run_id.as_ref())
            .await
            .into_diagnostic()
    }

    async fn create_session(
        &self,
        params: HttpSessionCreateParams,
    ) -> Result<HttpSessionCreateResponse> {
        if params.title.trim().is_empty() {
            return Err(miette!("session title cannot be empty"));
        }
        let session = SessionRecord::new(params.title.clone(), params.metadata);
        let thread = ThreadRecord::root(
            session.session_id.clone(),
            Some(params.title),
            json!({"source": "http"}),
        );
        self.session_store
            .create_session(session.clone())
            .await
            .into_diagnostic()?;
        self.session_store
            .create_thread(thread.clone())
            .await
            .into_diagnostic()?;
        Ok(HttpSessionCreateResponse { session, thread })
    }

    async fn list_sessions(&self) -> Result<Vec<SessionRecord>> {
        self.session_store.list_sessions().await.into_diagnostic()
    }

    async fn show_session(&self, session_id: SessionId) -> Result<SessionShowReport> {
        let session = self
            .session_store
            .get_session(&session_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
        let mut threads = Vec::new();
        for thread in self
            .session_store
            .list_threads(&session.session_id)
            .await
            .into_diagnostic()?
        {
            let steps = self
                .session_store
                .list_steps(&thread.thread_id)
                .await
                .into_diagnostic()?;
            threads.push(ThreadWithSteps { thread, steps });
        }
        Ok(SessionShowReport { session, threads })
    }

    async fn fork_thread(
        &self,
        session_id: SessionId,
        params: HttpThreadForkParams,
    ) -> Result<ThreadForkReport> {
        self.session_store
            .get_session(&session_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
        let parent_thread_id = ThreadId(params.parent_thread_id);
        let parent = self
            .session_store
            .get_thread(&parent_thread_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("thread '{}' was not found", parent_thread_id.0))?;
        if parent.session_id != session_id {
            return Err(miette!(
                "thread '{}' does not belong to session '{}'",
                parent_thread_id.0,
                session_id.0
            ));
        }
        let thread = ThreadRecord::fork(
            session_id.clone(),
            parent_thread_id.clone(),
            params.title,
            params.metadata,
        );
        self.session_store
            .create_thread(thread.clone())
            .await
            .into_diagnostic()?;
        Ok(ThreadForkReport {
            session_id: session_id.0,
            parent_thread_id: parent_thread_id.0,
            thread,
        })
    }

    async fn get_proposal(&self, proposal_id: ProposalId) -> Result<ProposalEnvelope> {
        self.proposal_store
            .get_proposal(&proposal_id)
            .await
            .into_diagnostic()?
            .ok_or_else(|| miette!("proposal '{}' was not found", proposal_id.0))
    }

    async fn decide_proposal(
        &self,
        proposal_id: ProposalId,
        params: HttpProposalDecisionParams,
    ) -> Result<ProposalDecisionResponse> {
        let mut proposal = self.get_proposal(proposal_id.clone()).await?;
        let decision = parse_approval_decision(&params.decision)?;
        proposal.status = match decision {
            ApprovalDecisionKind::Approve => ProposalStatus::Approved,
            ApprovalDecisionKind::Deny => ProposalStatus::Denied,
        };
        self.proposal_store
            .update_proposal(proposal.clone())
            .await
            .into_diagnostic()?;
        let response = ProposalDecisionResponse {
            decision: ApprovalDecision {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                proposal_id,
                decision,
                decided_at: time::OffsetDateTime::now_utc(),
                comment: params.comment,
            },
            proposal,
        };
        append_proposal_decision_trace_event(&self.store_path, &response).await?;
        Ok(response)
    }

    async fn apply_proposal(&self, proposal_id: ProposalId) -> Result<ProposalActionResponse> {
        self.execute_proposal_action(proposal_id, ProposalAction::Apply)
            .await
    }

    async fn undo_proposal(&self, proposal_id: ProposalId) -> Result<ProposalActionResponse> {
        self.execute_proposal_action(proposal_id, ProposalAction::Undo)
            .await
    }

    async fn execute_proposal_action(
        &self,
        proposal_id: ProposalId,
        action: ProposalAction,
    ) -> Result<ProposalActionResponse> {
        let mut proposal = self.get_proposal(proposal_id).await?;
        let tool = proposal_action_tool(&self.catalog, &proposal.kind)?;
        let response = execute_proposal_action_with_store(
            self.proposal_store.as_ref(),
            self.services.as_ref(),
            &mut proposal,
            tool,
            action,
        )
        .await?;
        append_proposal_action_trace_event(&self.store_path, &response).await?;
        Ok(response)
    }
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

#[derive(Debug, Deserialize)]
struct RegistryFile {
    agents: Vec<AgentManifest>,
}

#[derive(Debug, Deserialize)]
struct AgentManifest {
    #[serde(flatten)]
    spec: AgentSpec,
    #[serde(default = "default_runner")]
    runner: String,
}

struct CliRegistry {
    agents: Vec<Arc<dyn Agent>>,
}

impl CliRegistry {
    fn list_specs(&self) -> Vec<AgentSpec> {
        self.agents.iter().map(|agent| agent.spec()).collect()
    }

    fn into_agent_registry(self) -> Arc<InMemoryAgentRegistry> {
        InMemoryAgentRegistry::shared(self.agents)
    }
}

async fn load_registry(path: Utf8PathBuf) -> Result<CliRegistry> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read registry at {path}: {e}"))?;
    let file: RegistryFile = serde_yaml::from_slice(&bytes)
        .map_err(|e| miette!("failed to parse registry at {path}: {e}"))?;
    let agents = file
        .agents
        .into_iter()
        .map(|manifest| match manifest.runner.as_str() {
            "echo" => Ok(Arc::new(EchoAgent {
                spec: manifest.spec,
            }) as Arc<dyn Agent>),
            other => Err(miette!("unsupported agent runner '{other}'")),
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(CliRegistry { agents })
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
                trigger: agent_core::TriggerKind::Manual,
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
            write_json(golden_path, &actual).await?;
            checked.push("golden_trace:updated".to_owned());
        } else {
            let expected = read_json(golden_path.clone()).await?;
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
    outcome: &agent_runtime::RunOutcome,
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

async fn run_eval_path(
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

async fn create_eval_from_run(
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
    write_json(golden_trace_abs.clone(), &normalized_trace).await?;

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

    write_yaml(out.clone(), &case).await?;
    let report = EvalCreateReport {
        id: eval_id,
        run_id: run_id.0,
        agent_id: record.agent_id,
        eval_file: out.to_string(),
        golden_trace: golden_trace_abs.to_string(),
    };
    serde_json::to_value(report).into_diagnostic()
}

async fn create_session(store_path: Utf8PathBuf, title: String) -> Result<SessionCreateReport> {
    let store = FileSessionStore::new(store_path).await.into_diagnostic()?;
    let session = SessionRecord::new(title.clone(), json!({}));
    let thread = ThreadRecord::root(session.session_id.clone(), Some(title), json!({}));
    store
        .create_session(session.clone())
        .await
        .into_diagnostic()?;
    store
        .create_thread(thread.clone())
        .await
        .into_diagnostic()?;
    Ok(SessionCreateReport { session, thread })
}

fn run_metadata(session: Option<&str>, thread: Option<&str>) -> Value {
    json!({
        "session_id": session,
        "thread_id": thread,
    })
}

async fn record_session_step(
    store_path: &Utf8Path,
    thread_id: Option<&str>,
    outcome: &agent_runtime::RunOutcome,
) -> Result<()> {
    let Some(thread_id) = thread_id else {
        return Ok(());
    };
    let store = FileSessionStore::new(store_path.to_path_buf())
        .await
        .into_diagnostic()?;
    let thread_id = ThreadId(thread_id.to_owned());
    let thread = store
        .get_thread(&thread_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("thread '{}' was not found", thread_id.0))?;
    let step = StepRecord::agent_run(
        thread.thread_id,
        outcome.result.run_id.clone(),
        outcome.result.summary.clone(),
        json!({
            "agent_id": outcome.result.agent_id.clone(),
            "status": outcome.result.status.clone(),
        }),
    );
    store.create_step(step).await.into_diagnostic()
}

async fn show_session(store_path: Utf8PathBuf, session_id: SessionId) -> Result<SessionShowReport> {
    let store = FileSessionStore::new(store_path).await.into_diagnostic()?;
    let session = store
        .get_session(&session_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
    let mut threads = Vec::new();
    for thread in store
        .list_threads(&session.session_id)
        .await
        .into_diagnostic()?
    {
        let steps = store
            .list_steps(&thread.thread_id)
            .await
            .into_diagnostic()?;
        threads.push(ThreadWithSteps { thread, steps });
    }
    Ok(SessionShowReport { session, threads })
}

async fn fork_thread(
    store_path: Utf8PathBuf,
    session_id: SessionId,
    parent_thread_id: ThreadId,
    title: Option<String>,
) -> Result<ThreadForkReport> {
    let store = FileSessionStore::new(store_path).await.into_diagnostic()?;
    store
        .get_session(&session_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("session '{}' was not found", session_id.0))?;
    let parent = store
        .get_thread(&parent_thread_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("thread '{}' was not found", parent_thread_id.0))?;
    if parent.session_id != session_id {
        return Err(miette!(
            "thread '{}' does not belong to session '{}'",
            parent_thread_id.0,
            session_id.0
        ));
    }
    let thread = ThreadRecord::fork(
        session_id.clone(),
        parent_thread_id.clone(),
        title,
        json!({}),
    );
    store
        .create_thread(thread.clone())
        .await
        .into_diagnostic()?;
    Ok(ThreadForkReport {
        session_id: session_id.0,
        parent_thread_id: parent_thread_id.0,
        thread,
    })
}

async fn create_command_from_run(
    run_id: String,
    store_path: Utf8PathBuf,
    out: Utf8PathBuf,
    description: Option<String>,
    catalog: Option<Utf8PathBuf>,
    registry: Option<Utf8PathBuf>,
) -> Result<CommandCreateReport> {
    if catalog.is_some() && registry.is_some() {
        return Err(miette!("use only one of --catalog or --registry"));
    }
    let store = FileRunStore::new(store_path).await.into_diagnostic()?;
    let run_id = RunId(run_id);
    let record = store
        .get_run(&run_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("run '{}' was not found", run_id.0))?;

    let command_id = command_id_from_path(&out).unwrap_or_else(|| default_command_id(&record));
    let frontmatter = CommandFrontmatter {
        description: Some(description.unwrap_or_else(|| {
            format!(
                "Replay {} from captured run {}",
                record.agent_id, record.run_id.0
            )
        })),
        agent: record.agent_id.clone(),
        catalog: catalog.map(|path| path.to_string()),
        registry: registry.map(|path| path.to_string()),
        source_run_id: Some(record.run_id.0.clone()),
        source_run_status: Some(record.status.clone()),
        created_at: Some(
            time::OffsetDateTime::now_utc()
                .format(&Rfc3339)
                .unwrap_or_else(|_| time::OffsetDateTime::now_utc().to_string()),
        ),
    };
    let markdown = render_command_markdown(&frontmatter, &record.input)?;
    write_text(out.clone(), &markdown).await?;
    Ok(CommandCreateReport {
        id: command_id,
        run_id: record.run_id.0,
        agent_id: record.agent_id,
        command_file: out.to_string(),
    })
}

async fn run_command_template(options: CommandRunOptions) -> Result<CommandRunReport> {
    if options.catalog.is_some() && options.registry.is_some() {
        return Err(miette!("use only one of --catalog or --registry"));
    }
    let text = fs_err::tokio::read_to_string(&options.command_file)
        .await
        .map_err(|e| miette!("failed to read command at {}: {e}", options.command_file))?;
    let template = parse_command_template(&text, &options.command_file)?;
    let registry_path =
        resolve_command_registry_path(&template.frontmatter, options.catalog, options.registry)?;
    let registry = match registry_path {
        CommandRegistryPath::Catalog(path) => load_catalog_registry(path).await?,
        CommandRegistryPath::Registry(path) => load_registry(path).await?.into_agent_registry(),
    };
    let store = Arc::new(
        FileRunStore::new(options.store.clone())
            .await
            .into_diagnostic()?,
    );
    let proposal_store = Arc::new(
        FileProposalStore::new(options.store.clone())
            .await
            .into_diagnostic()?,
    );
    let services = Arc::new(CliServices::with_proposal_store(
        tool_overrides(options.tool_host, options.mock_tool, options.tool_source).await?,
        proposal_store,
    ));
    let runner = AgentRunner::new(registry, store, services).with_policy(execution_policy(
        options.timeout_seconds,
        options.max_retries,
        options.retry_backoff_ms,
    ));
    let outcome = runner
        .run_once(
            &template.frontmatter.agent,
            RunRequest {
                protocol_version: PROTOCOL_VERSION.to_owned(),
                run_id: None,
                input: template.input,
                user: None,
                trigger: TriggerKind::Manual,
                metadata: json!({
                    "source": "command_template",
                    "command_file": options.command_file.to_string(),
                    "source_run_id": template.frontmatter.source_run_id,
                }),
            },
        )
        .await
        .into_diagnostic()?;
    write_store_trace(&options.store, &outcome.trace).await?;
    if let Some(path) = options.trace_out {
        write_json(path, &outcome.trace).await?;
    }
    Ok(CommandRunReport {
        command_file: options.command_file.to_string(),
        agent_id: outcome.result.agent_id.clone(),
        result: outcome.result,
        trace: outcome.trace,
    })
}

fn resolve_command_registry_path(
    frontmatter: &CommandFrontmatter,
    catalog: Option<Utf8PathBuf>,
    registry: Option<Utf8PathBuf>,
) -> Result<CommandRegistryPath> {
    if let Some(path) = catalog {
        return Ok(CommandRegistryPath::Catalog(path));
    }
    if let Some(path) = registry {
        return Ok(CommandRegistryPath::Registry(path));
    }
    match (&frontmatter.catalog, &frontmatter.registry) {
        (Some(_), Some(_)) => Err(miette!(
            "command frontmatter must not contain both catalog and registry"
        )),
        (Some(path), None) => Ok(CommandRegistryPath::Catalog(Utf8PathBuf::from(path))),
        (None, Some(path)) => Ok(CommandRegistryPath::Registry(Utf8PathBuf::from(path))),
        (None, None) => Ok(CommandRegistryPath::Registry(Utf8PathBuf::from(
            "examples/agent-runtime/agents.yaml",
        ))),
    }
}

fn render_command_markdown(frontmatter: &CommandFrontmatter, input: &Value) -> Result<String> {
    let frontmatter = serde_yaml::to_string(frontmatter).into_diagnostic()?;
    let input = serde_json::to_string_pretty(input).into_diagnostic()?;
    Ok(format!(
        "---\n{frontmatter}---\n\nRun the configured agent with this captured input. Replace or extend `$ARGUMENTS` when invoking the command to add run-specific instructions.\n\n```json\n{input}\n```\n"
    ))
}

fn parse_command_template(markdown: &str, path: &Utf8Path) -> Result<CommandTemplate> {
    let Some(rest) = markdown.strip_prefix("---\n") else {
        return Err(miette!(
            "command template at {path} must start with YAML frontmatter"
        ));
    };
    let Some((frontmatter, body)) = rest.split_once("\n---") else {
        return Err(miette!(
            "command template at {path} is missing closing frontmatter marker"
        ));
    };
    let frontmatter: CommandFrontmatter = serde_yaml::from_str(frontmatter)
        .map_err(|e| miette!("failed to parse command frontmatter at {path}: {e}"))?;
    if frontmatter.agent.trim().is_empty() {
        return Err(miette!("command frontmatter at {path} must include agent"));
    }
    let input_text = extract_json_fence(body)
        .ok_or_else(|| miette!("command template at {path} must include a json code fence"))?;
    let input = serde_json::from_str(input_text)
        .map_err(|e| miette!("failed to parse command input JSON at {path}: {e}"))?;
    Ok(CommandTemplate { frontmatter, input })
}

fn extract_json_fence(body: &str) -> Option<&str> {
    let (_, after_open) = body.split_once("```json")?;
    let after_open = after_open.strip_prefix('\n').unwrap_or(after_open);
    let (json, _) = after_open.split_once("```")?;
    Some(json.trim())
}

fn command_id_from_path(path: &Utf8Path) -> Option<String> {
    path.file_stem().map(sanitize_eval_id)
}

fn default_command_id(record: &AgentRunRecord) -> String {
    format!(
        "{}_{}",
        sanitize_eval_id(&record.agent_id),
        sanitize_eval_id(&record.run_id.0)
    )
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

async fn export_debug_bundle(
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
        Some(path) => Some(read_json(path.clone()).await?),
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
    write_json(out.join("manifest.json"), &manifest).await?;
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

fn string_metadata(metadata: &Value, key: &str) -> Option<String> {
    metadata
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

async fn build_metrics_summary(
    store_path: &Utf8Path,
    run_store: &FileRunStore,
    proposal_store: &FileProposalStore,
) -> Result<RuntimeMetricsSummary> {
    let runs = run_store.list_runs(None, None).await.into_diagnostic()?;
    let proposals = proposal_store
        .list_proposals(None)
        .await
        .into_diagnostic()?;
    let mut runs_by_status = BTreeMap::new();
    let mut total_run_latency_ms = 0_u64;
    let mut completed_latency_count = 0_u64;
    let mut tool_call_count = 0_usize;
    let mut failed_tool_call_count = 0_usize;
    let mut total_tool_call_latency_ms = 0_u64;
    let mut replay_count = 0_usize;
    let mut llm_total_tokens = 0_u64;
    let mut proposal_created_count = 0_usize;
    let mut proposal_approved_count = 0_usize;
    let mut proposal_denied_count = 0_usize;
    let mut proposal_applied_count = 0_usize;

    for run in &runs {
        *runs_by_status
            .entry(run_status_key(&run.status))
            .or_insert(0) += 1;
        if let Some(finished_at) = run.finished_at {
            let latency_ms = (finished_at - run.started_at).whole_milliseconds();
            if latency_ms >= 0 {
                total_run_latency_ms =
                    total_run_latency_ms.saturating_add(u64::try_from(latency_ms).unwrap_or(0));
                completed_latency_count = completed_latency_count.saturating_add(1);
            }
        }
        if let Some(trace) = read_store_trace(store_path, &run.run_id).await? {
            if trace_started_by_replay(&trace) {
                replay_count += 1;
            }
            for event in event_records_from_trace(&trace) {
                let kind = event.get("kind").and_then(Value::as_str);
                let payload = event.get("payload").unwrap_or(&Value::Null);
                match kind {
                    Some("tool_call_finished") => {
                        tool_call_count += 1;
                        total_tool_call_latency_ms =
                            total_tool_call_latency_ms.saturating_add(payload_duration_ms(payload));
                    }
                    Some("tool_call_failed") => {
                        tool_call_count += 1;
                        failed_tool_call_count += 1;
                        total_tool_call_latency_ms =
                            total_tool_call_latency_ms.saturating_add(payload_duration_ms(payload));
                    }
                    Some("llm_response") | Some("llm.round.finished") => {
                        llm_total_tokens =
                            llm_total_tokens.saturating_add(payload_total_tokens(payload));
                    }
                    Some("proposal_created") => {
                        proposal_created_count += 1;
                    }
                    Some("proposal_decided") => {
                        match payload.get("decision").and_then(Value::as_str) {
                            Some("approve" | "approved") => proposal_approved_count += 1,
                            Some("deny" | "denied") => proposal_denied_count += 1,
                            _ => {}
                        }
                    }
                    Some("proposal_applied") => {
                        proposal_applied_count += 1;
                    }
                    _ => {}
                }
            }
        }
    }

    let mut proposals_by_status = BTreeMap::new();
    for proposal in &proposals {
        *proposals_by_status
            .entry(proposal_status_key(&proposal.status))
            .or_insert(0) += 1;
    }
    if proposal_created_count == 0 {
        proposal_created_count = proposals.len();
    }
    if proposal_approved_count == 0 {
        proposal_approved_count = count_run_status(&proposals_by_status, "approved");
    }
    if proposal_denied_count == 0 {
        proposal_denied_count = count_run_status(&proposals_by_status, "denied");
    }
    if proposal_applied_count == 0 {
        proposal_applied_count = count_run_status(&proposals_by_status, "applied");
    }
    let generated_at = time::OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .into_diagnostic()?;
    Ok(RuntimeMetricsSummary {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        runtime_version: RUNTIME_VERSION.to_owned(),
        generated_at,
        store_root: store_path.to_string(),
        run_count: runs.len(),
        successful_run_count: count_run_status(&runs_by_status, "completed"),
        skipped_run_count: count_run_status(&runs_by_status, "skipped"),
        failed_run_count: count_failure_runs(&runs_by_status),
        timeout_count: count_run_status(&runs_by_status, "timed_out"),
        total_run_latency_ms,
        average_run_latency_ms: average_ms(total_run_latency_ms, completed_latency_count),
        tool_call_count,
        failed_tool_call_count,
        total_tool_call_latency_ms,
        average_tool_call_latency_ms: average_ms(
            total_tool_call_latency_ms,
            tool_call_count as u64,
        ),
        replay_count,
        proposal_count: proposals.len(),
        proposal_created_count,
        proposal_approved_count,
        proposal_denied_count,
        proposal_applied_count,
        proposals_by_status,
        runs_by_status,
        llm_total_tokens,
    })
}

fn run_status_key(status: &agent_core::AgentRunStatus) -> String {
    serde_json::to_value(status)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| format!("{status:?}"))
}

fn proposal_status_key(status: &ProposalStatus) -> String {
    serde_json::to_value(status)
        .ok()
        .and_then(|value| value.as_str().map(ToOwned::to_owned))
        .unwrap_or_else(|| format!("{status:?}"))
}

fn count_run_status(counts: &BTreeMap<String, usize>, status: &str) -> usize {
    counts.get(status).copied().unwrap_or(0)
}

fn count_failure_runs(counts: &BTreeMap<String, usize>) -> usize {
    ["failed", "cancelled", "timed_out", "abandoned"]
        .iter()
        .map(|status| count_run_status(counts, status))
        .sum()
}

fn average_ms(total: u64, count: u64) -> Option<f64> {
    (count > 0).then(|| total as f64 / count as f64)
}

fn payload_duration_ms(payload: &Value) -> u64 {
    payload
        .get("duration_ms")
        .and_then(Value::as_u64)
        .unwrap_or(0)
}

fn payload_total_tokens(payload: &Value) -> u64 {
    payload
        .get("usage")
        .and_then(|usage| usage.get("total_tokens"))
        .or_else(|| payload.get("total_tokens"))
        .and_then(Value::as_u64)
        .unwrap_or(0)
}

fn trace_started_by_replay(trace: &Value) -> bool {
    trace
        .get("events")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .any(|event| {
            event.get("kind").and_then(Value::as_str) == Some("run_started")
                && event
                    .get("payload")
                    .and_then(|payload| payload.get("trigger"))
                    .and_then(Value::as_str)
                    == Some("replay")
        })
}

fn build_prompt_manifest(
    catalog: &AgentRuntimeCatalog,
    agent_id: Option<&str>,
) -> Result<PromptManifest> {
    let agent = select_prompt_manifest_agent(catalog, agent_id)?;
    let prompt_version = string_metadata(&agent.metadata, "prompt_version")
        .unwrap_or_else(|| format!("{}.prompt.v1", agent.id));
    let manifest_id = string_metadata(&agent.metadata, "prompt_id")
        .unwrap_or_else(|| format!("{}_prompt", agent.id));
    let model_family =
        string_metadata(&agent.metadata, "model_family").unwrap_or_else(|| "unknown".to_owned());
    let provider =
        string_metadata(&agent.metadata, "provider").unwrap_or_else(|| "unknown".to_owned());
    let model = string_metadata(&agent.metadata, "model").unwrap_or_else(|| "unknown".to_owned());
    let tool_schema_version = string_metadata(&agent.metadata, "tool_schema_version")
        .unwrap_or_else(|| catalog.catalog_version.clone());
    let blocks = catalog
        .prompt_blocks
        .iter()
        .map(|block| PromptManifestBlock {
            index: block.index,
            source: format!("catalog.prompt_blocks[{}]", block.index),
            content_hash: prompt_block_hash(&block.text),
            text: block.text.clone(),
        })
        .collect();
    Ok(PromptManifest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        id: manifest_id,
        version: prompt_version,
        agent_id: agent.id.clone(),
        agent_version: agent.version.clone(),
        catalog_version: catalog.catalog_version.clone(),
        generated_at: catalog.generated_at,
        model_family,
        provider,
        model,
        tool_schema_version,
        active_domains: catalog.active_domains.clone(),
        blocks,
    })
}

fn select_prompt_manifest_agent<'a>(
    catalog: &'a AgentRuntimeCatalog,
    agent_id: Option<&str>,
) -> Result<&'a AgentSpec> {
    if let Some(agent_id) = agent_id {
        return catalog
            .agents
            .iter()
            .find(|agent| agent.id == agent_id)
            .ok_or_else(|| miette!("agent '{agent_id}' not found in catalog"));
    }
    match catalog.agents.as_slice() {
        [agent] => Ok(agent),
        [] => Err(miette!(
            "catalog has no agents; pass --agent-id after adding one"
        )),
        _ => Err(miette!(
            "catalog has multiple agents; pass --agent-id to choose a prompt manifest"
        )),
    }
}

fn prompt_block_hash(text: &str) -> String {
    format!("blake3:{}", blake3::hash(text.as_bytes()).to_hex())
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

async fn append_proposal_created_trace_event(
    store_path: &Utf8Path,
    proposal: &ProposalEnvelope,
) -> Result<()> {
    append_store_trace_event(
        store_path,
        &proposal.run_id,
        TraceEvent::new(
            "proposal_created",
            json!({
                "proposal_id": proposal.proposal_id.0.clone(),
                "run_id": proposal.run_id.0.clone(),
                "agent_id": proposal.agent_id.clone(),
                "kind": proposal.kind.clone(),
                "summary": proposal.summary.clone(),
                "status": proposal.status.clone(),
            }),
        ),
    )
    .await
}

async fn append_proposal_decision_trace_event(
    store_path: &Utf8Path,
    response: &ProposalDecisionResponse,
) -> Result<()> {
    append_store_trace_event(
        store_path,
        &response.proposal.run_id,
        TraceEvent::new(
            "proposal_decided",
            json!({
                "proposal_id": response.proposal.proposal_id.0.clone(),
                "run_id": response.proposal.run_id.0.clone(),
                "agent_id": response.proposal.agent_id.clone(),
                "kind": response.proposal.kind.clone(),
                "decision": response.decision.decision.clone(),
                "status": response.proposal.status.clone(),
                "comment": response.decision.comment.clone(),
            }),
        ),
    )
    .await
}

async fn append_proposal_action_trace_event(
    store_path: &Utf8Path,
    response: &ProposalActionResponse,
) -> Result<()> {
    let event_kind = match response.action.as_str() {
        "apply" => "proposal_applied",
        "undo" => "proposal_undone",
        _ => "proposal_action_finished",
    };
    append_store_trace_event(
        store_path,
        &response.proposal.run_id,
        TraceEvent::new(
            event_kind,
            json!({
                "proposal_id": response.proposal.proposal_id.0.clone(),
                "run_id": response.proposal.run_id.0.clone(),
                "agent_id": response.proposal.agent_id.clone(),
                "kind": response.proposal.kind.clone(),
                "action": response.action,
                "status": response.proposal.status.clone(),
                "tool": response.tool.clone(),
                "tool_output": response.tool_output.clone(),
            }),
        ),
    )
    .await
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

async fn execute_proposal_action(
    proposal_id: ProposalId,
    store_path: Utf8PathBuf,
    catalog_path: Utf8PathBuf,
    tool_overrides: ToolOverrides,
    action: ProposalAction,
) -> Result<ProposalActionResponse> {
    let catalog = read_catalog(catalog_path).await?;
    let store = FileProposalStore::new(store_path.clone())
        .await
        .into_diagnostic()?;
    let services = CliServices::new(tool_overrides);
    let mut proposal = store
        .get_proposal(&proposal_id)
        .await
        .into_diagnostic()?
        .ok_or_else(|| miette!("proposal '{}' was not found", proposal_id.0))?;
    let tool = proposal_action_tool(&catalog, &proposal.kind)?;
    let response =
        execute_proposal_action_with_store(&store, &services, &mut proposal, tool, action).await?;
    append_proposal_action_trace_event(&store_path, &response).await?;
    Ok(response)
}

async fn execute_proposal_action_with_store(
    store: &dyn AgentProposalStore,
    services: &dyn AgentServices,
    proposal: &mut ProposalEnvelope,
    tool: String,
    action: ProposalAction,
) -> Result<ProposalActionResponse> {
    let required = action.required_status();
    if proposal.status != required {
        return Err(miette!(
            "proposal '{}' must be {:?} before {} but is {:?}",
            proposal.proposal_id.0,
            required,
            action.as_str(),
            proposal.status
        ));
    }

    proposal.status = action.in_progress_status();
    store
        .update_proposal(proposal.clone())
        .await
        .into_diagnostic()?;

    let tool_input = json!({
        "action": action.as_str(),
        "proposal": proposal.clone(),
    });
    let tool_output = match services.call_tool(&tool, tool_input).await {
        Ok(output) => output,
        Err(err) => {
            proposal.status = action.failure_status();
            store
                .update_proposal(proposal.clone())
                .await
                .into_diagnostic()?;
            return Err(miette!(err.record.message));
        }
    };

    proposal.status = action.success_status();
    store
        .update_proposal(proposal.clone())
        .await
        .into_diagnostic()?;
    Ok(ProposalActionResponse {
        action: action.as_str().to_owned(),
        tool,
        tool_output,
        proposal: proposal.clone(),
    })
}

fn proposal_action_tool(catalog: &AgentRuntimeCatalog, kind: &str) -> Result<String> {
    catalog
        .proposal_kinds
        .iter()
        .find(|spec| spec.kind == kind)
        .map(|spec| spec.tool_name.clone())
        .ok_or_else(|| miette!("proposal kind '{kind}' is not present in the active catalog"))
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

async fn replay_trace(options: ReplayTraceOptions) -> Result<()> {
    let source_trace = read_trace(options.trace_file).await?;
    if options.mode == ReplayMode::Deterministic {
        let report = deterministic_replay_report(source_trace)?;
        if let Some(path) = options.trace_out {
            write_json(path, &report.trace).await?;
        }
        return print_json(&report);
    }
    let registry = match options.catalog {
        Some(path) => load_catalog_registry(path).await?,
        None => load_registry(options.registry).await?.into_agent_registry(),
    };
    let store = Arc::new(
        FileRunStore::new(options.store.clone())
            .await
            .into_diagnostic()?,
    );
    let proposal_store = Arc::new(
        FileProposalStore::new(options.store.clone())
            .await
            .into_diagnostic()?,
    );
    let services = Arc::new(CliServices::with_proposal_store(
        tool_overrides(options.tool_host, options.mock_tool, options.tool_source).await?,
        proposal_store,
    ));
    let runner = AgentRunner::new(registry, store, services).with_policy(execution_policy(
        options.timeout_seconds,
        options.max_retries,
        options.retry_backoff_ms,
    ));
    let report = replay_source_trace(&runner, &options.store, source_trace, options.mode).await?;
    if let Some(path) = options.trace_out {
        write_json(path, &report.trace).await?;
    }
    print_json(&report)
}

async fn replay_source_trace(
    runner: &AgentRunner,
    store_path: &Utf8Path,
    source_trace: agent_core::AgentTrace,
    mode: ReplayMode,
) -> Result<ReplayExecutionReport> {
    let source_output = source_trace.output.clone();
    let outcome = runner
        .run_once(
            &source_trace.agent_id,
            run_request_from_trace(&source_trace),
        )
        .await
        .into_diagnostic()?;
    write_store_trace(store_path, &outcome.trace).await?;
    Ok(ReplayExecutionReport {
        mode,
        source_run_id: source_trace.run_id,
        replay_run_id: outcome.result.run_id.clone(),
        agent_id: outcome.result.agent_id.clone(),
        output_matches: source_output == outcome.result.output,
        result: outcome.result,
        trace: outcome.trace,
    })
}

fn deterministic_replay_report(
    source_trace: agent_core::AgentTrace,
) -> Result<ReplayExecutionReport> {
    let result = AgentRunResult {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        run_id: source_trace.run_id.clone(),
        agent_id: source_trace.agent_id.clone(),
        status: agent_core::AgentRunStatus::Completed,
        started_at: source_trace.started_at,
        finished_at: source_trace.finished_at,
        summary: Some("deterministic replay reused source trace output".to_owned()),
        output: source_trace.output.clone(),
        error: None,
    };
    Ok(ReplayExecutionReport {
        mode: ReplayMode::Deterministic,
        source_run_id: source_trace.run_id.clone(),
        replay_run_id: source_trace.run_id.clone(),
        agent_id: source_trace.agent_id.clone(),
        result,
        trace: source_trace,
        output_matches: true,
    })
}

fn run_request_from_trace(trace: &agent_core::AgentTrace) -> RunRequest {
    RunRequest {
        protocol_version: PROTOCOL_VERSION.to_owned(),
        run_id: None,
        input: trace.input.clone(),
        user: None,
        trigger: TriggerKind::Replay,
        metadata: json!({
            "source": "trace_replay",
            "source_run_id": trace.run_id.0
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
    value: &impl serde::Serialize,
    files: &mut BTreeMap<String, String>,
) -> Result<()> {
    write_json(out.join(name), value).await?;
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

fn bundle_file_key(name: &str) -> String {
    name.trim_end_matches(".json")
        .trim_end_matches(".jsonl")
        .to_owned()
}

async fn write_redacted_bundle_json(
    out: &Utf8Path,
    name: &str,
    value: &impl serde::Serialize,
    files: &mut BTreeMap<String, String>,
    report: &mut RedactionReport,
) -> Result<()> {
    let mut value = serde_json::to_value(value).into_diagnostic()?;
    redact_json_value(&mut value, "$", report);
    write_bundle_json(out, name, &value, files).await
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

async fn write_store_trace(store: &Utf8Path, trace: &agent_core::AgentTrace) -> Result<()> {
    write_json(store_trace_path(store, &trace.run_id), trace).await
}

async fn read_store_trace(store: &Utf8Path, run_id: &RunId) -> Result<Option<Value>> {
    let path = store_trace_path(store, run_id);
    if !path.exists() {
        return Ok(None);
    }
    read_json(path).await.map(Some)
}

async fn append_store_trace_event(
    store: &Utf8Path,
    run_id: &RunId,
    event: TraceEvent,
) -> Result<()> {
    let Some(mut trace) = read_store_trace(store, run_id).await? else {
        return Ok(());
    };
    let events = trace
        .get_mut("events")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| miette!("trace for run '{}' has no events array", run_id.0))?;
    events.push(serde_json::to_value(event).into_diagnostic()?);
    write_json(store_trace_path(store, run_id), &trace).await
}

fn store_trace_path(store: &Utf8Path, run_id: &RunId) -> Utf8PathBuf {
    store
        .join("traces")
        .join(format!("{}.trace.json", run_id.0))
}

async fn run_tui(
    catalog_path: Option<Utf8PathBuf>,
    trace_path: Option<Utf8PathBuf>,
    store_path: Utf8PathBuf,
    once: bool,
) -> Result<()> {
    let state = load_tui_state(catalog_path, trace_path, store_path).await?;
    if once {
        println!("{}", render_tui_once(&state)?);
        return Ok(());
    }
    run_tui_terminal(state)
}

async fn load_tui_state(
    catalog_path: Option<Utf8PathBuf>,
    trace_path: Option<Utf8PathBuf>,
    store_path: Utf8PathBuf,
) -> Result<TuiState> {
    let catalog_summary = match &catalog_path {
        Some(path) => Some(CatalogSummary::from_catalog(
            &read_catalog(path.clone()).await?,
        )),
        None => None,
    };
    let trace = match &trace_path {
        Some(path) => Some(read_trace(path.clone()).await?),
        None => None,
    };
    let recent_runs = read_recent_runs(&store_path).await?;
    let status = format!(
        "catalog: {} | trace: {} | runs: {}",
        catalog_summary
            .as_ref()
            .map(|summary| summary.agent_count.to_string())
            .unwrap_or_else(|| "not loaded".to_owned()),
        trace
            .as_ref()
            .map(|trace| trace.run_id.0.clone())
            .unwrap_or_else(|| "not loaded".to_owned()),
        recent_runs.len()
    );
    Ok(TuiState {
        catalog_path,
        trace_path,
        store_path,
        catalog_summary,
        trace,
        recent_runs,
        status,
    })
}

async fn read_recent_runs(store_path: &Utf8Path) -> Result<Vec<AgentRunRecord>> {
    let runs_dir = store_path.join("runs");
    if !runs_dir.exists() {
        return Ok(vec![]);
    }
    let mut entries = fs_err::tokio::read_dir(&runs_dir)
        .await
        .map_err(|e| miette!("failed to read runs at {runs_dir}: {e}"))?;
    let mut records = Vec::new();
    while let Some(entry) = entries.next_entry().await.into_diagnostic()? {
        let path = Utf8PathBuf::from_path_buf(entry.path())
            .map_err(|path| miette!("non-UTF-8 run path: {}", path.display()))?;
        if path.extension() != Some("json") {
            continue;
        }
        let record = serde_json::from_value::<AgentRunRecord>(read_json(path).await?)
            .map_err(|e| miette!("failed to parse run record: {e}"))?;
        records.push(record);
    }
    records.sort_by_key(|record| record.started_at);
    records.reverse();
    records.truncate(8);
    Ok(records)
}

fn render_tui_once(state: &TuiState) -> Result<String> {
    let backend = TestBackend::new(100, 30);
    let mut terminal = Terminal::new(backend).into_diagnostic()?;
    terminal
        .draw(|frame| render_tui_frame(frame, state))
        .into_diagnostic()?;
    Ok(buffer_to_string(terminal.backend().buffer()))
}

fn run_tui_terminal(state: TuiState) -> Result<()> {
    crossterm::terminal::enable_raw_mode().into_diagnostic()?;
    let mut stdout = io::stdout();
    crossterm::execute!(stdout, crossterm::terminal::EnterAlternateScreen).into_diagnostic()?;
    let result = run_tui_event_loop(
        &mut Terminal::new(CrosstermBackend::new(stdout)).into_diagnostic()?,
        &state,
    );
    crossterm::terminal::disable_raw_mode().into_diagnostic()?;
    let mut stdout = io::stdout();
    crossterm::execute!(stdout, crossterm::terminal::LeaveAlternateScreen).into_diagnostic()?;
    result
}

fn run_tui_event_loop(
    terminal: &mut Terminal<CrosstermBackend<Stdout>>,
    state: &TuiState,
) -> Result<()> {
    loop {
        terminal
            .draw(|frame| render_tui_frame(frame, state))
            .into_diagnostic()?;
        if crossterm::event::poll(Duration::from_millis(250)).into_diagnostic()?
            && let crossterm::event::Event::Key(key) = crossterm::event::read().into_diagnostic()?
            && matches!(
                key.code,
                crossterm::event::KeyCode::Char('q') | crossterm::event::KeyCode::Esc
            )
        {
            return Ok(());
        }
    }
}

fn render_tui_frame(frame: &mut Frame<'_>, state: &TuiState) {
    let root = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(10),
            Constraint::Length(5),
        ])
        .split(frame.area());
    let body = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(42), Constraint::Percentage(58)])
        .split(root[1]);

    frame.render_widget(
        Paragraph::new(Line::from(vec![
            Span::styled(
                "Agent Runtime TUI",
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::raw("  q/esc quit"),
        ]))
        .block(Block::default().borders(Borders::ALL)),
        root[0],
    );
    frame.render_widget(catalog_panel(state), body[0]);
    frame.render_widget(trace_panel(state), body[1]);
    frame.render_widget(status_panel(state), root[2]);
}

fn catalog_panel(state: &TuiState) -> List<'static> {
    let mut items = Vec::new();
    items.push(ListItem::new(format!(
        "catalog: {}",
        state
            .catalog_path
            .as_ref()
            .map(ToString::to_string)
            .unwrap_or_else(|| "not loaded".to_owned())
    )));
    if let Some(summary) = &state.catalog_summary {
        items.extend([
            ListItem::new(format!("protocol: {}", summary.protocol_version)),
            ListItem::new(format!("domains: {}", summary.active_domains.join(", "))),
            ListItem::new(format!("agents: {}", summary.agent_count)),
            ListItem::new(format!("tools: {}", summary.tool_count)),
            ListItem::new(format!("proposal kinds: {}", summary.proposal_kind_count)),
            ListItem::new(format!("prompt blocks: {}", summary.prompt_block_count)),
        ]);
    } else {
        items.push(ListItem::new("load with --catalog <path>"));
    }
    items.push(ListItem::new(""));
    items.push(ListItem::new("recent runs"));
    if state.recent_runs.is_empty() {
        items.push(ListItem::new("none"));
    } else {
        items.extend(state.recent_runs.iter().map(|run| {
            ListItem::new(format!(
                "{} {} {:?}",
                run.run_id.0, run.agent_id, run.status
            ))
        }));
    }
    List::new(items).block(
        Block::default()
            .title("Catalog / Runs")
            .borders(Borders::ALL),
    )
}

fn trace_panel(state: &TuiState) -> List<'static> {
    let mut items = Vec::new();
    items.push(ListItem::new(format!(
        "trace: {}",
        state
            .trace_path
            .as_ref()
            .map(ToString::to_string)
            .unwrap_or_else(|| "not loaded".to_owned())
    )));
    if let Some(trace) = &state.trace {
        items.extend([
            ListItem::new(format!("run: {}", trace.run_id.0)),
            ListItem::new(format!("agent: {}@{}", trace.agent_id, trace.agent_version)),
            ListItem::new(format!("events: {}", trace.events.len())),
            ListItem::new(format!("started: {}", trace.started_at)),
            ListItem::new(format!("finished: {}", trace.finished_at)),
            ListItem::new(""),
        ]);
        items.extend(
            trace
                .events
                .iter()
                .take(12)
                .map(|event| ListItem::new(format!("{} {}", event.occurred_at, event.kind))),
        );
    } else {
        items.push(ListItem::new("load with --trace <path>"));
    }
    List::new(items).block(Block::default().title("Trace").borders(Borders::ALL))
}

fn status_panel(state: &TuiState) -> Paragraph<'static> {
    Paragraph::new(vec![
        Line::from(state.status.clone()),
        Line::from(format!("store: {}", state.store_path)),
        Line::from(
            "This TUI reads the same catalog, trace, and file-store contracts as CLI/server.",
        ),
    ])
    .block(Block::default().title("Status").borders(Borders::ALL))
}

fn buffer_to_string(buffer: &Buffer) -> String {
    let area = buffer.area;
    let mut lines = Vec::new();
    for y in area.top()..area.bottom() {
        let mut line = String::new();
        for x in area.left()..area.right() {
            line.push_str(buffer[(x, y)].symbol());
        }
        lines.push(line.trim_end().to_owned());
    }
    lines.join("\n")
}

async fn load_catalog_registry(path: Utf8PathBuf) -> Result<Arc<InMemoryAgentRegistry>> {
    let catalog = read_catalog(path).await?;
    Ok(registry_from_catalog(&catalog))
}

fn registry_from_catalog(catalog: &AgentRuntimeCatalog) -> Arc<InMemoryAgentRegistry> {
    let agents = catalog
        .agents
        .iter()
        .cloned()
        .map(|spec| Arc::new(CatalogDryRunAgent { spec }) as Arc<dyn Agent>)
        .collect::<Vec<_>>();
    InMemoryAgentRegistry::shared(agents)
}

struct EchoAgent {
    spec: AgentSpec,
}

#[async_trait]
impl Agent for EchoAgent {
    fn spec(&self) -> AgentSpec {
        self.spec.clone()
    }

    async fn run(&self, ctx: AgentContext) -> std::result::Result<AgentRunResult, AgentError> {
        ctx.trace
            .emit(TraceEvent::new(
                "echo_agent.input_received",
                ctx.input.clone(),
            ))
            .await?;
        let output = if let Some(tool_input) = ctx.input.get("tool_input") {
            call_traced_tool(&ctx, "echo", tool_input.clone()).await?
        } else {
            ctx.input.clone()
        };
        Ok(AgentRunResult::completed(
            ctx.run_id,
            self.spec.id.clone(),
            ctx.now,
            output,
            Some("echoed input".to_owned()),
        ))
    }
}

struct CatalogDryRunAgent {
    spec: AgentSpec,
}

#[async_trait]
impl Agent for CatalogDryRunAgent {
    fn spec(&self) -> AgentSpec {
        self.spec.clone()
    }

    async fn run(&self, ctx: AgentContext) -> std::result::Result<AgentRunResult, AgentError> {
        ctx.trace
            .emit(TraceEvent::new(
                "catalog_dry_run.agent_selected",
                json!({
                    "agent_id": self.spec.id.clone(),
                    "agent_version": self.spec.version.clone(),
                    "source": "agent_catalog.v1"
                }),
            ))
            .await?;
        let tool_result = match ctx.input.get("tool_call") {
            Some(call) => Some(run_requested_tool_call(&ctx, call).await?),
            None => None,
        };
        let proposal_result = match ctx.input.get("proposal") {
            Some(proposal) => Some(run_requested_proposal(&ctx, &self.spec.id, proposal).await?),
            None => None,
        };
        Ok(AgentRunResult::completed(
            ctx.run_id,
            self.spec.id.clone(),
            ctx.now,
            json!({
                "mode": "catalog_dry_run",
                "agent": self.spec.clone(),
                "input": ctx.input,
                "tool_result": tool_result,
                "proposal": proposal_result,
                "note": "Catalog dry-run validates Rust runtime lifecycle only; Flutter business logic is not executed."
            }),
            Some("catalog dry-run completed".to_owned()),
        ))
    }
}

async fn run_requested_proposal(
    ctx: &AgentContext,
    agent_id: &str,
    proposal: &Value,
) -> Result<ProposalEnvelope, AgentError> {
    let kind = proposal
        .get("kind")
        .and_then(Value::as_str)
        .ok_or_else(|| AgentError::validation("proposal.kind is required"))?;
    let summary = proposal
        .get("summary")
        .and_then(Value::as_str)
        .ok_or_else(|| AgentError::validation("proposal.summary is required"))?;
    let payload = proposal
        .get("payload")
        .cloned()
        .unwrap_or_else(|| json!({}));
    let envelope = ProposalEnvelope::new(
        ctx.run_id.clone(),
        agent_id.to_owned(),
        kind.to_owned(),
        summary.to_owned(),
        payload,
    );
    ctx.services.create_proposal(envelope.clone()).await?;
    Ok(envelope)
}

async fn run_requested_tool_call(ctx: &AgentContext, call: &Value) -> Result<Value, AgentError> {
    let name = call
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| AgentError::validation("tool_call.name is required"))?;
    let input = call.get("input").cloned().unwrap_or_else(|| json!({}));
    ctx.trace
        .emit(TraceEvent::new(
            "catalog_dry_run.tool_call_requested",
            json!({"name": name, "input": input}),
        ))
        .await?;
    call_traced_tool(ctx, name, input).await
}

async fn call_traced_tool(
    ctx: &AgentContext,
    name: &str,
    input: Value,
) -> Result<Value, AgentError> {
    let tool_call_id = ToolCallId::new_v7();
    let input_hash = tool_input_hash(&input);
    let started_at = std::time::Instant::now();
    ctx.trace
        .emit(TraceEvent::new(
            "tool_call_started",
            json!({
                "tool_call_id": tool_call_id.0.clone(),
                "tool_name": name,
                "input_hash": input_hash.clone(),
                "input": input.clone(),
            }),
        ))
        .await?;

    match ctx.services.call_tool(name, input.clone()).await {
        Ok(output) => {
            ctx.trace
                .emit(TraceEvent::new(
                    "tool_call_finished",
                    json!({
                        "tool_call_id": tool_call_id.0.clone(),
                        "tool_name": name,
                        "input_hash": input_hash.clone(),
                        "duration_ms": started_at.elapsed().as_millis(),
                        "status": "completed",
                        "output": output.clone(),
                    }),
                ))
                .await?;
            Ok(output)
        }
        Err(error) => {
            ctx.trace
                .emit(TraceEvent::new(
                    "tool_call_failed",
                    json!({
                        "tool_call_id": tool_call_id.0.clone(),
                        "tool_name": name,
                        "input_hash": input_hash.clone(),
                        "duration_ms": started_at.elapsed().as_millis(),
                        "status": "failed",
                        "error": error.record.clone(),
                    }),
                ))
                .await?;
            Err(AgentError {
                record: error.record,
            })
        }
    }
}

fn tool_input_hash(input: &Value) -> String {
    let bytes = serde_json::to_vec(input).unwrap_or_default();
    format!("blake3:{}", blake3::hash(&bytes).to_hex())
}

#[derive(Debug, Clone, Default)]
struct ToolOverrides {
    mock_tools: BTreeMap<String, Value>,
    source_specs: Vec<ToolSpec>,
    source_tools: BTreeMap<String, ToolSourceRuntime>,
    tool_host: Option<ProcessToolHost>,
}

#[derive(Default)]
struct CliServices {
    state: InMemoryStateStore,
    tools: ToolOverrides,
    proposal_store: Option<Arc<FileProposalStore>>,
}

impl CliServices {
    fn new(tools: ToolOverrides) -> Self {
        Self {
            state: InMemoryStateStore::default(),
            tools,
            proposal_store: None,
        }
    }

    fn with_proposal_store(tools: ToolOverrides, proposal_store: Arc<FileProposalStore>) -> Self {
        Self {
            state: InMemoryStateStore::default(),
            tools,
            proposal_store: Some(proposal_store),
        }
    }
}

#[async_trait]
impl AgentServices for CliServices {
    async fn call_tool(&self, name: &str, input: Value) -> std::result::Result<Value, ToolError> {
        if let Some(output) = self.tools.mock_tools.get(name) {
            return Ok(output.clone());
        }
        if let Some(host) = self.tools.source_tools.get(name) {
            return host.call(name, input).await;
        }
        if let Some(host) = &self.tools.tool_host {
            return host.call(name, input).await;
        }
        match name {
            "echo" => Ok(json!({"echo": input})),
            _ => Err(ToolError {
                record: agent_core::AgentErrorRecord {
                    kind: agent_core::AgentErrorKind::ToolError,
                    code: "unknown_tool".to_owned(),
                    message: format!("unknown tool '{name}'"),
                    retryable: false,
                    details: json!({}),
                },
            }),
        }
    }

    async fn emit_event(
        &self,
        _event: agent_core::AgentEvent,
    ) -> std::result::Result<(), AgentError> {
        Ok(())
    }

    async fn load_state(&self, key: &str) -> std::result::Result<Option<Value>, AgentError> {
        self.state
            .load("cli", key)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))
    }

    async fn save_state(&self, key: &str, value: Value) -> std::result::Result<(), AgentError> {
        self.state
            .save("cli", key, value)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))
    }

    async fn create_proposal(
        &self,
        proposal: ProposalEnvelope,
    ) -> std::result::Result<(), AgentError> {
        let Some(store) = &self.proposal_store else {
            return Err(AgentError::validation(
                "proposal creation requires a configured proposal store",
            ));
        };
        store
            .create_proposal(proposal)
            .await
            .map_err(|e| AgentError::internal(e.to_string()))
    }
}

#[derive(Debug, Clone)]
struct ProcessToolHost {
    command: String,
    args: Vec<String>,
}

#[derive(Debug, Clone)]
struct ToolSourceRuntime {
    protocol: ToolSourceProtocol,
    host: Option<ProcessToolHost>,
    http: Option<HttpToolEndpoint>,
}

impl ToolSourceRuntime {
    fn from_source(source: &ToolSourceDefinition) -> Result<Self> {
        let host = match source.protocol {
            ToolSourceProtocol::JsonlToolCall | ToolSourceProtocol::McpStdio => {
                let command = source.command.as_ref().ok_or_else(|| {
                    miette!(
                        "tool source '{}' command is required for protocol {:?}",
                        source.id,
                        source.protocol
                    )
                })?;
                if command.trim().is_empty() {
                    return Err(miette!(
                        "tool source '{}' command cannot be empty",
                        source.id
                    ));
                }
                Some(ProcessToolHost {
                    command: command.clone(),
                    args: source.args.clone(),
                })
            }
            ToolSourceProtocol::HttpJson => None,
        };
        let http = match source.protocol {
            ToolSourceProtocol::HttpJson => {
                let endpoint = source.endpoint.as_ref().ok_or_else(|| {
                    miette!(
                        "tool source '{}' endpoint is required for http_json",
                        source.id
                    )
                })?;
                validate_http_tool_endpoint(&source.id, endpoint)?;
                Some(HttpToolEndpoint {
                    endpoint: endpoint.clone(),
                    headers: source.headers.clone(),
                })
            }
            ToolSourceProtocol::JsonlToolCall | ToolSourceProtocol::McpStdio => None,
        };
        Ok(Self {
            protocol: source.protocol,
            host,
            http,
        })
    }

    async fn call(&self, name: &str, input: Value) -> std::result::Result<Value, ToolError> {
        match self.protocol {
            ToolSourceProtocol::JsonlToolCall => {
                self.host
                    .as_ref()
                    .ok_or_else(|| {
                        tool_error("tool_source_missing_host", "tool source host missing")
                    })?
                    .call(name, input)
                    .await
            }
            ToolSourceProtocol::McpStdio => {
                self.host
                    .as_ref()
                    .ok_or_else(|| {
                        tool_error("tool_source_missing_host", "tool source host missing")
                    })?
                    .call_mcp_tool(name, input)
                    .await
            }
            ToolSourceProtocol::HttpJson => {
                self.http
                    .as_ref()
                    .ok_or_else(|| {
                        tool_error(
                            "tool_source_missing_http_endpoint",
                            "HTTP tool endpoint missing",
                        )
                    })?
                    .call(name, input)
                    .await
            }
        }
    }
}

#[derive(Debug, Clone)]
struct HttpToolEndpoint {
    endpoint: String,
    headers: BTreeMap<String, String>,
}

impl HttpToolEndpoint {
    async fn call(&self, name: &str, input: Value) -> std::result::Result<Value, ToolError> {
        let client = reqwest::Client::new();
        let payload = json!({
            "protocol_version": PROTOCOL_VERSION,
            "method": "tool.call",
            "tool": name,
            "input": input,
        });
        let mut request = client.post(&self.endpoint).json(&payload);
        for (key, value) in &self.headers {
            request = request.header(key, value);
        }
        let response = request
            .send()
            .await
            .map_err(|e| tool_error("http_tool_request_failed", e.to_string()))?;
        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| tool_error("http_tool_response_read_failed", e.to_string()))?;
        if !status.is_success() {
            return Err(tool_error(
                "http_tool_status_failed",
                format!("HTTP tool endpoint returned {status}: {body}"),
            ));
        }
        let value: Value = serde_json::from_str(&body)
            .map_err(|e| tool_error("http_tool_response_decode_failed", e.to_string()))?;
        if let Some(error) = value.get("error") {
            return Err(tool_error("http_tool_error", error.to_string()));
        }
        Ok(value
            .get("output")
            .or_else(|| value.get("result"))
            .cloned()
            .unwrap_or(value))
    }
}

impl ProcessToolHost {
    async fn call(&self, name: &str, input: Value) -> std::result::Result<Value, ToolError> {
        let mut child = TokioCommand::new(&self.command)
            .args(&self.args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| tool_error("tool_host_spawn_failed", e.to_string()))?;

        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| tool_error("tool_host_stdin_missing", "tool host stdin missing"))?;
        let request = json!({
            "jsonrpc": "2.0",
            "id": "tool_call",
            "method": "tool.call",
            "params": {
                "name": name,
                "input": input,
            }
        });
        let mut encoded = serde_json::to_vec(&request)
            .map_err(|e| tool_error("tool_host_encode_failed", e.to_string()))?;
        encoded.push(b'\n');
        stdin
            .write_all(&encoded)
            .await
            .map_err(|e| tool_error("tool_host_write_failed", e.to_string()))?;
        drop(stdin);

        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| tool_error("tool_host_stdout_missing", "tool host stdout missing"))?;
        let mut lines = BufReader::new(stdout).lines();
        let line = lines
            .next_line()
            .await
            .map_err(|e| tool_error("tool_host_read_failed", e.to_string()))?
            .ok_or_else(|| {
                tool_error("tool_host_empty_response", "tool host returned no response")
            })?;
        let response: Value = serde_json::from_str(&line)
            .map_err(|e| tool_error("tool_host_decode_failed", e.to_string()))?;

        let status = child
            .wait()
            .await
            .map_err(|e| tool_error("tool_host_wait_failed", e.to_string()))?;
        if !status.success() {
            return Err(tool_error(
                "tool_host_failed",
                format!("tool host exited with {status}"),
            ));
        }
        if let Some(error) = response.get("error") {
            return Err(tool_error_from_json("tool_host_error", error));
        }
        response.get("result").cloned().ok_or_else(|| {
            tool_error(
                "tool_host_missing_result",
                "tool host response missing result",
            )
        })
    }

    async fn call_mcp_tool(
        &self,
        name: &str,
        input: Value,
    ) -> std::result::Result<Value, ToolError> {
        let mut child = TokioCommand::new(&self.command)
            .args(&self.args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| tool_error("mcp_spawn_failed", e.to_string()))?;

        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| tool_error("mcp_stdin_missing", "MCP stdin missing"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| tool_error("mcp_stdout_missing", "MCP stdout missing"))?;
        let mut lines = BufReader::new(stdout).lines();

        write_json_line(
            &mut stdin,
            json!({
                "jsonrpc": "2.0",
                "id": "initialize",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "agent-runtime", "version": "0.1.0"}
                }
            }),
            "mcp_initialize_write_failed",
        )
        .await?;
        read_json_rpc_response(&mut lines, "initialize", "mcp_initialize_failed").await?;

        write_json_line(
            &mut stdin,
            json!({
                "jsonrpc": "2.0",
                "id": "tools_call",
                "method": "tools/call",
                "params": {
                    "name": name,
                    "arguments": input,
                }
            }),
            "mcp_tool_call_write_failed",
        )
        .await?;
        let response =
            read_json_rpc_response(&mut lines, "tools_call", "mcp_tool_call_failed").await?;
        drop(stdin);
        let status = child
            .wait()
            .await
            .map_err(|e| tool_error("mcp_wait_failed", e.to_string()))?;
        if !status.success() {
            return Err(tool_error(
                "mcp_failed",
                format!("MCP server exited with {status}"),
            ));
        }
        Ok(response)
    }
}

fn process_tool_host(args: Vec<String>) -> Result<Option<ProcessToolHost>> {
    let Some((command, rest)) = args.split_first() else {
        return Ok(None);
    };
    Ok(Some(ProcessToolHost {
        command: command.clone(),
        args: rest.to_vec(),
    }))
}

async fn write_json_line(
    stdin: &mut tokio::process::ChildStdin,
    value: Value,
    code: &str,
) -> std::result::Result<(), ToolError> {
    let mut encoded =
        serde_json::to_vec(&value).map_err(|e| tool_error("json_encode_failed", e.to_string()))?;
    encoded.push(b'\n');
    stdin
        .write_all(&encoded)
        .await
        .map_err(|e| tool_error(code, e.to_string()))
}

async fn read_json_rpc_response(
    lines: &mut tokio::io::Lines<BufReader<tokio::process::ChildStdout>>,
    id: &str,
    code: &str,
) -> std::result::Result<Value, ToolError> {
    loop {
        let line = lines
            .next_line()
            .await
            .map_err(|e| tool_error(code, e.to_string()))?
            .ok_or_else(|| tool_error(code, "JSON-RPC peer returned no response"))?;
        let response: Value =
            serde_json::from_str(&line).map_err(|e| tool_error(code, e.to_string()))?;
        if response.get("id").and_then(Value::as_str) != Some(id) {
            continue;
        }
        if let Some(error) = response.get("error") {
            return Err(tool_error_from_json(code, error));
        }
        return response
            .get("result")
            .cloned()
            .ok_or_else(|| tool_error(code, "JSON-RPC response missing result"));
    }
}

async fn tool_overrides(
    tool_host: Vec<String>,
    mock_tool: Vec<String>,
    tool_source: Vec<Utf8PathBuf>,
) -> Result<ToolOverrides> {
    let mut mock_tools = BTreeMap::new();
    for spec in mock_tool {
        let (name, raw_value) = spec
            .split_once('=')
            .ok_or_else(|| miette!("mock tool must use NAME=JSON or NAME=@PATH: {spec}"))?;
        let name = name.trim();
        if name.is_empty() {
            return Err(miette!("mock tool name cannot be empty"));
        }
        let value = if let Some(path) = raw_value.strip_prefix('@') {
            if path.is_empty() {
                return Err(miette!("mock tool path cannot be empty for '{name}'"));
            }
            read_json(Utf8PathBuf::from(path)).await?
        } else {
            serde_json::from_str(raw_value)
                .map_err(|e| miette!("failed to parse mock tool '{name}' JSON: {e}"))?
        };
        mock_tools.insert(name.to_owned(), value);
    }

    let mut source_tools = BTreeMap::new();
    let mut source_specs = Vec::new();
    for source in load_tool_sources(tool_source).await? {
        let runtime = ToolSourceRuntime::from_source(&source)?;
        for tool in source.tools.into_iter() {
            if source_tools
                .insert(tool.name.clone(), runtime.clone())
                .is_some()
            {
                return Err(miette!("duplicate tool-source tool '{}'", tool.name));
            }
            source_specs.push(tool);
        }
    }

    Ok(ToolOverrides {
        mock_tools,
        source_specs,
        source_tools,
        tool_host: process_tool_host(tool_host)?,
    })
}

async fn load_tool_source_specs(paths: Vec<Utf8PathBuf>) -> Result<Vec<ToolSpec>> {
    Ok(load_tool_sources(paths)
        .await?
        .into_iter()
        .flat_map(|source| source.tools)
        .collect())
}

async fn load_tool_sources(paths: Vec<Utf8PathBuf>) -> Result<Vec<ToolSourceDefinition>> {
    let mut sources = Vec::new();
    for path in paths {
        let manifest = read_tool_source_manifest(path).await?;
        if let Some(version) = &manifest.version
            && version != "tool_source.v1"
        {
            return Err(miette!(
                "unsupported tool source manifest version '{version}'"
            ));
        }
        for source in manifest.sources {
            if source.id.trim().is_empty() {
                return Err(miette!("tool source id cannot be empty"));
            }
            sources.push(source);
        }
    }
    Ok(sources)
}

fn validate_http_tool_endpoint(source_id: &str, endpoint: &str) -> Result<()> {
    if endpoint.trim().is_empty() {
        return Err(miette!(
            "tool source '{source_id}' endpoint cannot be empty"
        ));
    }
    let url = reqwest::Url::parse(endpoint)
        .map_err(|e| miette!("tool source '{source_id}' endpoint is not a valid URL: {e}"))?;
    match url.scheme() {
        "http" | "https" => Ok(()),
        scheme => Err(miette!(
            "tool source '{source_id}' endpoint must use http or https, got '{scheme}'"
        )),
    }
}

async fn read_tool_source_manifest(path: Utf8PathBuf) -> Result<ToolSourceManifest> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read tool source at {path}: {e}"))?;
    match path.extension() {
        Some("yaml" | "yml") => serde_yaml::from_slice(&bytes)
            .map_err(|e| miette!("failed to parse tool source YAML at {path}: {e}")),
        _ => serde_json::from_slice(&bytes)
            .map_err(|e| miette!("failed to parse tool source JSON at {path}: {e}")),
    }
}

fn source_has_tool(sources: &[ToolSourceDefinition], name: &str) -> bool {
    sources
        .iter()
        .any(|source| source.tools.iter().any(|tool| tool.name == name))
}

fn tool_error(code: &str, message: impl Into<String>) -> ToolError {
    ToolError {
        record: agent_core::AgentErrorRecord {
            kind: agent_core::AgentErrorKind::ToolError,
            code: code.to_owned(),
            message: message.into(),
            retryable: false,
            details: json!({}),
        },
    }
}

fn tool_error_from_json(default_code: &str, error: &Value) -> ToolError {
    let code = error
        .get("code")
        .and_then(Value::as_i64)
        .map(|code| format!("json_rpc_{code}"))
        .unwrap_or_else(|| default_code.to_owned());
    let message = error
        .get("message")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .unwrap_or_else(|| error.to_string());
    let retryable = error
        .get("data")
        .and_then(|data| data.get("retryable"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    ToolError {
        record: agent_core::AgentErrorRecord {
            kind: agent_core::AgentErrorKind::ToolError,
            code,
            message,
            retryable,
            details: error.get("data").cloned().unwrap_or_else(|| json!({})),
        },
    }
}

#[allow(dead_code)]
fn builtin_tools() -> Vec<ToolSpec> {
    vec![ToolSpec {
        name: "echo".to_owned(),
        description: "Return the input unchanged inside an echo envelope.".to_owned(),
        input_schema: json!({"type": "object"}),
        output_schema: Some(json!({"type": "object"})),
        risk: ToolRisk::ReadOnly,
        metadata: json!({}),
    }]
}

async fn read_catalog(path: Utf8PathBuf) -> Result<AgentRuntimeCatalog> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read catalog at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse catalog at {path}: {e}"))
}

async fn serve_http(server: RuntimeServer, host: String, port: u16) -> Result<()> {
    let addr: SocketAddr = format!("{host}:{port}")
        .parse()
        .map_err(|e| miette!("invalid listen address {host}:{port}: {e}"))?;
    let app = Router::new()
        .route("/healthz", get(http_healthz))
        .route("/catalog/summary", get(http_catalog_summary))
        .route("/metrics/summary", get(http_metrics_summary))
        .route("/agents/{agent_id}/run", post(http_agent_run))
        .route("/runs", get(http_runs))
        .route("/runs/{run_id}", get(http_run_inspect))
        .route("/runs/{run_id}/trace", get(http_run_trace))
        .route("/runs/{run_id}/events", get(http_run_events))
        .route("/runs/{run_id}/replay", post(http_run_replay))
        .route("/tools", get(http_tools))
        .route("/tools/{tool_name}/call", post(http_tool_call))
        .route("/proposals", get(http_proposals).post(http_proposal_create))
        .route("/proposals/{proposal_id}", get(http_proposal_inspect))
        .route(
            "/proposals/{proposal_id}/decision",
            post(http_proposal_decide),
        )
        .route("/proposals/{proposal_id}/apply", post(http_proposal_apply))
        .route("/proposals/{proposal_id}/undo", post(http_proposal_undo))
        .route("/sessions", get(http_sessions).post(http_session_create))
        .route("/sessions/{session_id}", get(http_session_show))
        .route("/sessions/{session_id}/fork", post(http_session_fork))
        .with_state(server);
    let listener = TcpListener::bind(addr).await.into_diagnostic()?;
    eprintln!("agent serve listening on http://{addr}");
    axum::serve(listener, app).await.into_diagnostic()
}

async fn http_healthz() -> Json<Value> {
    Json(json!({"status": "ok"}))
}

async fn http_catalog_summary(State(server): State<RuntimeServer>) -> Json<CatalogSummary> {
    Json(CatalogSummary::from_catalog(&server.catalog))
}

async fn http_tools(State(server): State<RuntimeServer>) -> Json<Vec<ToolSpec>> {
    Json(server.catalog.tools.clone())
}

async fn http_metrics_summary(State(server): State<RuntimeServer>) -> Response {
    match server.metrics_summary().await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "metrics_summary_failed",
            err,
        ),
    }
}

async fn http_agent_run(
    State(server): State<RuntimeServer>,
    Path(agent_id): Path<String>,
    Json(params): Json<HttpAgentRunParams>,
) -> Response {
    match server
        .run_agent(agent_id, params.input, params.session_id, params.thread_id)
        .await
    {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::INTERNAL_SERVER_ERROR, "agent_run_failed", err),
    }
}

async fn http_runs(
    State(server): State<RuntimeServer>,
    Query(params): Query<HttpRunListParams>,
) -> Response {
    match server.list_runs(params.agent_id, params.limit).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::INTERNAL_SERVER_ERROR, "run_list_failed", err),
    }
}

async fn http_run_inspect(
    State(server): State<RuntimeServer>,
    Path(run_id): Path<String>,
) -> Response {
    match server.get_run(RunId(run_id)).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::NOT_FOUND, "run_not_found", err),
    }
}

async fn http_run_trace(
    State(server): State<RuntimeServer>,
    Path(run_id): Path<String>,
) -> Response {
    match server.get_run_trace(RunId(run_id)).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::NOT_FOUND, "trace_not_found", err),
    }
}

async fn http_run_events(
    State(server): State<RuntimeServer>,
    Path(run_id): Path<String>,
) -> Response {
    match server.get_run_trace(RunId(run_id)).await {
        Ok(trace) => {
            let events = event_records_from_trace(&trace);
            let stream = stream::iter(events.into_iter().map(|event| {
                let kind = event
                    .get("kind")
                    .and_then(Value::as_str)
                    .unwrap_or("trace_event")
                    .to_owned();
                let data = serde_json::to_string(&event).unwrap_or_else(|_| "{}".to_owned());
                Ok::<_, Infallible>(Event::default().event(kind).data(data))
            }));
            Sse::new(stream).into_response()
        }
        Err(err) => http_error(StatusCode::NOT_FOUND, "trace_not_found", err),
    }
}

async fn http_run_replay(
    State(server): State<RuntimeServer>,
    Path(run_id): Path<String>,
) -> Response {
    match server.replay_run(RunId(run_id)).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::INTERNAL_SERVER_ERROR, "run_replay_failed", err),
    }
}

async fn http_tool_call(
    State(server): State<RuntimeServer>,
    Path(tool_name): Path<String>,
    Json(params): Json<HttpToolCallParams>,
) -> Response {
    match server.call_tool(tool_name, params.input).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::INTERNAL_SERVER_ERROR, "tool_call_failed", err),
    }
}

async fn http_proposal_create(
    State(server): State<RuntimeServer>,
    Json(params): Json<HttpProposalCreateParams>,
) -> Response {
    match server.create_proposal(params).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "proposal_create_failed",
            err,
        ),
    }
}

async fn http_proposals(
    State(server): State<RuntimeServer>,
    Query(params): Query<HttpProposalListParams>,
) -> Response {
    match server.list_proposals(params.run_id).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "proposal_list_failed",
            err,
        ),
    }
}

async fn http_proposal_inspect(
    State(server): State<RuntimeServer>,
    Path(proposal_id): Path<String>,
) -> Response {
    match server.get_proposal(ProposalId(proposal_id)).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::NOT_FOUND, "proposal_not_found", err),
    }
}

async fn http_proposal_decide(
    State(server): State<RuntimeServer>,
    Path(proposal_id): Path<String>,
    Json(params): Json<HttpProposalDecisionParams>,
) -> Response {
    match server
        .decide_proposal(ProposalId(proposal_id), params)
        .await
    {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "proposal_decide_failed",
            err,
        ),
    }
}

async fn http_proposal_apply(
    State(server): State<RuntimeServer>,
    Path(proposal_id): Path<String>,
) -> Response {
    match server.apply_proposal(ProposalId(proposal_id)).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "proposal_apply_failed",
            err,
        ),
    }
}

async fn http_proposal_undo(
    State(server): State<RuntimeServer>,
    Path(proposal_id): Path<String>,
) -> Response {
    match server.undo_proposal(ProposalId(proposal_id)).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "proposal_undo_failed",
            err,
        ),
    }
}

async fn http_session_create(
    State(server): State<RuntimeServer>,
    Json(params): Json<HttpSessionCreateParams>,
) -> Response {
    match server.create_session(params).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "session_create_failed",
            err,
        ),
    }
}

async fn http_sessions(State(server): State<RuntimeServer>) -> Response {
    match server.list_sessions().await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "session_list_failed",
            err,
        ),
    }
}

async fn http_session_show(
    State(server): State<RuntimeServer>,
    Path(session_id): Path<String>,
) -> Response {
    match server.show_session(SessionId(session_id)).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(StatusCode::NOT_FOUND, "session_not_found", err),
    }
}

async fn http_session_fork(
    State(server): State<RuntimeServer>,
    Path(session_id): Path<String>,
    Json(params): Json<HttpThreadForkParams>,
) -> Response {
    match server.fork_thread(SessionId(session_id), params).await {
        Ok(response) => Json(response).into_response(),
        Err(err) => http_error(
            StatusCode::INTERNAL_SERVER_ERROR,
            "session_fork_failed",
            err,
        ),
    }
}

fn http_error(status: StatusCode, code: &str, err: impl std::fmt::Display) -> Response {
    (
        status,
        Json(HttpErrorBody {
            code: code.to_owned(),
            message: err.to_string(),
        }),
    )
        .into_response()
}

async fn serve_stdio(server: RuntimeServer) -> Result<()> {
    let stdin = BufReader::new(tokio::io::stdin());
    let mut lines = stdin.lines();
    let mut stdout = tokio::io::stdout();

    while let Some(line) = lines.next_line().await.into_diagnostic()? {
        if line.trim().is_empty() {
            continue;
        }
        let response = handle_stdio_line(&server, &line).await;
        let encoded = serde_json::to_vec(&response).into_diagnostic()?;
        stdout.write_all(&encoded).await.into_diagnostic()?;
        stdout.write_all(b"\n").await.into_diagnostic()?;
        stdout.flush().await.into_diagnostic()?;
    }
    Ok(())
}

async fn run_dev_tool_host() -> Result<()> {
    let stdin = BufReader::new(tokio::io::stdin());
    let mut lines = stdin.lines();
    let mut stdout = tokio::io::stdout();
    while let Some(line) = lines.next_line().await.into_diagnostic()? {
        if line.trim().is_empty() {
            continue;
        }
        let response = handle_dev_tool_host_line(&line);
        let encoded = serde_json::to_vec(&response).into_diagnostic()?;
        stdout.write_all(&encoded).await.into_diagnostic()?;
        stdout.write_all(b"\n").await.into_diagnostic()?;
        stdout.flush().await.into_diagnostic()?;
    }
    Ok(())
}

async fn run_dev_mcp_server() -> Result<()> {
    let stdin = BufReader::new(tokio::io::stdin());
    let mut lines = stdin.lines();
    let mut stdout = tokio::io::stdout();
    while let Some(line) = lines.next_line().await.into_diagnostic()? {
        if line.trim().is_empty() {
            continue;
        }
        let response = handle_dev_mcp_line(&line);
        let encoded = serde_json::to_vec(&response).into_diagnostic()?;
        stdout.write_all(&encoded).await.into_diagnostic()?;
        stdout.write_all(b"\n").await.into_diagnostic()?;
        stdout.flush().await.into_diagnostic()?;
    }
    Ok(())
}

async fn run_dev_score_hook() -> Result<()> {
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

fn handle_dev_mcp_line(line: &str) -> StdioResponse {
    let request = match serde_json::from_str::<StdioRequest>(line) {
        Ok(request) => request,
        Err(err) => return stdio_error(None, -32700, format!("parse error: {err}")),
    };
    match request.method.as_str() {
        "initialize" => stdio_result(
            request.id,
            json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "dev-mcp-server", "version": "0.1.0"}
            }),
        ),
        "tools/list" => stdio_result(
            request.id,
            json!({
                "tools": [{
                    "name": "mcp_echo",
                    "description": "Echo through a dev MCP server.",
                    "inputSchema": {"type": "object"}
                }]
            }),
        ),
        "tools/call" => {
            let name = request
                .params
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or_default();
            let arguments = request
                .params
                .get("arguments")
                .cloned()
                .unwrap_or_else(|| json!({}));
            stdio_result(
                request.id,
                json!({
                    "content": [{"type": "text", "text": serde_json::to_string(&json!({
                        "host": "dev-mcp-server",
                        "tool": name,
                        "input": arguments,
                    })).unwrap_or_default()}],
                    "structuredContent": {
                        "host": "dev-mcp-server",
                        "tool": name,
                        "input": arguments,
                    },
                    "isError": false
                }),
            )
        }
        _ => stdio_error(request.id, -32601, "method not found"),
    }
}

fn handle_dev_tool_host_line(line: &str) -> StdioResponse {
    let request = match serde_json::from_str::<ToolHostRequest>(line) {
        Ok(request) => request,
        Err(err) => return stdio_error(None, -32700, format!("parse error: {err}")),
    };
    if request.method != "tool.call" {
        return stdio_error(request.id, -32601, "method not found");
    }
    let params = match serde_json::from_value::<ToolCallParams>(request.params) {
        Ok(params) => params,
        Err(err) => return stdio_error(request.id, -32602, format!("invalid params: {err}")),
    };
    if let Some(path) = params.input.get("fail_once_path").and_then(Value::as_str)
        && !std::path::Path::new(path).exists()
    {
        if let Err(err) = std::fs::write(path, b"failed-once") {
            return stdio_error(
                request.id,
                -32001,
                format!("failed to write fail_once_path: {err}"),
            );
        }
        return stdio_error_with_data(
            request.id,
            -32000,
            "dev tool host retryable failure",
            json!({"retryable": true, "fail_once_path": path}),
        );
    }
    stdio_result(
        request.id,
        json!({
            "host": "dev-tool-host",
            "tool": params.name,
            "input": params.input,
        }),
    )
}

async fn handle_stdio_line(server: &RuntimeServer, line: &str) -> StdioResponse {
    let request = match serde_json::from_str::<StdioRequest>(line) {
        Ok(request) => request,
        Err(err) => {
            return stdio_error(None, -32700, format!("parse error: {err}"));
        }
    };

    if request.jsonrpc.as_deref().is_some_and(|v| v != "2.0") {
        return stdio_error(request.id, -32600, "invalid jsonrpc version");
    }

    match request.method.as_str() {
        "catalog.summary" => stdio_result(
            request.id,
            serde_json::to_value(CatalogSummary::from_catalog(&server.catalog))
                .unwrap_or_else(|err| json!({"serialization_error": err.to_string()})),
        ),
        "agent.run" => {
            let params = match serde_json::from_value::<AgentRunParams>(request.params) {
                Ok(params) => params,
                Err(err) => {
                    return stdio_error(request.id, -32602, format!("invalid params: {err}"));
                }
            };
            let outcome = server
                .run_agent(
                    params.agent_id,
                    params.input,
                    params.session_id,
                    params.thread_id,
                )
                .await;
            match outcome {
                Ok(outcome) => stdio_result(
                    request.id,
                    json!({
                        "result": outcome.result,
                        "trace": outcome.trace,
                    }),
                ),
                Err(err) => stdio_error(request.id, -32000, err.to_string()),
            }
        }
        _ => stdio_error(request.id, -32601, "method not found"),
    }
}

fn stdio_result(id: Option<Value>, result: Value) -> StdioResponse {
    StdioResponse {
        jsonrpc: "2.0",
        id,
        result: Some(result),
        error: None,
    }
}

fn stdio_error(id: Option<Value>, code: i32, message: impl Into<String>) -> StdioResponse {
    StdioResponse {
        jsonrpc: "2.0",
        id,
        result: None,
        error: Some(StdioError {
            code,
            message: message.into(),
            data: None,
        }),
    }
}

fn stdio_error_with_data(
    id: Option<Value>,
    code: i32,
    message: impl Into<String>,
    data: Value,
) -> StdioResponse {
    StdioResponse {
        jsonrpc: "2.0",
        id,
        result: None,
        error: Some(StdioError {
            code,
            message: message.into(),
            data: Some(data),
        }),
    }
}

async fn read_json(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
}

async fn read_trace(path: Utf8PathBuf) -> Result<agent_core::AgentTrace> {
    let value = read_json(path.clone()).await?;
    serde_json::from_value(value).map_err(|e| miette!("failed to parse trace at {path}: {e}"))
}

async fn validate_json(
    schema_path: Utf8PathBuf,
    instance_path: Utf8PathBuf,
) -> Result<ValidationReport> {
    let schema = read_json(schema_path.clone()).await?;
    let instance = read_json(instance_path.clone()).await?;
    let validator = jsonschema::validator_for(&schema)
        .map_err(|e| miette!("failed to compile JSON schema: {e}"))?;
    let errors = validator
        .iter_errors(&instance)
        .map(|error| error.to_string())
        .collect::<Vec<_>>();

    Ok(ValidationReport {
        schema: schema_path.to_string(),
        instance: instance_path.to_string(),
        valid: errors.is_empty(),
        errors,
    })
}

async fn read_command_input(
    input: Option<Utf8PathBuf>,
    input_json: Option<String>,
) -> Result<Value> {
    match (input, input_json) {
        (Some(_), Some(_)) => Err(miette!("use only one of --input or --input-json")),
        (Some(path), None) => read_json(path).await,
        (None, Some(value)) => serde_json::from_str(&value)
            .map_err(|e| miette!("failed to parse --input-json as JSON: {e}")),
        (None, None) => Ok(json!({})),
    }
}

fn ensure_catalog_has_tool(catalog: &AgentRuntimeCatalog, name: &str) -> Result<()> {
    if catalog.tools.iter().any(|tool| tool.name == name) {
        return Ok(());
    }
    Err(miette!(
        "tool '{name}' is not present in the active catalog"
    ))
}

fn parse_approval_decision(value: &str) -> Result<ApprovalDecisionKind> {
    match value {
        "approve" | "approved" => Ok(ApprovalDecisionKind::Approve),
        "deny" | "denied" => Ok(ApprovalDecisionKind::Deny),
        other => Err(miette!(
            "unsupported approval decision '{other}', expected approve or deny"
        )),
    }
}

fn print_json(value: &impl serde::Serialize) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(value).into_diagnostic()?);
    Ok(())
}

async fn write_json(path: Utf8PathBuf, value: &impl serde::Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    let bytes = serde_json::to_vec_pretty(value).into_diagnostic()?;
    fs_err::tokio::write(path, bytes).await.into_diagnostic()
}

async fn write_yaml(path: Utf8PathBuf, value: &impl serde::Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    let text = serde_yaml::to_string(value).into_diagnostic()?;
    fs_err::tokio::write(path, text).await.into_diagnostic()
}

async fn write_text(path: Utf8PathBuf, text: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    fs_err::tokio::write(path, text).await.into_diagnostic()
}

fn default_runner() -> String {
    "echo".to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_markdown_has_frontmatter_and_captured_input() {
        let frontmatter = CommandFrontmatter {
            description: Some("Replay review".to_owned()),
            agent: "execution_review".to_owned(),
            catalog: Some("fixtures/agent-runtime/catalog.valid.json".to_owned()),
            registry: None,
            source_run_id: Some("run_01".to_owned()),
            source_run_status: Some(agent_core::AgentRunStatus::Completed),
            created_at: Some("2026-06-28T00:00:00Z".to_owned()),
        };

        let markdown = render_command_markdown(&frontmatter, &json!({"message": "hello"})).unwrap();

        assert!(markdown.starts_with("---\n"));
        assert!(markdown.contains("agent: execution_review"));
        assert!(markdown.contains("source_run_id: run_01"));
        assert!(markdown.contains("```json\n{\n  \"message\": \"hello\"\n}\n```"));
    }

    #[test]
    fn command_template_parses_frontmatter_and_json_fence() {
        let markdown = r#"---
agent: echo_agent
registry: examples/agent-runtime/agents.yaml
---

```json
{"message":"hello"}
```
"#;

        let template =
            parse_command_template(markdown, Utf8Path::new(".agent-runtime/commands/echo.md"))
                .unwrap();

        assert_eq!(template.frontmatter.agent, "echo_agent");
        assert_eq!(
            template.frontmatter.registry.as_deref(),
            Some("examples/agent-runtime/agents.yaml")
        );
        assert_eq!(template.input, json!({"message": "hello"}));
    }
}
