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
    data::{
        backup, capture, clock, db, favorites, finance, garmin, meals, notes, pending, photos,
        settings, tasks, weights,
    },
    i18n::s,
    ui::{Type, Typo, color, space},
};

/// The app's UI set (`nsh.json` `"rust"`).
#[native_module("naviwealth-health/native")]
fn native(registry: &mut Registry) {
    registry.register::<App>();
}

/// For headless tests: no quotes or exchange rates from the public
/// providers, whose transport the engine's stub network cannot intercept.
#[doc(hidden)]
pub fn disable_live_market_data() {
    data::market::disable_live();
}

/// The root: loads what the device keeps, keeps "today" current, and shows
/// the navigation stack on the canvas.
#[component]
pub fn App() -> impl IntoElement {
    tasks::mark_root();
    if let Err(error) = db::open()
        .and_then(|()| finance::load())
        .and_then(|()| crate::data::valuation::load())
        .and_then(|()| capture::load())
        .and_then(|()| data::statement_import::load())
        .and_then(|()| data::catalog::load())
        .and_then(|()| data::market::load())
    {
        log::error!("startup: local data unavailable: {error}");
        return view()
            .flex_1()
            .bg(color::CANVAS)
            .p(px(space::GUTTER))
            .pt_safe_area_plus(px(40.0))
            .gap_4()
            .child(
                text(|| s().storage_unavailable)
                    .typo(Type::Title)
                    .text_color(color::INK),
            )
            .child(
                text(|| s().storage_unavailable_body)
                    .typo(Type::Body)
                    .text_color(color::BODY),
            )
            .into_element();
    }
    meals::load();
    favorites::load();
    pending::load();
    notes::load();
    weights::load();
    garmin::load();
    backup::load();
    // At start, and as soon as a key is connected. The memo re-runs the
    // effect only when that changes, not on every sync state change (which
    // would cancel the pull it started).
    let linked = computed(garmin::connected);
    effect(move || {
        if linked.get() {
            tasks::spawn_app(garmin::refresh(false));
        }
    });
    // The day's backup, at start and once backups are set up.
    let backing_up = computed(backup::configured);
    effect(move || {
        if backing_up.get() {
            spawn(async {
                let _ = backup::backup_now(false).await;
            });
        }
    });
    settings::load();
    data::keyboard::track();
    spawn(photos::sweep_orphans());
    // Midnight, and coming back to the app, move "today" on.
    set_interval(Duration::from_secs(30), clock::tick);
    effect(move || {
        if lifecycle() == nsh_core::platform::Lifecycle::Active {
            untracked(clock::tick);
            tasks::spawn_app(garmin::refresh(false));
            tasks::spawn_app(data::market::refresh(false));
            tasks::spawn_app(async {
                let _ = backup::backup_now(false).await;
            });
        }
    });
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    preview::apply();
    view()
        .flex_1()
        .bg(color::CANVAS)
        .text_color(color::BODY)
        .child(shell::shell())
        .into_element()
}
