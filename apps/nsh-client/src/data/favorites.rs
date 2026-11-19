//! Favorites ([`crate::domain::favorite`]), kept in the database's
//! `saved_meals` table and mirrored in a private signal like the meals.
//! A favorite shares its photo file with the meals it came from or made.

use std::collections::HashSet;

use navi_health::store;
use nsh_core::prelude::*;

use super::{clock, db, meals};
use crate::domain::{
    favorite::{Favorite, by_use},
    meal::{Day, Meal, MealSlot},
};

#[derive(Clone, Default, PartialEq)]
struct Favorites(Vec<Favorite>);

fn favorites() -> Signal<Favorites> {
    global::<Favorites>()
}

/// Reads the kept favorites; the root calls it once, after [`db::open`].
pub fn load() -> Result<(), String> {
    let list = db::with(store::favorites)
        .ok_or("the database is not open")?
        .map_err(|e| e.to_string())?;
    favorites().set(Favorites(list));
    Ok(())
}

fn reflect(favorite: Favorite) {
    favorites().update(
        |list| match list.0.iter_mut().find(|kept| kept.id == favorite.id) {
            Some(kept) => *kept = favorite,
            None => list.0.push(favorite),
        },
    );
}

fn put(favorite: Favorite) -> Result<(), String> {
    db::with(|c| store::save_favorite(c, &favorite))
        .ok_or("the database is not open")?
        .map_err(|e| e.to_string())?;
    reflect(favorite);
    Ok(())
}

/// Every favorite, most recently used first (tracked).
pub fn all() -> Vec<Favorite> {
    favorites().with(|list| by_use(&list.0))
}

/// Whether there is any favorite (tracked).
pub fn any() -> bool {
    favorites().with(|list| !list.0.is_empty())
}

/// The favorite saved from the meal `meal_id`, if any (tracked).
pub fn of_meal(meal_id: &str) -> Option<Favorite> {
    favorites().with(|list| {
        list.0
            .iter()
            .find(|favorite| favorite.source_meal.as_deref() == Some(meal_id))
            .cloned()
    })
}

/// The favorite `id` (untracked).
pub fn get(id: &str) -> Option<Favorite> {
    favorites().with_untracked(|list| list.0.iter().find(|f| f.id == id).cloned())
}

/// Keeps `meal` as a favorite. Kept photos are never rewritten, so the
/// favorite shares the meal's file; the sweep keeps it while either refers
/// to it.
pub fn save_from(meal: &Meal) -> Result<Favorite, String> {
    let id = format!("f{}", meals::new_meal_id());
    let favorite = Favorite::from_meal(meal, id, meal.photo.clone(), clock::now_ms());
    put(favorite.clone())?;
    Ok(favorite)
}

/// Removes a favorite only after the database commits.
pub fn remove(id: &str) -> Result<Option<Favorite>, String> {
    let removed = db::with(|c| store::remove_favorite(c, id))
        .ok_or("the database is not open")?
        .map_err(|e| e.to_string())?;
    favorites().update(|list| list.0.retain(|f| f.id != id));
    Ok(removed)
}

pub fn restore(favorite: Favorite) -> Result<(), String> {
    put(favorite)
}

/// The meal and favorite's last-use time commit together before UI publication.
pub fn log(id: &str, day: Day) -> Result<Option<Meal>, String> {
    let Some(mut favorite) = get(id) else {
        return Ok(None);
    };
    let now = clock::now_ms();
    let (hour, minute) = clock::hour_minute(now);
    let meal = favorite.to_meal(
        meals::new_meal_id(),
        day,
        MealSlot::at(hour, minute),
        now,
        favorite.photo.clone(),
        meals::new_food_id,
    );
    favorite.used_at_ms = now;
    db::with(|c| store::log_favorite(c, &favorite, &meal))
        .ok_or("the database is not open")?
        .map_err(|e| e.to_string())?;
    batch(|| {
        meals::reflect(meal.clone());
        reflect(favorite);
    });
    Ok(Some(meal))
}

/// The photos the favorites refer to.
pub fn photo_names() -> HashSet<String> {
    favorites().with_untracked(|list| list.0.iter().filter_map(|f| f.photo.clone()).collect())
}
