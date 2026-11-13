//! The meal being reviewed: the page's own state and the steps of its
//! flow (prepare the photo, ask before sending it, analyze, edit, save).
//! Nothing is written to the meals before Save.

use std::{rc::Rc, time::Duration};

use health_core::consent::Consent;
use nsh_core::{Haptic, HapticNotification, prelude::*};

use crate::{
    data::{clock, meals, photos, settings, vision},
    domain::{
        VisionFailure,
        account::ModelAccount,
        meal::{Day, Meal, MealSlot},
        nutrition::{Food, MAX_FOODS_PER_MEAL},
        recognition::Lang,
    },
    i18n::s,
    nav,
};

/// Where the review is.
#[derive(Debug, Clone, PartialEq)]
pub enum Phase {
    /// The picked photo is being prepared.
    Preparing,
    /// No account can analyze photos yet.
    NeedsAccount,
    /// Waiting for the user to allow sending the photo.
    Consent,
    /// The user chose not to send it.
    NotSent,
    /// The model is working.
    Analyzing,
    /// Foods to review (estimated, added by hand, or saved before).
    Ready,
    /// The model found no food.
    NoFood,
    /// Analysis failed.
    Failed(VisionFailure),
}

/// The meal's photo: what shows, and what is sent and kept.
#[derive(Clone)]
pub struct Photo {
    pub uri: SharedString,
    pub upload: Option<Rc<Vec<u8>>>,
    pub keep: Option<Rc<Vec<u8>>>,
}

impl PartialEq for Photo {
    fn eq(&self, other: &Self) -> bool {
        self.uri == other.uri
    }
}

/// Which food the editor shows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Editing {
    Food(u64),
    New,
}

/// The review's state; `Copy`, provided to the page's parts as context.
#[derive(Clone, Copy)]
pub struct Draft {
    pub day: Day,
    pub meal_id: Stored<Option<String>>,
    logged_at: Stored<Option<i64>>,
    photo_name: Stored<Option<String>>,
    pub foods: Signal<Vec<Food>>,
    pub slot: Signal<MealSlot>,
    pub title: Signal<Option<String>>,
    pub model: Signal<Option<String>>,
    pub prompt_version: Signal<Option<String>>,
    pub phase: Signal<Phase>,
    pub skipped: Signal<usize>,
    pub photo: Signal<Option<Photo>>,
    /// Where the photo was sent: host and model, for the page to say.
    pub sent_to: Signal<Option<(String, String)>>,
    pub slow: Signal<bool>,
    pub dirty: Signal<bool>,
    pub editing: Signal<Option<Editing>>,
    pub consent_open: Signal<bool>,
    analysis: Stored<Option<Spawned<()>>>,
}

impl Draft {
    /// A new meal on `day`, its slot from the time of day.
    pub fn new(day: Day) -> Self {
        let (hour, minute) = clock::hour_minute(clock::now_ms());
        Self {
            day,
            meal_id: stored(None),
            logged_at: stored(None),
            photo_name: stored(None),
            foods: signal(Vec::new()),
            slot: signal(MealSlot::at(hour, minute)),
            title: signal(None),
            model: signal(None),
            prompt_version: signal(None),
            phase: signal(Phase::Ready),
            skipped: signal(0),
            photo: signal(None),
            sent_to: signal(None),
            slow: signal(false),
            dirty: signal(false),
            editing: signal(None),
            consent_open: signal(false),
            analysis: stored(None),
        }
    }

    /// The saved meal `meal`, to edit.
    pub fn editing_meal(meal: &Meal) -> Self {
        let draft = Self::new(meal.day);
        draft.meal_id.replace(Some(meal.id.clone()));
        draft.logged_at.replace(Some(meal.logged_at_ms));
        draft.photo_name.replace(meal.photo.clone());
        draft.foods.set(meal.foods.clone());
        draft.slot.set(meal.slot);
        draft.title.set(meal.title.clone());
        draft.model.set(meal.model.clone());
        draft.prompt_version.set(meal.prompt_version.clone());
        draft
    }

    /// Whether it is a meal saved before.
    pub fn is_saved_meal(&self) -> bool {
        self.meal_id.with(|id| id.is_some())
    }

    /// The kept photo's name, for a saved meal.
    pub fn kept_photo(&self) -> Option<String> {
        self.photo_name.with(|name| name.clone())
    }

    /// Prepares the picked photo of `capture`, then goes on to analyze it.
    pub fn prepare(self, capture: u64) {
        self.phase.set(Phase::Preparing);
        self.photo.set(None);
        self.photo_name.replace(None);
        let Some(bytes) = photos::take(capture) else {
            self.phase.set(Phase::Failed(VisionFailure::Photo));
            return;
        };
        let bytes = Rc::try_unwrap(bytes).unwrap_or_else(|shared| (*shared).clone());
        spawn(async move {
            let prepared = background(async move { photos::prepare(&bytes) }).await;
            match prepared {
                Ok(Some((upload, keep))) => {
                    self.photo.set(Some(Photo {
                        uri: photos::data_uri(&keep),
                        upload: Some(Rc::new(upload)),
                        keep: Some(Rc::new(keep)),
                    }));
                    self.begin();
                }
                _ => self.phase.set(Phase::Failed(VisionFailure::Photo)),
            }
        });
    }

    /// Analyzes the photo, asking first unless the user chose not to be
    /// asked about this account.
    pub fn begin(self) {
        if self
            .photo
            .with_untracked(|p| p.as_ref().is_none_or(|p| p.upload.is_none()))
        {
            return;
        }
        match settings::ready_account() {
            None => self.phase.set(Phase::NeedsAccount),
            Some(account) if settings::is_trusted(&account) => self.analyze(account),
            Some(_) => {
                self.phase.set(Phase::Consent);
                self.consent_open.set(true);
            }
        }
    }

    /// The user allowed sending the photo to `account` (the account the
    /// consent named, never one changed since).
    pub fn consent_given(self, account: ModelAccount, dont_ask_again: bool) {
        self.consent_open.set(false);
        if dont_ask_again {
            settings::set_trusted(&account, true);
        }
        self.analyze(account);
    }

    /// The consent was dismissed: nothing is sent.
    pub fn consent_declined(self) {
        self.consent_open.set(false);
        if self.phase.get_untracked() == Phase::Consent {
            self.phase.set(Phase::NotSent);
        }
    }

    fn analyze(self, account: ModelAccount) {
        let Some(upload) = self
            .photo
            .with_untracked(|p| p.as_ref().and_then(|p| p.upload.clone()))
        else {
            return;
        };
        if let Some(task) = self.analysis.replace(None) {
            task.cancel();
        }
        let Ok(consent) = Consent::approve(vision::upload_target(&account), true) else {
            self.phase.set(Phase::Failed(VisionFailure::Refused));
            return;
        };
        self.phase.set(Phase::Analyzing);
        self.slow.set(false);
        self.dirty.set(true);
        self.sent_to
            .set(Some((account.host(), account.model.trim().to_owned())));
        let lang = Lang::from_language(locale().language());
        let task = spawn(async move {
            let slow_after = spawn(async move {
                timer(Duration::from_secs(15)).await;
                self.slow.set(true);
            });
            let result = vision::recognize(account, upload, lang, consent).await;
            slow_after.cancel();
            match result {
                Ok(estimate) => {
                    let found = estimate.recognition.foods.len();
                    batch(|| {
                        self.foods.set(estimate.recognition.foods);
                        self.title.set(estimate.recognition.title);
                        self.model.set(Some(estimate.model));
                        self.prompt_version.set(Some(estimate.prompt_version));
                        self.skipped.set(estimate.recognition.skipped);
                        self.phase.set(if found == 0 {
                            Phase::NoFood
                        } else {
                            Phase::Ready
                        });
                    });
                    haptic(Haptic::Notification(HapticNotification::Success));
                    announce_for_accessibility(s().food_count(found));
                }
                Err(failure) => {
                    log::warn!("vision: recognition failed: {failure:?}");
                    self.phase.set(Phase::Failed(failure));
                    haptic(Haptic::Notification(HapticNotification::Error));
                }
            }
        });
        self.analysis.replace(Some(task));
    }

    /// Analyzes again after a failure.
    pub fn retry(self) {
        self.begin();
    }

    /// Adds `food` (the editor's new food).
    pub fn add_food(self, food: Food) {
        self.foods.update(|foods| {
            if foods.len() < MAX_FOODS_PER_MEAL {
                foods.push(food);
            }
        });
        self.phase.set(Phase::Ready);
        self.dirty.set(true);
    }

    /// Replaces the food with `food`'s id.
    pub fn update_food(self, food: Food) {
        self.foods.update(|foods| {
            if let Some(kept) = foods.iter_mut().find(|kept| kept.id == food.id) {
                *kept = food;
            }
        });
        self.dirty.set(true);
    }

    /// Removes the food `id`.
    pub fn remove_food(self, id: u64) {
        self.foods
            .update(|foods| foods.retain(|food| food.id != id));
        self.dirty.set(true);
    }

    /// Whether Save can keep the meal (tracked).
    pub fn can_save(&self) -> bool {
        let busy = matches!(self.phase.get(), Phase::Preparing | Phase::Analyzing);
        !busy
            && self
                .foods
                .with(|foods| !foods.is_empty() && foods.iter().all(|food| food.validate().is_ok()))
    }

    /// Whether leaving would lose work (tracked).
    pub fn has_unsaved_work(&self) -> bool {
        self.dirty.get() || matches!(self.phase.get(), Phase::Analyzing)
    }

    /// Keeps the meal and closes the page.
    pub fn save(self) {
        if !untracked(|| self.can_save()) {
            return;
        }
        let id = self
            .meal_id
            .with(|id| id.clone())
            .unwrap_or_else(meals::new_meal_id);
        let photo = match self.photo.get_untracked().and_then(|photo| photo.keep) {
            Some(jpeg) => {
                let name = format!("{id}.jpg");
                photos::keep(&name, &jpeg);
                Some(name)
            }
            None => self.photo_name.with(|name| name.clone()),
        };
        meals::save(Meal {
            id,
            day: self.day,
            logged_at_ms: self.logged_at.with(|at| at.unwrap_or_else(clock::now_ms)),
            slot: self.slot.get_untracked(),
            title: self.title.get_untracked(),
            foods: self.foods.get_untracked(),
            photo,
            model: self.model.get_untracked(),
            prompt_version: self.prompt_version.get_untracked(),
        });
        self.dirty.set(false);
        nav::pop();
    }
}
