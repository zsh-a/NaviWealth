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
            Constraint::Length(1),
            Constraint::Min(8),
            Constraint::Length(3),
        ])
        .split(frame.area());
    let body = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(42), Constraint::Percentage(58)])
        .split(root[1]);

    frame.render_widget(status_line(state), root[0]);
    frame.render_widget(context_panel(state), body[0]);
    frame.render_widget(output_panel(state), body[1]);
    frame.render_widget(command_panel(state), root[2]);
}

fn status_line(_state: &TuiState) -> Paragraph<'static> {
    Paragraph::new(Line::from(vec![
        Span::styled(
            "Agent Runtime",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("  natural input  |  /help commands  |  Enter sends  |  Esc exits"),
    ]))
}

fn context_panel(state: &TuiState) -> List<'static> {
    let mut items = Vec::new();
    items.push(ListItem::new(format!(
        "registry: {}",
        state.options.registry_path
    )));
    items.push(ListItem::new(format!(
        "store: {}",
        state.options.store_path
    )));
    if let Some(summary) = &state.catalog_summary {
        items.extend([
            ListItem::new(format!(
                "catalog: {} agents, {} tools",
                summary.agent_count, summary.tool_count
            )),
            ListItem::new(format!("domains: {}", summary.active_domains.join(", "))),
        ]);
    } else {
        items.push(ListItem::new("catalog: not loaded"));
    }
    items.push(ListItem::new(""));
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
        ]);
        items.extend(
            trace
                .events
                .iter()
                .rev()
                .take(6)
                .rev()
                .map(|event| ListItem::new(format!("event: {}", event.kind))),
        );
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
    List::new(items).block(Block::default().title("Context").borders(Borders::ALL))
}

fn output_panel(state: &TuiState) -> List<'static> {
    let items = if state.log_lines.is_empty() {
        vec![ListItem::new("no output yet")]
    } else {
        state
            .log_lines
            .iter()
            .map(|line| ListItem::new(line.clone()))
            .collect()
    };
    List::new(items).block(Block::default().title("Output").borders(Borders::ALL))
}

fn command_panel(state: &TuiState) -> Paragraph<'static> {
    let prompt = if state.command_input.starts_with('/') {
        "/"
    } else {
        ">"
    };
    let text = if state.input_mode {
        if let Some(command) = state.command_input.strip_prefix('/') {
            format!("{prompt} {command}")
        } else {
            format!("{prompt} {}", state.command_input)
        }
    } else {
        "Type a message, or use /help".to_owned()
    };
    Paragraph::new(text).block(Block::default().title("Input").borders(Borders::ALL))
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
