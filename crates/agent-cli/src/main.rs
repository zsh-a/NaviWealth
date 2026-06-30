use std::time::Duration;

use agent_core::{AgentRunStore, RunId};
use agent_runtime::{ExecutionPolicy, recover_stale_runs};
use agent_store::{FileProposalStore, FileRunStore};
use camino::Utf8PathBuf;
use clap::{Parser, Subcommand};
use miette::{IntoDiagnostic, Result, miette};
use serde::Serialize;

mod catalog;
mod chat;
mod cli_input;
mod commands;
mod config;
mod debug_bundle;
mod dev_stdio;
mod eval;
mod metrics;
mod proposal;
mod registry;
mod replay;
mod runtime_server;
mod server;
mod session;
mod stdio_protocol;
mod tools;
mod trace_store;
mod tui;

use commands::catalog::{CatalogCommand, run_catalog_command};
use commands::llm::{LlmCompleteOptions, run_llm_complete};
use commands::proposal::{ProposalCommand, run_proposal_command};
use commands::run::{RunCliOptions, TickCliOptions, run_agent_once, tick_agents};
use commands::session::{SessionCommand, run_session_command};
use commands::tool::{ToolCommand, run_tool_command};
use commands::workflow::{CommandRunOptions, create_command_from_run, run_command_template};
use config::{
    configured_path, configured_paths, configured_string, configured_u16, configured_u32,
    configured_u64, load_agent_config,
};
use debug_bundle::export_debug_bundle;
use dev_stdio::{run_dev_mcp_server, run_dev_tool_host};
use eval::{create_eval_from_run, run_dev_score_hook, run_eval_path};
use metrics::build_metrics_summary;
use registry::load_registry;
use replay::{ReplayMode, ReplayTraceOptions, replay_trace};
use runtime_server::RuntimeServer;
use server::{serve_http, serve_stdio};
use tools::tool_overrides;
use trace_store::read_json;
use tui::{TuiOptions, run_tui};

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
        #[arg(long, default_value = DEFAULT_REGISTRY)]
        registry: Utf8PathBuf,
        #[arg(long)]
        catalog: Option<Utf8PathBuf>,
        #[arg(long)]
        trace: Option<Utf8PathBuf>,
        #[arg(long, default_value = DEFAULT_STORE)]
        store: Utf8PathBuf,
        #[arg(long, num_args = 1.., value_name = "COMMAND")]
        tool_host: Vec<String>,
        #[arg(long, value_name = "NAME=JSON_OR_@PATH")]
        mock_tool: Vec<String>,
        #[arg(long)]
        tool_source: Vec<Utf8PathBuf>,
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
        #[arg(long, default_value = "2023-06-01")]
        anthropic_version: String,
        #[arg(long)]
        temperature: Option<f32>,
        #[arg(long)]
        max_output_tokens: Option<u32>,
        #[arg(long, default_value_t = 4)]
        max_tool_rounds: u32,
        #[arg(long, default_value_t = DEFAULT_TIMEOUT_SECONDS)]
        timeout_seconds: u64,
        #[arg(long, default_value_t = 0)]
        max_retries: u32,
        #[arg(long, default_value_t = 0)]
        retry_backoff_ms: u64,
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
            run_agent_once(RunCliOptions {
                agent_id,
                registry,
                catalog,
                tool_overrides: tool_overrides(tool_host, mock_tool, tool_source).await?,
                input,
                trace_out,
                session,
                thread,
                store,
                timeout_seconds,
                max_retries,
                retry_backoff_ms,
            })
            .await?;
        }
        Command::Tick { registry, store } => {
            let registry =
                configured_path(registry, DEFAULT_REGISTRY, config.runtime.registry.as_ref());
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            tick_agents(TickCliOptions { registry, store }).await?;
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
        Command::Tool { command } => {
            run_tool_command(command).await?;
        }
        Command::Proposal { command } => {
            run_proposal_command(command).await?;
        }
        Command::Session { command } => {
            run_session_command(command).await?;
        }
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
                run_llm_complete(LlmCompleteOptions {
                    prompt,
                    provider,
                    model,
                    mock_response,
                    api_base_url,
                    api_key_env,
                    temperature,
                    max_output_tokens,
                    anthropic_version,
                })
                .await?;
            }
        },
        Command::Catalog { command } => {
            run_catalog_command(command).await?;
        }
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
            registry,
            catalog,
            trace,
            store,
            tool_host,
            mock_tool,
            tool_source,
            provider,
            model,
            mock_response,
            api_base_url,
            api_key_env,
            anthropic_version,
            temperature,
            max_output_tokens,
            max_tool_rounds,
            timeout_seconds,
            max_retries,
            retry_backoff_ms,
            once,
        } => {
            let catalog = catalog.or_else(|| config.runtime.catalog.clone());
            let registry =
                configured_path(registry, DEFAULT_REGISTRY, config.runtime.registry.as_ref());
            let store = configured_path(store, DEFAULT_STORE, config.runtime.store.as_ref());
            let tool_source = configured_paths(tool_source, config.runtime.tool_sources.as_ref());
            let timeout_seconds = configured_u64(
                timeout_seconds,
                DEFAULT_TIMEOUT_SECONDS,
                config.runtime.timeout_seconds,
            );
            let max_retries = configured_u32(max_retries, 0, config.runtime.max_retries);
            let retry_backoff_ms =
                configured_u64(retry_backoff_ms, 0, config.runtime.retry_backoff_ms);
            run_tui(TuiOptions {
                catalog_path: catalog,
                trace_path: trace,
                store_path: store,
                registry_path: registry,
                tool_overrides: tool_overrides(tool_host, mock_tool, tool_source).await?,
                chat: chat::ChatLlmOptions {
                    provider,
                    model,
                    mock_response,
                    api_base_url,
                    api_key_env,
                    anthropic_version,
                    temperature,
                    max_output_tokens,
                    max_tool_rounds,
                },
                timeout_seconds,
                max_retries,
                retry_backoff_ms,
                once,
            })
            .await?;
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

pub(crate) fn print_json(value: &impl serde::Serialize) -> Result<()> {
    println!("{}", serde_json::to_string_pretty(value).into_diagnostic()?);
    Ok(())
}
