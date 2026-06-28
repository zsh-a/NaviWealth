use std::{collections::BTreeMap, process::Stdio, sync::Arc};

use agent_core::{
    AgentError, AgentProposalStore, AgentServices, AgentStateStore, PROTOCOL_VERSION,
    ProposalEnvelope, ToolError, ToolRisk, ToolSpec,
};
use agent_store::{FileProposalStore, InMemoryStateStore};
use async_trait::async_trait;
use camino::Utf8PathBuf;
use miette::{Result, miette};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command as TokioCommand;

#[derive(Debug, Clone, Default)]
pub(crate) struct ToolOverrides {
    pub(crate) mock_tools: BTreeMap<String, Value>,
    pub(crate) source_specs: Vec<ToolSpec>,
    pub(crate) source_tools: BTreeMap<String, ToolSourceRuntime>,
    pub(crate) tool_host: Option<ProcessToolHost>,
}

#[derive(Default)]
pub(crate) struct CliServices {
    state: InMemoryStateStore,
    pub(crate) tools: ToolOverrides,
    proposal_store: Option<Arc<FileProposalStore>>,
}

impl CliServices {
    pub(crate) fn new(tools: ToolOverrides) -> Self {
        Self {
            state: InMemoryStateStore::default(),
            tools,
            proposal_store: None,
        }
    }

    pub(crate) fn with_proposal_store(
        tools: ToolOverrides,
        proposal_store: Arc<FileProposalStore>,
    ) -> Self {
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

#[derive(Debug, Clone, Deserialize)]
struct ToolSourceManifest {
    #[serde(default)]
    version: Option<String>,
    #[serde(default)]
    sources: Vec<ToolSourceDefinition>,
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct ToolSourceDefinition {
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

#[derive(Debug, Clone)]
pub(crate) struct ProcessToolHost {
    command: String,
    args: Vec<String>,
}

#[derive(Debug, Clone)]
pub(crate) struct ToolSourceRuntime {
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

    pub(crate) async fn call(
        &self,
        name: &str,
        input: Value,
    ) -> std::result::Result<Value, ToolError> {
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
    pub(crate) async fn call(
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

pub(crate) async fn tool_overrides(
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
            read_json_file(Utf8PathBuf::from(path)).await?
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

pub(crate) async fn load_tool_source_specs(paths: Vec<Utf8PathBuf>) -> Result<Vec<ToolSpec>> {
    Ok(load_tool_sources(paths)
        .await?
        .into_iter()
        .flat_map(|source| source.tools)
        .collect())
}

pub(crate) async fn load_tool_sources(
    paths: Vec<Utf8PathBuf>,
) -> Result<Vec<ToolSourceDefinition>> {
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

pub(crate) fn source_has_tool(sources: &[ToolSourceDefinition], name: &str) -> bool {
    sources
        .iter()
        .any(|source| source.tools.iter().any(|tool| tool.name == name))
}

#[allow(dead_code)]
pub(crate) fn builtin_tools() -> Vec<ToolSpec> {
    vec![ToolSpec {
        name: "echo".to_owned(),
        description: "Return the input unchanged inside an echo envelope.".to_owned(),
        input_schema: json!({"type": "object"}),
        output_schema: Some(json!({"type": "object"})),
        risk: ToolRisk::ReadOnly,
        metadata: json!({}),
    }]
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

async fn read_json_file(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
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
