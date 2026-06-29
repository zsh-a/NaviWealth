use miette::{IntoDiagnostic, Result};
use ratatui::{
    Frame, Terminal,
    backend::TestBackend,
    buffer::Buffer,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph},
};

use super::data::TuiState;

pub(super) fn render_tui_once(state: &TuiState) -> Result<String> {
    let backend = TestBackend::new(110, 34);
    let mut terminal = Terminal::new(backend).into_diagnostic()?;
    terminal
        .draw(|frame| render_tui_frame(frame, state))
        .into_diagnostic()?;
    Ok(buffer_to_string(terminal.backend().buffer()))
}

pub(super) fn render_tui_frame(frame: &mut Frame<'_>, state: &TuiState) {
    let root = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(12),
            Constraint::Length(3),
            Constraint::Length(5),
        ])
        .split(frame.area());
    let body = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(40), Constraint::Percentage(60)])
        .split(root[1]);
    let right = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(body[1]);

    frame.render_widget(header_panel(), root[0]);
    frame.render_widget(catalog_panel(state), body[0]);
    frame.render_widget(trace_panel(state), right[0]);
    frame.render_widget(log_panel(state), right[1]);
    frame.render_widget(command_panel(state), root[2]);
    frame.render_widget(status_panel(state), root[3]);
}

fn header_panel() -> Paragraph<'static> {
    Paragraph::new(Line::from(vec![
        Span::styled(
            "Agent Runtime TUI",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("  : command  r run  t tool  p replay  R refresh  ? help  q/esc quit"),
    ]))
    .block(Block::default().borders(Borders::ALL))
}

fn catalog_panel(state: &TuiState) -> List<'static> {
    let mut items = Vec::new();
    items.push(ListItem::new(format!(
        "catalog: {}",
        state
            .options
            .catalog_path
            .as_ref()
            .map(ToString::to_string)
            .unwrap_or_else(|| "not loaded".to_owned())
    )));
    items.push(ListItem::new(format!(
        "registry: {}",
        state.options.registry_path
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
            .trace_label
            .clone()
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
                .rev()
                .take(10)
                .rev()
                .map(|event| ListItem::new(format!("{} {}", event.occurred_at, event.kind))),
        );
    } else {
        items.push(ListItem::new("load with --trace <path> or :replay <path>"));
    }
    List::new(items).block(Block::default().title("Trace").borders(Borders::ALL))
}

fn log_panel(state: &TuiState) -> List<'static> {
    let items = if state.log_lines.is_empty() {
        vec![ListItem::new("no debug output yet")]
    } else {
        state
            .log_lines
            .iter()
            .rev()
            .take(12)
            .rev()
            .map(|line| ListItem::new(line.clone()))
            .collect()
    };
    List::new(items).block(Block::default().title("Debug Output").borders(Borders::ALL))
}

fn command_panel(state: &TuiState) -> Paragraph<'static> {
    let prompt = if state.input_mode { ">" } else { " " };
    let text = if state.input_mode {
        format!("{prompt} {}", state.command_input)
    } else {
        "Press ':' to type a command. Example: run echo_agent {\"message\":\"hi\"}".to_owned()
    };
    Paragraph::new(text).block(Block::default().title("Command").borders(Borders::ALL))
}

fn status_panel(state: &TuiState) -> Paragraph<'static> {
    Paragraph::new(vec![
        Line::from(state.status.clone()),
        Line::from(format!("store: {}", state.options.store_path)),
        Line::from(
            "Commands: run <agent_id> [json] | tool <name> [json] | replay <trace> | inspect <run_id> | refresh | clear | help",
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
