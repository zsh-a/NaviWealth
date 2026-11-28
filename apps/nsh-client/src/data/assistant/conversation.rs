//! Conversation composition and record cards. The model may only prepare drafts;
//! the existing capture transaction remains the sole confirmation boundary.
use super::*;
use crate::data::{capture, photos};
use crate::domain::{
    assistant_proposal, backup_bundle,
    capture::{AskAnswer, AskUser, Draft, Turn},
};
use std::collections::HashMap;

pub(super) const SELECTED: &str = "conversation.selected.v1";
thread_local! {
    static RECEIPTS: RefCell<HashMap<String, capture::CaptureUndo>> = RefCell::new(HashMap::new());
}

#[derive(Clone, PartialEq)]
pub(super) struct DiscardUndo {
    draft: Draft,
    outcomes: Vec<(String, store::RecordAction)>,
}

pub fn capture_focus() -> Option<String> {
    state().with(|s| s.capture_focus.clone())
}

pub fn focus_capture(id: &str) {
    state().update(|s| s.capture_focus = Some(id.into()));
}

pub fn clear_capture_focus(id: &str) {
    state().update(|s| {
        if s.capture_focus.as_deref() == Some(id) {
            s.capture_focus = None;
        }
    });
}

fn ensure_session() -> Result<Session, String> {
    if current().is_none() {
        new_session()?;
    }
    current().ok_or_else(|| "session_missing".into())
}

pub fn set_composer(text: String) -> Result<(), String> {
    if text.chars().count() > 8000 {
        return Err(copy(
            "Enter up to 8,000 characters",
            "请输入不超过 8,000 字的消息",
        ));
    }
    let mut session = ensure_session()?;
    if session.composer == text {
        return Ok(());
    }
    session.composer = text;
    if session.messages.is_empty() && !session.composer.trim().is_empty() {
        session.title = session.composer.trim().chars().take(48).collect();
    }
    session.updated_at_ms = clock::now_ms();
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}

pub fn add_attachment(name: String) -> Result<(), String> {
    if !backup_bundle::is_photo_name(&name) || photos::bytes(&name).is_none() {
        return Err(copy(
            "The image is unavailable. Attach it again.",
            "图片不可用，请重新添加。",
        ));
    }
    let mut session = ensure_session()?;
    if session.attachments.contains(&name) {
        return Ok(());
    }
    if session.attachments.len() >= 4 {
        return Err(copy("Attach up to four images", "每条消息最多添加四张图片"));
    }
    session.attachments.push(name);
    if session.messages.is_empty() && session.composer.trim().is_empty() {
        session.title = copy("Photo conversation", "图片对话");
    }
    session.updated_at_ms = clock::now_ms();
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}

pub fn remove_attachment(name: &str) -> Result<(), String> {
    let mut session = ensure_session()?;
    session.attachments.retain(|item| item != name);
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}

pub fn edit_capture(id: &str) -> Result<(), String> {
    if busy() {
        return Err(copy("Stop the current task first", "请先停止当前任务"));
    }
    let mut session = ensure_session()?;
    if !session
        .messages
        .iter()
        .any(|message| message.capture_id.as_deref() == Some(id))
        || capture::get(id).is_none()
    {
        return Err(copy(
            "This draft is no longer available",
            "这份草稿已不可用",
        ));
    }
    session.editing_capture = Some(id.into());
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}

pub fn cancel_edit_capture() -> Result<(), String> {
    let mut session = ensure_session()?;
    session.editing_capture = None;
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}

pub(super) fn refresh_sessions() -> Result<(), String> {
    let sessions = local(store::sessions)?;
    state().update(|s| s.sessions = sessions);
    Ok(())
}

pub fn confirm_capture(draft: &Draft) -> Result<(), String> {
    if busy() {
        return Err(copy("Wait for the task to finish", "请等待任务结束"));
    }
    let session = ensure_session()?;
    if !session
        .messages
        .iter()
        .any(|m| m.capture_id.as_deref() == Some(&draft.id))
    {
        return Err("conversation_draft_missing".into());
    }
    let receipt = capture::confirm_review(draft)?;
    RECEIPTS.with(|r| r.borrow_mut().insert(draft.id.clone(), receipt));
    refresh_sessions()
}

pub fn discard_capture(id: &str) -> Result<(), String> {
    if busy() {
        return Err(copy("Wait for the task to finish", "请等待任务结束"));
    }
    let session = ensure_session()?;
    if !session
        .messages
        .iter()
        .any(|m| m.capture_id.as_deref() == Some(id))
    {
        return Err("conversation_draft_missing".into());
    }
    let draft = capture::get(id).ok_or("draft_missing")?;
    let outcomes = local(|c| {
        let tx = c.unchecked_transaction().map_err(|_| "assistant_storage")?;
        store::record_capture_outcome(&tx, id, &draft.records, store::RecordStatus::Discarded)?;
        let outcomes = discarded_outcomes(&tx, id)?;
        tx.execute("DELETE FROM capture_drafts WHERE id=?1", [id])
            .map_err(|_| "assistant_storage")?;
        tx.commit().map_err(|_| "assistant_storage")?;
        Ok(outcomes)
    })?;
    state().update(|s| {
        s.discarded
            .insert(id.into(), DiscardUndo { draft, outcomes });
    });
    capture::load()?;
    refresh_sessions()
}

fn discarded_outcomes(
    c: &rusqlite::Connection,
    id: &str,
) -> Result<Vec<(String, store::RecordAction)>, String> {
    Ok(store::sessions(c)?
        .into_iter()
        .filter_map(|session| {
            session
                .record_actions
                .into_iter()
                .find(|a| a.capture_id == id)
                .map(|action| (session.id, action))
        })
        .collect())
}

pub fn can_restore_capture(id: &str) -> bool {
    state().with(|s| s.discarded.contains_key(id))
}

/// Restore the draft and retire its discard receipt together. Later actions,
/// session deletion and a replacement draft invalidate this app-lifetime undo.
pub fn restore_capture(id: &str) -> Result<(), String> {
    if busy() {
        return Err(copy("Wait for the task to finish", "请等待任务结束"));
    }
    let undo = state()
        .with_untracked(|s| s.discarded.get(id).cloned())
        .ok_or_else(|| copy("This draft can no longer be restored", "这份草稿已无法恢复"))?;
    local(|c| {
        let tx = c.unchecked_transaction().map_err(|_| "assistant_storage")?;
        let exists: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM capture_drafts WHERE id=?1)",
                [id],
                |r| r.get(0),
            )
            .map_err(|_| "assistant_storage")?;
        if exists || undo.outcomes.is_empty() || discarded_outcomes(&tx, id)? != undo.outcomes {
            return Err(copy(
                "The draft changed. Your newer changes were kept.",
                "草稿已变更，已保留较新的修改。",
            ));
        }
        for (session_id, expected) in &undo.outcomes {
            if expected.status != store::RecordStatus::Discarded {
                return Err("invalid_discard_undo".into());
            }
            let mut session = store::session(&tx, session_id)?.ok_or("session_missing")?;
            session.record_actions.retain(|a| a.capture_id != id);
            store::save_session(&tx, &session)?;
        }
        let body = serde_json::to_string(&undo.draft).map_err(|_| "assistant_storage")?;
        tx.execute(
            "INSERT INTO capture_drafts(id,created_at_ms,body) VALUES(?1,?2,?3)",
            rusqlite::params![id, undo.draft.created_at_ms, body],
        )
        .map_err(|_| "assistant_storage")?;
        tx.commit().map_err(|_| "assistant_storage".into())
    })?;
    state().update(|s| {
        s.discarded.remove(id);
    });
    capture::load()?;
    refresh_sessions()?;
    focus_capture(id);
    Ok(())
}

pub fn can_undo_capture(id: &str) -> bool {
    state().with(|_| ());
    RECEIPTS.with(|r| r.borrow().contains_key(id))
}
pub fn undo_capture(id: &str) -> Result<(), String> {
    if busy() {
        return Err(copy("Wait for the task to finish", "请等待任务结束"));
    }
    let receipt = RECEIPTS
        .with(|r| r.borrow().get(id).cloned())
        .ok_or("undo_expired")?;
    capture::undo(&receipt)?;
    RECEIPTS.with(|r| r.borrow_mut().remove(id));
    refresh_sessions()
}
pub fn view_capture(id: &str) -> Result<(), String> {
    let session = ensure_session()?;
    let action = session
        .record_actions
        .iter()
        .find(|a| a.capture_id == id && a.status == store::RecordStatus::Saved)
        .ok_or("saved_record_missing")?;
    crate::nav::push(crate::nav::Route::SavedBatch {
        id: id.into(),
        records: action.records.clone().into(),
    });
    Ok(())
}

pub(super) fn request_images(session: &Session) -> Result<Vec<String>, String> {
    let mut images = session
        .editing_capture
        .as_deref()
        .and_then(capture::get)
        .map(|d| d.sent_images())
        .unwrap_or_default();
    if images.is_empty() && session.attachments.is_empty() {
        // Reuse only the most recent image-bearing exchange within two user turns.
        // Long conversations never resend all historical photos.
        images = session
            .messages
            .iter()
            .rev()
            .filter(|m| m.role == Role::User)
            .take(2)
            .find(|m| !m.images.is_empty())
            .map(|m| m.images.clone())
            .unwrap_or_default();
    }
    for name in &session.attachments {
        if !images.contains(name) {
            images.push(name.clone());
        }
    }
    if images.len() > 4 {
        return Err(copy(
            "This request has more than four images. Start a new message or remove attachments.",
            "本次请求超过四张图片，请新建消息或移除附件。",
        ));
    }
    Ok(images)
}
pub(super) fn image_inputs(names: &[String]) -> Result<Vec<navi_assistant::ImageInput>, String> {
    names
        .iter()
        .map(|name| {
            let data = photos::bytes(name).ok_or_else(|| {
                copy(
                    "A referenced image is missing. Attach it again or start a new conversation.",
                    "引用的图片已缺失，请重新添加或新建对话。",
                )
            })?;
            let mime_type = if data.starts_with(b"\x89PNG") {
                "image/png"
            } else {
                "image/jpeg"
            }
            .into();
            Ok(navi_assistant::ImageInput { mime_type, data })
        })
        .collect()
}

pub(super) fn run_context(session: &Session, images: &[String]) -> Value {
    let drafts: Vec<_> = session
        .messages
        .iter()
        .filter_map(|m| m.capture_id.as_ref())
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .filter_map(|id| capture::get(id))
        .take(8)
        .map(|draft| {
            let mut value = json!({"capture_id":draft.id});
            super::super::vision::record_context(&mut value, &draft);
            let original = draft.sent_images();
            value["images_available"] = json!(original.iter().all(|name| images.contains(name)));
            if let Some(records) = value["current_records"].as_array_mut() {
                for record in records {
                    if let Some(number) = record["meal"]["source_image"].as_u64() {
                        let mapped = number
                            .checked_sub(1)
                            .and_then(|n| original.get(n as usize))
                            .and_then(|name| images.iter().position(|candidate| candidate == name))
                            .map(|index| index + 1);
                        record["meal"]["source_image"] = json!(mapped);
                    }
                }
            }
            value
        })
        .collect();
    json!({"pending_record_drafts":drafts,"editing_capture":session.editing_capture,
        "record_actions":session.record_actions.iter().rev().take(12).map(|action|json!({
            "capture_id":action.capture_id,"status":action.status,
            "record_count":action.records.len(),"saved_at_ms":action.saved_at_ms
        })).collect::<Vec<_>>(),
        "image_numbers":(1..=images.len()).collect::<Vec<_>>(),
        "question_proposals":session.pending.iter().filter_map(|p|match &p.kind {
            PendingKind::Questions{request,answers}=>Some(json!({"id":p.id,"questions":request.questions,"answers":answers})),
            _=>None,
        }).collect::<Vec<_>>(),
        "local_context":settings::ready_account().map(|account|super::super::capture_context::for_request(&account))})
}

pub(in crate::data) fn propose_records(
    session_id: &str,
    value: &Value,
    target: Option<&str>,
) -> Result<Value, String> {
    let mut session = state()
        .with_untracked(|s| s.sessions.iter().find(|v| v.id == session_id).cloned())
        .ok_or("session_missing")?;
    let (images, snapshots, request_id) = state().with_untracked(|s| {
        (
            s.active_images.clone(),
            s.draft_snapshots.clone(),
            s.request_id.clone(),
        )
    });
    let owner = session
        .messages
        .iter()
        .rev()
        .find(|m| m.role == Role::User)
        .ok_or("owner_message_missing")?;
    let owner_text = owner.text.clone();
    let explicit_target = target.or(session.editing_capture.as_deref());
    let explicit_target = explicit_target.map(str::to_owned);
    if let Some(target) = explicit_target.as_deref()
        && owner.record_targets.iter().any(|id| id == target)
    {
        if capture::get(target).is_some() {
            return Ok(json!({"status":"awaiting_confirmation","capture_id":target,
                "note":"This user message already updated the card. Do not apply the same correction twice. A further change requires a new user message."}));
        }
        if let Some(action) = session
            .record_actions
            .iter()
            .find(|a| a.capture_id == target)
        {
            return Ok(json!({"status":action.status,"capture_id":target,
                "note":"This request was already handled. Do not repeat the correction."}));
        }
        return Err("draft_no_longer_pending".into());
    }
    let mut draft = if let Some(id) = explicit_target.as_deref() {
        let expected = snapshots.get(id).ok_or("draft_not_in_request")?;
        let current = capture::get(id).ok_or("draft_no_longer_pending")?;
        if expected != &current {
            return Err("draft_changed_review_again".into());
        }
        if !current
            .sent_images()
            .iter()
            .all(|name| images.contains(name))
        {
            return Err("draft_images_not_in_request".into());
        }
        current
    } else {
        let mut draft = capture::new();
        draft.id = format!("{request_id}-record");
        draft
    };
    assistant_proposal::apply_with_images(value, &mut draft, &images, &owner_text)
        .map_err(|_| "capture_invalid_records".to_owned())?;
    if explicit_target.is_none() {
        // A retry of the same submitted message never creates another batch.
        if let Some(existing) = capture::get(&draft.id) {
            if existing.records == draft.records {
                return Ok(json!({"status":"awaiting_confirmation","capture_id":draft.id}));
            }
            return Err("draft_already_proposed".into());
        }
        if let Some(action) = session
            .record_actions
            .iter()
            .find(|a| a.capture_id == draft.id)
        {
            return Ok(
                json!({"status":action.status,"capture_id":draft.id,"note":"This request was already handled. Do not create it again."}),
            );
        }
        if session
            .messages
            .iter()
            .filter_map(|m| m.capture_id.as_deref())
            .collect::<std::collections::HashSet<_>>()
            .into_iter()
            .filter(|id| capture::get(id).is_some())
            .count()
            >= 8
        {
            return Err("too_many_proposals".into());
        }
    }
    if let Some(target) = explicit_target.as_ref()
        && let Some(owner) = session
            .messages
            .iter_mut()
            .rev()
            .find(|m| m.role == Role::User)
    {
        owner.editing_capture = Some(target.clone());
    }
    draft.model = settings::ready_account()
        .map(|a| a.model)
        .unwrap_or_default();
    if let Some(owner) = session
        .messages
        .iter_mut()
        .rev()
        .find(|m| m.role == Role::User)
        && !owner.record_targets.contains(&draft.id)
    {
        owner.record_targets.push(draft.id.clone());
    }
    if let Some(message) = session
        .messages
        .iter_mut()
        .find(|m| m.capture_id.as_deref() == Some(&draft.id))
    {
        message.text = value["text"].as_str().unwrap_or_default().into();
    } else {
        session.messages.push(Message {
            id: id(),
            role: Role::Assistant,
            text: value["text"].as_str().unwrap_or_default().into(),
            capture_id: Some(draft.id.clone()),
            created_at_ms: clock::now_ms(),
            ..Default::default()
        });
    }
    session.editing_capture = None;
    session.updated_at_ms = clock::now_ms();
    local(|c| {
        let tx = c.unchecked_transaction().map_err(|_| "assistant_storage")?;
        let body = serde_json::to_string(&draft).map_err(|_| "assistant_storage")?;
        tx.execute("INSERT INTO capture_drafts(id,created_at_ms,body) VALUES(?1,?2,?3) ON CONFLICT(id) DO UPDATE SET body=excluded.body", rusqlite::params![draft.id,draft.created_at_ms,body]).map_err(|_|"assistant_storage")?;
        store::save_session(&tx, &session)?;
        tx.commit().map_err(|_| "assistant_storage".into())
    })?;
    capture::load()?;
    publish(session);
    Ok(
        json!({"status":"awaiting_confirmation","capture_id":draft.id,"note":"Editable draft only. No business record has been saved."}),
    )
}

pub(in crate::data) fn ask_questions(session_id: &str, args: &Value) -> Result<Value, String> {
    let question_id = id();
    let blocks = json!([{"type":"tool_use","id":question_id,"name":"ask_user","input":args}]);
    let request =
        AskUser::parse(&question_id, args, blocks).map_err(|_| "capture_invalid_questions")?;
    if let Some(existing) = state().with_untracked(|s| {
        s.sessions
            .iter()
            .find(|v| v.id == session_id)
            .and_then(|session| {
                session.pending.iter().find(|p| {
                    matches!(&p.kind,
            PendingKind::Questions {request: prior, ..} if prior.questions == request.questions)
                })
            })
            .map(|p| p.id.clone())
    }) {
        return Ok(json!({"status":"awaiting_confirmation","proposal_id":existing}));
    }
    propose(
        session_id,
        PendingKind::Questions {
            request,
            answers: Vec::new(),
        },
    )
}

pub fn answer_questions(
    expected: &str,
    answers: Vec<AskAnswer>,
    text: String,
) -> Result<(), String> {
    let mut session = ensure_session()?;
    let index = session
        .pending
        .iter()
        .position(|p| p.id == expected)
        .ok_or("question_no_longer_pending")?;
    let PendingKind::Questions { request, .. } = &session.pending[index].kind else {
        return Err("question_no_longer_pending".into());
    };
    request
        .validate_answers(&answers, &text, !session.attachments.is_empty())
        .map_err(|_| "invalid_question_answers")?;
    let mut lines = Vec::new();
    for answer in answers {
        let question = request
            .questions
            .iter()
            .find(|q| q.id == answer.question_id)
            .ok_or("invalid_question_answers")?;
        let selected = answer
            .option_id
            .as_ref()
            .and_then(|id| question.options.iter().find(|o| &o.id == id));
        lines.push(format!(
            "{}: {}",
            question.text,
            selected.map(|o| o.label.as_str()).unwrap_or(&answer.text)
        ));
    }
    if !text.trim().is_empty() {
        lines.push(text);
    }
    if lines.is_empty() {
        lines.push(copy("Skip optional questions", "跳过可选问题"));
    }
    session.composer = lines.join("\n");
    // Retain the question until send is accepted; prepare_send resolves this ID
    // atomically with the new owner message.
    local(|c| store::save_session(c, &session))?;
    state().update(|s| s.answering = Some(expected.into()));
    publish(session.clone());
    let result = send(session.composer);
    if result.is_err() {
        state().update(|s| s.answering = None);
    }
    result
}

pub fn open_capture_session(capture_id: &str) -> Result<(), String> {
    if let Some(session_id) = state().with_untracked(|s| {
        s.sessions
            .iter()
            .find(|v| {
                v.messages
                    .iter()
                    .any(|m| m.capture_id.as_deref() == Some(capture_id))
            })
            .map(|v| v.id.clone())
    }) {
        select(&session_id)?;
    } else {
        let draft = capture::get(capture_id).ok_or("draft_missing")?;
        let session = adopt_draft(&draft)?;
        Storage::set_item(SELECTED, &session.id).map_err(|_| "session_selection_storage")?;
        state().update(|s| {
            s.selected = Some(session.id.clone());
            s.sessions.insert(0, session);
        });
    }
    focus_capture(capture_id);
    crate::nav::push(crate::nav::Route::Assistant);
    Ok(())
}

fn adopt_draft(draft: &Draft) -> Result<Session, String> {
    let mut session = Session {
        id: format!("conversation-{}", draft.id),
        title: draft.input.chars().take(48).collect(),
        created_at_ms: draft.created_at_ms,
        updated_at_ms: draft.created_at_ms,
        ..Default::default()
    };
    if session.title.is_empty() {
        session.title = copy("Photo record", "图片记录");
    }
    if draft.transcript.is_empty() {
        session.composer = draft.input.clone();
        session.attachments = draft.staged_images();
    } else {
        // Keep owner corrections and questions visible without replaying legacy
        // provider tool identities through the new agent runtime.
        for turn in &draft.transcript {
            let (role, text, images) = match turn {
                Turn::Owner { text, images, .. } => (Role::User, text.clone(), images.clone()),
                Turn::ToolAnswer {
                    text,
                    answers,
                    images,
                    ..
                } => {
                    let mut lines = answers
                        .iter()
                        .map(|answer| {
                            format!(
                                "{}: {}",
                                answer.question_id,
                                answer.option_id.as_deref().unwrap_or(&answer.text)
                            )
                        })
                        .collect::<Vec<_>>();
                    if !text.is_empty() {
                        lines.push(text.clone());
                    }
                    (Role::User, lines.join("\n"), images.clone())
                }
                Turn::AskUser { request } => (
                    Role::Assistant,
                    request
                        .questions
                        .iter()
                        .map(|q| q.text.clone())
                        .collect::<Vec<_>>()
                        .join("\n"),
                    Vec::new(),
                ),
                Turn::Assistant {
                    records, questions, ..
                } => (
                    Role::Assistant,
                    if questions.is_empty() {
                        copy(
                            &format!("Prepared {records} records"),
                            &format!("已准备 {records} 条记录"),
                        )
                    } else {
                        questions
                            .iter()
                            .map(|q| q.text.clone())
                            .collect::<Vec<_>>()
                            .join("\n")
                    },
                    Vec::new(),
                ),
            };
            session.messages.push(Message {
                id: id(),
                role,
                text,
                images,
                created_at_ms: draft.created_at_ms,
                ..Default::default()
            });
        }
        if let Some(first) = session.messages.iter_mut().find(|m| m.role == Role::User)
            && first.images.is_empty()
            && let Some(photo) = &draft.photo
        {
            first.images.push(photo.clone());
        }
        session.composer = draft.correction.clone();
        session.attachments = draft.staged_images();
    }
    session.messages.push(Message {
        id: id(),
        role: Role::Assistant,
        text: String::new(),
        capture_id: Some(draft.id.clone()),
        created_at_ms: draft.created_at_ms,
        ..Default::default()
    });
    session.editing_capture = draft.records.is_empty().then(|| draft.id.clone());
    if let Some(request) = draft.pending_ask_user() {
        session.pending.push(PendingAction {
            id: id(),
            kind: PendingKind::Questions {
                request: request.clone(),
                answers: draft.answers.clone(),
            },
        });
    }
    local(|c| store::create_session(c, &session))?;
    Ok(session)
}

pub(super) fn migrate_drafts() -> Result<(), String> {
    let linked = local(store::linked_capture_ids)?;
    for draft in capture::all() {
        if !linked.contains(&draft.id) {
            adopt_draft(&draft)?;
        }
    }
    Ok(())
}

pub(super) fn clear_receipts() {
    RECEIPTS.with(|r| r.borrow_mut().clear());
}

pub fn set_question_answers(expected: &str, answers: &[AskAnswer]) -> Result<(), String> {
    let mut session = ensure_session()?;
    let proposal = session
        .pending
        .iter_mut()
        .find(|p| p.id == expected)
        .ok_or("question_no_longer_pending")?;
    let PendingKind::Questions {
        request,
        answers: stored,
    } = &mut proposal.kind
    else {
        return Err("question_no_longer_pending".into());
    };
    request
        .validate_answers(answers, "staged", false)
        .map_err(|_| "invalid_question_answers")?;
    *stored = answers.to_vec();
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}

pub(super) fn import_proposal(
    session: &mut Session,
    index: usize,
    value: Value,
) -> Result<(), String> {
    let mut draft = capture::new();
    draft.id = format!("{}-record", session.pending[index].id);
    assistant_proposal::apply(&value, &mut draft)?;
    session.messages.push(Message {
        id: id(),
        role: Role::Assistant,
        text: value["text"].as_str().unwrap_or_default().into(),
        capture_id: Some(draft.id.clone()),
        created_at_ms: clock::now_ms(),
        ..Default::default()
    });
    session.pending.remove(index);
    session.updated_at_ms = clock::now_ms();
    local(|c| {
        let tx = c.unchecked_transaction().map_err(|_| "assistant_storage")?;
        let body = serde_json::to_string(&draft).map_err(|_| "assistant_storage")?;
        tx.execute(
            "INSERT INTO capture_drafts(id,created_at_ms,body) VALUES(?1,?2,?3)",
            rusqlite::params![draft.id, draft.created_at_ms, body],
        )
        .map_err(|_| "assistant_storage")?;
        store::save_session(&tx, session)?;
        tx.commit().map_err(|_| "assistant_storage".into())
    })
}

pub(super) fn migrate_proposals() -> Result<(), String> {
    for mut session in local(store::sessions)? {
        while let Some((index, value)) =
            session
                .pending
                .iter()
                .enumerate()
                .find_map(|(i, p)| match &p.kind {
                    PendingKind::Records { proposal } => Some((i, proposal.clone())),
                    _ => None,
                })
        {
            import_proposal(&mut session, index, value)?;
        }
    }
    capture::load()
}
