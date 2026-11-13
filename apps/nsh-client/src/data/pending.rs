//! Recognition drafts ([`crate::domain::pending`]): kept in the database's
//! `meal_drafts` table (not in backups: they are moments, not records) and
//! mirrored in a private signal. A recognition runs under the app's root,
//! so closing the review page never cancels it; its result lands on the
//! draft, if the draft still exists.

use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
};

use health_core::consent::Consent;
use nsh_core::{Haptic, HapticNotification, prelude::*};
use rusqlite::params;

use super::{db, tasks, vision};
use crate::domain::{
    VisionFailure,
    account::ModelAccount,
    pending::{PendingMeal, PendingStatus},
    recognition::Lang,
};

#[derive(Clone, Default, PartialEq)]
struct Drafts(Vec<PendingMeal>);

fn drafts() -> Signal<Drafts> {
    global::<Drafts>()
}

thread_local! {
    /// Why the last recognition of a draft failed (this run of the app).
    static FAILURES: RefCell<HashMap<String, VisionFailure>> = RefCell::new(HashMap::new());
    /// Each draft's latest recognition; an older one's result is dropped.
    static RUNS: RefCell<HashMap<String, u64>> = RefCell::new(HashMap::new());
}

/// Reads the kept drafts; the root calls it once, after [`db::open`].
pub fn load() {
    let list = db::with(|connection| -> rusqlite::Result<Vec<PendingMeal>> {
        let mut statement =
            connection.prepare("SELECT body FROM meal_drafts ORDER BY created_at_ms")?;
        let bodies = statement.query_map([], |row| row.get::<_, String>(0))?;
        let mut list = Vec::new();
        for body in bodies {
            if let Ok(draft) = serde_json::from_str::<PendingMeal>(&body?)
                && draft.is_valid()
            {
                list.push(draft.restored());
            }
        }
        Ok(list)
    })
    .and_then(|read| {
        read.map_err(|error| log::error!("drafts: cannot read the database: {error}"))
            .ok()
    })
    .unwrap_or_default();
    drafts().set(Drafts(list));
}

/// Every draft, newest first (tracked).
pub fn all() -> Vec<PendingMeal> {
    drafts().with(|d| d.0.iter().rev().cloned().collect())
}

/// The draft `id`, while it exists (tracked).
pub fn get(id: &str) -> Option<PendingMeal> {
    drafts().with(|d| d.0.iter().find(|p| p.id == id).cloned())
}

/// Why the draft `id`'s recognition failed, when this run knows.
pub fn failure(id: &str) -> Option<VisionFailure> {
    FAILURES.with(|f| f.borrow().get(id).cloned())
}

/// Keeps `draft`, replacing the one with its id.
pub fn put(draft: PendingMeal) {
    if !draft.is_valid() {
        return;
    }
    if let Ok(body) = serde_json::to_string(&draft) {
        let written = db::with(|connection| {
            connection.execute(
                "INSERT INTO meal_drafts (id, created_at_ms, body) VALUES (?1, ?2, ?3)
                 ON CONFLICT (id) DO UPDATE SET body = excluded.body",
                params![draft.id, draft.created_at_ms, body],
            )
        });
        if let Some(Err(error)) = written {
            log::error!("drafts: {} was not kept: {error}", draft.id);
        }
    }
    drafts().update(|d| match d.0.iter_mut().find(|kept| kept.id == draft.id) {
        Some(kept) => *kept = draft,
        None => d.0.push(draft),
    });
}

/// Drops the draft `id` (saved as a meal, or discarded); a recognition
/// still running for it is ignored when it ends.
pub fn remove(id: &str) {
    RUNS.with(|r| r.borrow_mut().remove(id));
    FAILURES.with(|f| f.borrow_mut().remove(id));
    let deleted =
        db::with(|connection| connection.execute("DELETE FROM meal_drafts WHERE id = ?1", [id]));
    if let Some(Err(error)) = deleted {
        log::error!("drafts: {id} was not deleted: {error}");
    }
    drafts().update(|d| d.0.retain(|p| p.id != id));
}

/// Keeps `draft` as analyzing and reads its photo `jpeg` with `account`
/// under the app's root; the result updates the draft.
pub fn recognize(
    mut draft: PendingMeal,
    account: ModelAccount,
    jpeg: Rc<Vec<u8>>,
    lang: Lang,
    consent: Consent,
) {
    let id = draft.id.clone();
    let run = RUNS.with(|r| {
        let mut runs = r.borrow_mut();
        let next = runs.get(&id).copied().unwrap_or(0) + 1;
        runs.insert(id.clone(), next);
        next
    });
    FAILURES.with(|f| f.borrow_mut().remove(&id));
    draft.status = PendingStatus::Analyzing;
    put(draft);
    tasks::spawn_app(async move {
        let result = vision::recognize(account, jpeg, lang, consent).await;
        let current = RUNS.with(|r| r.borrow().get(&id).copied()) == Some(run);
        let Some(mut draft) = untracked(|| get(&id)).filter(|_| current) else {
            return;
        };
        match result {
            Ok(estimate) => {
                let found = estimate.recognition.foods.len();
                draft.foods = estimate.recognition.foods;
                draft.title = estimate.recognition.title;
                draft.model = Some(estimate.model);
                draft.prompt_version = Some(estimate.prompt_version);
                draft.skipped = estimate.recognition.skipped;
                draft.status = if found == 0 {
                    PendingStatus::NoFood
                } else {
                    PendingStatus::Ready
                };
                haptic(Haptic::Notification(HapticNotification::Success));
            }
            Err(failure) => {
                log::warn!("vision: recognition failed: {failure:?}");
                FAILURES.with(|f| f.borrow_mut().insert(id.clone(), failure));
                draft.status = PendingStatus::Failed;
                haptic(Haptic::Notification(HapticNotification::Error));
            }
        }
        put(draft);
    });
}

/// The photos the drafts refer to.
pub fn photo_names() -> HashSet<String> {
    drafts().with_untracked(|d| d.0.iter().map(|p| p.photo.clone()).collect())
}
