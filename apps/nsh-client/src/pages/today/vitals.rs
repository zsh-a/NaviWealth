//! Three vitals asked about daily: last night's sleep, the latest weight
//! and Body Battery (with resting heart rate). Pressing weight logs it;
//! pressing a Garmin vital shows all of the day's Garmin data, or Settings
//! before a key is connected.

use nsh_base::button;
use nsh_core::prelude::*;

use crate::{
    data::{garmin, weights},
    domain::meal::Day,
    i18n::s,
    nav::{self, Route},
    pages::home::Sheets,
    ui::{
        Icon, Type, Typo, color,
        figures::{Scale, stat},
        icon,
        surface::HAIRLINE,
        theme::{motion, radius},
    },
};

pub fn vitals(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let sheets = Sheets::get();
    let summary = computed(move || garmin::on(day()));
    let has_garmin =
        move || garmin::connected() || summary.with(|d| d.as_ref().is_some_and(|d| !d.is_empty()));
    let open_garmin = move || {
        if has_garmin() {
            sheets.garmin.set(true);
        } else {
            nav::push(Route::Settings);
        }
    };
    let latest = move || weights::latest_until(day());
    view()
        .flex_row()
        .items_stretch()
        .child(when(has_garmin, move || {
            tile(
                Icon::Moon,
                || s().sleep,
                move || {
                    summary.with(|d| {
                        d.as_ref()
                            .and_then(|d| d.sleep_seconds)
                            .map(|v| s().sleep_time(v))
                    })
                },
                || "",
                move || {
                    summary
                        .with(|d| {
                            d.as_ref()
                                .and_then(|d| d.sleep_score)
                                .map(|v| s().sleep_score(v))
                        })
                        .unwrap_or_default()
                },
                open_garmin,
            )
        }))
        .child(when(has_garmin, divider))
        .child(tile(
            Icon::Scale,
            || s().weight,
            move || latest().map(|entry| s().kg(entry.kg)),
            || "kg",
            move || match latest() {
                None => s().tap_to_log.to_owned(),
                Some(entry) if entry.day == day() => weights::weekly_change(entry)
                    .map(|delta| s().week_change(delta))
                    .unwrap_or_default(),
                Some(entry) => s().weight_days_ago(day().days_since(entry.day)),
            },
            move || sheets.weight.set(Some(day())),
        ))
        .child(when(has_garmin, divider))
        .child(when(has_garmin, move || {
            tile(
                Icon::Bolt,
                || s().body_battery,
                move || {
                    summary.with(|d| {
                        d.as_ref()
                            .and_then(|d| d.body_battery_high)
                            .map(|v| v.to_string())
                    })
                },
                || "",
                move || {
                    summary
                        .with(|d| {
                            d.as_ref()
                                .and_then(|d| d.resting_hr)
                                .map(|v| format!("{} {v}", s().resting))
                        })
                        .unwrap_or_default()
                },
                open_garmin,
            )
        }))
}

/// A hairline between two vitals.
fn divider() -> impl IntoElement {
    view().w(px(HAIRLINE)).my(px(10.0)).bg(color::LINE)
}

/// One vital laid flat on the canvas: its name, its figure and a caption.
/// It shades softly while pressed instead of sitting on a card.
fn tile(
    glyph: Icon,
    name: fn() -> &'static str,
    value: impl Fn() -> Option<String> + Copy + 'static,
    unit: fn() -> &'static str,
    caption: impl Fn() -> String + Copy + 'static,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    button()
        .on_press(press)
        .flex_1()
        .min_w(px(0.0))
        .px(px(6.0))
        .py(px(8.0))
        .gap(px(6.0))
        .rounded(px(radius::WELL))
        .transition_colors()
        .duration(motion::INSTANT)
        .active(|s| s.bg(color::SUNKEN))
        .focus_visible(|s| s.bg(color::SURFACE_2))
        .accessibility_label(move || {
            let value = value().map_or_else(|| "—".to_owned(), |v| format!("{v} {}", unit()));
            Some(format!("{}, {value}", name()).into())
        })
        .child(
            view()
                .flex_row()
                .items_center()
                .gap(px(6.0))
                .child(icon(glyph, 15.0, color::MUTED))
                .child(
                    text(name)
                        .typo(Type::Caption)
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(color::MUTED)
                        .number_of_lines(1),
                ),
        )
        .child(stat(value, move || unit().to_owned(), Scale::Tile))
        .child(
            text(caption)
                .typo(Type::Caption)
                .tabular_nums()
                .text_color(color::MUTED)
                .number_of_lines(2),
        )
}
