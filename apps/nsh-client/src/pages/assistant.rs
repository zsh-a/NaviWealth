//! Persistent conversations share native navigation and the owner's model account.
//! Only explicit Send calls the model; memory and record proposals stay reviewable.

use std::time::Duration;

use nsh_base::{alert_dialog, nav_page, text_view};
use nsh_core::{element::Screen, prelude::*};

use super::parts::{status_bar, top_bar};
use crate::{
    data::{
        assistant,
        assistant_store::{Message, Role},
    },
    domain::recognition::Lang,
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color,
        feedback::confirm_discard,
        field::{field, text_input},
        space,
        surface::{hairline, row_button},
    },
};

fn copy(en: &'static str, zh: &'static str) -> &'static str {
    if s().lang == Lang::Zh { zh } else { en }
}

pub(super) fn title() -> &'static str {
    copy("Assistant", "助手")
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Panel {
    Chat,
    History,
    Memory,
}

fn report(error: Signal<Option<String>>, result: Result<(), String>) {
    error.try_set(result.err());
}

pub(crate) fn page() -> Screen {
    let panel = signal(Panel::Chat);
    let input = signal(String::new());
    let memory_input = signal(String::new());
    let memory_editing = signal(None::<String>);
    let error = signal(None::<String>);
    let asking = signal(false);
    let input_height = signal(48.0f32);
    let shown = signal(40usize);
    let list = element_ref();
    let following = signal(true);
    let previous = stored(None::<(Option<String>, usize, usize)>);
    effect(move || {
        let session = assistant::current_view();
        let signature = (
            session.as_ref().map(|s| s.id.clone()),
            session.as_ref().map_or(0, |s| s.messages.len()),
            session
                .as_ref()
                .and_then(|s| s.messages.last())
                .map_or(0, |m| m.text.len()),
        );
        let prior = previous.replace(Some(signature.clone()));
        let switched = prior.as_ref().map(|s| &s.0) != Some(&signature.0);
        if switched {
            following.set(true);
        }
        if prior.as_ref() != Some(&signature) && (switched || following.get_untracked()) {
            set_timeout(Duration::from_millis(40), move || list.scroll_to_end(false));
        }
    });
    let back = move || {
        if panel.get_untracked() != Panel::Chat {
            panel.set(Panel::Chat);
        } else if !input.get_untracked().trim().is_empty()
            || !memory_input.get_untracked().trim().is_empty()
        {
            confirm_discard(asking, nav::pop);
        } else {
            nav::pop();
        }
    };
    let start = move || {
        let change = move || match assistant::new_session() {
            Ok(()) => {
                input.set(String::new());
                panel.set(Panel::Chat);
                shown.set(40);
                error.set(None);
            }
            Err(problem) => error.set(Some(problem)),
        };
        if input.get_untracked().trim().is_empty() {
            change()
        } else {
            confirm_discard(asking, change)
        }
    };
    nav_page()
        .title(|| SharedString::from(title()))
        .header_visible(false)
        .status_bar(status_bar)
        .pop_on_back(move || {
            panel.get() == Panel::Chat
                && input.with(|s| s.trim().is_empty())
                && memory_input.with(|s| s.trim().is_empty())
        })
        .on_back_press(back)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(
                    || title().into(),
                    back,
                    Some(
                        IconBtn::new(Icon::Plus, || copy("New conversation", "新对话").into())
                            .on_press(start)
                            .disabled(assistant::busy)
                            .into_element(),
                    ),
                ))
                .child(
                    view()
                        .flex_row()
                        .flex_wrap()
                        .items_center()
                        .px_3()
                        .gap_1()
                        .child(
                            Btn::ghost()
                                .size(Size::Small)
                                .icon(Icon::List)
                                .label(|| copy("Conversations", "对话记录").into())
                                .on_press(move || {
                                    dismiss_keyboard();
                                    panel.set(if panel.get_untracked() == Panel::History {
                                        Panel::Chat
                                    } else {
                                        Panel::History
                                    });
                                }),
                        )
                        .child(
                            Btn::ghost()
                                .size(Size::Small)
                                .icon(Icon::Bookmark)
                                .label(|| copy("Memory & search", "记忆与搜索").into())
                                .on_press(move || {
                                    dismiss_keyboard();
                                    panel.set(if panel.get_untracked() == Panel::Memory {
                                        Panel::Chat
                                    } else {
                                        Panel::Memory
                                    });
                                }),
                        ),
                )
                .child(when(
                    move || error.get().or_else(assistant::error).is_some(),
                    move || {
                        view().px(px(space::GUTTER)).py_2().child(
                            text(move || error.get().or_else(assistant::error).unwrap_or_default())
                                .typo(Type::Subhead)
                                .text_color(color::DANGER),
                        )
                    },
                ))
                .child(dynamic(move || match panel.get() {
                    Panel::Chat => view()
                        .flex_1()
                        .child(
                            scroll()
                                .element_ref(&list)
                                .on_scroll(move |event: &nsh_core::element::ScrollEvent| {
                                    following.set(
                                        event.content_size.height.0
                                            - event.size.height.0
                                            - event.offset.y.0
                                            < 80.0,
                                    );
                                })
                                .flex_1()
                                .keyboard_dismiss_mode(KeyboardDismissMode::OnDrag)
                                .child(
                                    view()
                                        .px(px(space::GUTTER))
                                        .pt_4()
                                        .pb_4()
                                        .gap_5()
                                        .child(when(
                                            || {
                                                assistant::current_view()
                                                    .is_none_or(|s| s.messages.is_empty())
                                            },
                                            empty,
                                        ))
                                        .child(when(
                                            move || {
                                                assistant::current_view()
                                                    .is_some_and(|s| s.messages.len() > shown.get())
                                            },
                                            move || {
                                                Btn::ghost()
                                                    .label(|| {
                                                        copy("Earlier messages", "更早的消息")
                                                            .into()
                                                    })
                                                    .on_press(move || shown.update(|n| *n += 40))
                                            },
                                        ))
                                        .child(each(
                                            move || {
                                                let all = assistant::current_view()
                                                    .map(|s| s.messages)
                                                    .unwrap_or_default();
                                                all.into_iter()
                                                    .rev()
                                                    .take(shown.get())
                                                    .collect::<Vec<_>>()
                                                    .into_iter()
                                                    .rev()
                                                    .collect::<Vec<_>>()
                                            },
                                            |m: &Message| m.id.clone(),
                                            |message, _| message_row(message),
                                        ))
                                        .child(when(
                                            || !assistant::status_text().is_empty(),
                                            || {
                                                text(assistant::status_text)
                                                    .typo(Type::Subhead)
                                                    .text_color(color::MUTED)
                                            },
                                        ))
                                        .child(pending(error)),
                                ),
                        )
                        .child(composer(input, input_height, error, asking))
                        .into_element(),
                    Panel::History => history(panel, input, asking, error).into_element(),
                    Panel::Memory => memory(error, memory_input, memory_editing).into_element(),
                })),
        )
}

fn empty() -> impl IntoElement {
    view().gap_3().pt_6()
        .child(text(|| copy("What would you like to work on?", "想一起处理什么？")).typo(Type::Title).text_color(color::INK))
        .child(text(|| copy(
            "Ask about your records, explore a question, or work through a task. Conversations stay on this device; saved memories can be reused in new conversations.",
            "查看自己的记录、查找资料，或一起完成一项任务。对话保存在本机，已保存的记忆可用于新的对话。"
        )).typo(Type::Body).text_color(color::MUTED))
        .child(when(|| !assistant::ready(), || {
            Btn::tonal().label(|| copy("Set up model", "设置模型").into()).on_press(|| nav::push(Route::ModelSettings))
        }))
}

fn message_row(message: ReadSignal<Message>) -> impl IntoElement {
    view()
        .gap_2()
        .pl(move || {
            px(if message.with(|m| m.role == Role::User) {
                24.0
            } else {
                0.0
            })
        })
        .child(
            text(move || match message.get().role {
                Role::User => copy("You", "你"),
                Role::Assistant => title(),
                Role::Tool => copy("Activity", "执行过程"),
            })
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(
            text_view()
                .markdown(move || Some(SharedString::from(message.get().text)))
                .selectable(true)
                // Model-supplied images must not issue implicit network requests.
                .render_image(|image: &nsh_base::text_view::Image| text(image.alt.clone()))
                .on_link_press(|event: &nsh_base::TextViewLinkPressEvent| {
                    if url::Url::parse(&event.url).is_ok_and(|u| {
                        matches!(u.scheme(), "http" | "https")
                            && u.host_str().is_some()
                            && u.username().is_empty()
                            && u.password().is_none()
                    }) {
                        drop(open_url(event.url.to_string()));
                    }
                })
                .typo(Type::Body)
                .text_color(color::BODY)
                .gap_2(),
        )
}

fn composer(
    input: Signal<String>,
    height: Signal<f32>,
    error: Signal<Option<String>>,
    asking: Signal<bool>,
) -> impl IntoElement {
    let submit = move || {
        if assistant::busy() || input.get_untracked().trim().is_empty() || asking.get_untracked() {
            return;
        }
        if assistant::consented() {
            send(input, error);
            return;
        }
        asking.set(true);
        let target = assistant::target();
        let answer = alert_dialog()
            .title(copy("Use this model for Assistant?", "将内容发送给这个模型？"))
            .description(format!("{target}\n\n{}", copy(
                "Your messages, saved memories and local records requested by tools go to this model. Search queries go to Brave Search; opened pages are fetched directly. Records and proposed memories are saved only after your confirmation. This choice is remembered for this model account.",
                "消息、已保存的记忆及工具请求的本地记录会发送给此模型。搜索词会发送给 Brave Search，网页会直接访问。记录和建议的记忆需经你确认后保存。此选择仅对当前模型账户生效。"
            )))
            .cancel("cancel", s().cancel)
            .action("send", copy("Agree and send", "同意并发送"))
            .show();
        spawn(async move {
            let accepted = answer
                .await
                .is_ok_and(|a| a.action.as_deref() == Some("send"));
            asking.set(false);
            if accepted {
                match assistant::grant_consent() {
                    Ok(()) => send(input, error),
                    Err(problem) => error.set(Some(problem)),
                }
            }
        });
    };
    view()
        .bg(color::CANVAS)
        .px(px(space::GUTTER))
        .pt_2()
        .pb_safe_area_plus(px(12.0))
        .gap_2()
        .child(hairline(0.0))
        .child(
            view()
                .flex_row()
                .items_end()
                .gap_2()
                .child(
                    text_input(input)
                        .multiline(true)
                        .min_w(px(0.0))
                        .flex_1()
                        .h(move || px(height.get()))
                        .on_content_size_change(move |size: &nsh_core::Size<Points>| {
                            height.set((size.height.0 + 16.0).clamp(48.0, 120.0))
                        })
                        .label(|| copy("Message Assistant", "给助手发消息"))
                        .placeholder(|| copy("Ask or describe a task", "提问或描述任务")),
                )
                .child(dynamic(move || {
                    if assistant::busy() {
                        Btn::tonal()
                            .label(|| copy("Stop", "停止").into())
                            .on_press(assistant::cancel)
                            .into_element()
                    } else {
                        IconBtn::new(Icon::Send, || copy("Send message", "发送消息").into())
                            .variant(Variant::Primary)
                            .on_press(submit)
                            .disabled(move || {
                                !assistant::ready()
                                    || input.with(|s| s.trim().is_empty())
                                    || asking.get()
                            })
                            .into_element()
                    }
                })),
        )
}

fn send(input: Signal<String>, error: Signal<Option<String>>) {
    match assistant::send(input.get_untracked()) {
        Ok(()) => {
            input.set(String::new());
            error.set(None);
            dismiss_keyboard();
        }
        Err(problem) => error.set(Some(problem)),
    }
}

fn pending(error: Signal<Option<String>>) -> impl IntoElement {
    dynamic(move || {
        let Some(proposal) = assistant::pending() else {
            return view().into_element();
        };
        let confirm_id = proposal.id.clone();
        let dismiss_id = proposal.id;
        let (heading, body, action) = match proposal.kind {
            assistant::PendingKind::Memory { text } => (
                copy("Remember this?", "保存这条记忆？"),
                text,
                copy("Save memory", "保存记忆"),
            ),
            assistant::PendingKind::Capture { text } => (
                copy("Review a new record", "核对新记录"),
                text,
                copy("Open record draft", "打开记录草稿"),
            ),
            assistant::PendingKind::Records { proposal } => {
                let Ok(proposal) = crate::domain::assistant_proposal::parse(&proposal) else {
                    return text(copy(
                        "This record proposal cannot be opened.",
                        "无法打开这条记录提议。",
                    ))
                    .typo(Type::Body)
                    .text_color(color::BODY)
                    .into_element();
                };
                (
                    copy("Review proposed records", "核对记录提议"),
                    format!(
                        "{}\n{}",
                        proposal.text,
                        if crate::i18n::s().lang == crate::domain::recognition::Lang::En {
                            format!(
                                "{} {}. Review the fields and accounts before saving.",
                                proposal.records.len(),
                                if proposal.records.len() == 1 {
                                    "editable record"
                                } else {
                                    "editable records"
                                }
                            )
                        } else {
                            format!(
                                "{} 条可编辑记录，请核对字段和账户后保存。",
                                proposal.records.len()
                            )
                        }
                    ),
                    copy("Review and edit", "核对并编辑"),
                )
            }
        };
        view()
            .gap_3()
            .pt_2()
            .child(hairline(0.0))
            .child(text(heading).typo(Type::Headline).text_color(color::INK))
            .child(text(body).typo(Type::Body).text_color(color::BODY))
            .child(
                Btn::primary()
                    .label(move || action.into())
                    .disabled(assistant::busy)
                    .on_press(move || report(error, assistant::confirm_pending(&confirm_id))),
            )
            .child(
                Btn::ghost()
                    .label(|| copy("Dismiss suggestion", "忽略建议").into())
                    .disabled(assistant::busy)
                    .on_press(move || report(error, assistant::dismiss_pending(&dismiss_id))),
            )
            .into_element()
    })
}

fn history(
    panel: Signal<Panel>,
    input: Signal<String>,
    asking: Signal<bool>,
    error: Signal<Option<String>>,
) -> impl IntoElement {
    scroll().flex_1().child(
        view()
            .px(px(space::GUTTER))
            .py_4()
            .pb_safe_area_plus(px(24.0))
            .gap_3()
            .child(
                text(|| copy("Conversations", "对话记录"))
                    .typo(Type::Title)
                    .text_color(color::INK),
            )
            .child(when(
                || assistant::conversation_list().is_empty(),
                || {
                    text(|| copy("No conversations yet.", "还没有对话。"))
                        .typo(Type::Body)
                        .text_color(color::MUTED)
                },
            ))
            .child(each(
                assistant::conversation_list,
                |session| session.id.clone(),
                move |session, _| {
                    view()
                        .gap_1()
                        .child(
                            view()
                                .flex_row()
                                .items_center()
                                .gap_2()
                                .child(
                                    row_button(move || {
                                        let id = session.get_untracked().id;
                                        let change = move || match assistant::select(&id) {
                                            Ok(()) => {
                                                input.set(String::new());
                                                panel.set(Panel::Chat);
                                                error.set(None);
                                            }
                                            Err(problem) => error.set(Some(problem)),
                                        };
                                        if input.get_untracked().trim().is_empty() {
                                            change()
                                        } else {
                                            confirm_discard(asking, change)
                                        }
                                    })
                                    .flex_1()
                                    .min_w(px(0.0))
                                    .disabled(assistant::busy)
                                    .child(
                                        text(move || session.get().title)
                                            .number_of_lines(2)
                                            .typo(Type::Body)
                                            .text_color(color::INK),
                                    ),
                                )
                                .child(
                                    IconBtn::new(Icon::Trash, || {
                                        copy("Delete conversation", "删除对话").into()
                                    })
                                    .on_press(move || {
                                        let session = session.get_untracked();
                                        delete_confirmation(
                                            copy("Delete this conversation?", "删除这段对话？"),
                                            session.title,
                                            move || assistant::delete_session(&session.id),
                                            error,
                                        );
                                    })
                                    .disabled(assistant::busy),
                                ),
                        )
                        .child(hairline(0.0))
                },
            )),
    )
}

fn memory(
    error: Signal<Option<String>>,
    input: Signal<String>,
    editing: Signal<Option<String>>,
) -> impl IntoElement {
    let key = signal(untracked(assistant::search_key));
    let list = element_ref();
    scroll().flex_1().keyboard_dismiss_mode(KeyboardDismissMode::OnDrag)
        .element_ref(&list)
        .child(view().px(px(space::GUTTER)).py_4().pb_safe_area_plus(px(24.0)).gap_4()
            .child(text(|| copy("Saved memories", "已保存的记忆")).typo(Type::Title).text_color(color::INK))
            .child(text(|| copy("These notes can be recalled in any conversation. Save only what you want the assistant to remember.",
                "这些内容可在不同对话中被检索。只保存你希望助手记住的信息。"))
                .typo(Type::Body).text_color(color::MUTED))
            .child(field(move || if editing.get().is_some() { copy("Edit memory", "编辑记忆") } else { copy("Add a memory", "添加记忆") }, text_input(input)
                .label(|| copy("Memory text", "记忆内容")).placeholder(|| copy("A preference or useful fact", "偏好或有用的信息"))
                .multiline(true).min_h(px(80.0))))
            .child(Btn::tonal().label(|| copy("Save memory", "保存记忆").into())
                .disabled(move || input.with(|s| s.trim().is_empty()) || assistant::busy())
                .on_press(move || match if let Some(id) = editing.get_untracked() {
                    assistant::update_memory(&id, input.get_untracked())
                } else { assistant::save_memory(input.get_untracked()) } {
                    Ok(()) => { input.set(String::new()); editing.set(None); error.set(None); dismiss_keyboard(); }
                    Err(problem) => error.set(Some(problem)),
                }))
            .child(when(move || editing.get().is_some(), move || {
                Btn::ghost().label(|| copy("Cancel editing", "取消编辑").into())
                    .on_press(move || { input.set(String::new()); editing.set(None); })
            }))
            .child(when(|| assistant::memories().is_empty(), || text(|| copy("No saved memories.", "还没有保存的记忆。"))
                .typo(Type::Subhead).text_color(color::MUTED)))
            .child(each(assistant::memories, |memory| memory.id.clone(), move |memory, _| {
                view().gap_2().child(hairline(0.0)).child(view().flex_row().items_start().gap_2()
                    .child(text(move || memory.get().text).typo(Type::Body).text_color(color::BODY).flex_1().min_w(px(0.0)))
                    .child(IconBtn::new(Icon::Pencil, || copy("Edit memory", "编辑记忆").into())
                        .on_press(move || {
                            let memory = memory.get_untracked();
                            input.set(memory.text);
                            editing.set(Some(memory.id));
                            list.scroll_to(Point { x: px(0.0), y: px(0.0) }, false);
                        }).disabled(assistant::busy))
                    .child(IconBtn::new(Icon::Trash, || copy("Delete memory", "删除记忆").into())
                        .on_press(move || {
                            let memory = memory.get_untracked();
                            delete_confirmation(copy("Delete this memory?", "删除这条记忆？"), memory.text,
                                move || assistant::delete_memory(&memory.id), error);
                        }).disabled(assistant::busy)))
            }))
            .child(view().pt_6().gap_3().child(hairline(0.0))
                .child(text(|| copy("Web search", "网页搜索")).typo(Type::Title).text_color(color::INK))
                .child(text(|| copy("Web search uses your Brave Search API key. Search terms go to Brave. Opening a web link does not require a search key.",
                    "网页搜索需要你的 Brave Search API key，搜索词会发送给 Brave。打开网页链接无需搜索密钥。"))
                    .typo(Type::Body).text_color(color::MUTED))
                .child(field(|| copy("Brave Search API key", "Brave Search API key"), text_input(key)
                    .label(|| copy("Search API key", "搜索 API key")).masked(true)
                    .on_blur(move || report(error, assistant::set_search_key(&key.get_untracked())))))
                .child(text(|| if assistant::search_configured() {
                    copy("Search is configured. The key stays on this device and is excluded from backups.", "已配置搜索。密钥仅保存在本机，不包含在备份中。")
                } else { copy("Add a key to enable web search. Changes are saved when you leave the field.", "填写密钥后即可搜索。离开输入框时保存。") }).typo(Type::Subhead).text_color(color::MUTED))
            )
        )
}

fn delete_confirmation(
    title: &'static str,
    description: String,
    remove: impl FnOnce() -> Result<(), String> + 'static,
    error: Signal<Option<String>>,
) {
    let answer = alert_dialog()
        .title(title)
        .description(description)
        .cancel("cancel", s().cancel)
        .destructive("delete", copy("Delete", "删除"))
        .show();
    spawn(async move {
        if answer
            .await
            .is_ok_and(|a| a.action.as_deref() == Some("delete"))
        {
            report(error, remove());
        }
    });
}
