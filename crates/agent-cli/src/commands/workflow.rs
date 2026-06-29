use std::sync::Arc;

use agent_core::{AgentRunRecord, AgentRunStore, PROTOCOL_VERSION, RunId, RunRequest, TriggerKind};
use agent_runtime::AgentRunner;
use agent_store::{FileProposalStore, FileRunStore};
use camino::{Utf8Path, Utf8PathBuf};
use miette::{IntoDiagnostic, Result, miette};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use time::format_description::well_known::Rfc3339;

use crate::catalog::load_catalog_registry;
use crate::config::execution_policy;
use crate::registry::load_registry;
use crate::tools::{CliServices, tool_overrides};
use crate::trace_store::{write_json, write_store_trace, write_text};

#[derive(Debug, Serialize)]
pub(crate) struct CommandCreateReport {
    id: String,
    run_id: String,
    agent_id: String,
    command_file: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct CommandFrontmatter {
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

pub(crate) struct CommandRunOptions {
    pub(crate) command_file: Utf8PathBuf,
    pub(crate) catalog: Option<Utf8PathBuf>,
    pub(crate) registry: Option<Utf8PathBuf>,
    pub(crate) store: Utf8PathBuf,
    pub(crate) tool_host: Vec<String>,
    pub(crate) mock_tool: Vec<String>,
    pub(crate) tool_source: Vec<Utf8PathBuf>,
    pub(crate) trace_out: Option<Utf8PathBuf>,
    pub(crate) timeout_seconds: u64,
    pub(crate) max_retries: u32,
    pub(crate) retry_backoff_ms: u64,
}

#[derive(Debug, Serialize)]
pub(crate) struct CommandRunReport {
    command_file: String,
    agent_id: String,
    result: agent_core::AgentRunResult,
    trace: agent_core::AgentTrace,
}

#[derive(Debug)]
enum CommandRegistryPath {
    Catalog(Utf8PathBuf),
    Registry(Utf8PathBuf),
}

pub(crate) async fn create_command_from_run(
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

pub(crate) async fn run_command_template(options: CommandRunOptions) -> Result<CommandRunReport> {
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

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
