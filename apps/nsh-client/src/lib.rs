//! NaviWealth's native client, written in Rust on NSH: HealthOS meal
//! logging. A photo of a meal becomes an editable estimate from the user's
//! own vision model; confirmed meals add up to the day's intake. Everything
//! stays on the device.

mod data;
pub mod domain;
mod i18n;
mod nav;
mod pages;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod preview;
mod shell;
mod ui;

use std::time::Duration;

use nsh_core::prelude::*;

use crate::{
    data::{clock, db, meals, photos, settings, weights},
    ui::color,
};

/// The app's UI set (`nsh.json` `"rust"`).
#[native_module("naviwealth-health/native")]
fn native(registry: &mut Registry) {
    registry.register::<App>();
}

/// The root: loads what the device keeps, keeps "today" current, and shows
/// the navigation stack on the canvas.
#[component]
pub fn App() -> impl IntoElement {
    db::open();
    meals::load();
    weights::load();
    settings::load();
    spawn(photos::sweep_orphans());
    // Midnight, and coming back to the app, move "today" on.
    set_interval(Duration::from_secs(30), clock::tick);
    effect(move || {
        if lifecycle() == nsh_core::platform::Lifecycle::Active {
            untracked(clock::tick);
        }
    });
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    preview::apply();
    view()
        .flex_1()
        .bg(color::CANVAS)
        .text_color(color::BODY)
        .child(shell::shell())
}
