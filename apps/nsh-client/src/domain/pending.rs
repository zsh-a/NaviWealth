//! Recognition drafts: a meal photo the model is reading or has read, not
//! yet confirmed. Leaving the review page never loses one; it waits on
//! Today and in Records until the owner saves or discards it. Nothing in a
//! draft counts toward a day.

use serde::{Deserialize, Serialize};

use super::{
    meal::{Day, MealSlot},
    nutrition::{Food, total},
};

/// Where a draft's recognition is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PendingStatus {
    /// The model is reading the photo.
    Analyzing,
    /// Foods to confirm.
    Ready,
    /// The model found no food.
    NoFood,
    /// Recognition failed, or the app closed while it ran.
    Failed,
}

/// A meal waiting for confirmation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PendingMeal {
    pub id: String,
    pub day: Day,
    pub slot: MealSlot,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default)]
    pub foods: Vec<Food>,
    /// The kept photo's name (shared with the meal it becomes).
    pub photo: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_version: Option<String>,
    /// Foods the model returned that could not be read.
    #[serde(default)]
    pub skipped: usize,
    pub status: PendingStatus,
    pub created_at_ms: i64,
}

impl PendingMeal {
    /// The energy of its foods.
    pub fn kcal(&self) -> f64 {
        total(&self.foods).kcal
    }

    /// As kept after a restart: a recognition that was running is lost
    /// with the app, and can be tried again.
    pub fn restored(mut self) -> Self {
        if self.status == PendingStatus::Analyzing {
            self.status = PendingStatus::Failed;
        }
        self
    }

    /// Whether it can be kept: an id, a photo, and foods only once read.
    pub fn is_valid(&self) -> bool {
        !self.id.is_empty()
            && !self.photo.is_empty()
            && (self.status != PendingStatus::Ready || !self.foods.is_empty())
            && self.foods.iter().all(|food| food.validate().is_ok())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::nutrition::{FoodSource, Nutrients};

    fn pending(status: PendingStatus, foods: Vec<Food>) -> PendingMeal {
        PendingMeal {
            id: "d1".into(),
            day: "2026-11-13".parse().unwrap(),
            slot: MealSlot::Dinner,
            title: None,
            foods,
            photo: "d1.jpg".into(),
            model: None,
            prompt_version: None,
            skipped: 0,
            status,
            created_at_ms: 1,
        }
    }

    #[test]
    fn a_running_recognition_does_not_survive_a_restart() {
        let restored = pending(PendingStatus::Analyzing, vec![]).restored();
        assert_eq!(restored.status, PendingStatus::Failed);
        let ready = Food {
            id: 1,
            name: "Rice".into(),
            grams: 150.0,
            per_100g: Nutrients::new(116.0, 2.6, 25.9, 0.3),
            source: FoodSource::Estimate,
            confidence: None,
            estimated_grams: Some(150.0),
        };
        let kept = pending(PendingStatus::Ready, vec![ready]).restored();
        assert_eq!(kept.status, PendingStatus::Ready);
        assert_eq!(kept.kcal(), 174.0);
    }

    #[test]
    fn a_ready_draft_needs_foods() {
        assert!(!pending(PendingStatus::Ready, vec![]).is_valid());
        assert!(pending(PendingStatus::Analyzing, vec![]).is_valid());
        assert!(pending(PendingStatus::NoFood, vec![]).is_valid());
    }
}
