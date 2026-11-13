//! Favorites ([`crate::domain::favorite`]), kept in the database's
//! `saved_meals` table and mirrored in a private signal like the meals.
//! A favorite shares its photo file with the meals it came from or made.

use std::collections::HashSet;

use nsh_core::prelude::*;
use rusqlite::{Connection, params};

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
pub fn load() {
    let list = db::with(|connection| {
        read_all(connection).unwrap_or_else(|error| {
            log::error!("favorites: cannot read the database: {error}");
            Vec::new()
        })
    })
    .unwrap_or_default();
    favorites().set(Favorites(list));
}

fn read_all(connection: &Connection) -> rusqlite::Result<Vec<Favorite>> {
    let mut statement = connection.prepare("SELECT body FROM saved_meals")?;
    let bodies = statement.query_map([], |row| row.get::<_, String>(0))?;
    let mut list = Vec::new();
    for body in bodies {
        if let Ok(favorite) = serde_json::from_str::<Favorite>(&body?)
            && favorite.is_valid()
        {
            list.push(favorite);
        }
    }
    Ok(list)
}

fn write(favorite: &Favorite) {
    let Ok(body) = serde_json::to_string(favorite) else {
        return;
    };
    let written = db::with(|connection| {
        connection.execute(
            "INSERT INTO saved_meals (id, saved_at_ms, used_at_ms, body) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT (id) DO UPDATE SET
                saved_at_ms = excluded.saved_at_ms, used_at_ms = excluded.used_at_ms,
                body = excluded.body",
            params![favorite.id, favorite.saved_at_ms, favorite.used_at_ms, body],
        )
    });
    if let Some(Err(error)) = written {
        log::error!("favorites: {} was not kept: {error}", favorite.id);
    }
}

fn put(favorite: Favorite) {
    write(&favorite);
    favorites().update(
        |list| match list.0.iter_mut().find(|kept| kept.id == favorite.id) {
            Some(kept) => *kept = favorite,
            None => list.0.push(favorite),
        },
    );
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
pub fn save_from(meal: &Meal) -> Option<Favorite> {
    let id = format!("f{}", meals::new_meal_id());
    let favorite = Favorite::from_meal(meal, id, meal.photo.clone(), clock::now_ms());
    if !favorite.is_valid() {
        return None;
    }
    put(favorite.clone());
    Some(favorite)
}

/// Removes the favorite `id` and gives it back (to undo). Its photo goes
/// with the next launch's sweep.
pub fn remove(id: &str) -> Option<Favorite> {
    let mut removed = None;
    favorites().update(|list| {
        if let Some(index) = list.0.iter().position(|f| f.id == id) {
            removed = Some(list.0.remove(index));
        }
    });
    if removed.is_some() {
        let deleted = db::with(|connection| {
            connection.execute("DELETE FROM saved_meals WHERE id = ?1", params![id])
        });
        if let Some(Err(error)) = deleted {
            log::error!("favorites: {id} was not deleted: {error}");
        }
    }
    removed
}

/// Puts back a favorite [`remove`] took.
pub fn restore(favorite: Favorite) {
    put(favorite);
}

/// Logs the favorite `id` as a new meal on `day` (its slot from the time
/// of day) and keeps it; gives the meal, to undo.
pub fn log(id: &str, day: Day) -> Option<Meal> {
    let mut favorite = get(id)?;
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
    meals::save(meal.clone());
    favorite.used_at_ms = now;
    put(favorite);
    Some(meal)
}

/// Marks the favorite `id` used now (logged after adjusting).
pub fn touch(id: &str) {
    if let Some(mut favorite) = get(id) {
        favorite.used_at_ms = clock::now_ms();
        put(favorite);
    }
}

/// The photos the favorites refer to.
pub fn photo_names() -> HashSet<String> {
    favorites().with_untracked(|list| list.0.iter().filter_map(|f| f.photo.clone()).collect())
}
