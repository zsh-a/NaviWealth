//! The confirmed meals, kept in the app's database ([`super::db`]) and
//! mirrored in a signal for the pages. The signal is private: pages read
//! through these functions and change meals only with [`save`], [`remove`]
//! and [`restore`]; each change is written to its row before returning.

use std::{
    collections::HashSet,
    sync::atomic::{AtomicU64, Ordering},
};

use nsh_core::{prelude::*, storage::Storage};
use rusqlite::{Connection, params};

use super::{clock, db};
use crate::domain::{
    meal::{Day, DaySummary, Meal, decode_meal, decode_meals, encode_meal, meals_of, summarize},
    nutrition::Food,
};

/// Where meals were kept before the database: moved once, then removed.
const LEGACY_KEY: &str = "meals.v1";

#[derive(Clone, Default, PartialEq)]
struct Meals(Vec<Meal>);

fn meals() -> Signal<Meals> {
    global::<Meals>()
}

/// Reads the kept meals; the root calls it once, after [`db::open`].
pub fn load() {
    let list = db::with(|connection| {
        move_legacy(connection);
        read_all(connection).unwrap_or_else(|error| {
            log::error!("meals: cannot read the database: {error}");
            Vec::new()
        })
    })
    .unwrap_or_default();
    meals().set(Meals(list));
}

/// Moves meals from the legacy key-value entry into the database in one
/// transaction, and removes the entry only after it commits. Meals already
/// in the database keep their row.
fn move_legacy(connection: &Connection) {
    let Some(raw) = Storage::get_item(LEGACY_KEY) else {
        return;
    };
    let legacy = decode_meals(&raw);
    let moved =
        (|| -> rusqlite::Result<()> {
            let tx = connection.unchecked_transaction()?;
            for meal in &legacy {
                tx.execute(
                "INSERT OR IGNORE INTO meals (id, day, logged_at_ms, body) VALUES (?1, ?2, ?3, ?4)",
                params![meal.id, meal.day.to_string(), meal.logged_at_ms, encode_meal(meal)],
            )?;
            }
            tx.commit()
        })();
    match moved {
        Ok(()) => {
            Storage::remove_item(LEGACY_KEY);
            log::info!("meals: moved {} meals into the database", legacy.len());
        }
        Err(error) => log::error!("meals: kept the legacy entry, the move failed: {error}"),
    }
}

fn read_all(connection: &Connection) -> rusqlite::Result<Vec<Meal>> {
    let mut statement = connection.prepare("SELECT body FROM meals ORDER BY logged_at_ms, id")?;
    let bodies = statement.query_map([], |row| row.get::<_, String>(0))?;
    let mut list = Vec::new();
    for body in bodies {
        if let Some(meal) = decode_meal(&body?) {
            list.push(meal);
        }
    }
    Ok(list)
}

fn write(meal: &Meal) {
    let written = db::with(|connection| {
        connection.execute(
            "INSERT INTO meals (id, day, logged_at_ms, body) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT (id) DO UPDATE SET
                day = excluded.day, logged_at_ms = excluded.logged_at_ms, body = excluded.body",
            params![
                meal.id,
                meal.day.to_string(),
                meal.logged_at_ms,
                encode_meal(meal)
            ],
        )
    });
    if let Some(Err(error)) = written {
        log::error!("meals: meal {} was not kept: {error}", meal.id);
    }
}

fn delete(id: &str) {
    let deleted =
        db::with(|connection| connection.execute("DELETE FROM meals WHERE id = ?1", params![id]));
    if let Some(Err(error)) = deleted {
        log::error!("meals: meal {id} was not deleted: {error}");
    }
}

/// `day`'s meals in the order they were logged (tracked).
pub fn on(day: Day) -> Vec<Meal> {
    meals().with(|meals| meals_of(&meals.0, day))
}

/// What `day`'s meals add up to (tracked).
pub fn summary(day: Day) -> DaySummary {
    meals().with(|meals| summarize(&meals.0, day))
}

/// The meal `id`, while it exists (tracked).
pub fn get(id: &str) -> Option<Meal> {
    meals().with(|meals| meals.0.iter().find(|meal| meal.id == id).cloned())
}

/// Adds `meal`, or replaces the one with its id.
pub fn save(meal: Meal) {
    write(&meal);
    meals().update(
        |meals| match meals.0.iter_mut().find(|kept| kept.id == meal.id) {
            Some(kept) => *kept = meal,
            None => meals.0.push(meal),
        },
    );
}

/// Removes the meal `id` and gives it back (to undo). Its photo stays
/// until the next launch sweeps photos no meal refers to.
pub fn remove(id: &str) -> Option<Meal> {
    let mut removed = None;
    meals().update(|meals| {
        if let Some(index) = meals.0.iter().position(|meal| meal.id == id) {
            removed = Some(meals.0.remove(index));
            delete(id);
        }
    });
    removed
}

/// Puts back a meal [`remove`] took.
pub fn restore(meal: Meal) {
    save(meal);
}

/// The most recently eaten foods, one per name (case-insensitive), newest
/// first: what the food editor offers to add again.
pub fn recent_foods(limit: usize) -> Vec<Food> {
    meals().with_untracked(|meals| latest_foods(&meals.0, limit))
}

fn latest_foods(meals: &[Meal], limit: usize) -> Vec<Food> {
    let mut ordered: Vec<&Meal> = meals.iter().collect();
    ordered.sort_by_key(|meal| std::cmp::Reverse(meal.logged_at_ms));
    let mut seen = HashSet::new();
    ordered
        .into_iter()
        .flat_map(|meal| meal.foods.iter())
        .filter(|food| seen.insert(food.name.trim().to_lowercase()))
        .take(limit)
        .cloned()
        .collect()
}

/// The photos the kept meals refer to.
pub fn photo_names() -> HashSet<String> {
    meals().with_untracked(|meals| meals.0.iter().filter_map(|m| m.photo.clone()).collect())
}

/// Every kept meal (tracked), for previews and tests.
pub fn all() -> Vec<Meal> {
    meals().with(|meals| meals.0.clone())
}

static NEXT: AtomicU64 = AtomicU64::new(0);

/// A new meal id, unique on this device.
pub fn new_meal_id() -> String {
    format!(
        "m{}-{}",
        clock::now_ms(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    )
}

/// A new food id, unique on this device.
pub fn new_food_id() -> u64 {
    let base = (clock::now_ms().max(0) as u64) << 12;
    base | (NEXT.fetch_add(1, Ordering::Relaxed) & 0xfff)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{
        meal::MealSlot,
        nutrition::{FoodSource, Nutrients},
    };

    fn meal(id: &str, at: i64, names: &[&str]) -> Meal {
        Meal {
            id: id.to_owned(),
            day: Day("2026-11-13".parse().unwrap()),
            logged_at_ms: at,
            slot: MealSlot::Lunch,
            title: None,
            foods: names
                .iter()
                .enumerate()
                .map(|(index, name)| Food {
                    id: at as u64 * 10 + index as u64,
                    name: (*name).to_owned(),
                    grams: 100.0,
                    per_100g: Nutrients::new(100.0, 1.0, 1.0, 1.0),
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
    fn recent_foods_are_newest_first_and_one_per_name() {
        let meals = vec![
            meal("old", 1, &["Rice", "Egg"]),
            meal("new", 3, &["rice ", "Tofu"]),
            meal("mid", 2, &["Apple"]),
        ];
        let names: Vec<_> = latest_foods(&meals, 10)
            .into_iter()
            .map(|food| food.name)
            .collect();
        assert_eq!(names, ["rice ", "Tofu", "Apple", "Egg"]);
        assert_eq!(latest_foods(&meals, 2).len(), 2);
    }
}
