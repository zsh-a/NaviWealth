//! Rows shared by Today and Records: a meal led by its photo and a weight
//! entry, grouped in one card with hairlines between them.

use nsh_core::prelude::*;

use crate::{
    data::{clock, photos},
    domain::{format, meal::Meal, weight::Weight},
    i18n::s,
    nav::{self, Route},
    ui::{Icon, Type, Typo, color, icon, radius, surface::row_button},
};

use super::today::{meal_title, slot_name};

/// A row's thumbnail side.
pub const THUMB: f32 = 52.0;
/// Where hairlines start: past the thumbnail.
pub const INSET: f32 = 12.0 + THUMB + 14.0;

/// A saved meal; pressing it opens it.
pub fn meal_row(meal: Meal) -> impl IntoElement {
    let id = meal.id.clone();
    let total = meal.total();
    let label = format!(
        "{}, {} {}",
        meal_title(&meal),
        format::kcal(total.kcal),
        s().kcal
    );
    row_button(move || nav::push(Route::EditMeal(id.clone())))
        .pl(px(12.0))
        .pr(px(18.0))
        .py(px(10.0))
        .gap(px(14.0))
        .accessibility_label(move || Some(label.clone().into()))
        .child(thumbnail(meal.photo.clone()))
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
                ),
        )
        .child(figure(format::kcal(total.kcal), s().kcal))
}

/// A weight entry; pressing it opens its editor.
pub fn weight_row(entry: Weight, open: impl Fn() + 'static) -> impl IntoElement {
    let kg = s().kg(entry.kg);
    row_button(open)
        .pl(px(12.0))
        .pr(px(18.0))
        .py(px(10.0))
        .gap(px(14.0))
        .accessibility_label({
            let label = format!("{}, {kg} kg", s().weight);
            move || Some(label.clone().into())
        })
        .child(glyph(Icon::Scale))
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
                        "{} · {}",
                        s().weight,
                        clock::time_label(entry.logged_at_ms)
                    ))
                    .typo(Type::Subhead)
                    .tabular_nums()
                    .text_color(color::MUTED),
                ),
        )
}

fn figure(value: String, unit: &'static str) -> impl IntoElement {
    view()
        .items_end()
        .child(
            text(value)
                .typo(Type::Figure)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(text(unit).typo(Type::Caption).text_color(color::MUTED))
}

fn glyph(glyph: Icon) -> impl IntoElement {
    view()
        .size(px(THUMB))
        .rounded(px(radius::THUMB))
        .bg(color::SURFACE_2)
        .items_center()
        .justify_center()
        .child(icon(glyph, 24.0, color::MUTED))
}

fn thumbnail(photo: Option<String>) -> impl IntoElement {
    let photo = stored(photo);
    let uri = move || photo.with(|p| p.as_deref().and_then(photos::uri));
    view()
        .size(px(THUMB))
        .rounded(px(radius::THUMB))
        .overflow_hidden()
        .bg(color::SURFACE_2)
        .items_center()
        .justify_center()
        .child(
            when(
                move || uri().is_some(),
                move || {
                    image(move || uri().unwrap_or_default())
                        .object_fit(ResizeMode::Cover)
                        .size(px(THUMB))
                        .accessibility_elements_hidden(true)
                },
            )
            .otherwise(|| icon(Icon::Utensils, 22.0, color::FAINT)),
        )
}
