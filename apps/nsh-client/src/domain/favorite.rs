//! Favorites: meals the owner eats often, kept apart from the meal they
//! came from so they can be logged again on any day. A favorite is a copy:
//! changing or deleting the original meal leaves it as it was.

use serde::{Deserialize, Serialize};

use super::{
    meal::{Day, Meal, MealSlot},
    nutrition::{Food, MAX_FOODS_PER_MEAL, Nutrients, total},
};

/// A meal kept to log again.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Favorite {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub foods: Vec<Food>,
    /// The meal's photo (a device-local name, shared with the meal).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub photo: Option<String>,
    /// The meal it was saved from, while that is the one the owner sees.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_meal: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_version: Option<String>,
    pub saved_at_ms: i64,
    /// When it was last logged (or saved); orders the list.
    pub used_at_ms: i64,
}

impl Favorite {
    /// A favorite `id` with `meal`'s title, foods and provenance, and
    /// `photo`.
    pub fn from_meal(meal: &Meal, id: String, photo: Option<String>, now_ms: i64) -> Self {
        Self {
            id,
            title: meal.title.clone(),
            foods: meal.foods.clone(),
            photo,
            source_meal: Some(meal.id.clone()),
            model: meal.model.clone(),
            prompt_version: meal.prompt_version.clone(),
            saved_at_ms: now_ms,
            used_at_ms: now_ms,
        }
    }

    /// A new meal `id` on `day` with this favorite's foods (fresh ids from
    /// `food_id`), title and provenance; its photo is `photo`.
    pub fn to_meal(
        &self,
        id: String,
        day: Day,
        slot: MealSlot,
        now_ms: i64,
        photo: Option<String>,
        mut food_id: impl FnMut() -> u64,
    ) -> Meal {
        Meal {
            id,
            day,
            logged_at_ms: now_ms,
            slot,
            title: self.title.clone(),
            foods: self
                .foods
                .iter()
                .map(|food| Food {
                    id: food_id(),
                    ..food.clone()
                })
                .collect(),
            photo,
            model: self.model.clone(),
            prompt_version: self.prompt_version.clone(),
        }
    }

    /// What it adds up to.
    pub fn total(&self) -> Nutrients {
        total(&self.foods)
    }

    /// Its title, or its foods' names when the model gave none.
    pub fn name(&self) -> String {
        match self.title.as_deref().map(str::trim) {
            Some(title) if !title.is_empty() => title.to_owned(),
            _ => self
                .foods
                .iter()
                .map(|food| food.name.trim())
                .collect::<Vec<_>>()
                .join(", "),
        }
    }

    /// Whether it can be kept: an id and 1 to 30 valid foods.
    pub fn is_valid(&self) -> bool {
        !self.id.is_empty()
            && (1..=MAX_FOODS_PER_MEAL).contains(&self.foods.len())
            && self.foods.iter().all(|food| food.validate().is_ok())
    }
}

/// `favorites` most recently used first.
pub fn by_use(favorites: &[Favorite]) -> Vec<Favorite> {
    let mut list = favorites.to_vec();
    list.sort_by(|a, b| {
        b.used_at_ms
            .cmp(&a.used_at_ms)
            .then_with(|| b.id.cmp(&a.id))
    });
    list
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::nutrition::FoodSource;

    fn meal() -> Meal {
        Meal {
            id: "m1".into(),
            day: "2026-11-10".parse().unwrap(),
            logged_at_ms: 10,
            slot: MealSlot::Breakfast,
            title: Some("Oatmeal".into()),
            foods: vec![Food {
                id: 1,
                name: "Oats".into(),
                grams: 50.0,
                per_100g: Nutrients::new(380.0, 13.0, 67.0, 7.0),
                source: FoodSource::Manual,
                confidence: None,
                estimated_grams: None,
            }],
            photo: Some("m1.jpg".into()),
            model: Some("vision-1".into()),
            prompt_version: Some("p3".into()),
        }
    }

    #[test]
    fn a_favorite_copies_the_meal_and_logs_a_new_one() {
        let favorite = Favorite::from_meal(&meal(), "f1".into(), Some("f1.jpg".into()), 20);
        assert!(favorite.is_valid());
        assert_eq!(favorite.source_meal.as_deref(), Some("m1"));
        assert_eq!(favorite.photo.as_deref(), Some("f1.jpg"));
        assert_eq!(favorite.total().kcal, 190.0);

        let day: Day = "2026-11-13".parse().unwrap();
        let logged = favorite.to_meal("m2".into(), day, MealSlot::Lunch, 30, None, || 99);
        assert_eq!(logged.id, "m2");
        assert_eq!(logged.day, day);
        assert_eq!(logged.slot, MealSlot::Lunch);
        assert_eq!(logged.foods[0].id, 99, "foods get fresh ids");
        assert_eq!(logged.foods[0].grams, 50.0);
        assert_eq!(logged.model.as_deref(), Some("vision-1"));
        assert!(logged.is_valid());
    }

    #[test]
    fn the_name_falls_back_to_the_foods() {
        let mut favorite = Favorite::from_meal(&meal(), "f1".into(), None, 0);
        assert_eq!(favorite.name(), "Oatmeal");
        favorite.title = Some("  ".into());
        assert_eq!(favorite.name(), "Oats");
    }

    #[test]
    fn the_most_recently_used_come_first() {
        let base = Favorite::from_meal(&meal(), "a".into(), None, 1);
        let newer = Favorite {
            id: "b".into(),
            used_at_ms: 5,
            ..base.clone()
        };
        let ids: Vec<_> = by_use(&[base, newer]).into_iter().map(|f| f.id).collect();
        assert_eq!(ids, ["b", "a"]);
    }
}
