//! Records: everything logged, newest day first, each day with what its
//! meals add up to; all, meals only or weights only. Older days come on
//! request so a long history stays light.

use std::collections::BTreeMap;

use nsh_base::button;
use nsh_core::{geometry::Point, prelude::*};

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
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color,
        feedback::empty_state,
        icon,
        segmented::{Segment, segmented},
        space,
        surface::{card, hairline},
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
    let sheets = Sheets::get();
    // The one day the calendar opened, shown alone until All days.
    let focus = signal(None::<Day>);
    let list = element_ref();
    effect(move || {
        let Some(day) = sheets.jump_to.get() else {
            return;
        };
        untracked(|| {
            sheets.jump_to.set(None);
            filter.set(Filter::All);
            focus.set(Some(day));
        });
        list.scroll_to(
            Point {
                x: px(0.0),
                y: px(0.0),
            },
            false,
        );
    });
    // A focused day whose records are all gone falls back to every day.
    effect(move || {
        if let Some(day) = focus.get()
            && !days.with(|d| d.iter().any(|r| r.day == day))
        {
            untracked(|| focus.set(None));
        }
    });
    // The days the list shows: the focused day, or the filter's days.
    let listed = computed(move || match focus.get() {
        Some(day) => days.with(|d| d.iter().filter(|d| d.day == day).cloned().collect()),
        None => days.with(|d| d.iter().take(shown.get()).cloned().collect::<Vec<_>>()),
    });
    effect(move || {
        let names: Vec<String> = listed.with(|days| {
            days.iter()
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
    scroll().flex_1().element_ref(&list).child(
        view()
            .px(px(space::GUTTER))
            .pt_safe_area_plus(px(10.0))
            .pb(move || px(dock_clearance()))
            .gap_5()
            .child(
                view()
                    .flex_row()
                    .items_center()
                    .gap_3()
                    .px(px(4.0))
                    .pt_2()
                    .child(
                        view()
                            .flex_1()
                            .min_w(px(0.0))
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
                    .child(
                        IconBtn::new(Icon::Calendar, || s().go_to_day.into())
                            .variant(Variant::Secondary)
                            .on_press(move || sheets.jump.set(true)),
                    ),
            )
            .child(
                when(
                    move || focus.get().is_some(),
                    move || focus_bar(focus, days),
                )
                .otherwise(move || {
                    segmented(
                        vec![
                            Segment::new(Filter::All, || s().all_records.into()),
                            Segment::new(Filter::Meals, || s().meals.into()),
                            Segment::new(Filter::Weight, || s().weight.into()),
                        ],
                        move || filter.get(),
                        move |f| filter.set(f),
                    )
                }),
            )
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
                            move || listed.get(),
                            |d: &DayRecords| d.day,
                            |d, _| {
                                dynamic(move || {
                                    let d = d.get();
                                    untracked(move || day_section(d))
                                })
                            },
                        ))
                        .child(when(
                            move || focus.get().is_none() && days.with(Vec::len) > shown.get(),
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

/// Over a focused day: its short date, steps to the days with records before and after it,
/// and All days back to the whole list.
fn focus_bar(focus: Signal<Option<Day>>, days: Memo<Vec<DayRecords>>) -> impl IntoElement {
    // Days are newest first: the next index is the earlier day.
    let step = move |earlier: bool| {
        let day = focus.get()?;
        days.with(|d| {
            let at = d.iter().position(|r| r.day == day)?;
            let to = if earlier {
                at.checked_add(1)?
            } else {
                at.checked_sub(1)?
            };
            d.get(to).map(|r| r.day)
        })
    };
    view()
        .flex_row()
        .items_center()
        .gap_2()
        .child(
            IconBtn::new(Icon::ChevronLeft, || s().previous_day.into())
                .on_press(move || {
                    if let Some(day) = untracked(|| step(true)) {
                        focus.set(Some(day));
                    }
                })
                .disabled(move || step(true).is_none()),
        )
        .child(
            text(move || focus.get().map(|d| s().short_date(d)).unwrap_or_default())
                .typo(Type::Headline)
                .text_color(color::INK)
                .text_center()
                .number_of_lines(1)
                .flex_1(),
        )
        .child(
            IconBtn::new(Icon::ChevronRight, || s().next_day.into())
                .on_press(move || {
                    if let Some(day) = untracked(|| step(false)) {
                        focus.set(Some(day));
                    }
                })
                .disabled(move || step(false).is_none()),
        )
        .child(
            Btn::tonal()
                .size(Size::Small)
                .label(|| s().all_days.into())
                .on_press(move || focus.set(None)),
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
    let kcal = (records.meals > 0).then(|| format!("{} {}", format::kcal(records.kcal), s().kcal));
    let weight = records.weight.map(|w| {
        button()
            .on_press(move || sheets.weight.set(Some(w.day)))
            .flex_row()
            .items_center()
            .gap(px(4.0))
            .h(px(28.0))
            .px(px(10.0))
            .rounded_full()
            .bg(color::SURFACE_2)
            .active(|s| s.bg(color::SUNKEN))
            .accessibility_label({
                let label = format!(
                    "{}, {}, {} kg",
                    s().edit_weight,
                    s().long_date(w.day),
                    s().kg(w.kg)
                );
                move || Some(label.clone().into())
            })
            .child(icon(Icon::Scale, 13.0, color::MUTED))
            .child(
                text(format!("{} kg", s().kg(w.kg)))
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_color(color::BODY),
            )
    });
    view()
        .gap_3()
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .min_h(px(32.0))
                .px(px(4.0))
                .child(
                    text(title)
                        .typo(Type::Headline)
                        .text_color(color::INK)
                        .number_of_lines(1)
                        .flex_1()
                        .role(AccessibilityRole::Header),
                )
                .child(kcal.map(|kcal| {
                    text(kcal)
                        .typo(Type::Subhead)
                        .tabular_nums()
                        .text_color(color::MUTED)
                        .number_of_lines(1)
                }))
                .child(weight),
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
