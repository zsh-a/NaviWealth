//! Three vitals asked about daily: last night's sleep, the latest weight
//! and Body Battery (with resting heart rate). Pressing weight logs it;
//! pressing a Garmin vital shows all of the day's Garmin data, or Settings
//! before a key is connected.

use nsh_core::prelude::*;

use crate::{
    data::{garmin, weights},
    domain::meal::Day,
    i18n::s,
    nav::{self, Route},
    pages::home::Sheets,
    ui::{Icon, Type, Typo, color, icon, surface::card_button},
};

pub fn vitals(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let sheets = Sheets::get();
    let summary = computed(move || garmin::on(day()));
    let has_garmin = || garmin::connected() || garmin::has_days();
    let open_garmin = move || {
        if has_garmin() {
            sheets.garmin.set(true);
        } else {
            nav::push(Route::Settings);
        }
    };
    let garmin_caption = move |value: Option<String>| -> String {
        match value {
            Some(value) => value,
            None if !has_garmin() => s().connect_garmin.to_owned(),
            None => String::new(),
        }
    };
    let latest = move || weights::latest_until(day());
    view()
        .flex_row()
        .gap(px(10.0))
        .child(tile(
            Icon::Moon,
            || s().sleep,
            move || {
                summary.with(|d| {
                    d.as_ref()
                        .and_then(|d| d.sleep_seconds)
                        .map(|v| s().sleep_time(v))
                })
            },
            move || {
                garmin_caption(summary.with(|d| {
                    d.as_ref()
                        .and_then(|d| d.sleep_score)
                        .map(|v| s().sleep_score(v))
                }))
            },
            open_garmin,
        ))
        .child(tile(
            Icon::Scale,
            || s().weight,
            move || latest().map(|entry| format!("{} kg", s().kg(entry.kg))),
            move || match latest() {
                None => s().tap_to_log.to_owned(),
                Some(entry) if entry.day == day() => weights::weekly_change(entry)
                    .map(|delta| s().week_change(delta))
                    .unwrap_or_default(),
                Some(entry) => s().weight_days_ago(day().days_since(entry.day)),
            },
            move || sheets.weight.set(Some(day())),
        ))
        .child(tile(
            Icon::Bolt,
            || s().body_battery,
            move || {
                summary.with(|d| {
                    d.as_ref()
                        .and_then(|d| d.body_battery_high)
                        .map(|v| v.to_string())
                })
            },
            move || {
                garmin_caption(summary.with(|d| {
                    d.as_ref()
                        .and_then(|d| d.resting_hr)
                        .map(|v| format!("{} {v}", s().resting))
                }))
            },
            open_garmin,
        ))
}

fn tile(
    glyph: Icon,
    name: fn() -> &'static str,
    value: impl Fn() -> Option<String> + Copy + 'static,
    caption: impl Fn() -> String + Copy + 'static,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    card_button(press)
        .flex_1()
        .min_w(px(0.0))
        .px(px(14.0))
        .pt(px(14.0))
        .pb(px(13.0))
        .gap(px(8.0))
        .accessibility_label(move || {
            Some(format!("{}, {}", name(), value().unwrap_or_else(|| "—".into())).into())
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
        .child(
            text(move || value().unwrap_or_else(|| "—".into()))
                .typo(Type::Figure)
                .tabular_nums()
                .text_color(move || {
                    if value().is_some() {
                        color::INK
                    } else {
                        color::FAINT
                    }
                })
                .number_of_lines(1),
        )
        .child(
            text(caption)
                .typo(Type::Caption)
                .tabular_nums()
                .text_color(color::MUTED)
                .number_of_lines(1),
        )
}
