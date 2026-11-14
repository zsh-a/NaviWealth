//! Rows shared by Today and Records: a meal led by its photo when it has
//! one, and a weight entry, grouped in one card with hairlines between
//! them. A row without a photo starts with its text: no placeholder art.

use nsh_core::prelude::*;

use crate::{
    data::{clock, photos},
    domain::{format, meal::Meal, weight::Weight},
    i18n::s,
    nav::{self, Route},
    ui::{Type, Typo, color, radius, space, surface::row_button},
};

use super::today::{meal_title, slot_name};

/// A row's thumbnail side.
pub const THUMB: f32 = 52.0;
/// A row's leading padding without a photo, and where hairlines start.
pub const INSET: f32 = space::CARD;

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
    let photo = meal.photo.clone();
    row_button(move || nav::push(Route::EditMeal(id.clone())))
        .pl(px(if photo.is_some() { 12.0 } else { INSET }))
        .pr(px(18.0))
        .py(px(10.0))
        .gap(px(14.0))
        .accessibility_label(move || Some(label.clone().into()))
        .child(photo.map(thumbnail))
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
        .pl(px(INSET))
        .pr(px(18.0))
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
