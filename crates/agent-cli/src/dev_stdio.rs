use miette::{IntoDiagnostic, Result};
use serde::Deserialize;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use crate::stdio_protocol::{
    StdioRequest, StdioResponse, stdio_error, stdio_error_with_data, stdio_result,
};

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

pub(crate) async fn run_dev_tool_host() -> Result<()> {
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

pub(crate) async fn run_dev_mcp_server() -> Result<()> {
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
