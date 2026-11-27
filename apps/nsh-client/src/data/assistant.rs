//! App-owned assistant lifecycle. Model work runs on Tokio; all business and
//! SQLite access stays on the NSH owner thread. A cancelled/restored run loses
//! its generation before any late callback can change the current database.
use std::{
    cell::RefCell,
    sync::{
        Arc, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

use futures::{
    StreamExt,
    channel::{mpsc, oneshot},
};
use navi_assistant::{CancellationToken, Config, Event, Limits, RunResult};
use nsh_core::{prelude::*, storage::Storage};
use serde_json::{Value, json};

use super::{assistant_store as store, assistant_tools, assistant_web, clock, db, settings, tasks};
use crate::domain::account::Provider;
use store::{ActionOutcome, ActionStatus, Memory, Message, Role, Session, Status};
pub use store::{PendingAction, PendingKind};

const CONSENT: &str = "assistant.consent.v1";
const SEARCH_KEY: &str = "secret.assistant-search-key.v1";
static IDS: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Default, PartialEq)]
struct State {
    sessions: Vec<Session>,
    memories: Vec<Memory>,
    selected: Option<String>,
    running: Option<String>,
    generation: u64,
    error: Option<String>,
    activity: String,
    consent: Vec<String>,
    search_key: String,
}
thread_local! { static CANCEL: RefCell<Option<CancellationToken>> = const { RefCell::new(None) }; }
fn state() -> Signal<State> {
    global::<State>()
}
fn id() -> String {
    format!(
        "assistant-{}-{}",
        clock::now_ms(),
        IDS.fetch_add(1, Ordering::Relaxed)
    )
}
fn local<T>(f: impl FnOnce(&rusqlite::Connection) -> Result<T, String>) -> Result<T, String> {
    db::with(f).ok_or_else(|| copy("Local storage is unavailable", "本地存储不可用"))?
}
pub(super) fn copy(en: &str, zh: &str) -> String {
    if crate::i18n::s().lang == crate::domain::recognition::Lang::Zh {
        zh.into()
    } else {
        en.into()
    }
}

pub fn load() -> Result<(), String> {
    local(store::recover)?;
    let sessions = local(store::sessions)?;
    let memories = local(store::memories)?;
    state().set(State {
        selected: sessions.first().map(|s| s.id.clone()),
        sessions,
        memories,
        consent: Storage::get_item(CONSENT)
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default(),
        search_key: Storage::get_item(SEARCH_KEY).unwrap_or_default(),
        generation: IDS.fetch_add(1, Ordering::Relaxed),
        ..State::default()
    });
    Ok(())
}
#[derive(Clone, PartialEq)]
pub struct ConversationSummary {
    pub id: String,
    pub title: String,
    pub updated_at_ms: i64,
    pub status: Status,
}
pub fn conversation_list() -> Vec<ConversationSummary> {
    state().with(|s| {
        let mut list: Vec<_> = s
            .sessions
            .iter()
            .map(|v| ConversationSummary {
                id: v.id.clone(),
                title: v.title.clone(),
                updated_at_ms: v.updated_at_ms,
                status: v.status,
            })
            .collect();
        list.sort_by_key(|v| std::cmp::Reverse(v.updated_at_ms));
        list
    })
}
/// UI reads do not copy provider payloads, signatures or tool-result bodies.
pub fn current_view() -> Option<Session> {
    state().with(|s| {
        s.sessions
            .iter()
            .find(|v| Some(&v.id) == s.selected.as_ref())
            .map(|v| Session {
                id: v.id.clone(),
                title: v.title.clone(),
                created_at_ms: v.created_at_ms,
                updated_at_ms: v.updated_at_ms,
                messages: v.messages.clone(),
                status: v.status,
                pending: v.pending.clone(),
                ..Session::default()
            })
    })
}
fn current() -> Option<Session> {
    state().with(|s| {
        s.sessions
            .iter()
            .find(|v| Some(&v.id) == s.selected.as_ref())
            .cloned()
    })
}
pub fn busy() -> bool {
    state().with(|s| s.running.is_some())
}
pub fn error() -> Option<String> {
    state().with(|s| s.error.clone())
}
pub fn status_text() -> String {
    state().with(|s| {
        if s.running.is_some() {
            return s.activity.clone();
        }
        match s
            .sessions
            .iter()
            .find(|v| Some(&v.id) == s.selected.as_ref())
            .map(|v| v.status)
        {
            Some(Status::Interrupted) => copy(
                "Interrupted. Send a message to continue.",
                "上次任务已中断，发送消息可继续。",
            ),
            Some(Status::Failed) => copy(
                "The last request failed. You can send again.",
                "上次请求未完成，可以重新发送。",
            ),
            _ => String::new(),
        }
    })
}
pub fn select(id: &str) -> Result<(), String> {
    // Keep in-flight streaming content; otherwise reload the durable record.
    if !state().with_untracked(|s| s.running.as_deref() == Some(id)) {
        let session = local(|c| store::session(c, id))?.ok_or("session_missing")?;
        publish(session);
    }
    state().update(|s| {
        s.selected = Some(id.into());
        s.error = None;
    });
    Ok(())
}
pub fn new_session() -> Result<(), String> {
    let now = clock::now_ms();
    let session = Session {
        id: id(),
        title: copy("New conversation", "新对话"),
        created_at_ms: now,
        updated_at_ms: now,
        ..Session::default()
    };
    local(|c| store::create_session(c, &session))?;
    state().update(|s| {
        s.selected = Some(session.id.clone());
        s.sessions.insert(0, session);
        s.error = None;
    });
    Ok(())
}
pub fn delete_session(id: &str) -> Result<(), String> {
    if state().with_untracked(|s| s.running.as_deref() == Some(id)) {
        return Err(copy(
            "Stop this task before deleting it",
            "请先停止任务再删除对话",
        ));
    }
    local(|c| store::delete_session(c, id))?;
    state().update(|s| {
        s.sessions.retain(|v| v.id != id);
        if s.selected.as_deref() == Some(id) {
            s.selected = s.sessions.first().map(|v| v.id.clone());
        }
    });
    Ok(())
}
pub fn memories() -> Vec<Memory> {
    state().with(|s| s.memories.clone())
}
pub fn save_memory(text: String) -> Result<(), String> {
    let memory = Memory {
        id: id(),
        text: text.trim().into(),
        source_session: None,
        updated_at_ms: clock::now_ms(),
    };
    local(|c| store::save_memory(c, &memory))?;
    refresh_memories()
}
pub fn delete_memory(id: &str) -> Result<(), String> {
    local(|c| store::delete_memory(c, id))?;
    refresh_memories()
}
pub fn update_memory(id: &str, text: String) -> Result<(), String> {
    let mut memory = memories()
        .into_iter()
        .find(|m| m.id == id)
        .ok_or("memory_missing")?;
    memory.text = text.trim().into();
    memory.updated_at_ms = clock::now_ms();
    local(|c| store::save_memory(c, &memory))?;
    refresh_memories()
}
fn refresh_memories() -> Result<(), String> {
    let memories = local(store::memories)?;
    state().update(|s| s.memories = memories);
    Ok(())
}
pub fn ready() -> bool {
    settings::ready_account().is_some()
}
pub fn target() -> String {
    settings::ready_account()
        .map(|a| {
            format!(
                "{} · {}{}",
                a.model,
                a.host(),
                if a.is_cleartext() { " (HTTP)" } else { "" }
            )
        })
        .unwrap_or_default()
}
pub fn consented() -> bool {
    settings::ready_account()
        .is_some_and(|a| state().with(|s| s.consent.contains(&a.fingerprint())))
}
pub fn grant_consent() -> Result<(), String> {
    let account =
        settings::ready_account().ok_or_else(|| copy("Configure a model first", "请先配置模型"))?;
    let mut consent = state().with_untracked(|s| s.consent.clone());
    if !consent.contains(&account.fingerprint()) {
        consent.push(account.fingerprint());
    }
    Storage::set_item(
        CONSENT,
        serde_json::to_string(&consent).map_err(|_| "consent_storage")?,
    )
    .map_err(|_| "consent_storage")?;
    state().update(|s| s.consent = consent);
    Ok(())
}
pub fn search_key() -> String {
    state().with(|s| s.search_key.clone())
}
pub fn search_configured() -> bool {
    !search_key().is_empty()
}
pub fn set_search_key(value: &str) -> Result<(), String> {
    let value = value.trim();
    if value.len() > 4096 || value.chars().any(char::is_control) {
        return Err("invalid_search_key".into());
    }
    Storage::set_item(SEARCH_KEY, value).map_err(|_| "search_key_storage")?;
    state().update(|s| s.search_key = value.into());
    Ok(())
}
pub fn pending() -> Option<PendingAction> {
    state().with(|s| {
        s.sessions
            .iter()
            .find(|v| Some(&v.id) == s.selected.as_ref())
            .and_then(|v| v.pending.first())
            .cloned()
    })
}
pub fn dismiss_pending(expected: &str) -> Result<(), String> {
    if busy() {
        return Err(copy("Wait for the task to finish", "请等待任务结束"));
    }
    let mut session = current().ok_or("session_missing")?;
    if session.pending.first().is_none_or(|p| p.id != expected) {
        return Err(copy(
            "This proposal has changed. Review it again.",
            "提议已改变，请重新核对。",
        ));
    }
    let action = session.pending.remove(0);
    outcome(
        &mut session,
        ActionOutcome {
            proposal_id: action.id,
            status: ActionStatus::Dismissed,
            capture_id: None,
        },
    );
    session.updated_at_ms = clock::now_ms();
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}
pub fn confirm_pending(expected: &str) -> Result<(), String> {
    if busy() {
        return Err(copy("Wait for the task to finish", "请等待任务结束"));
    }
    let mut session = current().ok_or("session_missing")?;
    let action = session.pending.first().cloned().ok_or("proposal_missing")?;
    if action.id != expected {
        return Err(copy(
            "This proposal has changed. Review it again.",
            "提议已改变，请重新核对。",
        ));
    }
    let proposal_id = action.id.clone();
    session.pending.remove(0);
    session.updated_at_ms = clock::now_ms();
    let mut capture_id = None;
    local(|c| {
        let tx = c.unchecked_transaction().map_err(|_| "assistant_storage")?;
        match action.kind {
            PendingKind::Memory { text } => store::save_memory(
                &tx,
                &Memory {
                    id: action.id,
                    text,
                    source_session: Some(session.id.clone()),
                    updated_at_ms: clock::now_ms(),
                },
            )?,
            kind @ (PendingKind::Capture { .. } | PendingKind::Records { .. }) => {
                let mut draft = super::capture::new();
                match kind {
                    PendingKind::Capture { text } => {
                        if text.chars().count() > crate::domain::capture::MAX_INPUT {
                            return Err("proposal_too_large".into());
                        }
                        draft.input = text;
                    }
                    PendingKind::Records { proposal } => {
                        crate::domain::assistant_proposal::apply(&proposal, &mut draft)?;
                        // A host label, never the model's description, is the
                        // neutral entry into capture (including later corrections).
                        draft.input =
                            copy("Review assistant-proposed records", "核对助手提议的记录");
                        if let Some(crate::domain::capture::Turn::Owner { text, .. }) =
                            draft.transcript.first_mut()
                        {
                            *text = draft.input.clone();
                        }
                    }
                    PendingKind::Memory { .. } => unreachable!(),
                }
                let body = serde_json::to_string(&draft).map_err(|_| "assistant_storage")?;
                tx.execute(
                    "INSERT INTO capture_drafts(id,created_at_ms,body) VALUES(?1,?2,?3)",
                    rusqlite::params![draft.id, draft.created_at_ms, body],
                )
                .map_err(|_| "assistant_storage")?;
                capture_id = Some(draft.id);
            }
        }
        session.messages.push(Message {
            id: id(),
            role: Role::Tool,
            text: copy("Proposal confirmed", "已确认提议"),
        });
        outcome(
            &mut session,
            ActionOutcome {
                proposal_id,
                status: ActionStatus::Confirmed,
                capture_id: capture_id.clone(),
            },
        );
        store::save_session(&tx, &session)?;
        tx.commit().map_err(|_| "assistant_storage".to_owned())
    })?;
    publish(session);
    refresh_memories()?;
    if let Some(id) = capture_id {
        super::capture::load()?;
        super::incoming::show_capture(id);
        crate::nav::truncate(0);
    }
    Ok(())
}

fn outcome(session: &mut Session, outcome: ActionOutcome) {
    session.action_outcomes.push(outcome);
    if session.action_outcomes.len() > 32 {
        session.action_outcomes.remove(0);
    }
}

fn publish(session: Session) {
    state().update(|s| {
        if let Some(old) = s.sessions.iter_mut().find(|v| v.id == session.id) {
            *old = session;
        }
    });
}
fn mutate_session(id: &str, f: impl FnOnce(&mut Session)) {
    state().update(|s| {
        if let Some(session) = s.sessions.iter_mut().find(|v| v.id == id) {
            f(session);
        }
    });
}
fn save(id: &str) -> Result<(), String> {
    let mut session = state()
        .with_untracked(|s| s.sessions.iter().find(|v| v.id == id).cloned())
        .ok_or("session_missing")?;
    session.updated_at_ms = clock::now_ms().max(session.updated_at_ms);
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(())
}
fn runtime() -> Result<&'static tokio::runtime::Runtime, String> {
    static RUNTIME: OnceLock<Result<tokio::runtime::Runtime, String>> = OnceLock::new();
    RUNTIME
        .get_or_init(|| {
            tokio::runtime::Builder::new_multi_thread()
                .worker_threads(2)
                .enable_all()
                .build()
                .map_err(|_| "assistant_unavailable".into())
        })
        .as_ref()
        .map_err(Clone::clone)
}
enum WorkerEvent {
    Model(Event),
    Tool {
        name: String,
        args: Value,
        reply: oneshot::Sender<Result<Value, String>>,
    },
    Finished(Result<RunResult, String>),
}
struct CancelOnDrop(CancellationToken);
impl Drop for CancelOnDrop {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

pub fn send(text: String) -> Result<(), String> {
    let text = text.trim().to_owned();
    if text.is_empty() || text.chars().count() > 8000 {
        return Err(copy(
            "Enter up to 8,000 characters",
            "请输入不超过 8,000 字的消息",
        ));
    }
    if busy() {
        return Err(copy("A task is already running", "已有任务正在运行"));
    }
    let account =
        settings::ready_account().ok_or_else(|| copy("Configure a model first", "请先配置模型"))?;
    if !consented() {
        return Err(copy(
            "Confirm the model destination first",
            "请先确认模型的数据发送范围",
        ));
    }
    let runtime = runtime()?;
    if current().is_none() {
        new_session()?;
    }
    let mut session = current().ok_or("session_missing")?;
    if !session.pending.is_empty() {
        return Err(copy(
            "Review the pending proposal first",
            "请先处理待确认的提议",
        ));
    }
    if session
        .model_target
        .as_ref()
        .is_some_and(|target| *target != account.fingerprint())
    {
        return Err(copy(
            "The model changed. Start a new conversation.",
            "模型配置已改变，请新建对话。",
        ));
    }
    if session.messages.len() > 1800 || session.history.len() > 1800 {
        return Err(copy(
            "This conversation is full. Start a new one.",
            "此对话已满，请新建对话。",
        ));
    }
    if session.messages.is_empty() {
        session.title = text.chars().take(48).collect();
    }
    session.messages.push(Message {
        id: id(),
        role: Role::User,
        text: text.clone(),
    });
    session.status = Status::Running;
    session.model_target = Some(account.fingerprint());
    session.updated_at_ms = clock::now_ms();
    local(|c| store::save_session(c, &session))?;
    let session_id = session.id.clone();
    let history = session.history.clone();
    let context_summary = session.context_summary.clone();
    publish(session);
    let generation = IDS.fetch_add(1, Ordering::Relaxed);
    log::debug!(
        "assistant: starting run {generation}, {} saved messages",
        history.len()
    );
    state().update(|s| {
        s.running = Some(session_id.clone());
        s.generation = generation;
        s.error = None;
        s.activity = copy("Thinking…", "正在思考…");
    });
    let cancel = CancellationToken::new();
    CANCEL.with(|c| *c.borrow_mut() = Some(cancel.clone()));
    let (tx, rx) = mpsc::unbounded();
    let callback = tx.clone();
    let events = Arc::new(move |event| {
        let _ = callback.unbounded_send(WorkerEvent::Model(event));
    });
    let callback = tx.clone();
    let key = search_key();
    let handler: navi_assistant::ToolHandler = Arc::new(move |name, args| {
        let callback = callback.clone();
        let key = key.clone();
        Box::pin(async move {
            match name.as_str() {
                "web_search" => {
                    assistant_web::search(assistant_tools::string(&args, "query", 500)?, &key).await
                }
                "web_fetch" => {
                    assistant_web::fetch(assistant_tools::string(&args, "url", 4096)?).await
                }
                _ => {
                    let (reply, result) = oneshot::channel();
                    callback
                        .unbounded_send(WorkerEvent::Tool { name, args, reply })
                        .map_err(|_| "assistant_cancelled")?;
                    result.await.map_err(|_| "assistant_cancelled".to_owned())?
                }
            }
        })
    });
    let outcomes = state().with_untracked(|s| {
        s.sessions
            .iter()
            .find(|v| v.id == session_id)
            .map(|v| v.action_outcomes.clone())
            .unwrap_or_default()
    });
    let mut system_prompt = assistant_tools::system_prompt();
    system_prompt.push_str("\nTrusted app action outcomes, newer than prior tool results. Confirmed record proposal means only a capture draft was opened for review, not that a business record was posted. Query confirmed records to verify a later save:\n");
    system_prompt.push_str(&json!(outcomes).to_string());
    let config = Config {
        provider: match account.provider {
            Provider::Anthropic => navi_assistant::Provider::Anthropic,
            Provider::OpenAiCompatible => navi_assistant::Provider::OpenAiCompatible,
            Provider::OpenAiResponses => navi_assistant::Provider::OpenAiResponses,
        },
        base_url: account.normalized_base_url(),
        api_key: account.api_key,
        model: account.model,
        system_prompt,
        limits: Limits::default(),
        context_summary,
    };
    let worker_cancel = cancel.clone();
    runtime.spawn(async move {
        let result = navi_assistant::run(
            config,
            history,
            text,
            assistant_tools::specs(),
            handler,
            events,
            worker_cancel,
        )
        .await;
        let _ = tx.unbounded_send(WorkerEvent::Finished(result));
    });
    tasks::spawn_app(drive(session_id, generation, cancel, rx));
    Ok(())
}

async fn drive(
    session_id: String,
    generation: u64,
    cancel: CancellationToken,
    mut rx: mpsc::UnboundedReceiver<WorkerEvent>,
) {
    let _guard = CancelOnDrop(cancel.clone());
    while let Some(event) = rx.next().await {
        if !state().with_untracked(|s| {
            s.generation == generation && s.running.as_deref() == Some(&session_id)
        }) {
            break;
        }
        match event {
            WorkerEvent::Model(Event::SummaryStarted) => {
                if !cancel.is_cancelled() {
                    state().update(|s| {
                        s.activity = copy("Summarizing earlier conversation…", "正在整理早期对话…")
                    });
                }
            }
            WorkerEvent::Model(Event::SummaryUpdated { summary, history }) => {
                if cancel.is_cancelled() {
                    continue;
                }
                // The digest binds the summary to this exact native prefix.
                // Keep both in one session update, including on recovery/backup.
                mutate_session(&session_id, |s| {
                    s.history = history;
                    s.context_summary = Some(summary);
                    s.messages.push(Message {
                        id: id(),
                        role: Role::Tool,
                        text: copy(
                            "Earlier conversation summarized; the original messages remain saved.",
                            "已整理早期对话，原始消息仍保存在本地。",
                        ),
                    });
                });
                if save(&session_id).is_err() {
                    cancel.cancel();
                    state().update(|s| {
                        s.error = Some(copy("Could not save the conversation", "对话保存失败"))
                    });
                } else {
                    state().update(|s| s.activity = copy("Thinking…", "正在思考…"));
                }
            }
            WorkerEvent::Tool { name, args, reply } => {
                let result = if cancel.is_cancelled() {
                    Err("assistant_cancelled".into())
                } else {
                    assistant_tools::execute(&session_id, &name, &args)
                };
                let _ = reply.send(result);
            }
            WorkerEvent::Model(Event::TextDelta(text)) => mutate_session(&session_id, |s| {
                if let Some(last) = s.messages.last_mut().filter(|m| m.role == Role::Assistant) {
                    last.text.push_str(&text);
                } else {
                    s.messages.push(Message {
                        id: id(),
                        role: Role::Assistant,
                        text,
                    });
                }
            }),
            WorkerEvent::Model(Event::ToolStarted { name }) => {
                log::debug!("assistant: run {generation}, tool {name}");
                let label = assistant_tools::label(&name);
                state().update(|s| s.activity = label.clone());
                mutate_session(&session_id, |s| {
                    s.messages.push(Message {
                        id: id(),
                        role: Role::Tool,
                        text: label,
                    })
                });
            }
            WorkerEvent::Model(Event::ToolFinished { name, is_error }) => {
                if is_error {
                    mutate_session(&session_id, |s| {
                        s.messages.push(Message {
                            id: id(),
                            role: Role::Tool,
                            text: format!(
                                "{} · {}",
                                assistant_tools::label(&name),
                                copy("unavailable", "未完成")
                            ),
                        })
                    });
                }
            }
            WorkerEvent::Model(Event::ContextTrimmed { .. }) => {
                state().update(|s| s.activity = copy("Thinking…", "正在思考…"));
                mutate_session(&session_id, |s| {
                    s.messages.push(Message {
                        id: id(),
                        role: Role::Tool,
                        text: copy(
                            "Some earlier messages are outside this request's context; the originals remain saved.",
                            "部分早期消息未纳入本次上下文，原始消息仍已保存。",
                        ),
                    })
                });
            }
            WorkerEvent::Model(Event::Checkpoint(history)) => {
                mutate_session(&session_id, |s| s.history = history);
                if save(&session_id).is_err() {
                    cancel.cancel();
                    state().update(|s| {
                        s.error = Some(copy("Could not save the conversation", "对话保存失败"))
                    });
                }
            }
            WorkerEvent::Finished(result) => {
                let was_cancelled = cancel.is_cancelled();
                log::debug!(
                    "assistant: run {generation} finished, success={}, cancelled={was_cancelled}",
                    result.is_ok()
                );
                let failure = result.as_ref().err().cloned();
                mutate_session(&session_id, |s| {
                    s.status = if was_cancelled {
                        Status::Interrupted
                    } else if result.is_err() {
                        Status::Failed
                    } else {
                        Status::Idle
                    };
                    if let Ok(result) = result {
                        s.history = result.history;
                        if !was_cancelled {
                            s.context_summary = result.context_summary;
                        }
                        if !result.text.is_empty() {
                            if let Some(last) =
                                s.messages.last_mut().filter(|m| m.role == Role::Assistant)
                            {
                                last.text = result.text;
                            } else {
                                s.messages.push(Message {
                                    id: id(),
                                    role: Role::Assistant,
                                    text: result.text,
                                });
                            }
                        }
                    }
                });
                let saved = save(&session_id);
                state().update(|s| {
                    s.running = None;
                    s.activity = String::new();
                    if saved.is_err() {
                        s.error = Some(copy("Could not save the conversation", "对话保存失败"));
                    } else if !was_cancelled {
                        s.error = failure.map(|code| assistant_tools::error_text(&code));
                    }
                });
                CANCEL.with(|c| *c.borrow_mut() = None);
                return;
            }
        }
    }
    if state()
        .with_untracked(|s| s.generation == generation && s.running.as_deref() == Some(&session_id))
    {
        mutate_session(&session_id, |s| s.status = Status::Interrupted);
        let saved = save(&session_id);
        state().update(|s| {
            s.running = None;
            s.activity.clear();
            s.error = Some(if saved.is_err() {
                copy("Could not save the conversation", "对话保存失败")
            } else {
                copy(
                    "The task was interrupted. Send a message to continue.",
                    "任务已中断，发送消息可继续。",
                )
            });
        });
        CANCEL.with(|c| *c.borrow_mut() = None);
    }
}
pub fn cancel() {
    CANCEL.with(|c| {
        if let Some(cancel) = c.borrow().as_ref() {
            cancel.cancel();
        }
    });
}
/// Invalidates queued callbacks before restoring/replacing the database.
pub fn stop_for_restore() {
    cancel();
    state().update(|s| {
        s.generation = IDS.fetch_add(1, Ordering::Relaxed);
        if let Some(id) = s.running.take()
            && let Some(session) = s.sessions.iter_mut().find(|v| v.id == id)
        {
            session.status = Status::Interrupted;
        }
        s.activity.clear();
    });
}
pub(super) fn propose(session_id: &str, kind: PendingKind) -> Result<Value, String> {
    let mut session = state()
        .with_untracked(|s| s.sessions.iter().find(|v| v.id == session_id).cloned())
        .ok_or("session_missing")?;
    if let Some(existing) = session.pending.iter().find(|p| p.kind == kind) {
        return Ok(json!({"status":"awaiting_confirmation","proposal_id":existing.id}));
    }
    if session.pending.len() >= 8 {
        return Err("too_many_proposals".into());
    }
    let proposal = PendingAction { id: id(), kind };
    let proposal_id = proposal.id.clone();
    session.pending.push(proposal);
    session.updated_at_ms = clock::now_ms();
    local(|c| store::save_session(c, &session))?;
    publish(session);
    Ok(
        json!({"status":"awaiting_confirmation","proposal_id":proposal_id,
        "note":"Only a proposal was saved. The owner must use the confirmation button; no memory or business record was written."}),
    )
}
