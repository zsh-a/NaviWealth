use std::{convert::Infallible, net::SocketAddr};

use agent_core::{ProposalId, RunId, SessionId, ToolSpec};
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
use futures::stream;
use miette::{IntoDiagnostic, Result, miette};
use serde::Serialize;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;

use crate::{
    catalog::CatalogSummary,
    metrics::event_records_from_trace,
    runtime_server::{
        AgentRunParams, HttpAgentRunParams, HttpProposalCreateParams, HttpProposalDecisionParams,
        HttpProposalListParams, HttpRunListParams, HttpToolCallParams, RuntimeServer,
    },
    session::{HttpSessionCreateParams, HttpThreadForkParams},
    stdio_protocol::{StdioRequest, StdioResponse, stdio_error, stdio_result},
};

#[derive(Debug, Serialize)]
struct HttpErrorBody {
    code: String,
    message: String,
}

pub(crate) async fn serve_http(server: RuntimeServer, host: String, port: u16) -> Result<()> {
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

pub(crate) async fn serve_stdio(server: RuntimeServer) -> Result<()> {
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
