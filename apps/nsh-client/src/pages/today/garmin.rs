//! What Garmin measured today in full: last night's sleep, HRV, resting
//! heart rate, Body Battery, steps and stress, in a sheet opened from the
//! vitals. A failed update keeps the last data and says so.

use health_core::garmin::GarminDay;
use nsh_core::prelude::*;

use crate::{
    data::{
        clock,
        garmin::{self, Failure, SyncState},
    },
    domain::format,
    i18n::s,
    ui::{Type, Typo, color, radius},
};

/// Today's Garmin data in full, opened from a Garmin vital.
pub fn garmin_sheet() -> impl IntoElement {
    let summary = computed(|| garmin::on(clock::today()));
    view()
        .gap_4()
        .child(
            view()
                .flex_row()
                .items_baseline()
                .justify_between()
                .gap_3()
                .child(
                    text(|| s().garmin)
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .role(AccessibilityRole::Header),
                )
                .child(
                    text(status)
                        .typo(Type::Caption)
                        .text_color(move || {
                            if matches!(garmin::sync_state(), SyncState::Failed(_)) {
                                color::CAUTION
                            } else {
                                color::MUTED
                            }
                        })
                        .number_of_lines(2)
                        .flex_shrink(1.0)
                        .text_right(),
                ),
        )
        .child(
            when(
                move || summary.with(Option::is_some),
                move || metrics(move || summary.get().unwrap_or_default()),
            )
            .otherwise(|| {
                text(|| s().garmin_no_data)
                    .typo(Type::Subhead)
                    .text_color(color::MUTED)
            }),
        )
}

fn status() -> String {
    match garmin::sync_state() {
        SyncState::Syncing => s().garmin_syncing.to_owned(),
        SyncState::Failed(Failure::KeyRejected) => s().garmin_key_rejected.to_owned(),
        SyncState::Failed(Failure::Network) => s().garmin_network.to_owned(),
        SyncState::Failed(Failure::Unreadable) => s().garmin_unreadable.to_owned(),
        SyncState::Idle => String::new(),
    }
}

/// Three rows of two tiles.
fn metrics(day: impl Fn() -> GarminDay + Copy + 'static) -> impl IntoElement {
    let dash = || "—".to_owned();
    let row = |a: AnyElement, b: AnyElement| view().flex_row().gap(px(10.0)).child(a).child(b);
    view()
        .gap(px(10.0))
        .child(row(
            tile(
                || s().sleep,
                move || {
                    day()
                        .sleep_seconds
                        .map(|v| s().sleep_time(v))
                        .unwrap_or_else(dash)
                },
                move || day().sleep_score.map(|v| s().sleep_score(v)),
            ),
            tile(
                || s().hrv,
                move || day().hrv_ms.map(|v| format!("{v} ms")).unwrap_or_else(dash),
                move || day().hrv_status.map(|v| hrv_status(&v)),
            ),
        ))
        .child(row(
            tile(
                || s().resting_hr,
                move || {
                    day()
                        .resting_hr
                        .map(|v| format!("{v} bpm"))
                        .unwrap_or_else(dash)
                },
                || None,
            ),
            tile(
                || s().body_battery,
                move || {
                    day()
                        .body_battery_high
                        .map(|v| v.to_string())
                        .unwrap_or_else(dash)
                },
                || None,
            ),
        ))
        .child(row(
            tile(
                || s().steps,
                move || {
                    day()
                        .steps
                        .map(|v| format::kcal(f64::from(v)))
                        .unwrap_or_else(dash)
                },
                || None,
            ),
            tile(
                || s().stress,
                move || day().stress_avg.map(|v| v.to_string()).unwrap_or_else(dash),
                || None,
            ),
        ))
}

/// Garmin's HRV status words, readable.
fn hrv_status(status: &str) -> String {
    let mut words = status.to_lowercase().replace('_', " ");
    if let Some(first) = words.get(..1) {
        words = first.to_uppercase() + &words[1..];
    }
    words
}

fn tile(
    label: fn() -> &'static str,
    value: impl Fn() -> String + Copy + 'static,
    detail: impl Fn() -> Option<String> + Copy + 'static,
) -> AnyElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap(px(4.0))
        .px_3()
        .py(px(12.0))
        .rounded(px(radius::WELL))
        .bg(color::SURFACE_2)
        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
        .child(
            text(value)
                .typo(Type::Figure)
                .tabular_nums()
                .text_color(color::INK)
                .number_of_lines(1),
        )
        .child(when(
            move || detail().is_some(),
            move || {
                text(move || detail().unwrap_or_default())
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .number_of_lines(1)
            },
        ))
        .into_element()
}
