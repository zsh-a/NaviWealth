use std::collections::VecDeque;

use agent_core::AgentRunRecord;
use agent_llm::LlmMessage;
use camino::{Utf8Path, Utf8PathBuf};
use miette::{IntoDiagnostic, Result, miette};
use serde_json::Value;

use crate::{
    catalog::{CatalogSummary, read_catalog},
    chat::ChatLlmOptions,
    tools::ToolOverrides,
};

const MAX_LOG_LINES: usize = 80;

#[derive(Debug, Clone)]
pub(crate) struct TuiOptions {
    pub(crate) catalog_path: Option<Utf8PathBuf>,
    pub(crate) trace_path: Option<Utf8PathBuf>,
    pub(crate) store_path: Utf8PathBuf,
    pub(crate) registry_path: Utf8PathBuf,
    pub(crate) tool_overrides: ToolOverrides,
    pub(crate) chat: ChatLlmOptions,
    pub(crate) timeout_seconds: u64,
    pub(crate) max_retries: u32,
    pub(crate) retry_backoff_ms: u64,
    pub(crate) once: bool,
}

pub(super) struct TuiState {
    pub(super) options: TuiOptions,
    pub(super) catalog_summary: Option<CatalogSummary>,
    pub(super) trace: Option<agent_core::AgentTrace>,
    pub(super) trace_label: Option<String>,
    pub(super) recent_runs: Vec<AgentRunRecord>,
    pub(super) status: String,
    pub(super) input_mode: bool,
    pub(super) command_input: String,
    pub(super) log_lines: VecDeque<String>,
    pub(super) chat_messages: Vec<LlmMessage>,
}

impl TuiState {
    pub(super) async fn load(options: TuiOptions) -> Result<Self> {
        let catalog_summary = load_catalog_summary(options.catalog_path.as_ref()).await?;
        let trace = load_trace(options.trace_path.as_ref()).await?;
        let trace_label = options.trace_path.as_ref().map(ToString::to_string);
        let recent_runs = read_recent_runs(&options.store_path).await?;
        let status = status_line(&catalog_summary, &trace, recent_runs.len());
        let mut state = Self {
            options,
            catalog_summary,
            trace,
            trace_label,
            recent_runs,
            status,
            input_mode: true,
            command_input: String::new(),
            log_lines: VecDeque::new(),
            chat_messages: Vec::new(),
        };
        state.push_log("Ready. Type a message and press Enter. Use /help for commands.");
        Ok(state)
    }

    pub(super) async fn refresh(&mut self) -> Result<()> {
        self.catalog_summary = load_catalog_summary(self.options.catalog_path.as_ref()).await?;
        if let Some(path) = &self.options.trace_path {
            self.trace = Some(read_trace(path.clone()).await?);
            self.trace_label = Some(path.to_string());
        }
        self.refresh_runs().await?;
        Ok(())
    }

    pub(super) async fn refresh_runs(&mut self) -> Result<()> {
        self.recent_runs = read_recent_runs(&self.options.store_path).await?;
        self.status = status_line(&self.catalog_summary, &self.trace, self.recent_runs.len());
        Ok(())
    }

    pub(super) fn set_trace(&mut self, label: impl Into<String>, trace: agent_core::AgentTrace) {
        self.trace = Some(trace);
        self.trace_label = Some(label.into());
        self.status = status_line(&self.catalog_summary, &self.trace, self.recent_runs.len());
    }

    pub(super) fn enter_command(&mut self, prefix: &str) {
        self.input_mode = true;
        self.command_input.clear();
        self.command_input.push_str(prefix);
    }

    pub(super) fn push_log(&mut self, line: impl Into<String>) {
        let line = line.into();
        for part in line.lines() {
            self.log_lines.push_back(part.to_owned());
        }
        while self.log_lines.len() > MAX_LOG_LINES {
            self.log_lines.pop_front();
        }
    }

    pub(super) fn clear_log(&mut self) {
        self.log_lines.clear();
    }
}

async fn load_catalog_summary(path: Option<&Utf8PathBuf>) -> Result<Option<CatalogSummary>> {
    match path {
        Some(path) => Ok(Some(CatalogSummary::from_catalog(
            &read_catalog(path.clone()).await?,
        ))),
        None => Ok(None),
    }
}

async fn load_trace(path: Option<&Utf8PathBuf>) -> Result<Option<agent_core::AgentTrace>> {
    match path {
        Some(path) => Ok(Some(read_trace(path.clone()).await?)),
        None => Ok(None),
    }
}

pub(super) async fn read_recent_runs(store_path: &Utf8Path) -> Result<Vec<AgentRunRecord>> {
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

pub(super) async fn read_trace(path: Utf8PathBuf) -> Result<agent_core::AgentTrace> {
    let value = read_json(path.clone()).await?;
    serde_json::from_value(value).map_err(|e| miette!("failed to parse trace at {path}: {e}"))
}

async fn read_json(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
}

fn status_line(
    catalog_summary: &Option<CatalogSummary>,
    trace: &Option<agent_core::AgentTrace>,
    run_count: usize,
) -> String {
    format!(
        "catalog: {} | trace: {} | runs: {}",
        catalog_summary
            .as_ref()
            .map(|summary| summary.agent_count.to_string())
            .unwrap_or_else(|| "not loaded".to_owned()),
        trace
            .as_ref()
            .map(|trace| trace.run_id.0.clone())
            .unwrap_or_else(|| "not loaded".to_owned()),
        run_count
    )
}
