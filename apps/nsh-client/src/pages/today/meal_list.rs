//! The day's meals, newest first, as rows of one card led by each meal's
//! photo; a calm empty state when the day has none.

use navi_finance::journal::Transaction;
use nsh_core::prelude::*;

use crate::{
    data::{clock, finance, meals, photos},
    domain::meal::{Day, Meal, MealSlot},
    i18n::{Strings, s},
    pages::{
        finance::transaction_row,
        home::Sheets,
        rows::{divider, leading_width, meal_row, text_inset},
    },
    ui::{
        Type, Typo, color,
        surface::{card, section_header},
    },
};

#[derive(Clone, PartialEq)]
enum Record {
    Meal(Meal),
    Transaction(Transaction),
}

impl Record {
    fn key(&self) -> String {
        match self {
            Self::Meal(m) => format!("meal:{}", m.id),
            Self::Transaction(t) => format!("transaction:{}", t.id),
        }
    }
}

/// The records section of `day`.
pub fn meal_list(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let sheets = Sheets::get();
    let list = computed(move || {
        let mut records: Vec<Record> = meals::on(day())
            .into_iter()
            .map(Record::Meal)
            .chain(
                finance::transactions_snapshot()
                    .iter()
                    .filter(|t| t.at.date() == day().0)
                    .cloned()
                    .map(Record::Transaction),
            )
            .collect();
        records.sort_by_key(|r| {
            std::cmp::Reverse(match r {
                Record::Meal(m) => clock::zoned(m.logged_at_ms).time(),
                Record::Transaction(t) => t.at.time(),
            })
        });
        records
    });
    let leading = computed(move || {
        list.with(|records| {
            leading_width(
                records
                    .iter()
                    .any(|r| matches!(r, Record::Meal(meal) if meal.photo.is_some())),
            )
        })
    });
    // Kept photos load off the engine thread as the day's meals change.
    effect(move || {
        let names: Vec<String> = list.with(|list| {
            list.iter()
                .filter_map(|r| match r {
                    Record::Meal(m) => m.photo.clone(),
                    Record::Transaction(_) => None,
                })
                .collect()
        });
        if !names.is_empty() {
            spawn(photos::load(names));
        }
    });
    let count = move || list.with(Vec::len);
    view()
        .gap_3()
        .child(section_header(
            move || s().todays_records,
            Some(
                text(move || {
                    let n = count();
                    if n == 0 {
                        return String::new();
                    }
                    let meals_only = list.with(|l| l.iter().all(|r| matches!(r, Record::Meal(_))));
                    s().records_summary(n, meals_only)
                })
                .typo(Type::Subhead)
                .tabular_nums()
                .text_color(color::MUTED)
                .flex_shrink(1.0_f32)
                .min_w(px(0.0))
                .into_element(),
            ),
        ))
        .child(
            when(
                move || count() > 0,
                move || {
                    card().overflow_hidden().child(each(
                        list,
                        |record: &Record| record.key(),
                        move |record, index| {
                            dynamic(move || {
                                let record = record.get();
                                let width = leading.get();
                                let has_divider = index.get() > 0;
                                untracked(move || {
                                    let row = match record {
                                        Record::Meal(meal) => meal_row(meal, width).into_element(),
                                        Record::Transaction(transaction) => {
                                            let id = transaction.id.clone();
                                            transaction_row(transaction, width, move || {
                                                sheets.finance.set(Some(id.clone()))
                                            })
                                            .into_element()
                                        }
                                    };
                                    view()
                                        .child(has_divider.then(|| divider(text_inset(width))))
                                        .child(row)
                                })
                            })
                        },
                    ))
                },
            )
            .otherwise(move || {
                text(move || {
                    if day() == clock::today() {
                        s().empty_today
                    } else {
                        s().empty_day
                    }
                })
                .typo(Type::Subhead)
                .text_color(color::MUTED)
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
            prompt_version: None,
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
