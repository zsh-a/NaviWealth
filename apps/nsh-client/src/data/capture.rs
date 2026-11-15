//! Durable multimodal drafts. Recognition never writes records; confirmation
//! commits the entire batch and consumes its draft in one SQLite transaction.
use super::{clock, db, finance, meals, photos, tasks, vision, weights};
use crate::domain::{
    account::ModelAccount,
    capture::{Draft, MAX_INPUT, PROMPT_VERSION, Record, Status},
    meal::{Meal, encode_meal},
    recognition::Lang,
};
use finance_core::journal::{Entry, Source};
use health_core::consent::Consent;
use nsh_core::prelude::*;
use rusqlite::params;
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    sync::atomic::{AtomicU64, Ordering},
};

#[derive(Clone, Default, PartialEq)]
struct Drafts(Vec<Draft>);
fn state() -> Signal<Drafts> {
    global::<Drafts>()
}
thread_local! {
    static RUNS: RefCell<HashMap<String, u64>> = RefCell::new(HashMap::new());
    static FAILURES: RefCell<HashMap<String, crate::domain::VisionFailure>> = RefCell::new(HashMap::new());
}
pub fn failure(id: &str) -> Option<crate::domain::VisionFailure> {
    FAILURES.with(|f| f.borrow().get(id).cloned())
}
static NEXT: AtomicU64 = AtomicU64::new(0);

pub fn new() -> Draft {
    Draft {
        id: format!(
            "capture-{}-{}",
            clock::now_ms(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ),
        created_at_ms: clock::now_ms(),
        input: String::new(),
        correction: String::new(),
        photo: None,
        records: Vec::new(),
        question: String::new(),
        status: Status::Editing,
        model: String::new(),
    }
}

pub fn load() -> Result<(), String> {
    let list = db::with(|c| -> Result<Vec<Draft>, String> {
        let mut query = c
            .prepare("SELECT body FROM capture_drafts ORDER BY created_at_ms DESC")
            .map_err(|e| e.to_string())?;
        let rows = query
            .query_map([], |r| r.get::<_, String>(0))
            .map_err(|e| e.to_string())?;
        let mut list = Vec::new();
        for row in rows {
            let mut draft: Draft = serde_json::from_str(&row.map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())?;
            if draft.status == Status::Analyzing {
                draft.status = Status::Failed;
            }
            list.push(draft);
        }
        Ok(list)
    })
    .ok_or("database unavailable")??;
    state().set(Drafts(list));
    Ok(())
}

pub fn all() -> Vec<Draft> {
    state().with(|s| s.0.clone())
}

/// Refresh after an app-level transaction changes references in saved drafts.
pub(super) fn replace_mirror(drafts: Vec<Draft>) {
    state().set(Drafts(drafts));
}
pub fn get(id: &str) -> Option<Draft> {
    state().with(|s| s.0.iter().find(|d| d.id == id).cloned())
}
pub fn photo_names() -> HashSet<String> {
    state().with(|s| s.0.iter().filter_map(|d| d.photo.clone()).collect())
}

pub fn put(draft: Draft) -> Result<(), String> {
    let body = serde_json::to_string(&draft).map_err(|e| e.to_string())?;
    db::with(|c| c.execute("INSERT INTO capture_drafts(id,created_at_ms,body) VALUES (?1,?2,?3) ON CONFLICT(id) DO UPDATE SET body=excluded.body",
        params![draft.id,draft.created_at_ms,body])).ok_or("database unavailable")?.map_err(|e| e.to_string())?;
    state().update(|s| {
        s.0.retain(|d| d.id != draft.id);
        s.0.insert(0, draft);
    });
    Ok(())
}

pub fn remove(id: &str) -> Result<(), String> {
    db::with(|c| c.execute("DELETE FROM capture_drafts WHERE id=?1", [id]))
        .ok_or("database unavailable")?
        .map_err(|e| e.to_string())?;
    RUNS.with(|r| r.borrow_mut().remove(id));
    state().update(|s| s.0.retain(|d| d.id != id));
    Ok(())
}

pub fn recognize(
    mut draft: Draft,
    account: ModelAccount,
    consent: Consent,
    lang: Lang,
) -> Result<(), String> {
    if draft.input.chars().count() > MAX_INPUT || draft.correction.chars().count() > MAX_INPUT {
        return Err("input too long".into());
    }
    if draft.input.trim().is_empty() && draft.correction.trim().is_empty() && draft.photo.is_none()
    {
        return Err("empty input".into());
    }
    consent
        .check(&vision::upload_target(&account))
        .map_err(|e| e.to_string())?;
    let jpeg = draft
        .photo
        .as_ref()
        .map(|name| photos::bytes(name).ok_or("image unavailable"))
        .transpose()?;
    let id = draft.id.clone();
    if untracked(|| get(&id)).is_some_and(|d| d.status == Status::Analyzing) {
        return Ok(());
    }
    draft.status = Status::Analyzing;
    put(draft.clone())?;
    let run = NEXT.fetch_add(1, Ordering::Relaxed);
    RUNS.with(|r| r.borrow_mut().insert(id.clone(), run));
    FAILURES.with(|f| f.borrow_mut().remove(&id));
    let now = clock::zoned(clock::now_ms()).datetime();
    let context = serde_json::json!({"local_date":now.date().to_string(),"local_time":now.time().to_string(),
        "known_accounts":finance::accounts().iter().filter(|a| a.is_cash()).map(ToString::to_string).collect::<Vec<_>>(),
        "known_categories":finance_core::currency::Currency::ALL.into_iter().flat_map(|currency| finance_core::account::defaults::all().into_iter().filter(|a| matches!(a.kind(),finance_core::account::AccountKind::Expenses|finance_core::account::AccountKind::Income)).map(move |a|a.in_currency(currency).to_string())).collect::<Vec<_>>()});
    tasks::spawn_app(async move {
        let response =
            vision::recognize_record(account, draft.clone(), jpeg, lang, consent, context).await;
        if RUNS.with(|r| r.borrow().get(&id).copied()) != Some(run)
            || untracked(|| get(&id)).is_none()
        {
            return;
        }
        match response {
            Ok((records, question, model)) => {
                draft.records = records;
                draft.question = question;
                draft.model = model;
                // The current structured draft carries accepted corrections. Keep
                // the original input for provenance, but don't replay a correction.
                draft.correction.clear();
                draft.status = Status::Ready;
            }
            Err(error) => {
                log::warn!("capture: recognition failed: {error:?}");
                FAILURES.with(|f| f.borrow_mut().insert(id.clone(), error));
                draft.status = Status::Failed;
            }
        }
        if let Err(error) = put(draft.clone()) {
            log::error!("capture: could not retain result: {error}");
            draft.status = Status::Failed;
            state().update(|s| {
                if let Some(kept) = s.0.iter_mut().find(|d| d.id == id) {
                    *kept = draft;
                }
            });
        }
    });
    Ok(())
}

fn entry(draft: &Draft, index: usize, day: crate::domain::meal::Day) -> Entry {
    Entry {
        id: format!("{}-{index}", draft.id),
        at: day
            .0
            .to_datetime(clock::zoned(draft.created_at_ms).datetime().time()),
        payee: String::new(),
        note: String::new(),
        source: Source::Recognition {
            model: draft.model.clone(),
            prompt_version: PROMPT_VERSION.into(),
        },
    }
}

pub fn ready(draft: &Draft) -> bool {
    draft.status == Status::Ready
        && draft.correction.trim().is_empty()
        && !draft.records.is_empty()
        && draft.records.iter().enumerate().all(|(i, r)| match r {
            Record::Money { day, draft: money } => {
                money.valid() && money.transaction(entry(draft, i, *day), day.0).is_ok()
            }
            Record::Meal { estimate, .. } => {
                !estimate.foods.is_empty() && estimate.foods.iter().all(|f| f.validate().is_ok())
            }
            Record::Weight { kg, .. } => crate::domain::weight::valid_kg(*kg),
        })
}

pub fn confirm(id: &str) -> Result<(), String> {
    let draft = untracked(|| get(id))
        .filter(ready)
        .ok_or("draft is not ready")?;
    db::with(|c| -> Result<(), String> {
        let tx = c.unchecked_transaction().map_err(|e| e.to_string())?;
        // Consuming the draft is part of the same transaction, so a double tap,
        // process restart or failed write cannot create a partial/duplicate batch.
        let removed = tx.execute("DELETE FROM capture_drafts WHERE id=?1", [id]).map_err(|e| e.to_string())?;
        if removed != 1 { return Err("draft no longer exists".into()); }
        for (index, record) in draft.records.iter().enumerate() {
            match record {
                Record::Money { day, draft:money } => {
                    let t = money.transaction(entry(&draft,index,*day),day.0).map_err(|e| e.to_string())?;
                    finance_core::repository::save_in_transaction(&tx,&t).map_err(|e| e.to_string())?;
                }
                Record::Meal { day, slot, estimate } => {
                    let meal = Meal { id:format!("{}-{index}",draft.id), day:*day, logged_at_ms:draft.created_at_ms,
                        slot:*slot, title:estimate.title.clone(), foods:estimate.foods.clone(), photo:draft.photo.clone(),
                        model:Some(draft.model.clone()), prompt_version:Some(PROMPT_VERSION.into()) };
                    if !meal.is_valid() { return Err("invalid meal".into()); }
                    tx.execute("INSERT INTO meals(id,day,logged_at_ms,body) VALUES(?1,?2,?3,?4)",
                        params![meal.id,meal.day.to_string(),meal.logged_at_ms,encode_meal(&meal)]).map_err(|e| e.to_string())?;
                }
                Record::Weight { day, kg } => {
                    tx.execute("INSERT INTO weights(day,kg,logged_at_ms) VALUES(?1,?2,?3) ON CONFLICT(day) DO UPDATE SET kg=excluded.kg,logged_at_ms=excluded.logged_at_ms",
                        params![day.to_string(),crate::domain::weight::rounded(*kg),draft.created_at_ms]).map_err(|e| e.to_string())?;
                }
            }
        }
        tx.commit().map_err(|e| e.to_string())
    }).ok_or("database unavailable")??;
    state().update(|s| s.0.retain(|d| d.id != id));
    RUNS.with(|r| r.borrow_mut().remove(id));
    let mut preferences = super::settings::current().ledger;
    let mut has_money = false;
    for record in &draft.records {
        if let Record::Money { draft: money, .. } = record {
            has_money = true;
            preferences.own = money.account.as_ref().map(ToString::to_string);
            match money.kind {
                finance_core::recognition::Kind::Expense => {
                    preferences.expense = money.category.as_ref().map(ToString::to_string)
                }
                finance_core::recognition::Kind::Income => {
                    preferences.income = money.category.as_ref().map(ToString::to_string)
                }
                finance_core::recognition::Kind::Transfer => {
                    preferences.other = money.other_account.as_ref().map(ToString::to_string)
                }
            }
        }
    }
    if has_money {
        super::settings::save_ledger_defaults(preferences);
    }
    meals::load();
    weights::load();
    if let Err(error) = finance::load() {
        log::error!("capture: ledger refresh failed: {error}");
    }
    Ok(())
}
