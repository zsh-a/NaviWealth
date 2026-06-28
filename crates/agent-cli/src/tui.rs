use std::{
    io::{self, Stdout},
    time::Duration,
};

use agent_core::AgentRunRecord;
use camino::{Utf8Path, Utf8PathBuf};
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
use serde_json::Value;

use crate::catalog::{CatalogSummary, read_catalog};

struct TuiState {
    catalog_path: Option<Utf8PathBuf>,
    trace_path: Option<Utf8PathBuf>,
    store_path: Utf8PathBuf,
    catalog_summary: Option<CatalogSummary>,
    trace: Option<agent_core::AgentTrace>,
    recent_runs: Vec<AgentRunRecord>,
    status: String,
}

pub(crate) async fn run_tui(
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

async fn read_trace(path: Utf8PathBuf) -> Result<agent_core::AgentTrace> {
    let value = read_json(path.clone()).await?;
    serde_json::from_value(value).map_err(|e| miette!("failed to parse trace at {path}: {e}"))
}

async fn read_json(path: Utf8PathBuf) -> Result<Value> {
    let bytes = fs_err::tokio::read(&path)
        .await
        .map_err(|e| miette!("failed to read JSON at {path}: {e}"))?;
    serde_json::from_slice(&bytes).map_err(|e| miette!("failed to parse JSON at {path}: {e}"))
}
