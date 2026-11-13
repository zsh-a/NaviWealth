//! The review page as a recognition draft: opening one, following its
//! recognition while the page is open, keeping edits on it, and discarding
//! it (with Undo).

use std::rc::Rc;

use nsh_core::{element::Screen, prelude::*};

use super::draft::{Draft, Phase, Photo};
use crate::{
    data::{clock, pending, photos},
    domain::{
        VisionFailure,
        pending::{PendingMeal, PendingStatus},
    },
    i18n::s,
    nav,
    ui::toast::show_toast,
};

/// The recognition draft `id`, to confirm, try again or discard.
pub fn pending_meal_page(id: &str) -> Screen {
    let draft = match untracked(|| pending::get(id)) {
        Some(kept) => Draft::from_pending(&kept),
        None => Draft::new(untracked(clock::today)),
    };
    if let Some(name) = draft.kept_photo() {
        // Read in place (a small file), to show and to send again.
        let bytes = photos::bytes(&name).map(Rc::new);
        let uri = bytes
            .as_deref()
            .map(|jpeg| photos::data_uri(jpeg))
            .or_else(|| untracked(|| photos::uri(&name)));
        if let Some(uri) = uri {
            draft.photo.set(Some(Photo {
                uri,
                upload: bytes,
                keep: None,
            }));
        }
    }
    super::page(draft)
}

/// Discards the draft, closes the page and offers Undo on Today (its photo
/// stays until the next launch's sweep).
pub(super) fn discard(draft: Draft) {
    let Some(id) = draft.pending.get_untracked() else {
        return;
    };
    let Some(kept) = untracked(|| pending::get(&id)) else {
        return;
    };
    pending::remove(&id);
    nav::pop();
    show_toast(
        s().draft_discarded,
        Some((s().undo.into(), Rc::new(move || pending::put(kept.clone())))),
    );
}

impl Draft {
    /// The recognition draft `pending`, to confirm.
    pub fn from_pending(pending: &PendingMeal) -> Self {
        let draft = Self::new(pending.day);
        draft.pending.set(Some(pending.id.clone()));
        draft.photo_name.replace(Some(pending.photo.clone()));
        draft.foods.set(pending.foods.clone());
        draft.slot.set(pending.slot);
        draft.title.set(pending.title.clone());
        draft.model.set(pending.model.clone());
        draft.prompt_version.set(pending.prompt_version.clone());
        draft.skipped.set(pending.skipped);
        draft.phase.set(match pending.status {
            PendingStatus::Analyzing => Phase::Analyzing,
            PendingStatus::Ready => Phase::Ready,
            PendingStatus::NoFood => Phase::NoFood,
            // A run cut short by the app closing has no reason: say it
            // took too long, which is what the owner saw.
            PendingStatus::Failed => {
                Phase::Failed(pending::failure(&pending.id).unwrap_or(VisionFailure::Timeout))
            }
        });
        draft
    }

    /// Follows the draft's recognition while the page is open, and keeps
    /// the owner's edits on the draft as they are made.
    pub fn follow_pending(self) {
        effect(move || {
            let Some(id) = self.pending.get() else {
                return;
            };
            let Some(kept) = pending::get(&id) else {
                return;
            };
            if untracked(|| self.phase.get()) != Phase::Analyzing {
                return;
            }
            match kept.status {
                PendingStatus::Analyzing => {}
                PendingStatus::Ready | PendingStatus::NoFood => {
                    let found = kept.foods.len();
                    batch(|| {
                        self.foods.set(kept.foods);
                        self.title.set(kept.title);
                        self.model.set(kept.model);
                        self.prompt_version.set(kept.prompt_version);
                        self.skipped.set(kept.skipped);
                        self.phase.set(if found == 0 {
                            Phase::NoFood
                        } else {
                            Phase::Ready
                        });
                    });
                    announce_for_accessibility(s().food_count(found));
                }
                PendingStatus::Failed => self.phase.set(Phase::Failed(
                    pending::failure(&id).unwrap_or(VisionFailure::Timeout),
                )),
            }
        });
        effect(move || {
            let Some(id) = self.pending.get() else {
                return;
            };
            let (foods, slot, title, day) = (
                self.foods.get(),
                self.slot.get(),
                self.title.get(),
                self.day.get(),
            );
            if !self.dirty.get() {
                return;
            }
            untracked(|| {
                let Some(mut kept) = pending::get(&id) else {
                    return;
                };
                if kept.status == PendingStatus::Analyzing {
                    return;
                }
                kept.status = if foods.is_empty() {
                    PendingStatus::NoFood
                } else {
                    PendingStatus::Ready
                };
                kept.foods = foods;
                kept.slot = slot;
                kept.title = title;
                kept.day = day;
                pending::put(kept);
            });
        });
    }

    /// Whether this page sent the photo of a draft still kept.
    pub fn started_draft(&self) -> bool {
        self.started.with(|s| *s)
            && self
                .pending
                .get_untracked()
                .is_some_and(|id| untracked(|| pending::get(&id)).is_some())
    }
}
