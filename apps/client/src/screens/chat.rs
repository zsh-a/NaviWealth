//! 智能: device AI chat. The turn runs on the app-level tokio runtime
//! (the provider SDK owns the HTTP stack) and streams deltas into a
//! signal; AI writes are never applied without user confirmation (phase
//! 4: proposals).

use std::cell::Cell;
use std::rc::Rc;
use std::sync::Arc;

use futures::StreamExt;
use nsh_base::{input, theme};
use nsh_core::prelude::*;

use crate::ai::{self, LlmProfile};
use crate::state::Services;
use crate::ui;

#[derive(Clone, PartialEq)]
struct Msg {
    id: u64,
    role: Role,
    text: String,
    streaming: bool,
}

#[derive(Clone, Copy, PartialEq)]
enum Role {
    User,
    Assistant,
}

/// Events a background turn reports through the engine-thread pipe.
enum ChatEvent {
    Delta(String),
    Failed(String),
    Finished,
}

#[derive(Clone)]
struct ChatState {
    messages: Signal<Vec<Msg>>,
    draft: Signal<String>,
    busy: Signal<bool>,
    error: Signal<String>,
    /// Shared id counter (stable `each` keys across clones).
    next_id: Rc<Cell<u64>>,
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
        if let Some(last) = m.last_mut() {
            last.streaming = false;
        }
    });
}

impl ChatState {
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

        let user_id = self.next_id.get();
        self.next_id.set(user_id + 1);
        let assistant_id = self.next_id.get();
        self.next_id.set(assistant_id + 1);
        self.messages.update(|m| {
            m.push(Msg {
                id: user_id,
                role: Role::User,
                text: text_value.clone(),
                streaming: false,
            });
            m.push(Msg {
                id: assistant_id,
                role: Role::Assistant,
                text: String::new(),
                streaming: true,
            });
        });

        let _messages = self.messages;
        let _busy = self.busy;
        let _error = self.error;
        // The turn runs on the app-level tokio runtime; events cross to
        // the engine thread through the pipe (signals are
        // engine-thread-only).
        let job_services = services.clone();
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
                        return;
                    }
                };
                let mut stream = runner.stream(ai::turn_request(&profile_value, text_value));
                while let Some(event) = stream.next().await {
                    match event {
                        Ok(event) => {
                            if let Some(delta) = ai::delta_text(&event) {
                                report(&tx, ChatEvent::Delta(delta.to_owned()));
                            }
                            if let Some(message) = ai::error_text(&event) {
                                report(&tx, ChatEvent::Failed(message));
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
                report(&tx, ChatEvent::Finished);
            },
        );
    }

    fn bubble(message: ReadSignal<Msg>) -> impl IntoElement {
        // Alignment is fixed per row (the role of a message never
        // changes); text and colors follow the signal so streaming
        // deltas render.
        let is_user = message.with(|m| m.role == Role::User);
        let msg = message;
        let card = view()
            .max_w(px(300.0))
            .px(px(14.0))
            .py(px(10.0))
            .rounded(px(14.0))
            .bg(move || {
                if msg.get().role == Role::User {
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
                    if msg.get().role == Role::User {
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
}

#[allow(non_snake_case)]
pub fn ChatScreen() -> impl IntoElement {
    let services: Arc<Services> = use_context::<Arc<Services>>().expect("services context");

    let messages: Signal<Vec<Msg>> = signal(Vec::new());
    let draft: Signal<String> = signal(String::new());
    let busy: Signal<bool> = signal(false);
    let error: Signal<String> = signal(String::new());
    // The pipe's drain task runs under the screen's owner, so its
    // callbacks may set signals.
    let pipe = crate::bridge::EventPipe::new(move |event: ChatEvent| match event {
        ChatEvent::Delta(delta) => {
            messages.update(|m| {
                if let Some(last) = m.last_mut()
                    && last.role == Role::Assistant
                {
                    last.text.push_str(&delta);
                }
            });
        }
        ChatEvent::Failed(message) => error.set(message),
        ChatEvent::Finished => {
            mark_done(&messages);
            busy.set(false);
        }
    });
    let state = ChatState {
        messages,
        draft,
        busy,
        error,
        next_id: Rc::new(Cell::new(0)),
        pipe,
    };
    let profile: Signal<Option<LlmProfile>> = signal(None);
    let profile_ready: Signal<bool> = signal(false);

    {
        let services = services.clone();
        spawn(async move {
            let stored = services.llm_profile().await;
            profile.set(stored);
            profile_ready.set(true);
        });
    }

    let send_state = state.clone();
    let send_services = services.clone();
    let send_profile = profile;
    let send = move || send_state.send(&send_services, send_profile);

    view()
        .flex_1()
        .child(
            view()
                .px_4()
                .py_3()
                .child(text("智能").text_xl().font_weight(FontWeight::BOLD)),
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
                let send = send.clone();
                let send_submit = send.clone();
                view()
                    .flex_1()
                    .child(scroll().flex_1().px_4().child(each(
                        move || state_list.messages.get(),
                        |message: &Msg| message.id.to_string(),
                        move |message: ReadSignal<Msg>, _index: ReadSignal<usize>| {
                            ChatState::bubble(message)
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
