//! The day's meals: one card each, oldest first, led by the meal's photo;
//! a calm empty state when the day has none.

use nsh_core::prelude::*;

use crate::{
    data::{clock, meals, photos},
    domain::{
        format,
        meal::{Day, Meal, MealSlot},
    },
    i18n::{Strings, s},
    nav::{self, Route},
    ui::{
        Icon, Type, Typo, color,
        feedback::{appear, empty_state},
        icon, radius,
        surface::{card, card_button, section_header},
    },
};

const THUMB: f32 = 68.0;

/// The meals section of `day`.
pub fn meal_list(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let list = computed(move || meals::on(day()));
    // Kept photos load off the engine thread as the day's meals change.
    effect(move || {
        let names: Vec<String> =
            list.with(|list| list.iter().filter_map(|m| m.photo.clone()).collect());
        if !names.is_empty() {
            spawn(photos::load(names));
        }
    });
    let count = move || list.with(Vec::len);
    view()
        .gap_3()
        .child(section_header(
            move || s().meals,
            Some(
                text(move || {
                    let n = count();
                    if n == 0 {
                        String::new()
                    } else {
                        s().meal_count(n)
                    }
                })
                .typo(Type::Subhead)
                .text_color(color::MUTED)
                .into_element(),
            ),
        ))
        .child(
            when(
                move || count() > 0,
                move || {
                    view()
                        .gap_3()
                        .child(each(list, |meal: &Meal| meal.id.clone(), meal_card))
                },
            )
            .otherwise(move || {
                card().child(empty_state(
                    Icon::Utensils,
                    move || {
                        if day() == clock::today() {
                            s().empty_today
                        } else {
                            s().empty_day
                        }
                    },
                    || s().empty_body,
                ))
            }),
        )
}

/// What a meal is called: the model's title, else its foods.
pub fn meal_title(meal: &Meal) -> String {
    if let Some(title) = meal.title.as_ref().filter(|t| !t.trim().is_empty()) {
        return title.clone();
    }
    let names: Vec<&str> = meal.foods.iter().map(|f| f.name.as_str()).collect();
    match names.as_slice() {
        [] => String::new(),
        [one] => (*one).to_owned(),
        [first, second] => format!("{first}, {second}"),
        [first, second, rest @ ..] => format!("{first}, {second} +{}", rest.len()),
    }
}

/// A slot's name.
pub fn slot_name(strings: &Strings, slot: MealSlot) -> &'static str {
    match slot {
        MealSlot::Breakfast => strings.breakfast,
        MealSlot::Lunch => strings.lunch,
        MealSlot::Dinner => strings.dinner,
        MealSlot::Snack => strings.snack,
    }
}

fn meal_card(meal: ReadSignal<Meal>, index: ReadSignal<usize>) -> impl IntoElement {
    let id = meal.with_untracked(|meal| meal.id.clone());
    let total = move || meal.with(Meal::total);
    appear(
        index.get_untracked() as u32,
        card_button(move || nav::push(Route::EditMeal(id.clone())))
            .flex_row()
            .items_center()
            .gap(px(14.0))
            .p(px(12.0))
            .pr(px(18.0))
            .child(thumbnail(meal))
            .child(
                view()
                    .flex_1()
                    .min_w(px(0.0))
                    .gap(px(3.0))
                    .child(
                        text(move || meal.with(meal_title))
                            .typo(Type::Headline)
                            .text_color(color::INK)
                            .number_of_lines(1),
                    )
                    .child(
                        text(move || {
                            meal.with(|meal| {
                                format!(
                                    "{} · {}",
                                    slot_name(s(), meal.slot),
                                    clock::time_label(meal.logged_at_ms)
                                )
                            })
                        })
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .number_of_lines(1),
                    )
                    .child(
                        view()
                            .flex_row()
                            .gap(px(10.0))
                            .pt(px(3.0))
                            .child(macro_mark(color::PROTEIN, move || total().protein))
                            .child(macro_mark(color::CARBS, move || total().carbs))
                            .child(macro_mark(color::FAT, move || total().fat)),
                    ),
            )
            .child(
                view()
                    .items_end()
                    .child(
                        text(move || format::kcal(total().kcal))
                            .typo(Type::Figure)
                            .tabular_nums()
                            .text_color(color::INK),
                    )
                    .child(
                        text(|| s().kcal)
                            .typo(Type::Caption)
                            .text_color(color::MUTED),
                    ),
            ),
    )
}

fn macro_mark(tint: AdaptiveColor, grams: impl Fn() -> f64 + 'static) -> impl IntoElement {
    view()
        .flex_row()
        .items_center()
        .gap(px(4.0))
        .child(view().size(px(6.0)).rounded_full().bg(tint))
        .child(
            text(move || format!("{}g", format::grams(grams())))
                .typo(Type::Caption)
                .tabular_nums()
                .text_color(color::MUTED),
        )
}

fn thumbnail(meal: ReadSignal<Meal>) -> impl IntoElement {
    let uri = move || meal.with(|meal| meal.photo.as_deref().and_then(photos::uri));
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
            .otherwise(|| icon(Icon::Utensils, 24.0, color::FAINT)),
        )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::nutrition::{Food, FoodSource, Nutrients};

    fn meal(title: Option<&str>, names: &[&str]) -> Meal {
        Meal {
            id: "m".into(),
            day: "2026-11-12".parse().unwrap(),
            logged_at_ms: 0,
            slot: MealSlot::Lunch,
            title: title.map(str::to_owned),
            foods: names
                .iter()
                .map(|name| Food {
                    id: 1,
                    name: (*name).to_owned(),
                    grams: 10.0,
                    per_100g: Nutrients::ZERO,
                    source: FoodSource::Manual,
                    confidence: None,
                    estimated_grams: None,
                })
                .collect(),
            photo: None,
            model: None,
        }
    }

    #[test]
    fn titles_fall_back_to_food_names() {
        assert_eq!(meal_title(&meal(Some("牛肉面"), &["面"])), "牛肉面");
        assert_eq!(meal_title(&meal(None, &["Rice"])), "Rice");
        assert_eq!(meal_title(&meal(Some(" "), &["Rice", "Egg"])), "Rice, Egg");
        assert_eq!(meal_title(&meal(None, &["A", "B", "C", "D"])), "A, B +2");
    }
}
