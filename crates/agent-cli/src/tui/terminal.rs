use std::{
    io::{self, Stdout},
    time::Duration,
};

use crossterm::event::{Event, KeyCode, KeyModifiers};
use miette::{IntoDiagnostic, Result};
use ratatui::{Terminal, backend::CrosstermBackend};

use super::{commands::execute_command, data::TuiState, render::render_tui_frame};

pub(super) async fn run_tui_terminal(mut state: TuiState) -> Result<()> {
    crossterm::terminal::enable_raw_mode().into_diagnostic()?;
    let mut stdout = io::stdout();
    crossterm::execute!(stdout, crossterm::terminal::EnterAlternateScreen).into_diagnostic()?;
    let result = run_tui_event_loop(
        &mut Terminal::new(CrosstermBackend::new(stdout)).into_diagnostic()?,
        &mut state,
    )
    .await;
    crossterm::terminal::disable_raw_mode().into_diagnostic()?;
    let mut stdout = io::stdout();
    crossterm::execute!(stdout, crossterm::terminal::LeaveAlternateScreen).into_diagnostic()?;
    result
}

async fn run_tui_event_loop(
    terminal: &mut Terminal<CrosstermBackend<Stdout>>,
    state: &mut TuiState,
) -> Result<()> {
    loop {
        terminal
            .draw(|frame| render_tui_frame(frame, state))
            .into_diagnostic()?;
        if crossterm::event::poll(Duration::from_millis(100)).into_diagnostic()?
            && let Event::Key(key) = crossterm::event::read().into_diagnostic()?
        {
            if state.input_mode {
                if handle_input_key(state, key.code, key.modifiers).await? {
                    return Ok(());
                }
                continue;
            }
            match key.code {
                KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
                KeyCode::Char(':') | KeyCode::Char('/') => state.enter_command("/"),
                KeyCode::Char('r') => state.enter_command("/run "),
                KeyCode::Char('t') => state.enter_command("/tool "),
                KeyCode::Char('p') => state.enter_command("/replay "),
                KeyCode::Char('i') => state.enter_command("/inspect "),
                KeyCode::Char('R') => {
                    if let Err(error) = state.refresh().await {
                        state.push_log(format!("refresh failed: {error}"));
                    } else {
                        state.push_log("refreshed catalog/trace/store");
                    }
                }
                KeyCode::Char('?') => run_command(state, "/help").await,
                KeyCode::Char(ch) => {
                    state.enter_command("");
                    state.command_input.push(ch);
                }
                _ => {}
            }
        }
    }
}

async fn handle_input_key(
    state: &mut TuiState,
    code: KeyCode,
    modifiers: KeyModifiers,
) -> Result<bool> {
    match code {
        KeyCode::Esc => {
            if state.command_input.is_empty() {
                return Ok(true);
            }
            state.command_input.clear();
        }
        KeyCode::Enter => {
            let command = state.command_input.trim().to_owned();
            state.command_input.clear();
            run_command(state, &command).await;
        }
        KeyCode::Char('c') if modifiers.contains(KeyModifiers::CONTROL) => return Ok(true),
        KeyCode::Backspace => {
            state.command_input.pop();
        }
        KeyCode::Char('u') if modifiers.contains(KeyModifiers::CONTROL) => {
            state.command_input.clear();
        }
        KeyCode::Char(ch) => state.command_input.push(ch),
        _ => {}
    }
    Ok(false)
}

async fn run_command(state: &mut TuiState, command: &str) {
    if let Err(error) = execute_command(state, command).await {
        state.push_log(format!("command failed: {error}"));
    }
}
