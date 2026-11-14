//! Records: everything logged, newest day first, each day with what its
//! meals add up to; all, meals only or weights only. Older days come on
//! request so a long history stays light.

use std::collections::BTreeMap;

use nsh_core::prelude::*;

use super::{
    drafts::drafts_section,
    home::{Sheets, dock_clearance},
    rows::{INSET, meal_row, weight_row},
};
use crate::{
    data::{clock, meals, photos, weights},
    domain::{
        format,
        meal::{Day, Meal},
        weight::Weight,
    },
    i18n::s,
    ui::{
        Btn, Icon, Type, Typo, color,
        feedback::empty_state,
        icon,
        segmented::{Segment, segmented},
        space,
        surface::{card, hairline, row_button},
    },
};

/// Days shown at first, and added by Show earlier.
const PAGE: usize = 21;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Filter {
    All,
    Meals,
    Weight,
}

/// One row of a day.
#[derive(Clone, PartialEq)]
enum Entry {
    Meal(Meal),
    Weight(Weight),
}

/// A day with entries, newest entry first.
#[derive(Clone, PartialEq)]
struct DayRecords {
    day: Day,
    kcal: f64,
    meals: usize,
    weight: Option<Weight>,
    entries: Vec<Entry>,
}

pub fn records_tab() -> impl IntoElement {
    let filter = signal(Filter::All);
    let shown = signal(PAGE);
    let days = computed(move || group(meals::all(), weights::all(), filter.get()));
    effect(move || {
        let names: Vec<String> = days.with(|days| {
            days.iter()
                .take(shown.get())
                .flat_map(|d| d.entries.iter())
                .filter_map(|e| match e {
                    Entry::Meal(meal) => meal.photo.clone(),
                    Entry::Weight(..) => None,
                })
                .collect()
        });
        if !names.is_empty() {
            spawn(photos::load(names));
        }
    });
    scroll().flex_1().child(
        view()
            .px(px(space::GUTTER))
            .pt_safe_area_plus(px(10.0))
            .pb(move || px(dock_clearance()))
            .gap_5()
            .child(
                view()
                    .px(px(4.0))
                    .pt_2()
                    .gap(px(2.0))
                    .child(
                        text(|| s().history)
                            .typo(Type::Subhead)
                            .text_color(color::MUTED),
                    )
                    .child(
                        text(|| s().records)
                            .typo(Type::LargeTitle)
                            .text_color(color::INK)
                            .role(AccessibilityRole::Header),
                    ),
            )
            .child(segmented(
                vec![
                    Segment::new(Filter::All, || s().all_records.into()),
                    Segment::new(Filter::Meals, || s().meals.into()),
                    Segment::new(Filter::Weight, || s().weight.into()),
                ],
                move || filter.get(),
                move |f| filter.set(f),
            ))
            .child(drafts_section(true))
            .child(
                when(
                    move || days.with(Vec::is_empty),
                    || {
                        card().child(empty_state(
                            Icon::List,
                            || s().no_records,
                            || s().no_records_body,
                        ))
                    },
                )
                .otherwise(move || {
                    view()
                        .gap_5()
                        .child(each(
                            move || {
                                days.with(|d| {
                                    d.iter().take(shown.get()).cloned().collect::<Vec<_>>()
                                })
                            },
                            |d: &DayRecords| d.day,
                            |d, _| {
                                dynamic(move || {
                                    let d = d.get();
                                    untracked(move || day_section(d))
                                })
                            },
                        ))
                        .child(when(
                            move || days.with(Vec::len) > shown.get(),
                            move || {
                                Btn::secondary()
                                    .label(|| s().show_earlier.into())
                                    .on_press(move || shown.update(|n| *n += PAGE))
                            },
                        ))
                }),
            ),
    )
}

fn day_section(records: DayRecords) -> impl IntoElement {
    let sheets = Sheets::get();
    let today = untracked(clock::today);
    let title = match today.days_since(records.day) {
        0 => s().today.to_owned(),
        1 => s().yesterday.to_owned(),
        _ => s().long_date(records.day),
    };
    let mut summary = Vec::new();
    if records.meals > 0 {
        summary.push(format!(
            "{} {} · {}",
            format::kcal(records.kcal),
            s().kcal,
            s().meal_count(records.meals)
        ));
    }
    if let Some(w) = records.weight {
        summary.push(format!("{} kg", s().kg(w.kg)));
    }
    let summary = summary.join(" · ");
    let has_summary = !summary.is_empty();
    let summary_text = text(summary)
        .typo(Type::Subhead)
        .tabular_nums()
        .text_color(color::MUTED);
    let summary = match records.weight {
        Some(w) => row_button(move || sheets.weight.set(Some(w.day)))
            .min_h(px(48.0))
            .gap_2()
            .accessibility_label({
                let label = format!(
                    "{}, {}, {} kg",
                    s().edit_weight,
                    s().long_date(w.day),
                    s().kg(w.kg)
                );
                move || Some(label.clone().into())
            })
            .child(summary_text.flex_1())
            .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
            .into_element(),
        None => summary_text.into_element(),
    };
    view()
        .gap_3()
        .child(
            view()
                .gap(px(2.0))
                .px(px(4.0))
                .child(
                    text(title)
                        .typo(Type::Headline)
                        .text_color(color::INK)
                        .role(AccessibilityRole::Header),
                )
                .child(has_summary.then_some(summary)),
        )
        .child((!records.entries.is_empty()).then(|| {
            card()
                .overflow_hidden()
                .children(
                    records
                        .entries
                        .into_iter()
                        .enumerate()
                        .map(move |(i, entry)| {
                            let row = match entry {
                                Entry::Meal(meal) => meal_row(meal).into_element(),
                                Entry::Weight(w) => {
                                    weight_row(w, move || sheets.weight.set(Some(w.day)))
                                        .into_element()
                                }
                            };
                            view().child((i > 0).then(|| hairline(INSET))).child(row)
                        }),
                )
        }))
}

/// Newest days first. All folds weight into the header; Weight keeps editable rows.
fn group(meals: Vec<Meal>, weights: Vec<Weight>, filter: Filter) -> Vec<DayRecords> {
    let mut days: BTreeMap<Day, DayRecords> = BTreeMap::new();
    fn at(days: &mut BTreeMap<Day, DayRecords>, day: Day) -> &mut DayRecords {
        days.entry(day).or_insert_with(|| DayRecords {
            day,
            kcal: 0.0,
            meals: 0,
            weight: None,
            entries: Vec::new(),
        })
    }
    if filter != Filter::Weight {
        for meal in meals {
            let d = at(&mut days, meal.day);
            d.kcal += meal.total().kcal;
            d.meals += 1;
            d.entries.push(Entry::Meal(meal));
        }
    }
    if filter != Filter::Meals {
        for w in weights {
            let day = at(&mut days, w.day);
            if filter == Filter::All {
                day.weight = Some(w);
            } else {
                day.entries.push(Entry::Weight(w));
            }
        }
    }
    let at_ms = |e: &Entry| match e {
        Entry::Meal(m) => m.logged_at_ms,
        Entry::Weight(w) => w.logged_at_ms,
    };
    days.into_values()
        .rev()
        .map(|mut d| {
            d.entries.sort_by_key(|e| std::cmp::Reverse(at_ms(e)));
            d
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{
        meal::MealSlot,
        nutrition::{Food, FoodSource, Nutrients},
    };

    fn day(text: &str) -> Day {
        text.parse().unwrap()
    }

    fn meal(id: &str, on: &str, at: i64, kcal: f64) -> Meal {
        Meal {
            id: id.into(),
            day: day(on),
            logged_at_ms: at,
            slot: MealSlot::Lunch,
            title: None,
            foods: vec![Food {
                id: 1,
                name: "Rice".into(),
                grams: 100.0,
                per_100g: Nutrients::new(kcal, 1.0, 1.0, 1.0),
                source: FoodSource::Manual,
                confidence: None,
                estimated_grams: None,
            }],
            photo: None,
            model: None,
            prompt_version: None,
        }
    }

    fn weight(on: &str, kg: f64, at: i64) -> Weight {
        Weight {
            day: day(on),
            kg,
            logged_at_ms: at,
        }
    }

    #[test]
    fn all_folds_weights_into_headers_and_retains_weight_only_days() {
        let meals = vec![
            meal("a", "2026-11-12", 1, 300.0),
            meal("b", "2026-11-13", 3, 500.0),
            meal("c", "2026-11-13", 5, 200.0),
        ];
        let weights = vec![weight("2026-11-11", 68.9, 0), weight("2026-11-13", 68.4, 4)];
        let days = group(meals.clone(), weights.clone(), Filter::All);
        assert_eq!(
            days.iter().map(|d| d.day.to_string()).collect::<Vec<_>>(),
            ["2026-11-13", "2026-11-12", "2026-11-11"]
        );
        assert_eq!((days[0].kcal, days[0].meals), (700.0, 2));
        assert!(matches!(&days[0].entries[0], Entry::Meal(m) if m.id == "c"));
        assert!(matches!(&days[0].entries[1], Entry::Meal(m) if m.id == "b"));
        assert_eq!(days[0].entries.len(), 2);
        assert_eq!(days[0].weight.unwrap().kg, 68.4);
        assert!(days[2].entries.is_empty());
        assert_eq!(days[2].weight.unwrap().kg, 68.9);

        assert_eq!(
            group(meals.clone(), weights.clone(), Filter::Meals).len(),
            2
        );
        let only_weights = group(meals, weights, Filter::Weight);
        assert_eq!(only_weights.len(), 2);
        assert_eq!(only_weights[0].meals, 0);
        assert!(only_weights[0].weight.is_none());
        assert!(matches!(only_weights[0].entries[0], Entry::Weight(w) if w.kg == 68.4));
        let only_meals = group(
            vec![meal("a", "2026-11-13", 1, 300.0)],
            vec![weight("2026-11-13", 72.0, 0)],
            Filter::Meals,
        );
        assert!(only_meals[0].weight.is_none());
    }
}
