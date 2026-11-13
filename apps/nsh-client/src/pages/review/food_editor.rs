//! Editing one food: its name, the amount eaten (with portion shortcuts
//! around the estimate), and its nutrients per 100 g behind a disclosure.
//! The energy it adds is recalculated as the user types.

use nsh_core::prelude::*;

use super::draft::{Draft, Editing};
use crate::{
    data::meals,
    domain::{
        format::{self, field_number, parse_number},
        nutrition::{Food, FoodSource, MAX_GRAMS, Nutrients, clean_name, valid_grams},
    },
    i18n::s,
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant,
        button::chip,
        color,
        field::{field, note, number_input, text_input},
        surface::disclosure,
    },
};

const PORTIONS: [(f64, &str); 6] = [
    (0.5, "½×"),
    (0.75, "¾×"),
    (1.0, "1×"),
    (1.25, "1¼×"),
    (1.5, "1½×"),
    (2.0, "2×"),
];

/// The editor's content, made on each opening for the food the draft's
/// `editing` names.
#[component]
pub fn FoodEditor() -> impl IntoElement {
    let draft = use_context::<Draft>().expect("the review page provides its draft");
    let original = match untracked(|| draft.editing.get()) {
        Some(Editing::Food(id)) => draft
            .foods
            .with_untracked(|foods| foods.iter().find(|food| food.id == id).cloned()),
        _ => None,
    };
    let is_new = original.is_none();
    let base = original.clone().unwrap_or_else(|| Food {
        id: meals::new_food_id(),
        name: String::new(),
        grams: 100.0,
        per_100g: Nutrients::ZERO,
        source: FoodSource::Manual,
        confidence: None,
        estimated_grams: None,
    });
    let number = |value: f64| {
        if is_new {
            String::new()
        } else {
            field_number(value)
        }
    };
    let initial = [
        number(base.per_100g.kcal),
        number(base.per_100g.protein),
        number(base.per_100g.carbs),
        number(base.per_100g.fat),
    ];
    let name = signal(base.name.clone());
    let grams = signal(if is_new {
        String::new()
    } else {
        field_number(base.grams)
    });
    let fields = initial.clone().map(signal);
    let details_open = signal(is_new);
    let attempted = signal(false);

    let parsed_grams = move || grams.with(|g| parse_number(g));
    let per_100g = move || {
        let value = |index: usize| fields[index].with(|f| parse_number(f)).unwrap_or(0.0);
        let mut nutrients = Nutrients::new(value(0), value(1), value(2), value(3));
        if fields[0].with(|f| f.trim().is_empty()) && nutrients.macro_kcal() > 0.0 {
            nutrients.kcal = nutrients.macro_kcal().round();
        }
        nutrients
    };
    let name_error = move || attempted.get() && name.with(|n| n.trim().is_empty());
    let grams_error = move || attempted.get() && !parsed_grams().is_some_and(valid_grams);
    // A food needs its nutrition: an empty form is not a 0 kcal food.
    let nutrients_given = move || {
        fields
            .iter()
            .any(|field| field.with(|f| !f.trim().is_empty()))
    };
    let nutrients_ok = move || nutrients_given() && per_100g().is_valid_per_100g();
    let nutrients_error = move || attempted.get() && !nutrients_ok();

    let base_for_done = base.clone();
    let done = move || {
        attempted.set(true);
        let clean = clean_name(&name.get_untracked());
        let grams_value = untracked(parsed_grams).filter(|g| valid_grams(*g));
        let nutrients = untracked(per_100g);
        let nutrients_valid = untracked(nutrients_ok);
        if !nutrients_valid {
            details_open.set(true);
        }
        let (Some(grams_value), false, true) = (grams_value, clean.is_empty(), nutrients_valid)
        else {
            return;
        };
        let changed = fields
            .iter()
            .zip(&initial)
            .any(|(field, initial)| field.with_untracked(|f| f.trim() != initial.trim()));
        let food = Food {
            id: base_for_done.id,
            name: clean,
            grams: grams_value,
            per_100g: if changed || is_new {
                nutrients
            } else {
                base_for_done.per_100g
            },
            source: if changed || is_new {
                FoodSource::Manual
            } else {
                base_for_done.source.clone()
            },
            confidence: None,
            estimated_grams: base_for_done.estimated_grams,
        };
        if is_new {
            draft.add_food(food);
        } else {
            draft.update_food(food);
        }
        draft.editing.set(None);
    };
    let food_id = base.id;
    let step = move |sign: f64| {
        let current = untracked(parsed_grams).unwrap_or(0.0);
        let by = if current < 50.0 { 5.0 } else { 10.0 };
        let next = ((current / by).round() * by + sign * by).clamp(by, MAX_GRAMS);
        grams.set(field_number(next));
    };
    let estimate = base.estimated_grams;
    let source = base.source.clone();
    let model = draft.model.get_untracked();

    view()
        .gap_5()
        .child(
            view()
                .flex_row()
                .items_center()
                .justify_between()
                .child(
                    text(move || if is_new { s().add_food } else { s().edit_food })
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .role(AccessibilityRole::Header),
                )
                .child((!is_new).then(|| {
                    Btn::new(Variant::Danger)
                        .size(Size::Small)
                        .icon(Icon::Trash)
                        .label(|| s().remove.into())
                        .on_press(move || {
                            draft.remove_food(food_id);
                            draft.editing.set(None);
                        })
                })),
        )
        .child(
            field(
                || s().name,
                text_input(name)
                    .placeholder(|| s().name_placeholder.to_owned())
                    .max_length(80_u32)
                    .style_when(name_error, |s| s.border_color(color::DANGER)),
            )
            .child(note(
                move || name_error().then(|| s().error_name.into()),
                || true,
            )),
        )
        .child(
            field(
                || s().amount_eaten,
                view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .child(
                        IconBtn::new(Icon::Minus, || s().decrease.into())
                            .variant(Variant::Tonal)
                            .side(48.0)
                            .on_press(move || step(-1.0)),
                    )
                    .child(view().flex_1().child(number_input(
                        grams,
                        || s().grams_unit,
                        || s().amount_eaten,
                    )))
                    .child(
                        IconBtn::new(Icon::Plus, || s().increase.into())
                            .variant(Variant::Tonal)
                            .side(48.0)
                            .on_press(move || step(1.0)),
                    ),
            )
            .child(estimate.map(|estimate| {
                // One row of equal pills, however narrow the screen.
                view().flex_row().gap(px(6.0)).children(PORTIONS.iter().map(
                    move |(factor, label)| {
                        let target = (estimate * factor).round();
                        chip(
                            move || (*label).into(),
                            move || parsed_grams().is_some_and(|g| (g - target).abs() < 0.5),
                            move || grams.set(field_number(target)),
                        )
                        .flex_1()
                        .min_w(px(0.0))
                        .px_1()
                    },
                ))
            }))
            .child(note(
                move || grams_error().then(|| s().error_grams.into()),
                || true,
            )),
        )
        .child(when(
            move || parsed_grams().is_some_and(|g| g > 0.0),
            move || {
                view()
                    .gap(px(2.0))
                    .child(
                        text(move || {
                            let grams = parsed_grams().unwrap_or(0.0);
                            let eaten = per_100g().for_grams(grams);
                            s().portion(grams, eaten.kcal)
                        })
                        .typo(Type::Title)
                        .tabular_nums()
                        .text_color(color::INK),
                    )
                    .child(
                        text(move || {
                            let eaten = per_100g().for_grams(parsed_grams().unwrap_or(0.0));
                            format!(
                                "{} {} g · {} {} g · {} {} g",
                                s().protein,
                                format::grams(eaten.protein),
                                s().carbs,
                                format::grams(eaten.carbs),
                                s().fat,
                                format::grams(eaten.fat)
                            )
                        })
                        .typo(Type::Subhead)
                        .tabular_nums()
                        .text_color(color::MUTED),
                    )
            },
        ))
        .child(
            view()
                .gap_3()
                .child(disclosure(details_open, || s().per_100g.into()))
                .child(when(details_open, move || {
                    view()
                        .gap_3()
                        .child(
                            view()
                                .flex_row()
                                .gap_3()
                                .child(nutrient(fields[0], || s().energy, || s().kcal))
                                .child(nutrient(fields[1], || s().protein, || "g")),
                        )
                        .child(
                            view()
                                .flex_row()
                                .gap_3()
                                .child(nutrient(fields[2], || s().carbs, || "g"))
                                .child(nutrient(fields[3], || s().fat, || "g")),
                        )
                        .child(note(
                            move || nutrients_error().then(|| s().error_nutrients.into()),
                            || true,
                        ))
                })),
        )
        .child(
            text(move || match &source {
                FoodSource::Estimate => s().source_estimate(model.as_deref().unwrap_or("AI")),
                FoodSource::Catalog { fdc_id } => s().source_catalog(fdc_id),
                FoodSource::Manual => s().source_manual.to_owned(),
            })
            .typo(Type::Caption)
            .text_color(color::FAINT),
        )
        .child(
            view()
                .flex_row()
                .gap_3()
                .child(
                    Btn::secondary()
                        .label(|| s().cancel.into())
                        .on_press(move || draft.editing.set(None))
                        .flex_1(),
                )
                .child(
                    Btn::primary()
                        .label(|| s().done.into())
                        .on_press(done)
                        .flex_1(),
                ),
        )
}

fn nutrient(
    value: Signal<String>,
    label: fn() -> &'static str,
    unit: fn() -> &'static str,
) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .child(field(label, number_input(value, unit, label)))
}
