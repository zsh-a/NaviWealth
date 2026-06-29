use std::{sync::Arc, time::Duration};

use agent_core::{
    AgentProposalStore, AgentRunRecord, AgentRunResult, AgentRunStore, AgentRuntimeCatalog,
    AgentServices, AgentSessionStore, ApprovalDecision, ApprovalDecisionKind, PROTOCOL_VERSION,
    ProposalEnvelope, ProposalId, ProposalStatus, RunId, RunRequest, SessionId, SessionRecord,
    ThreadId, ThreadRecord,
};
use agent_llm::{
    AnthropicProvider, LlmProvider, LlmRequest, MockLlmProvider, OllamaProvider,
    OpenAiCompatibleProvider, user_message,
};
use agent_runtime::{AgentRunner, ExecutionPolicy, recover_stale_runs};
use agent_store::{FileProposalStore, FileRunStore, FileSessionStore};
use camino::{Utf8Path, Utf8PathBuf};
use clap::{Parser, Subcommand};
use miette::{IntoDiagnostic, Result, miette};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

mod catalog;
mod command_template;
mod config;
mod debug_bundle;
mod eval;
mod metrics;
mod proposal;
mod registry;
mod replay;
mod server;
mod session;
mod tools;
mod tui;

use catalog::{
    CatalogSummary, build_prompt_manifest, load_catalog_registry, read_catalog,
    registry_from_catalog,
};
use command_template::{CommandRunOptions, create_command_from_run, run_command_template};
use config::{
    configured_path, configured_paths, configured_string, configured_u16, configured_u32,
    configured_u64, execution_policy, load_agent_config,
};
use debug_bundle::export_debug_bundle;
use eval::{create_eval_from_run, run_dev_score_hook, run_eval_path};
use metrics::{RuntimeMetricsSummary, build_metrics_summary};
use proposal::{
    ProposalAction, ProposalActionResponse, ProposalDecisionResponse,
    append_proposal_action_trace_event, append_proposal_created_trace_event,
    append_proposal_decision_trace_event, execute_proposal_action_with_store,
    parse_approval_decision, proposal_action_tool,
};
use registry::load_registry;
use replay::{
    ReplayExecutionReport, ReplayMode, ReplayTraceOptions, replay_source_trace, replay_trace,
};
use server::{serve_http, serve_stdio};
use session::{
    HttpSessionCreateParams, HttpSessionCreateResponse, HttpThreadForkParams, SessionShowReport,
    ThreadForkReport, ThreadWithSteps, create_session, fork_thread, record_session_step,
    run_metadata, show_session,
};
use tools::{
    CliServices, ToolOverrides, builtin_tools, load_tool_source_specs, load_tool_sources,
    source_has_tool, tool_overrides,
};
use tui::run_tui;

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
struct ValidationReport {
    schema: String,
    instance: String,
    valid: bool,
    errors: Vec<String>,
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
struct ToolCallResponse {
    tool: String,
    output: Value,
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

pub(crate) async fn write_store_trace(
    store: &Utf8Path,
    trace: &agent_core::AgentTrace,
) -> Result<()> {
    write_json(store_trace_path(store, &trace.run_id), trace).await
}

pub(crate) async fn read_store_trace(store: &Utf8Path, run_id: &RunId) -> Result<Option<Value>> {
    let path = store_trace_path(store, run_id);
    if !path.exists() {
        return Ok(None);
    }
    read_json(path).await.map(Some)
}

fn store_trace_path(store: &Utf8Path, run_id: &RunId) -> Utf8PathBuf {
    store
        .join("traces")
        .join(format!("{}.trace.json", run_id.0))
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

pub(crate) async fn read_json(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
}

pub(crate) async fn read_trace(path: Utf8PathBuf) -> Result<agent_core::AgentTrace> {
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

pub(crate) fn print_json(value: &impl serde::Serialize) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(value).into_diagnostic()?);
    Ok(())
}

pub(crate) async fn write_json(path: Utf8PathBuf, value: &impl serde::Serialize) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    let bytes = serde_json::to_vec_pretty(value).into_diagnostic()?;
    fs_err::tokio::write(path, bytes).await.into_diagnostic()
}

pub(crate) async fn write_text(path: Utf8PathBuf, text: &str) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs_err::tokio::create_dir_all(parent)
            .await
            .into_diagnostic()?;
    }
    fs_err::tokio::write(path, text).await.into_diagnostic()
}
