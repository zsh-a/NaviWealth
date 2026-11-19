//! Body metrics, followed by two equally sized Garmin summaries.

use nsh_base::button;
use nsh_core::prelude::*;

use crate::{
    data::garmin,
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
    view()
        .gap_4()
        .child(
            view()
                .test_id("body-summary")
                .child(super::body::summary(day)),
        )
        .child(when(has_garmin, move || {
            view()
                .test_id("garmin-vitals")
                .flex_row()
                .items_stretch()
                .style_when(|| font_scale() > 1.2, |s| s.flex_col())
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
                ))
                .child(divider())
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
                ))
        }))
}

/// A hairline between two vitals.
fn divider() -> impl IntoElement {
    view()
        .w(px(HAIRLINE))
        .my(px(10.0))
        .style_when(
            || font_scale() > 1.2,
            |s| s.w_full().h(px(HAIRLINE)).my(px(2.0)),
        )
        .bg(color::LINE)
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
        .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
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
