//! 智能: device AI chat. The turn runs on the app-level tokio runtime
//! (the provider SDK owns the HTTP stack) and streams deltas into a
//! signal. Write tools never touch the database directly: their calls
//! surface as confirmation cards inside the bubble flow and only an
//! explicit user approval commits the write (through the domain
//! repositories, via the EventPipe back to this engine thread).

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::sync::Arc;

use futures::StreamExt;
use nsh_base::{input, theme};
use nsh_core::prelude::*;

use crate::ai::{self, LlmProfile, PendingWrite};
use crate::state::{DataVersion, Services};
use crate::ui;

#[derive(Clone, Copy, PartialEq)]
enum Role {
    User,
    Assistant,
}

/// Decision state of a confirm card. `Pending` is the only state that
/// accepts an action; a decision is recorded exactly once.
#[derive(Clone, PartialEq)]
enum ConfirmState {
    Pending,
    Executing,
    Applied(String),
    Denied,
    Failed(String),
}

#[derive(Clone, Copy, PartialEq)]
enum MsgKind {
    User,
    Assistant,
    Confirm,
}

#[derive(Clone, PartialEq)]
struct Msg {
    id: u64,
    kind: MsgKind,
    /// Bubble text, or the pending write's human summary on a card.
    text: String,
    streaming: bool,
    /// The write request (cards only).
    confirm: Option<PendingWrite>,
    confirm_state: ConfirmState,
    /// Card index for test ids (`confirm-approve-<n>` / `confirm-deny-<n>`).
    confirm_index: usize,
}

/// Events a background turn reports through the engine-thread pipe.
enum ChatEvent {
    Delta(String),
    Failed(String),
    /// Write requests extracted from write-tool outputs; delivered when
    /// the turn stream ends so the card never interrupts streaming.
    PendingWrites(Vec<PendingWrite>),
    /// An approved write finished executing.
    WriteResult {
        index: usize,
        result: Result<String, String>,
    },
    /// The turn ended; carries the accumulated assistant text for the
    /// multi-turn history.
    Finished {
        assistant_text: String,
    },
}

#[derive(Clone)]
struct ChatState {
    messages: Signal<Vec<Msg>>,
    draft: Signal<String>,
    busy: Signal<bool>,
    error: Signal<String>,
    /// Full multi-turn history (role + text), sent with every turn.
    history: Signal<Vec<ai::ChatTurnMessage>>,
    /// Write-confirmation outcomes to report to the model in the next
    /// turn's system note (engine-thread only).
    confirm_results: Rc<RefCell<Vec<String>>>,
    /// Shared id counters (stable `each` keys across clones).
    next_id: Rc<Cell<u64>>,
    next_confirm: Rc<Cell<usize>>,
    /// Engine-thread pump; created under the screen's owner.
    pipe: crate::bridge::EventPipe<ChatEvent>,
}

fn mock_profile() -> LlmProfile {
    LlmProfile {
        provider: "mock".to_owned(),
        base_url: String::new(),
        model: "mock-model".to_owned(),
        api_key: String::new(),
    }
}

fn mark_done(messages: &Signal<Vec<Msg>>) {
    messages.update(|m| {
        if let Some(last) = m
            .iter_mut()
            .rev()
            .find(|msg| msg.kind == MsgKind::Assistant)
        {
            last.streaming = false;
        }
    });
}

fn system_note(results: &[String]) -> Option<String> {
    if results.is_empty() {
        None
    } else {
        Some(format!(
            "以下是上一轮 AI 写入请求的用户确认结果（写入已经由用户决定）：\n- {}",
            results.join("\n- ")
        ))
    }
}

impl ChatState {
    fn push_bubble(&self, role: Role, text: String, streaming: bool) -> u64 {
        let id = self.next_id.get();
        self.next_id.set(id + 1);
        self.messages.update(|m| {
            m.push(Msg {
                id,
                kind: match role {
                    Role::User => MsgKind::User,
                    Role::Assistant => MsgKind::Assistant,
                },
                text,
                streaming,
                confirm: None,
                confirm_state: ConfirmState::Pending,
                confirm_index: usize::MAX,
            });
        });
        id
    }

    fn send(&self, services: &Arc<Services>, profile: Signal<Option<LlmProfile>>) {
        let text_value = self.draft.get().trim().to_owned();
        if text_value.is_empty() || self.busy.get() {
            return;
        }
        let profile_value = profile
            .get()
            .filter(|p| p.is_complete())
            .unwrap_or_else(mock_profile);
        self.busy.set(true);
        self.error.set(String::new());
        self.draft.set(String::new());

        // History snapshot BEFORE this turn's user message (the request
        // appends it as the new user turn).
        let history_snapshot = self.history.get();
        self.history.update(|h| {
            h.push(ai::ChatTurnMessage {
                role: "user".to_owned(),
                text: text_value.clone(),
            });
        });
        let system_note = system_note(&self.confirm_results.borrow());
        self.confirm_results.borrow_mut().clear();

        self.push_bubble(Role::User, text_value.clone(), false);
        self.push_bubble(Role::Assistant, String::new(), true);

        let _messages = self.messages;
        let _busy = self.busy;
        let _error = self.error;
        // The turn runs on the app-level tokio runtime; events cross to
        // the engine thread through the pipe (signals are
        // engine-thread-only).
        let job_services = services.clone();
        let tools = ai::tool_specs_for(&services.enabled_domain_keys());
        crate::bridge::spawn_job(
            services,
            self.pipe.sender(),
            move |tx: tokio::sync::mpsc::UnboundedSender<ChatEvent>| async move {
                let report = |tx: &tokio::sync::mpsc::UnboundedSender<ChatEvent>,
                              event: ChatEvent| {
                    let _ = tx.send(event);
                };
                let runner = match ai::runner(&job_services, &profile_value) {
                    Ok(runner) => runner,
                    Err(e) => {
                        report(&tx, ChatEvent::Failed(e));
                        report(
                            &tx,
                            ChatEvent::Finished {
                                assistant_text: String::new(),
                            },
                        );
                        return;
                    }
                };
                let request = ai::turn_request(
                    &profile_value,
                    &history_snapshot,
                    system_note,
                    text_value,
                    tools,
                );
                let mut stream = runner.stream(request);
                let mut assistant_text = String::new();
                let mut pending_writes = Vec::new();
                while let Some(event) = stream.next().await {
                    match event {
                        Ok(event) => {
                            if let Some(delta) = ai::delta_text(&event) {
                                assistant_text.push_str(delta);
                                report(&tx, ChatEvent::Delta(delta.to_owned()));
                            }
                            if let Some(message) = ai::error_text(&event) {
                                report(&tx, ChatEvent::Failed(message));
                            }
                            // Write tools report their pending request in
                            // the tool output; the card appears when the
                            // stream ends.
                            if event.kind == agent_chat::ChatTurnEventKind::ToolResult
                                && let Some(output) = event.tool_output.as_ref()
                                && let Some(write) = ai::pending_write_from_output(output)
                            {
                                pending_writes.push(write);
                            }
                            if event.kind == agent_chat::ChatTurnEventKind::Done {
                                break;
                            }
                        }
                        Err(e) => {
                            report(&tx, ChatEvent::Failed(e.to_string()));
                            break;
                        }
                    }
                }
                if !pending_writes.is_empty() {
                    report(&tx, ChatEvent::PendingWrites(pending_writes));
                }
                report(&tx, ChatEvent::Finished { assistant_text });
            },
        );
    }

    /// Approve a pending write (button on the card). The decision is
    /// recorded once; execution runs on the tokio runtime and reports
    /// back through the pipe (which bumps the shared data version).
    fn approve_write(&self, services: &Arc<Services>, index: usize) {
        let mut write: Option<PendingWrite> = None;
        self.messages.update(|m| {
            if let Some(msg) = m
                .iter_mut()
                .find(|msg| msg.kind == MsgKind::Confirm && msg.confirm_index == index)
                && msg.confirm_state == ConfirmState::Pending
            {
                msg.confirm_state = ConfirmState::Executing;
                write = msg.confirm.clone();
            }
        });
        let Some(write) = write else {
            return;
        };
        let job_services = services.clone();
        crate::bridge::spawn_job(
            services,
            self.pipe.sender(),
            move |tx: tokio::sync::mpsc::UnboundedSender<ChatEvent>| async move {
                let result = ai::execute_pending_write(&job_services, &write).await;
                let _ = tx.send(ChatEvent::WriteResult { index, result });
            },
        );
    }

    /// Reject a pending write: no database access, decision recorded for
    /// the next turn's system note.
    fn deny_write(&self, index: usize) {
        let mut summary = String::new();
        self.messages.update(|m| {
            if let Some(msg) = m
                .iter_mut()
                .find(|msg| msg.kind == MsgKind::Confirm && msg.confirm_index == index)
                && msg.confirm_state == ConfirmState::Pending
            {
                msg.confirm_state = ConfirmState::Denied;
                summary = msg.text.clone();
            }
        });
        if !summary.is_empty() {
            self.confirm_results
                .borrow_mut()
                .push(format!("已拒绝：{summary}（未写入任何数据）"));
        }
    }

    /// 清空会话: drop bubbles, history and the persisted session.
    fn clear(&self, services: &Arc<Services>) {
        if self.busy.get() {
            return;
        }
        self.messages.set(Vec::new());
        self.history.set(Vec::new());
        self.confirm_results.borrow_mut().clear();
        self.next_id.set(0);
        self.next_confirm.set(0);
        self.error.set(String::new());
        let job_services = services.clone();
        services.runtime.spawn(async move {
            job_services.settings_set(ai::CHAT_SESSION_KEY, "").await;
        });
    }

    fn bubble(message: ReadSignal<Msg>) -> impl IntoElement {
        // Alignment is fixed per row (the role of a message never
        // changes); text and colors follow the signal so streaming
        // deltas render.
        let is_user = message.with(|m| m.role_of_kind() == Role::User);
        let msg = message;
        let card = view()
            .max_w(px(300.0))
            .px(px(14.0))
            .py(px(10.0))
            .rounded(px(14.0))
            .bg(move || {
                if msg.get().role_of_kind() == Role::User {
                    theme().primary
                } else {
                    theme().card
                }
            })
            .child(
                text(move || {
                    let m = msg.get();
                    if m.text.is_empty() && m.streaming {
                        "…".to_owned()
                    } else {
                        m.text.clone()
                    }
                })
                .text_base()
                .text_color(move || {
                    if msg.get().role_of_kind() == Role::User {
                        theme().primary_foreground
                    } else {
                        theme().foreground
                    }
                }),
            );
        let row = view().flex_row();
        let row = if is_user {
            row.self_end()
        } else {
            row.self_start()
        };
        row.child(card)
    }

    /// The confirmation card: tool name, human summary, decision buttons.
    /// test ids are per card (`confirm-approve-<n>` / `confirm-deny-<n>`).
    fn confirm_card(
        message: ReadSignal<Msg>,
        state: ChatState,
        services: Arc<Services>,
    ) -> impl IntoElement {
        let msg = message;
        let index = msg.with(|m| m.confirm_index);
        let header = msg.with(|m| {
            m.confirm
                .as_ref()
                .map(|w| w.tool_name.clone())
                .unwrap_or_default()
        });
        let status_line = move || match &msg.get().confirm_state {
            ConfirmState::Pending => "待用户确认（未写入任何数据）".to_owned(),
            ConfirmState::Executing => "写入中…".to_owned(),
            ConfirmState::Applied(result) => result.clone(),
            ConfirmState::Denied => "已拒绝，未写入任何数据".to_owned(),
            ConfirmState::Failed(e) => format!("写入失败：{e}"),
        };
        let status_color = move || match &msg.get().confirm_state {
            ConfirmState::Applied(_) => theme().primary,
            ConfirmState::Failed(_) => theme().destructive,
            _ => theme().muted_foreground,
        };
        let card = view()
            .max_w(px(320.0))
            .gap_2()
            .px(px(14.0))
            .py(px(10.0))
            .rounded(px(14.0))
            .border_1()
            .border_color(move || theme().border)
            .bg(move || theme().card)
            .child(
                text(format!("AI 写入请求 · {header}"))
                    .text_sm()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(move || theme().muted_foreground),
            )
            .child(
                text(move || msg.get().text.clone())
                    .text_base()
                    .text_color(move || theme().foreground),
            )
            .child(text(status_line).text_sm().text_color(status_color))
            .child(when(
                move || msg.get().confirm_state == ConfirmState::Pending,
                move || {
                    let approve_state = state.clone();
                    let approve_services = services.clone();
                    let approve_index = index;
                    let deny_state = state.clone();
                    let deny_index = index;
                    view()
                        .flex_row()
                        .gap_2()
                        .child(
                            ui::primary_button_dyn(
                                "批准写入",
                                move || {
                                    approve_state.approve_write(&approve_services, approve_index)
                                },
                                format!("confirm-approve-{index}"),
                                None,
                            )
                            .flex_1(),
                        )
                        .child(
                            ui::secondary_button_dyn(
                                "拒绝",
                                move || deny_state.deny_write(deny_index),
                                format!("confirm-deny-{index}"),
                                None,
                            )
                            .flex_1(),
                        )
                },
            ));
        view().flex_row().self_start().child(card)
    }
}

impl Msg {
    /// The bubble role (cards align like assistant messages).
    fn role_of_kind(&self) -> Role {
        match self.kind {
            MsgKind::User => Role::User,
            MsgKind::Assistant | MsgKind::Confirm => Role::Assistant,
        }
    }
}

#[allow(non_snake_case)]
pub fn ChatScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");
    let data_version = use_context::<DataVersion>().expect("data version context");

    let messages: Signal<Vec<Msg>> = signal(Vec::new());
    let draft: Signal<String> = signal(String::new());
    let busy: Signal<bool> = signal(false);
    let error: Signal<String> = signal(String::new());
    let history: Signal<Vec<ai::ChatTurnMessage>> = signal(Vec::new());
    let confirm_results: Rc<RefCell<Vec<String>>> = Rc::new(RefCell::new(Vec::new()));
    let next_id: Rc<Cell<u64>> = Rc::new(Cell::new(0));
    let next_confirm: Rc<Cell<usize>> = Rc::new(Cell::new(0));
    // The pipe's drain task runs under the screen's owner, so its
    // callbacks may set signals.
    let pipe_next_id = next_id.clone();
    let pipe_next_confirm = next_confirm.clone();
    let pipe_confirm_results = confirm_results.clone();
    let pipe_services = services.clone();
    let pipe_data_version = data_version;
    let pipe = crate::bridge::EventPipe::new(move |event: ChatEvent| match event {
        ChatEvent::PendingWrites(writes) => {
            for write in writes {
                let index = pipe_next_confirm.get();
                pipe_next_confirm.set(index + 1);
                let id = pipe_next_id.get();
                pipe_next_id.set(id + 1);
                let summary = write.summary.clone();
                messages.update(|m| {
                    m.push(Msg {
                        id,
                        kind: MsgKind::Confirm,
                        text: summary,
                        streaming: false,
                        confirm: Some(write),
                        confirm_state: ConfirmState::Pending,
                        confirm_index: index,
                    });
                });
            }
        }
        ChatEvent::Delta(delta) => {
            messages.update(|m| {
                if let Some(last) = m
                    .iter_mut()
                    .rev()
                    .find(|msg| msg.kind == MsgKind::Assistant)
                {
                    last.text.push_str(&delta);
                }
            });
        }
        ChatEvent::Failed(message) => error.set(message),
        ChatEvent::WriteResult { index, result } => {
            let outcome = match result {
                Ok(line) => {
                    // Other screens reload (the ledger shows the entry).
                    pipe_data_version.0.update(|v| *v += 1);
                    pipe_confirm_results
                        .borrow_mut()
                        .push(format!("已批准并写入：{line}"));
                    ConfirmState::Applied(line)
                }
                Err(e) => {
                    pipe_confirm_results
                        .borrow_mut()
                        .push(format!("写入失败：{e}"));
                    ConfirmState::Failed(e)
                }
            };
            messages.update(|m| {
                if let Some(msg) = m
                    .iter_mut()
                    .find(|msg| msg.kind == MsgKind::Confirm && msg.confirm_index == index)
                {
                    msg.confirm_state = outcome;
                }
            });
        }
        ChatEvent::Finished { assistant_text } => {
            mark_done(&messages);
            let text = assistant_text.trim().to_owned();
            if !text.is_empty() {
                history.update(|h| {
                    h.push(ai::ChatTurnMessage {
                        role: "assistant".to_owned(),
                        text,
                    });
                });
            }
            // Persist the session (tokio runtime; the pump task dies with
            // this owner but the runtime outlives it).
            let session = history.get();
            let save_services = pipe_services.clone();
            pipe_services.runtime.spawn(async move {
                ai::save_session(&save_services, session).await;
            });
            busy.set(false);
        }
    });
    let state = ChatState {
        messages,
        draft,
        busy,
        error,
        history,
        confirm_results,
        next_id: next_id.clone(),
        next_confirm,
        pipe,
    };
    let profile: Signal<Option<LlmProfile>> = signal(None);
    let profile_ready: Signal<bool> = signal(false);

    {
        let services = services.clone();
        let history = state.history;
        let messages = state.messages;
        let next_id = state.next_id.clone();
        spawn(async move {
            let stored = services.llm_profile().await;
            profile.set(stored);
            // Restore the last session: bubbles first, then the history
            // the next send carries.
            let session = ai::load_session(&services).await;
            if !session.messages.is_empty() {
                let restored = session.messages.clone();
                messages.update(|m| {
                    for msg in restored {
                        let id = next_id.get();
                        next_id.set(id + 1);
                        m.push(Msg {
                            id,
                            kind: if msg.role == "user" {
                                MsgKind::User
                            } else {
                                MsgKind::Assistant
                            },
                            text: msg.text,
                            streaming: false,
                            confirm: None,
                            confirm_state: ConfirmState::Pending,
                            confirm_index: usize::MAX,
                        });
                    }
                });
                history.set(session.messages);
            }
            profile_ready.set(true);
        });
    }

    let send_state = state.clone();
    let send_services = services.clone();
    let send_profile = profile;
    let send = move || send_state.send(&send_services, send_profile);

    let clear_services = services.clone();
    let header_state = state.clone();
    let header_busy = header_state.busy;
    view()
        .flex_1()
        .child(
            view()
                .flex_row()
                .items_center()
                .px_4()
                .py_3()
                .gap_3()
                .child(
                    text("智能")
                        .text_xl()
                        .font_weight(FontWeight::BOLD)
                        .flex_1(),
                )
                .child(ui::secondary_button(
                    "清空会话",
                    move || header_state.clear(&clear_services),
                    "chat-clear",
                    Some(header_busy),
                )),
        )
        .child(when(
            move || !profile_ready.get(),
            move || {
                view().flex_1().items_center().justify_center().child(
                    text("加载中…")
                        .text_sm()
                        .text_color(move || theme().muted_foreground),
                )
            },
        ))
        .child(when(
            move || profile_ready.get(),
            move || {
                let state = state.clone();
                let state_list = state.clone();
                let state_row = state.clone();
                let row_services = services.clone();
                let send = send.clone();
                let send_submit = send.clone();
                view()
                    .flex_1()
                    .child(scroll().flex_1().px_4().child(each(
                        move || state_list.messages.get(),
                        |message: &Msg| message.id.to_string(),
                        move |message: ReadSignal<Msg>, _index: ReadSignal<usize>| {
                            // A message's kind never changes, so exactly
                            // one of the two regions ever renders.
                            let is_confirm = message.with(|m| m.kind == MsgKind::Confirm);
                            let card_state = state_row.clone();
                            let card_services = row_services.clone();
                            view()
                                .child(when(
                                    move || !is_confirm,
                                    move || ChatState::bubble(message),
                                ))
                                .child(when(
                                    move || is_confirm,
                                    move || {
                                        ChatState::confirm_card(
                                            message,
                                            card_state.clone(),
                                            card_services.clone(),
                                        )
                                    },
                                ))
                        },
                    )))
                    .child(
                        view()
                            .flex_row()
                            .gap_2()
                            .p_4()
                            .child(
                                input()
                                    .value(state.draft)
                                    .on_change(move |text: &str| state.draft.set(text.to_owned()))
                                    .placeholder("问点什么…")
                                    .on_submit(move |_: &str| send_submit.clone()())
                                    .flex_1()
                                    .h(px(44.0))
                                    .px(px(12.0))
                                    .rounded(move || theme().radius)
                                    .bg(move || theme().card)
                                    .border_1()
                                    .border_color(move || theme().border)
                                    .text_base()
                                    .test_id("chat-input"),
                            )
                            .child(ui::primary_button(
                                "发送",
                                send.clone(),
                                "chat-send",
                                Some(state.busy),
                            )),
                    )
                    .child(view().px_4().pb_2().child(ui::error_line(state.error)))
            },
        ))
}
