//! The appearance setting: the engine shows what it asks for at start and
//! on change, and 跟随系统 hands the decision back to the device.

mod common;

use common::*;
use nsh_core::{Command, StatusBarConfig, StatusBarStyle};

/// The status bar's content color marks what the engine shows: dark content
/// on the light canvas, light content on the dark one.
fn bar(style: StatusBarStyle) -> Command {
    Command::StatusBar(StatusBarConfig {
        style,
        hidden: false,
        animated: false,
    })
}

#[test]
fn the_app_shows_the_appearance_the_setting_asks_for() -> Result<(), String> {
    let dir = tempfile::tempdir().unwrap();
    let (mut app, storage) = start_in(Some(dir.path()), Vec::new(), None);
    assert!(
        app.screen().sent(&bar(StatusBarStyle::Dark)),
        "the device asks for light, so the app shows light"
    );

    app.press("label:Settings")?;
    app.wait_for("text:Appearance")?;
    app.clear_commands();
    app.press("text:Dark")?;
    app.wait_for("text:Dark")?;
    assert!(
        app.screen().sent(&bar(StatusBarStyle::Light)),
        "the app asks for dark and the engine follows"
    );

    // 跟随系统 hands the decision back: the device's light returns, and a
    // device change is followed again while it is chosen.
    app.clear_commands();
    app.press("text:Match system")?;
    app.wait_for("text:Dark")?;
    assert!(app.screen().sent(&bar(StatusBarStyle::Dark)));
    app.clear_commands();
    app.set_environment("the device turns dark", |e| {
        e.color_scheme = nsh_core::platform::ColorScheme::Dark;
    })?;
    assert!(app.screen().sent(&bar(StatusBarStyle::Light)));
    app.clear_commands();
    app.set_environment("the device turns light", |e| {
        e.color_scheme = nsh_core::platform::ColorScheme::Light;
    })?;
    assert!(app.screen().sent(&bar(StatusBarStyle::Dark)));

    // The choice is kept, and a restart applies it before anything is pressed.
    app.clear_commands();
    app.press("text:Dark")?;
    app.wait_for("text:Dark")?;
    assert!(app.screen().sent(&bar(StatusBarStyle::Light)));
    drop(app);
    let entries: Vec<_> = storage.entries().into_iter().collect();
    assert!(
        entries
            .iter()
            .any(|(key, value)| key == "settings.v1" && value.contains(r#""appearance":"Dark""#)),
        "the choice is kept"
    );
    let (mut app, _) = start_in(Some(dir.path()), entries, None);
    app.wait_for("label:Conversation")?;
    assert!(
        app.screen().sent(&bar(StatusBarStyle::Light)),
        "the kept dark choice applies at start"
    );
    Ok(())
}
