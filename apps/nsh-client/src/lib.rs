//! NaviWealth's local-first NSH client for finance and health. Domain crates
//! own record models, calculations and validated repositories; this app owns
//! device adapters, reactive UI and explicitly confirmed cross-domain writes.

mod data;
pub mod domain;
mod i18n;
mod incoming;
mod nav;
mod pages;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
mod preview;
mod scale;
mod shell;
mod ui;

use std::time::Duration;

use nsh_core::prelude::*;

use crate::{
    data::{
        backup, body_metrics, capture, clock, db, favorites, finance, garmin, meals, notes,
        pending, photos, settings, tasks, updates, weights,
    },
    i18n::s,
    ui::{Type, Typo, color, space},
};

/// The app's UI set (`nsh.json` `"rust"`).
#[native_module("naviwealth/native")]
fn native(registry: &mut Registry) {
    registry
        .register::<App>()
        .module::<scale::Scale>()
        .module::<incoming::Incoming>();
}

/// For headless tests: no quotes or exchange rates from the public
/// providers, whose transport the engine's stub network cannot intercept.
#[doc(hidden)]
pub fn disable_live_market_data() {
    data::market::disable_live();
}

/// Route capture requests through the supplied NSH network (headless fixtures).
#[doc(hidden)]
pub fn use_host_capture_transport() {
    data::vision::use_host_capture_transport();
}

/// For headless tests: whether update checks may reach the public
/// releases API.
#[doc(hidden)]
pub fn set_live_updates(live: bool) {
    data::updates::set_live(live);
}

/// Shares queued for the next app start, as the TSX entry would forward them.
static STARTUP_SHARES: std::sync::Mutex<Vec<data::incoming::Shared>> =
    std::sync::Mutex::new(Vec::new());

/// For headless tests: a share (`Incoming.receive`'s JSON) the next app start
/// receives once its data is loaded, as from the TSX entry.
#[doc(hidden)]
pub fn share_on_start(shared: serde_json::Value) -> Result<(), String> {
    let shared = serde_json::from_value(shared).map_err(|e| e.to_string())?;
    STARTUP_SHARES
        .lock()
        .map_err(|_| "poisoned".to_owned())?
        .push(shared);
    Ok(())
}

/// The optional capabilities supplied by the mixed TSX entry.
#[derive(Clone, PartialEq, Props)]
pub struct AppProps {
    /// The TSX entry can present the scale flow through the Android host.
    #[prop(default)]
    pub scale_enabled: Prop<bool>,
    /// Disable live optional refreshes for local headless development hosts.
    #[prop(default)]
    pub test_mode: Prop<bool>,
}

/// Requests handled by the mixed TSX entry, outside the existing Rust pages.
#[derive(Clone, PartialEq, Event)]
pub enum AppEvent {
    /// Open the scale connection and measurement flow.
    OpenScale,
}

/// The root: loads what the device keeps, keeps "today" current, and shows
/// the navigation stack on the canvas.
#[component]
pub fn App(props: AppProps, cx: Scope<AppEvent>) -> impl IntoElement {
    if cfg!(debug_assertions) && props.test_mode.get() {
        disable_live_market_data();
        use_host_capture_transport();
        set_live_updates(false);
    }
    scale::provide_launcher(props.scale_enabled.get(), move || {
        cx.emit(AppEvent::OpenScale)
    });
    tasks::mark_root();
    if let Err(error) = db::open()
        .and_then(|()| finance::load())
        .and_then(|()| capture::load())
        .and_then(|()| data::statement_import::load())
        .and_then(|()| data::catalog::load())
        .and_then(|()| data::market::load())
        .and_then(|()| meals::load())
        .and_then(|()| favorites::load())
        .and_then(|()| pending::load())
        .and_then(|()| data::assistant::load())
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
    notes::load();
    weights::load();
    body_metrics::load();
    updates::load();
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
    // The appearance override, applied before the first frame and on every
    // change; 跟随系统 hands the decision back to the device.
    set_color_scheme(settings::appearance().scheme());
    effect(move || set_color_scheme(settings::appearance().scheme()));
    for shared in STARTUP_SHARES
        .lock()
        .map(|mut queued| std::mem::take(&mut *queued))
        .unwrap_or_default()
    {
        data::incoming::receive(shared);
    }
    data::keyboard::track();
    spawn(photos::sweep_orphans());
    data::market::start();
    // Midnight, and coming back to the app, move "today" on.
    set_interval(Duration::from_secs(30), clock::tick);
    effect(move || {
        if lifecycle() == nsh_core::platform::Lifecycle::Active {
            untracked(clock::tick);
            tasks::spawn_app(garmin::refresh(false));
            data::updates::check(false);
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
