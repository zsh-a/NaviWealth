//! Meals: confirmed foods on a local calendar day, how they are kept on
//! the device, and what a day adds up to.

use std::{fmt, str::FromStr};

use jiff::civil::Date;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use super::nutrition::{Food, MAX_FOODS_PER_MEAL, Nutrients, total};

/// A local calendar day. Meals keep the day they were eaten on, so another
/// time zone never moves one to a different day.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Day(pub Date);

impl Day {
    /// The day `days` after this one (before, when negative).
    pub fn plus_days(self, days: i32) -> Day {
        self.0
            .checked_add(jiff::Span::new().days(days))
            .map(Day)
            .unwrap_or(self)
    }

    /// Days from `other` to this day.
    pub fn days_since(self, other: Day) -> i32 {
        let span = self.0.since(other.0).unwrap_or_default();
        span.get_days()
    }
}

impl fmt::Display for Day {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl FromStr for Day {
    type Err = String;

    fn from_str(text: &str) -> Result<Self, Self::Err> {
        text.trim()
            .parse::<Date>()
            .map(Day)
            .map_err(|error| error.to_string())
    }
}

impl Serialize for Day {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for Day {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let text = String::deserialize(deserializer)?;
        text.parse().map_err(serde::de::Error::custom)
    }
}

/// Which meal of the day.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MealSlot {
    Breakfast,
    Lunch,
    Dinner,
    Snack,
}

impl MealSlot {
    /// Every slot, in the order of a day.
    pub const ALL: [MealSlot; 4] = [
        MealSlot::Breakfast,
        MealSlot::Lunch,
        MealSlot::Dinner,
        MealSlot::Snack,
    ];

    /// The usual slot for a meal at `hour`:`minute` local time.
    pub fn at(hour: u8, minute: u8) -> MealSlot {
        match u32::from(hour) * 60 + u32::from(minute) {
            240..630 => MealSlot::Breakfast,
            630..870 => MealSlot::Lunch,
            1020..1290 => MealSlot::Dinner,
            _ => MealSlot::Snack,
        }
    }
}

/// A confirmed meal.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Meal {
    pub id: String,
    /// The local day it counts toward.
    pub day: Day,
    /// When it was logged (Unix milliseconds); orders a day's meals.
    pub logged_at_ms: i64,
    pub slot: MealSlot,
    /// A short name the model suggested ("Beef noodle soup").
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub foods: Vec<Food>,
    /// The device-local photo's name; photos never leave the device.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub photo: Option<String>,
    /// The model that estimated it, as provenance.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// The shared recognition prompt that produced the editable estimate.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_version: Option<String>,
}

impl Meal {
    /// What the meal adds up to.
    pub fn total(&self) -> Nutrients {
        total(&self.foods)
    }

    /// Whether it can be kept: an id and 1 to 30 valid foods.
    pub fn is_valid(&self) -> bool {
        !self.id.is_empty()
            && (1..=MAX_FOODS_PER_MEAL).contains(&self.foods.len())
            && self.foods.iter().all(|food| food.validate().is_ok())
    }
}

/// What one day adds up to.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct DaySummary {
    pub total: Nutrients,
    pub meals: usize,
}

/// The meals of `day`, in the order they were logged.
pub fn meals_of(meals: &[Meal], day: Day) -> Vec<Meal> {
    let mut of_day: Vec<Meal> = meals.iter().filter(|m| m.day == day).cloned().collect();
    of_day.sort_by_key(|meal| meal.logged_at_ms);
    of_day
}

/// What `day`'s meals add up to.
pub fn summarize(meals: &[Meal], day: Day) -> DaySummary {
    meals
        .iter()
        .filter(|meal| meal.day == day)
        .fold(DaySummary::default(), |summary, meal| DaySummary {
            total: summary.total + meal.total(),
            meals: summary.meals + 1,
        })
}

#[derive(Serialize, Deserialize)]
struct Stored<T> {
    version: u32,
    meals: Vec<T>,
}

/// The legacy key-value form of `meals` (`meals.v1`), read once to move
/// meals into the database.
pub fn encode_meals(meals: &[Meal]) -> String {
    serde_json::to_string(&Stored {
        version: 1,
        meals: meals.to_vec(),
    })
    .unwrap_or_else(|_| "{\"version\":1,\"meals\":[]}".to_owned())
}

/// The meals in `raw`; a meal that cannot be read or is not valid is left
/// out (logged) instead of losing the others.
pub fn decode_meals(raw: &str) -> Vec<Meal> {
    let Ok(stored) = serde_json::from_str::<Stored<serde_json::Value>>(raw) else {
        log::warn!("meals: unreadable storage, starting empty");
        return Vec::new();
    };
    if stored.version != 1 {
        log::warn!("meals: unknown storage version {}", stored.version);
        return Vec::new();
    }
    stored
        .meals
        .into_iter()
        .filter_map(|value| checked(serde_json::from_value::<Meal>(value)))
        .collect()
}

/// One meal's stored form: a database row's body.
pub fn encode_meal(meal: &Meal) -> String {
    serde_json::to_string(meal).unwrap_or_default()
}

/// The meal in a row's `raw` body, if it can be read and is valid (logged
/// otherwise).
pub fn decode_meal(raw: &str) -> Option<Meal> {
    checked(serde_json::from_str::<Meal>(raw))
}

fn checked(read: serde_json::Result<Meal>) -> Option<Meal> {
    match read {
        Ok(meal) if meal.is_valid() => Some(meal),
        Ok(meal) => {
            log::warn!("meals: dropped invalid meal {}", meal.id);
            None
        }
        Err(error) => {
            log::warn!("meals: dropped unreadable meal: {error}");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::nutrition::FoodSource;

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
                name: "Soup".into(),
                grams: 100.0,
                per_100g: Nutrients::new(kcal, 1.0, 1.0, 1.0),
                source: FoodSource::Estimate,
                confidence: None,
                estimated_grams: None,
            }],
            photo: None,
            model: None,
            prompt_version: None,
        }
    }

    #[test]
    fn slots_follow_the_clock() {
        assert_eq!(MealSlot::at(7, 30), MealSlot::Breakfast);
        assert_eq!(MealSlot::at(10, 29), MealSlot::Breakfast);
        assert_eq!(MealSlot::at(12, 0), MealSlot::Lunch);
        assert_eq!(MealSlot::at(15, 30), MealSlot::Snack);
        assert_eq!(MealSlot::at(19, 0), MealSlot::Dinner);
        assert_eq!(MealSlot::at(23, 0), MealSlot::Snack);
        assert_eq!(MealSlot::at(2, 0), MealSlot::Snack);
    }

    #[test]
    fn days_step_and_compare() {
        let d = day("2026-11-12");
        assert_eq!(d.plus_days(-1), day("2026-11-11"));
        assert_eq!(d.plus_days(20), day("2026-12-02"));
        assert_eq!(d.days_since(day("2026-11-10")), 2);
        assert_eq!(d.to_string(), "2026-11-12");
    }

    #[test]
    fn a_day_sums_only_its_meals_in_order() {
        let meals = vec![
            meal("b", "2026-11-12", 20, 300.0),
            meal("a", "2026-11-12", 10, 200.0),
            meal("c", "2026-11-11", 5, 900.0),
        ];
        let summary = summarize(&meals, day("2026-11-12"));
        assert_eq!(summary.meals, 2);
        assert_eq!(summary.total.kcal, 500.0);
        let ids: Vec<_> = meals_of(&meals, day("2026-11-12"))
            .into_iter()
            .map(|m| m.id)
            .collect();
        assert_eq!(ids, ["a", "b"]);
        assert_eq!(summarize(&meals, day("2026-11-13")), DaySummary::default());
    }

    #[test]
    fn storage_round_trips_and_drops_only_bad_meals() {
        let kept = meal("a", "2026-11-12", 10, 200.0);
        let raw = encode_meals(std::slice::from_ref(&kept));
        assert_eq!(decode_meals(&raw), vec![kept.clone()]);

        let mut value: serde_json::Value = serde_json::from_str(&raw).unwrap();
        let mut broken = serde_json::to_value(meal("b", "2026-11-12", 11, 200.0)).unwrap();
        broken["foods"][0]["grams"] = serde_json::json!(-5);
        value["meals"].as_array_mut().unwrap().push(broken);
        value["meals"]
            .as_array_mut()
            .unwrap()
            .push(serde_json::json!({"id": 3}));
        assert_eq!(decode_meals(&value.to_string()), vec![kept]);
        assert!(decode_meals("not json").is_empty());
        assert!(decode_meals("{\"version\":9,\"meals\":[]}").is_empty());
    }

    #[test]
    fn a_row_body_round_trips_and_refuses_bad_meals() {
        let kept = meal("a", "2026-11-12", 10, 200.0);
        assert_eq!(decode_meal(&encode_meal(&kept)), Some(kept));
        let mut broken = serde_json::to_value(meal("b", "2026-11-12", 11, 200.0)).unwrap();
        broken["foods"][0]["grams"] = serde_json::json!(-5);
        assert_eq!(decode_meal(&broken.to_string()), None);
        assert_eq!(decode_meal("not json"), None);
    }
}
