//! The confirmed meals, kept in the app's database ([`super::db`]) and
//! mirrored in a signal for the pages. The signal is private: pages read
//! through these functions and change meals only with [`save`], [`remove`]
//! and [`restore`]; each change is written to its row before returning.

use std::{
    collections::HashSet,
    sync::atomic::{AtomicU64, Ordering},
};

use navi_health::store;
use nsh_core::{prelude::*, storage::Storage};
use rusqlite::Connection;

use super::{clock, db};
use crate::domain::{
    meal::{Day, DaySummary, Meal, meals_of, summarize},
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
pub fn load() -> Result<(), String> {
    let list = db::with(|connection| {
        move_legacy(connection)?;
        store::meals(connection).map_err(|error| error.to_string())
    })
    .ok_or("the database is not open")??;
    meals().set(Meals(list));
    Ok(())
}

/// The legacy entry is removed only after every record validates and the
/// complete inventory commits. A malformed entry remains recoverable.
fn move_legacy(connection: &Connection) -> Result<(), String> {
    let Some(raw) = Storage::get_item(LEGACY_KEY) else {
        return Ok(());
    };
    #[derive(serde::Deserialize)]
    struct Legacy {
        version: u32,
        meals: Vec<Meal>,
    }
    let legacy: Legacy = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if legacy.version != 1 || legacy.meals.iter().any(|meal| !meal.is_valid()) {
        return Err("invalid legacy meals".into());
    }
    store::import_legacy_meals(connection, &legacy.meals).map_err(|e| e.to_string())?;
    Storage::remove_item(LEGACY_KEY);
    log::debug!("meals: migrated {} records", legacy.meals.len());
    Ok(())
}

/// Publish only a committed meal. Cross-domain confirmation uses this after
/// its host-owned transaction succeeds.
pub(super) fn reflect(meal: Meal) {
    meals().update(
        |meals| match meals.0.iter_mut().find(|kept| kept.id == meal.id) {
            Some(kept) => *kept = meal,
            None => meals.0.push(meal),
        },
    );
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
pub fn save(meal: Meal) -> Result<(), String> {
    save_review(meal, None)
}

/// A legacy recognition review consumes its draft in the same transaction as
/// the confirmed meal, just like unified capture.
pub fn save_review(meal: Meal, pending_id: Option<&str>) -> Result<(), String> {
    db::with(|connection| -> Result<(), String> {
        let tx = connection
            .unchecked_transaction()
            .map_err(|e| e.to_string())?;
        store::save_meal(&tx, &meal).map_err(|e| e.to_string())?;
        if let Some(id) = pending_id {
            let removed = tx
                .execute("DELETE FROM meal_drafts WHERE id=?1", [id])
                .map_err(|e| e.to_string())?;
            if removed != 1 {
                return Err("draft no longer exists".into());
            }
        }
        tx.commit().map_err(|e| e.to_string())
    })
    .ok_or("the database is not open")??;
    reflect(meal);
    if let Some(id) = pending_id {
        super::pending::forget(id);
    }
    Ok(())
}

/// Removes a committed meal and returns it for Undo only after success.
pub fn remove(id: &str) -> Result<Option<Meal>, String> {
    let removed = db::with(|c| store::remove_meal(c, id))
        .ok_or("the database is not open")?
        .map_err(|e| e.to_string())?;
    meals().update(|meals| meals.0.retain(|meal| meal.id != id));
    Ok(removed)
}

pub fn restore(meal: Meal) -> Result<(), String> {
    save(meal)
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
