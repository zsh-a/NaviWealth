//! Durable multimodal drafts. Recognition never writes records; confirmation
//! commits the entire batch and consumes its draft in one SQLite transaction.
use super::{clock, db, finance, meals, photos, tasks, vision, weights};
use crate::domain::{
    account::ModelAccount,
    capture::{Draft, MAX_ATTACHMENTS, MAX_INPUT, PROMPT_VERSION, Record, Status, Turn},
    meal::Meal,
    recognition::Lang,
};
use navi_finance::journal::{Entry, Source};
use navi_health::consent::Consent;
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
        attachments: Vec::new(),
        answers: Vec::new(),
        records: Vec::new(),
        question: String::new(),
        transcript: Vec::new(),
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
            list.push(draft.migrated());
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
    state().with(|s| s.0.iter().flat_map(Draft::image_names).collect())
}

pub fn put(draft: Draft) -> Result<(), String> {
    if draft.image_names().len() > MAX_ATTACHMENTS {
        return Err("too many images".into());
    }
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
    if draft.image_names().len() > MAX_ATTACHMENTS {
        return Err("too many images".into());
    }
    if let Some(kept) = untracked(|| get(&draft.id)) {
        if kept.status == Status::Analyzing {
            return Ok(());
        }
        if draft.pending_ask_user().map(|ask| &ask.call_id)
            != kept.pending_ask_user().map(|ask| &ask.call_id)
        {
            return Err("question changed; reopen the draft".into());
        }
    }
    prepare_turn(&mut draft)?;
    consent
        .check(&vision::upload_target(&account))
        .map_err(|e| e.to_string())?;
    let images = draft
        .image_names()
        .into_iter()
        .map(|name| {
            photos::bytes(&name)
                .map(|bytes| (name, bytes))
                .ok_or("image unavailable")
        })
        .collect::<Result<Vec<_>, _>>()?;
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
        "known_categories":navi_finance::currency::Currency::ALL.into_iter().flat_map(|currency| navi_finance::account::defaults::all().into_iter().filter(|a| matches!(a.kind(),navi_finance::account::AccountKind::Expenses|navi_finance::account::AccountKind::Income)).map(move |a|a.in_currency(currency).to_string())).collect::<Vec<_>>()});
    tasks::spawn_app(async move {
        let response =
            vision::recognize_record(account, draft.clone(), images, lang, consent, context).await;
        if RUNS.with(|r| r.borrow().get(&id).copied()) != Some(run)
            || untracked(|| get(&id)).is_none()
        {
            return;
        }
        match response {
            Ok(vision::CaptureResponse::Records {
                records,
                questions,
                reply,
                model,
                provider_output,
            }) => {
                let proposed = records.len();
                draft.records = records;
                draft.model = model;
                // The whole reply is kept so the next request replays the
                // conversation as it happened.
                draft.transcript.push(Turn::Assistant {
                    reply,
                    records: proposed,
                    questions,
                    provider_output,
                });
                draft.status = Status::Ready;
            }
            Ok(vision::CaptureResponse::AskUser { request, model }) => {
                if accept_ask_user(&mut draft, request, model).is_err() {
                    FAILURES.with(|f| {
                        f.borrow_mut()
                            .insert(id.clone(), crate::domain::VisionFailure::Unreadable)
                    });
                    draft.status = Status::Failed;
                }
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

/// A provider call may suspend only after the preceding owner message or tool
/// result. It may neither replace an unanswered decision nor reuse a call id.
fn accept_ask_user(
    draft: &mut Draft,
    request: crate::domain::capture::AskUser,
    model: String,
) -> Result<(), String> {
    if draft.pending_ask_user().is_some()
        || draft.transcript.iter().any(|turn| {
            matches!(turn, Turn::AskUser { request: prior } if prior.call_id == request.call_id)
        })
    {
        return Err("duplicate or overlapping decision".into());
    }
    draft.model = model;
    draft.answers.clear();
    draft.transcript.push(Turn::AskUser { request });
    draft.status = Status::Ready;
    Ok(())
}

/// Commit exactly one owner-initiated continuation to the draft. A failed
/// request retries its already committed message instead of duplicating it.
fn prepare_turn(draft: &mut Draft) -> Result<(), String> {
    let message = draft.correction.trim().to_owned();
    let images = draft.staged_images();
    if let Some(request) = draft.pending_ask_user() {
        request
            .validate_answers(&draft.answers, &message, !images.is_empty())
            .map_err(|_| "invalid answer".to_owned())?;
        let call_id = request.call_id.clone();
        draft.transcript.push(Turn::ToolAnswer {
            call_id,
            answers: std::mem::take(&mut draft.answers),
            text: message,
            images,
        });
    } else {
        // Answers must never fall through into plain text or a different call.
        if !draft.answers.is_empty() {
            return Err("no pending question".into());
        }
        if draft.transcript.is_empty() {
            if draft.input.trim().is_empty() && images.is_empty() {
                return Err("empty input".into());
            }
            draft.transcript.push(Turn::Owner {
                text: draft.input.clone(),
                photo: !images.is_empty(),
                images,
            });
        } else if !message.is_empty() || !images.is_empty() {
            draft.transcript.push(Turn::Owner {
                text: message,
                photo: !images.is_empty(),
                images,
            });
        }
    }
    draft.attachments.clear();
    draft.correction.clear();
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

/// An answered tool call still needs a validated final model reply. In
/// particular, "keep previous result" after a failed continuation cannot
/// accidentally confirm records from before the pending decision.
pub fn awaiting_tool_resolution(draft: &Draft) -> bool {
    draft
        .transcript
        .iter()
        .rev()
        .find_map(|turn| match turn {
            Turn::AskUser { .. } => Some(true),
            Turn::Assistant { .. } => Some(false),
            Turn::Owner { .. } | Turn::ToolAnswer { .. } => None,
        })
        .unwrap_or(false)
}

pub fn ready(draft: &Draft) -> bool {
    draft.status == Status::Ready
        && draft.correction.trim().is_empty()
        && !draft.has_staged_images()
        && draft.answers.is_empty()
        && draft.pending_ask_user().is_none()
        && !awaiting_tool_resolution(draft)
        && draft.pending_questions().is_empty()
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
                    navi_finance::repository::save_in_transaction(&tx,&t).map_err(|e| e.to_string())?;
                }
                Record::Meal { day, slot, estimate } => {
                    let meal = Meal { id:format!("{}-{index}",draft.id), day:*day, logged_at_ms:draft.created_at_ms,
                        slot:*slot, title:estimate.title.clone(), foods:estimate.foods.clone(), photo:draft.photo.clone(),
                        model:Some(draft.model.clone()), prompt_version:Some(PROMPT_VERSION.into()) };
                    if !meal.is_valid() { return Err("invalid meal".into()); }
                    navi_health::store::insert_meal(&tx, &meal).map_err(|e| e.to_string())?;
                }
                Record::Weight { day, kg } => {
                    super::scale::reconcile_weight_in_transaction(&tx, &day.to_string(), Some(crate::domain::weight::rounded(*kg))).map_err(|e| e.to_string())?;
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
                navi_finance::recognition::Kind::Expense => {
                    preferences.expense = money.category.as_ref().map(ToString::to_string)
                }
                navi_finance::recognition::Kind::Income => {
                    preferences.income = money.category.as_ref().map(ToString::to_string)
                }
                navi_finance::recognition::Kind::Transfer => {
                    preferences.other = money.other_account.as_ref().map(ToString::to_string)
                }
            }
        }
    }
    if has_money {
        super::settings::save_ledger_defaults(preferences);
    }
    if let Err(error) = meals::load() {
        log::error!("capture: committed meals could not refresh: {error}");
    }
    weights::load();
    super::body_metrics::load();
    if let Err(error) = finance::load() {
        log::error!("capture: ledger refresh failed: {error}");
    }
    Ok(())
}

#[cfg(test)]
mod ask_user_tests {
    use super::*;
    use crate::domain::capture::{AskAnswer, AskOption, AskQuestion, AskUser};

    fn pending() -> Draft {
        let mut draft = new();
        draft.status = Status::Ready;
        draft.transcript.push(Turn::Owner {
            text: "Lunch".into(),
            photo: false,
            images: Vec::new(),
        });
        draft.transcript.push(Turn::AskUser {
            request: AskUser {
                call_id: "ask-portion".into(),
                questions: vec![AskQuestion {
                    id: "portion".into(),
                    text: "How much did you eat?".into(),
                    reason: "The photo does not show consumption.".into(),
                    required: true,
                    options: vec![AskOption {
                        id: "half".into(),
                        label: "Half".into(),
                        description: "100 g".into(),
                    }],
                }],
                blocks: serde_json::json!([]),
                provider_output: None,
            },
        });
        draft
    }

    #[test]
    fn answer_is_bound_to_call_and_retry_does_not_duplicate_it() {
        let mut draft = pending();
        assert!(!ready(&draft));
        let before = draft.clone();
        assert!(prepare_turn(&mut draft).is_err());
        assert_eq!(
            draft, before,
            "no user input leaves pending decision untouched"
        );
        draft.answers.push(AskAnswer {
            question_id: "portion".into(),
            option_id: Some("half".into()),
            text: String::new(),
        });
        prepare_turn(&mut draft).unwrap();
        assert!(draft.answers.is_empty());
        assert!(
            matches!(draft.transcript.last(), Some(Turn::ToolAnswer { call_id, answers, .. })
            if call_id == "ask-portion" && answers[0].question_id == "portion")
        );
        let committed = draft.clone();
        prepare_turn(&mut draft).unwrap();
        assert_eq!(
            draft, committed,
            "failed continuation retries the same tool result"
        );
    }

    #[test]
    fn wrong_question_answer_is_rejected_without_consuming_evidence() {
        let mut draft = pending();
        draft.answers.push(AskAnswer {
            question_id: "another-question".into(),
            option_id: Some("half".into()),
            text: String::new(),
        });
        draft.attachments.push("label.png".into());
        let before = draft.clone();
        assert!(prepare_turn(&mut draft).is_err());
        assert_eq!(draft, before);
    }

    #[test]
    fn image_only_answer_keeps_evidence_with_the_tool_result() {
        let mut draft = pending();
        draft.attachments.push("label.png".into());
        prepare_turn(&mut draft).unwrap();
        assert!(draft.attachments.is_empty());
        assert!(
            matches!(draft.transcript.last(), Some(Turn::ToolAnswer { call_id, images, .. })
            if call_id == "ask-portion" && images == &["label.png"])
        );
        assert!(draft.image_names().contains(&"label.png".to_owned()));
    }
    #[test]
    fn answered_tool_still_requires_a_final_reply_before_confirmation() {
        let mut draft = pending();
        draft.correction = "I ate half".into();
        prepare_turn(&mut draft).unwrap();
        assert!(awaiting_tool_resolution(&draft));
        draft.transcript.push(Turn::Assistant {
            reply: "{}".into(),
            records: 0,
            questions: Vec::new(),
            provider_output: None,
        });
        assert!(!awaiting_tool_resolution(&draft));
    }
    #[test]
    fn a_new_tool_call_cannot_replace_an_unanswered_decision() {
        let mut draft = pending();
        let mut request = draft.pending_ask_user().unwrap().clone();
        request.call_id = "different-call".into();
        let before = draft.clone();
        assert!(accept_ask_user(&mut draft, request, "test".into()).is_err());
        assert_eq!(draft, before);
    }

    #[test]
    fn an_answered_tool_call_id_cannot_be_reused() {
        let mut draft = pending();
        let request = draft.pending_ask_user().unwrap().clone();
        draft.correction = "Half".into();
        prepare_turn(&mut draft).unwrap();
        let before = draft.clone();
        assert!(accept_ask_user(&mut draft, request, "test".into()).is_err());
        assert_eq!(draft, before);
    }
    #[test]
    fn explicit_submission_can_skip_all_optional_questions() {
        let mut draft = pending();
        let Some(Turn::AskUser { request }) = draft.transcript.last_mut() else {
            panic!("ask");
        };
        request.questions[0].required = false;
        prepare_turn(&mut draft).unwrap();
        assert!(
            matches!(draft.transcript.last(), Some(Turn::ToolAnswer { call_id, answers, text, images })
            if call_id == "ask-portion" && answers.is_empty() && text.is_empty() && images.is_empty())
        );
        assert!(awaiting_tool_resolution(&draft));
    }
}
