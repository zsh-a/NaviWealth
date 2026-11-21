//! Sheets above the software keyboard on Android. NSH 0.6.1 presents every
//! sheet in a dialog window whose root Android lays out above the keyboard
//! (`ModalHost` reports the shrunk root), while the activity still reports
//! the keyboard height. The sheet must meet the keyboard, not float a
//! keyboard's height above it.
mod common;

use common::*;
use nsh_core::{EdgeInsets, Points, Size, ViewKind};

const WIDTH: f32 = 390.0;
const HEIGHT: f32 = 844.0;
const KEYBOARD: f32 = 300.0;
const NAVIGATION: f32 = 24.0;

fn node(app: &Headless, test_id: &str) -> nsh_testing::LayoutNode {
    app.screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.test_id.as_deref() == Some(test_id) && !n.hidden)
        .unwrap_or_else(|| panic!("no {test_id}"))
}

/// The keyboard shows (`height` > 0) or hides as on an Android phone: the
/// environment reports it, and the sheet's dialog root fits above it.
fn keyboard(app: &mut Headless, height: f32) -> Result<(), String> {
    keyboard_reported(app, height, height)
}

/// As [`keyboard`], with the activity reporting `reported` (Android may
/// leave it at 0 while a dialog holds the keyboard).
fn keyboard_reported(app: &mut Headless, height: f32, reported: f32) -> Result<(), String> {
    app.set_environment("keyboard", |e| {
        e.keyboard_height = Points(reported);
        e.safe_area.bottom = Points(NAVIGATION);
    })?;
    let modal = app
        .screen()
        .layout_nodes()
        .into_iter()
        .find(|n| n.kind == ViewKind::Modal)
        .ok_or("no dialog")?;
    let insets = EdgeInsets {
        bottom: Points(NAVIGATION),
        ..EdgeInsets::default()
    };
    app.engine().control().set_root_size(
        modal.id,
        Size::new(Points(WIDTH), Points(HEIGHT - height)),
        insets,
    );
    // Let the engine lay the dialog out again at that size.
    std::thread::sleep(Duration::from_millis(300));
    app.set_environment("laid out", |_| {})
}

fn bottom(app: &Headless, test_id: &str) -> f32 {
    let bounds = node(app, test_id).bounds;
    bounds.origin.y.0 + bounds.size.height.0
}

#[test]
fn the_capture_sheet_meets_the_keyboard_in_its_dialog() -> Result<(), String> {
    let (mut app, _) = start(account(true), None);
    app.set_viewport(Size::new(Points(WIDTH), Points(HEIGHT)))?;
    app.press("label:New entry")?;
    app.wait_for("label:What would you like to record?")?;
    let resting = bottom(&app, "task-sheet");
    assert!(
        (resting - HEIGHT).abs() <= 1.0,
        "without a keyboard it rests on the bottom edge ({resting})"
    );
    keyboard(&mut app, KEYBOARD)?;
    // Only the navigation bar's inset padding lies under the keyboard: the
    // sheet's content ends just above it, with no gap of backdrop between.
    let keyboard_top = HEIGHT - KEYBOARD;
    let under = bottom(&app, "task-sheet") - keyboard_top;
    assert!(
        (under - NAVIGATION).abs() <= 1.0,
        "the sheet should reach {NAVIGATION} pt under the keyboard, not {under}"
    );
    assert!(bottom(&app, "task-header") < keyboard_top);
    keyboard(&mut app, 0.0)?;
    let rested = bottom(&app, "task-sheet");
    assert!(
        (rested - HEIGHT).abs() <= 1.0,
        "it returns to the bottom edge ({rested})"
    );
    Ok(())
}

#[test]
fn the_sheet_also_meets_a_keyboard_only_its_dialog_reports() -> Result<(), String> {
    let (mut app, _) = start(account(true), None);
    app.set_viewport(Size::new(Points(WIDTH), Points(HEIGHT)))?;
    app.press("label:New entry")?;
    app.wait_for("label:What would you like to record?")?;
    keyboard_reported(&mut app, KEYBOARD, 0.0)?;
    let under = bottom(&app, "task-sheet") - (HEIGHT - KEYBOARD);
    assert!(
        (under - NAVIGATION).abs() <= 1.0,
        "the sheet should reach {NAVIGATION} pt under the keyboard, not {under}"
    );
    Ok(())
}
