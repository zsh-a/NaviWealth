//! The confirmed meals, kept in the app's device storage. Their signal is
//! private: pages read through these functions and change meals only with
//! [`save`], [`remove`] and [`restore`].

use std::{
    collections::HashSet,
    sync::atomic::{AtomicU64, Ordering},
};

use nsh_core::{prelude::*, storage::Storage};

use super::{clock, photos};
use crate::domain::meal::{
    Day, DaySummary, MAX_KEPT_MEALS, Meal, decode_meals, encode_meals, meals_of, summarize,
};

const KEY: &str = "meals.v1";

#[derive(Clone, Default, PartialEq)]
struct Meals(Vec<Meal>);

fn meals() -> Signal<Meals> {
    global::<Meals>()
}

/// Reads the kept meals; the root calls it once.
pub fn load() {
    let list = Storage::get_item(KEY)
        .map(|raw| decode_meals(&raw))
        .unwrap_or_default();
    meals().set(Meals(list));
}

fn persist(list: &[Meal]) {
    if Storage::set_item(KEY, encode_meals(list)).is_err() {
        log::error!("meals: device storage is full; the last change was not kept");
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

/// Adds `meal`, or replaces the one with its id. The oldest meals beyond
/// the kept maximum go, with their photos.
pub fn save(meal: Meal) {
    let mut dropped = Vec::new();
    meals().update(|meals| {
        match meals.0.iter_mut().find(|kept| kept.id == meal.id) {
            Some(kept) => *kept = meal,
            None => meals.0.push(meal),
        }
        if meals.0.len() > MAX_KEPT_MEALS {
            meals.0.sort_by_key(|meal| meal.logged_at_ms);
            let excess = meals.0.len() - MAX_KEPT_MEALS;
            dropped.extend(meals.0.drain(..excess));
        }
        persist(&meals.0);
    });
    for meal in dropped {
        if let Some(photo) = meal.photo {
            photos::delete(&photo);
        }
    }
}

/// Removes the meal `id` and gives it back (to undo). Its photo stays
/// until the next launch sweeps photos no meal refers to.
pub fn remove(id: &str) -> Option<Meal> {
    let mut removed = None;
    meals().update(|meals| {
        if let Some(index) = meals.0.iter().position(|meal| meal.id == id) {
            removed = Some(meals.0.remove(index));
            persist(&meals.0);
        }
    });
    removed
}

/// Puts back a meal [`remove`] took.
pub fn restore(meal: Meal) {
    save(meal);
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
