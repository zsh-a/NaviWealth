//! Rows shared by Today and Records: a meal led by its photo when it has
//! one, and a weight entry, separated by hairlines on the canvas. Without a photo, meals use the same leading footprint with the
//! semantic meal icon.

use nsh_core::prelude::*;

use crate::{
    data::{body_metrics, clock, photos},
    domain::{format, meal::Meal, weight::Weight},
    i18n::s,
    nav::{self, Route},
    ui::{
        Icon, Type, Typo, color, radius,
        surface::{hairline, row_button},
    },
};

use super::today::{meal_title, slot_name};

/// A row's thumbnail side.
pub const THUMB: f32 = 52.0;
/// Align timeline rows with the surrounding page content.
pub const INSET: f32 = 4.0;
/// Where the text of a row with a leading footprint starts; its divider
/// starts here too, so hairlines underline text rather than icons.
pub fn text_inset(leading: f32) -> f32 {
    INSET + leading + 14.0
}

pub const ICON_COLUMN: f32 = 28.0;

pub fn leading_width(has_photo: bool) -> f32 {
    if has_photo { THUMB } else { ICON_COLUMN }
}

/// The leading footprint of a row without a photo: its semantic icon, small
/// and quiet, so the column aligns without reading as a column of icons.
pub fn glyph(icon: Icon, width: f32, height: f32) -> View {
    view()
        .w(px(width))
        .h(px(height))
        .flex_shrink_0()
        .items_center()
        .justify_center()
        .child(crate::ui::icon(icon, 20.0, color::MUTED))
}

/// The divider begins at the title of the following row.
pub fn divider(leading: f32) -> View {
    hairline(0.0).ml(px(leading))
}

/// A saved meal; pressing it opens it.
pub fn meal_row(meal: Meal, leading: f32) -> impl IntoElement {
    let id = meal.id.clone();
    let total = meal.total();
    let label = format!(
        "{}, {} {}",
        meal_title(&meal),
        format::kcal(total.kcal),
        s().kcal
    );
    let photo = meal.photo.clone();
    row_button(move || nav::push(Route::EditMeal(id.clone())))
        .px(px(INSET))
        .py(px(10.0))
        .gap(px(14.0))
        .accessibility_label(move || Some(label.clone().into()))
        .child(match photo {
            Some(photo) => thumbnail(photo).into_element(),
            None => glyph(Icon::Utensils, leading, THUMB).into_element(),
        })
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap(px(3.0))
                .child(
                    text(meal_title(&meal))
                        .typo(Type::Headline)
                        .text_color(color::INK)
                        .number_of_lines(1),
                )
                .child(
                    text(format!(
                        "{} · {}",
                        slot_name(s(), meal.slot),
                        clock::time_label(meal.logged_at_ms)
                    ))
                    .typo(Type::Subhead)
                    .tabular_nums()
                    .text_color(color::MUTED)
                    .number_of_lines(1),
                )
                .child(when(
                    || font_scale() > 1.2,
                    move || figure(format::kcal(total.kcal), s().kcal),
                )),
        )
        .child(when(
            || font_scale() <= 1.2,
            move || figure(format::kcal(total.kcal), s().kcal),
        ))
}

/// A weight entry; pressing it opens its editor.
pub fn weight_row(entry: Weight, open: impl Fn() + 'static) -> impl IntoElement {
    let kg = s().kg(entry.kg);
    row_button(open)
        .px(px(INSET))
        .py(px(10.0))
        .gap(px(14.0))
        .accessibility_label({
            let label = format!("{}, {kg} kg", s().weight);
            move || Some(label.clone().into())
        })
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap(px(3.0))
                .child(
                    text(format!("{kg} kg"))
                        .typo(Type::Headline)
                        .tabular_nums()
                        .text_color(color::INK),
                )
                .child(
                    text(format!(
                        "{} · {}{}",
                        s().weight,
                        clock::time_label(entry.logged_at_ms),
                        body_metrics::on(entry.day).map_or_else(String::new, |m| {
                            format!(" · {} {:.1}%", s().body_fat, m.metrics.body_fat_percent)
                        }),
                    ))
                    .typo(Type::Subhead)
                    .tabular_nums()
                    .text_color(color::MUTED),
                ),
        )
}

fn figure(value: String, unit: &'static str) -> impl IntoElement {
    view()
        .flex_row()
        .items_baseline()
        .gap(px(4.0))
        .child(
            text(value)
                .typo(Type::Figure)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(text(unit).typo(Type::Caption).text_color(color::MUTED))
}

/// The meal's photo; its well shows while the photo loads.
fn thumbnail(photo: String) -> impl IntoElement {
    let photo = stored(photo);
    let uri = move || photo.with(|p| photos::uri(p));
    view()
        .size(px(THUMB))
        .rounded(px(radius::THUMB))
        .overflow_hidden()
        .bg(color::PHOTO_WELL)
        .child(when(
            move || uri().is_some(),
            move || {
                image(move || uri().unwrap_or_default())
                    .object_fit(ResizeMode::Cover)
                    .size(px(THUMB))
                    .accessibility_elements_hidden(true)
            },
        ))
}
