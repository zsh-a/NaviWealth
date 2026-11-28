//! Persistent conversations share native navigation and the owner's model account.
//! Only explicit Send calls the model; memory and record proposals stay reviewable.

use std::time::Duration;

#[path = "assistant_scroll.rs"]
mod thread_scroll;
use thread_scroll::ThreadScroll;

use nsh_base::{alert_dialog, nav_page, text_view};
use nsh_core::{element::Screen, picker::PickRequest, prelude::*};

use super::parts::{status_bar, top_bar};
use crate::{
    data::{
        assistant,
        assistant_store::{Message, Role, RunStep},
        clock, photos,
    },
    domain::recognition::Lang,
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color,
        feedback::confirm_discard,
        field::{field, text_input},
        space,
        surface::{disclosure, hairline, row_button},
    },
};

fn copy(en: &'static str, zh: &'static str) -> &'static str {
    if s().lang == Lang::Zh { zh } else { en }
}

pub(super) fn title() -> &'static str {
    copy("Conversation", "对话")
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

fn keyboard_remainder(window_height: f32, root_height: Option<f32>, reported: f32) -> f32 {
    let native_shrink = root_height.map_or(0.0, |height| (window_height - height).max(0.0));
    (reported - native_shrink).max(0.0)
}

/// Adoption keeps an internal capture link for persistence. It is not a
/// conversational turn until it has something to review or a failure to show.
fn visible_messages() -> Vec<Message> {
    let Some(session) = assistant::current_view() else {
        return Vec::new();
    };
    session
        .messages
        .iter()
        .enumerate()
        .filter(|(index, message)| {
            if !message.text.is_empty() || !message.images.is_empty() {
                return true;
            }
            let Some(id) = message.capture_id.as_deref() else {
                return true;
            };
            if session.messages[*index + 1..]
                .iter()
                .any(|later| later.capture_id.as_deref() == Some(id))
            {
                return false;
            }
            crate::data::capture::get(id).is_none_or(|draft| {
                !draft.records.is_empty() || draft.status == crate::domain::capture::Status::Failed
            })
        })
        .map(|(_, message)| message.clone())
        .collect()
}

pub(crate) fn page() -> Screen {
    let panel = signal(Panel::Chat);
    let root_height = signal(None::<f32>);
    // Android may overlay its IME or resize the native root. Consume only
    // the keyboard height the native root has not already made room for.
    let keyboard_shrink = move || {
        root_height
            .get()
            .map_or(0.0, |height| (window().height.0 - height).max(0.0))
    };
    let keyboard_open = computed(move || keyboard_height().0 > 0.0 || keyboard_shrink() > 100.0);
    let keyboard_padding =
        move || keyboard_remainder(window().height.0, root_height.get(), keyboard_height().0);
    let input = signal(String::new());
    effect(move || {
        let value = assistant::current_view()
            .map(|session| session.composer)
            .unwrap_or_default();
        if input.get_untracked() != value {
            input.set(value);
        }
    });
    let memory_input = signal(String::new());
    let memory_editing = signal(None::<String>);
    let error = signal(None::<String>);
    let asking = signal(false);
    let input_height = signal(48.0f32);
    let shown = signal(40usize);
    let thread = ThreadScroll::new();
    provide_context(thread);
    let list = thread.list;
    let following = thread.following;
    effect(move || {
        if let Some(id) = assistant::capture_focus() {
            let messages = visible_messages();
            if let Some(index) = messages
                .iter()
                .rposition(|m| m.capture_id.as_deref() == Some(&id))
            {
                following.set(false);
                shown.update(|n| *n = (*n).max(messages.len() - index));
            } else {
                assistant::clear_capture_focus(&id);
            }
        }
    });
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
        if switched && assistant::capture_focus().is_none() {
            following.set(true);
        }
        if prior.as_ref() != Some(&signature)
            && following.get_untracked()
            && assistant::capture_focus().is_none()
        {
            set_timeout(Duration::from_millis(40), move || {
                if following.get_untracked() && assistant::capture_focus().is_none() {
                    list.scroll_to_end(false);
                }
            });
        }
    });
    let back = move || {
        if panel.get_untracked() != Panel::Chat {
            panel.set(Panel::Chat);
        } else if !memory_input.get_untracked().trim().is_empty() {
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
        change()
    };
    nav_page()
        .title(|| SharedString::from(title()))
        .header_visible(false)
        .status_bar(status_bar)
        .pop_on_back(move || {
            panel.get() == Panel::Chat && memory_input.with(|s| s.trim().is_empty())
        })
        .on_back_press(back)
        .child(
            view()
                .test_id("conversation-root")
                .flex_1()
                .on_layout(move |bounds: &Bounds<Points>| root_height.set(Some(bounds.size.height.0)))
                .pb(move || px(keyboard_padding()))
                .bg(color::CANVAS)
                .child(top_bar(
                    || title().into(),
                    back,
                    Some(
                        Btn::ghost()
                            .size(Size::Small)
                            .icon(Icon::Plus)
                            .label(|| copy("New conversation", "新对话").into())
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
                            text(|| {
                                assistant::current_view()
                                    .map(|session| session.title)
                                    .unwrap_or_default()
                            })
                            .typo(Type::Subhead)
                            .text_color(color::MUTED)
                            .flex_1()
                            .min_w(px(0.0))
                            .number_of_lines(1),
                        ),
                )
                .child(when(
                    move || error.get().or_else(assistant::error).is_some(),
                    move || {
                        view()
                            .px(px(space::GUTTER))
                            .py_2()
                            .gap_2()
                            .child(
                                text(move || {
                                    error.get().or_else(assistant::error).unwrap_or_default()
                                })
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
                                    thread.offset.set(event.offset.y.0);
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
                                                visible_messages().is_empty()
                                            },
                                            empty,
                                        ))
                                        .child(when(
                                            move || {
                                                visible_messages().len() > shown.get()
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
                                                let all = visible_messages();
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
                                        .child(when(
                                            || assistant::current_view().is_some_and(|session| {
                                                matches!(session.status, crate::data::assistant_store::Status::Failed | crate::data::assistant_store::Status::Interrupted)
                                                    && session.messages.iter().any(|message| message.role == Role::User)
                                            }),
                                            move || Btn::ghost().size(Size::Small)
                                                .label(|| copy("Retry", "重试").into())
                                                .disabled(assistant::busy)
                                                .on_press(move || report(error, assistant::retry())),
                                        ))
                                        .child(pending(error)),
                                ),
                        )
                        .child(when(move || !following.get(), move || {
                            Btn::ghost().size(Size::Small)
                                .label(|| copy("Back to latest", "回到最新").into())
                                .on_press(move || thread.latest())
                        }))
                        .child(composer(input, input_height, error, asking, move || keyboard_open.get()))
                        .into_element(),
                    Panel::History => history(panel, error).into_element(),
                    Panel::Memory => memory(error, memory_input, memory_editing).into_element(),
                }))
                .child(crate::ui::toast::toast_host(|| 168.0)),
        )
}

fn empty() -> impl IntoElement {
    view().gap_3().pt_6()
        .child(text(|| copy("A place for your day", "随手记录，接着聊")).typo(Type::Title).text_color(color::INK))
        .child(text(|| copy(
            "Send a photo, record something, or ask a question. Review proposed records here before saving.",
            "发张照片、记一笔，或问个问题。记录会先留在这里，等你核对后保存。"
        )).typo(Type::Body).text_color(color::MUTED))
        .child(when(|| !assistant::ready(), || {
            view().gap_2()
                .child(text(copy("You can also use + to record by hand or reuse a favorite meal without a model.", "也可以点下方＋手动记录或使用收藏餐食，无需配置模型。"))
                    .typo(Type::Subhead).text_color(color::MUTED))
                .child(Btn::tonal().label(|| copy("Set up model", "设置模型").into()).on_press(|| nav::push(Route::ModelSettings)))
        }))
}

fn message_row(message: ReadSignal<Message>) -> impl IntoElement {
    // Keep editors mounted while unrelated conversation tokens arrive.
    let capture_card = computed(move || {
        let current = message.get();
        let id = current.capture_id?;
        let latest = assistant::current_view()
            .and_then(|session| {
                session
                    .messages
                    .into_iter()
                    .rev()
                    .find(|m| m.capture_id.as_deref() == Some(&id))
            })
            .is_some_and(|m| m.id == current.id);
        Some((id, latest))
    });
    let thread = use_context::<ThreadScroll>().expect("conversation scroll context");
    let row = element_ref();
    effect(move || {
        if let Some((id, true)) = capture_card.get()
            && assistant::capture_focus().as_deref() == Some(&id)
        {
            thread.reveal(row, id);
        }
    });
    view()
        .element_ref(&row)
        .test_id(&format!(
            "conversation-message-{}",
            message.get_untracked().id
        ))
        .on_layout(move |_: &Bounds<Points>| {
            if let Some((id, true)) = capture_card.get()
                && assistant::capture_focus().as_deref() == Some(&id)
            {
                thread.reveal(row, id);
            }
        })
        .style_when(
            move || {
                capture_card.get().is_some_and(|(id, latest)| {
                    latest && thread.highlighted.get().as_deref() == Some(&id)
                })
            },
            |style| style.bg(color::ACCENT_SOFT),
        )
        .gap_2()
        .pl(move || {
            px(if message.with(|m| m.role == Role::User) {
                24.0
            } else {
                0.0
            })
        })
        .child(when(
            move || {
                let current = message.get();
                let messages = visible_messages();
                let position = messages
                    .iter()
                    .position(|m| m.id == current.id)
                    .unwrap_or(0);
                position == 0
                    || clock::day_of(messages[position - 1].created_at_ms)
                        != clock::day_of(current.created_at_ms)
            },
            move || {
                text(move || s().long_date(clock::day_of(message.get().created_at_ms)))
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
            },
        ))
        .child(each(
            move || message.get().images,
            |name| name.clone(),
            |name, _| {
                spawn(photos::load(vec![name.get_untracked()]));
                image(move || photos::uri(&name.get()).unwrap_or_default())
                    .w(px(180.0))
                    .h(px(132.0))
                    .object_fit(ResizeMode::Cover)
                    .rounded(px(12.0))
                    .accessibility_elements_hidden(true)
            },
        ))
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
        .child(when(
            move || message.with(|m| !m.run_steps.is_empty()),
            move || run_details(message),
        ))
        .child(dynamic(move || {
            let Some((id, latest)) = capture_card.get() else {
                return view().into_element();
            };
            if latest {
                super::capture::inline_review(id).into_element()
            } else {
                text(copy("Record updated below", "记录已在下方更新"))
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .into_element()
            }
        }))
}

fn run_details(message: ReadSignal<Message>) -> impl IntoElement {
    let open = signal(false);
    view()
        .gap_2()
        .child(disclosure(open, move || {
            let failures = message.with(|m| {
                m.run_steps
                    .iter()
                    .filter(|step| matches!(step, RunStep::Tool { error: Some(code), .. } if !matches!(code.as_str(), "tool_no_result" | "tool_interrupted")))
                    .count()
            });
            if failures == 0 {
                copy("Run details", "运行详情").into()
            } else if s().lang == Lang::Zh {
                format!("运行详情 · {failures} 次调用失败").into()
            } else {
                format!("Run details · {failures} failed").into()
            }
        }))
        .child(when(
            move || open.get(),
            move || {
                text(move || {
                    message.with(|m| {
                        m.run_steps
                            .iter()
                            .map(step_text)
                            .collect::<Vec<_>>()
                            .join("\n\n")
                    })
                })
                .typo(Type::Subhead)
                .text_color(color::BODY)
            },
        ))
}

fn step_text(step: &RunStep) -> String {
    match step {
        RunStep::Thinking(text) => format!("{}\n{}", copy("Model thinking", "模型思考"), text)
            .trim_end()
            .to_owned(),
        RunStep::Tool {
            name,
            error,
            call_id,
        } => {
            let outcome = match error.as_deref() {
                None => copy("Completed", "已完成"),
                Some("tool_no_result") => copy("No result received", "尚未收到结果"),
                Some("tool_interrupted") => copy(
                    "Interrupted before the result was received",
                    "调用中断，结果未知",
                ),
                Some("invalid_tool_arguments") => {
                    copy("Invalid tool arguments", "调用参数格式不正确")
                }
                Some("capture_invalid_records") => {
                    copy("Draft failed record validation", "草稿内容未通过记录校验")
                }
                Some("draft_images_not_in_request") => copy(
                    "Draft photos missing from this request",
                    "本次请求缺少草稿引用的图片",
                ),
                Some("draft_changed") => copy(
                    "Draft changed or is no longer pending",
                    "草稿已变更或已结束审核",
                ),
                Some("too_many_proposals") => {
                    copy("Pending draft limit reached", "待确认草稿已达上限")
                }
                Some("search_not_configured") => copy("Search key missing", "未配置搜索密钥"),
                _ => copy("Tool call failed", "工具调用失败"),
            };
            if call_id.is_empty() {
                format!("{name} · {outcome}")
            } else {
                format!(
                    "{name} · {outcome}\n{} {call_id}",
                    copy("Call ID", "调用 ID")
                )
            }
        }
        RunStep::MoreStepsOmitted => copy("Further steps omitted", "更多步骤已省略").into(),
    }
}

fn composer(
    input: Signal<String>,
    height: Signal<f32>,
    error: Signal<Option<String>>,
    asking: Signal<bool>,
    keyboard_open: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    // Streaming events update the session throughout a press. Keep the Stop
    // button mounted until the run actually finishes.
    let busy = computed(assistant::busy);
    let options = signal(false);
    let favorites = signal(false);
    let composer_focus = element_ref();
    let previous_target = stored(None::<String>);
    effect(move || {
        let target = assistant::current_view().and_then(|s| s.editing_capture);
        if previous_target.replace(target.clone()) != target && target.is_some() {
            set_timeout(Duration::from_millis(40), move || composer_focus.focus());
        }
    });
    let picking = signal(false);
    let finance = signal(None::<String>);
    let weight = signal(None);
    let overview = signal(None);
    let empty_input = move || {
        input.with(|text| text.trim().is_empty())
            && assistant::current_view().is_none_or(|session| session.attachments.is_empty())
    };
    let submit = move || {
        if assistant::busy() || empty_input() || asking.get_untracked() || picking.get_untracked() {
            return;
        }
        if assistant::consented() {
            send(input, error);
            return;
        }
        asking.set(true);
        let target = assistant::target();
        let answer = alert_dialog()
            .title(copy("Send to your configured model?", "将内容发送给这个模型？"))
            .description(format!("{target}\n\n{}", copy(
                "Your messages, attached photos, and local account and category names go to the model account shown above. Depending on your settings and request, it may also receive recent records, favorites, approved memories and tool query results. Search queries go to Brave Search; opened pages are fetched directly. Records and proposed memories are saved only after your confirmation. This choice is remembered for this model account.",
                "消息、附加照片以及本地账户和分类名称会发送给上方你配置的模型账户。按你的设置或任务需要，还可能附带近期记录、收藏、已确认的记忆及工具查询结果。搜索词会发送给 Brave Search，网页会直接访问。记录和建议的记忆需经你确认后保存。此选择仅对当前模型账户生效。"
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
        .test_id("conversation-composer")
        .bg(color::CANVAS)
        .px(px(space::GUTTER))
        .pt_2()
        .pb(move || {
            px(12.0
                + if keyboard_open() {
                    0.0
                } else {
                    safe_area().bottom.0
                })
        })
        .gap_2()
        .child(hairline(0.0))
        .child(when(
            || {
                assistant::current_view()
                    .and_then(|session| session.editing_capture)
                    .and_then(|id| crate::data::capture::get(&id))
                    .is_some_and(|draft| !draft.records.is_empty())
            },
            move || {
                view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .child(
                        text(|| {
                            let brief = assistant::current_view()
                                .and_then(|session| session.editing_capture)
                                .and_then(|id| crate::data::capture::get(&id))
                                .map(|draft| super::capture::record_brief(&draft.records))
                                .unwrap_or_default();
                            format!(
                                "{}\n{brief}",
                                copy("Editing selected record", "正在修改选中的记录")
                            )
                        })
                        .typo(Type::Caption)
                        .text_color(color::ACCENT_INK)
                        .min_w(px(0.0))
                        .number_of_lines(3)
                        .flex_1(),
                    )
                    .child(
                        Btn::ghost()
                            .size(Size::Small)
                            .label(|| copy("Locate", "定位").into())
                            .on_press(|| {
                                dismiss_keyboard();
                                if let Some(id) =
                                    assistant::current_view().and_then(|s| s.editing_capture)
                                {
                                    assistant::focus_capture(&id);
                                }
                            }),
                    )
                    .child(
                        IconBtn::new(Icon::Close, || {
                            copy("Cancel record editing", "取消修改记录").into()
                        })
                        .on_press(move || report(error, assistant::cancel_edit_capture())),
                    )
            },
        ))
        .child(view().flex_row().flex_wrap().gap_2().child(each(
            || {
                assistant::current_view()
                    .map(|session| session.attachments)
                    .unwrap_or_default()
            },
            |name| name.clone(),
            move |name, _| {
                spawn(photos::load(vec![name.get_untracked()]));
                view()
                    .flex_row()
                    .items_center()
                    .gap_1()
                    .child(
                        image(move || photos::uri(&name.get()).unwrap_or_default())
                            .size(px(56.0))
                            .object_fit(ResizeMode::Cover)
                            .rounded(px(8.0)),
                    )
                    .child(
                        IconBtn::new(Icon::Close, || copy("Remove photo", "移除照片").into())
                            .on_press(move || {
                                report(error, assistant::remove_attachment(&name.get_untracked()))
                            })
                            .disabled(assistant::busy),
                    )
            },
        )))
        .child(when(
            move || options.get(),
            move || {
                view()
                    .flex_row()
                    .flex_wrap()
                    .gap_1()
                    .child(
                        Btn::ghost()
                            .size(Size::Small)
                            .icon(Icon::Photo)
                            .label(|| copy("Add photos", "添加照片").into())
                            .disabled(move || picking.get() || assistant::busy())
                            .on_press(move || {
                                options.set(false);
                                pick_photos(picking, error);
                            }),
                    )
                    .child(
                        Btn::ghost()
                            .size(Size::Small)
                            .label(|| copy("Meal by hand", "手动记餐").into())
                            .on_press(move || {
                                options.set(false);
                                nav::push(Route::NewMeal {
                                    day: clock::today(),
                                    capture: None,
                                });
                            }),
                    )
                    .child(
                        Btn::ghost()
                            .size(Size::Small)
                            .label(|| copy("Transaction by hand", "手动记账").into())
                            .on_press(move || {
                                options.set(false);
                                finance.set(Some(String::new()));
                            }),
                    )
                    .child(
                        Btn::ghost()
                            .size(Size::Small)
                            .label(|| copy("Weight by hand", "手动记体重").into())
                            .on_press(move || {
                                options.set(false);
                                weight.set(Some(clock::today()));
                            }),
                    )
                    .child(
                        Btn::ghost()
                            .size(Size::Small)
                            .icon(Icon::Bookmark)
                            .label(|| copy("Favorite meals", "收藏餐食").into())
                            .on_press(move || {
                                options.set(false);
                                favorites.set(true);
                            }),
                    )
            },
        ))
        .child(when(
            move || picking.get(),
            || {
                text(|| copy("Preparing photos…", "正在准备照片…"))
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
            },
        ))
        .child(
            view()
                .flex_row()
                .items_end()
                .gap_2()
                .child(
                    IconBtn::new(Icon::Plus, || {
                        copy("Attach or add manually", "添加照片或手动记录").into()
                    })
                    .on_press(move || {
                        dismiss_keyboard();
                        options.update(|value| *value = !*value);
                    }),
                )
                .child(
                    text_input(input)
                        .element_ref(&composer_focus)
                        .on_change(move |value: &str| {
                            options.set(false);
                            input.set(value.into());
                            report(error, assistant::set_composer(value.into()));
                        })
                        .multiline(true)
                        .min_w(px(0.0))
                        .flex_1()
                        .h(move || px(height.get()))
                        .on_content_size_change(move |size: &nsh_core::Size<Points>| {
                            height.set((size.height.0 + 16.0).clamp(48.0, 120.0))
                        })
                        .label(|| copy("Message", "消息"))
                        .placeholder(|| copy("Record something or ask…", "记点什么，或问个问题…")),
                )
                .child(dynamic(move || {
                    if busy.get() {
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
                                    || empty_input()
                                    || asking.get()
                                    || picking.get()
                            })
                            .into_element()
                    }
                })),
        )
        .child(super::finance::finance_editor(finance))
        .child(crate::ui::sheet::bottom_sheet(
            move || favorites.get(),
            move || favorites.set(false),
            view()
                .gap_3()
                .child(
                    when(crate::data::favorites::any, move || {
                        super::capture::favorites::favorites_row(move || favorites.set(false))
                    })
                    .otherwise(|| {
                        text(copy(
                            "Save a meal as a favorite from its details, then log it again here.",
                            "在餐食详情中收藏，之后就能在这里快速记录。",
                        ))
                        .typo(Type::Body)
                        .text_color(color::MUTED)
                    }),
                )
                .child(
                    Btn::ghost()
                        .label(|| s().close.into())
                        .on_press(move || favorites.set(false)),
                ),
        ))
        .child(crate::ui::sheet::task_host_with_keyboard(
            move || weight.get().is_some(),
            move || weight.set(None),
            || true,
            move || super::today::weight_editor(weight, overview).into_element(),
        ))
}

static NEXT_PHOTO: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn pick_photos(picking: Signal<bool>, error: Signal<Option<String>>) {
    if assistant::current_view().is_none()
        && let Err(problem) = assistant::set_composer(String::new())
    {
        error.try_set(Some(problem));
        return;
    }
    let session = assistant::current_view();
    let selected = session.as_ref().map(|session| session.id.clone());
    let remaining = crate::domain::capture::MAX_ATTACHMENTS
        .saturating_sub(session.map_or(0, |session| session.attachments.len()));
    if remaining == 0 {
        error.try_set(Some(
            copy(
                "Remove a photo before adding another.",
                "请先移除一张照片再添加。",
            )
            .into(),
        ));
        return;
    }
    picking.set(true);
    let request = pick_images(PickRequest::new(true, remaining as u32));
    crate::data::tasks::spawn_app(async move {
        for file in request.await.into_iter().take(remaining) {
            let bytes = file.data.to_vec();
            let prepared = blocking(move || photos::prepare_capture(&bytes))
                .await
                .ok()
                .flatten();
            if assistant::current_view().map(|session| session.id) != selected {
                break;
            }
            let Some((upload, _)) = prepared else {
                error.try_set(Some(s().failure_photo.0.into()));
                continue;
            };
            let serial = NEXT_PHOTO.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let extension = if upload.starts_with(b"\x89PNG") {
                "png"
            } else {
                "jpg"
            };
            let name = format!("conversation-{}-{serial}.{extension}", clock::now_ms());
            if photos::keep(&name, &upload).is_err() {
                error.try_set(Some(s().error_transaction_storage.into()));
                continue;
            }
            report(error, assistant::add_attachment(name));
        }
        picking.try_set(false);
    });
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
    each(
        || {
            assistant::current_view()
                .map(|session| session.pending)
                .unwrap_or_default()
        },
        |proposal| proposal.id.clone(),
        move |proposal, _| {
            dynamic(move || {
                let proposal = proposal.get();
                let confirm_id = proposal.id.clone();
                let dismiss_id = proposal.id.clone();
                if let assistant::PendingKind::Questions { request, answers } = proposal.kind {
                    return untracked(move || questions(proposal.id, request, answers, error))
                        .into_element();
                }
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
                    assistant::PendingKind::Records { .. } => (
                        copy("Review proposed records", "核对记录提议"),
                        String::new(),
                        copy("Review and edit", "核对并编辑"),
                    ),
                    assistant::PendingKind::Questions { .. } => unreachable!(),
                };
                view()
                    .gap_3()
                    .pt_2()
                    .child(hairline(0.0))
                    .child(text(heading).typo(Type::Headline).text_color(color::INK))
                    .child(text(body).typo(Type::Body).text_color(color::BODY))
                    .child(
                        Btn::tonal()
                            .label(move || action.into())
                            .disabled(assistant::busy)
                            .on_press(move || {
                                report(error, assistant::confirm_pending(&confirm_id))
                            }),
                    )
                    .child(
                        Btn::ghost()
                            .size(Size::Small)
                            .label(|| copy("Dismiss suggestion", "忽略建议").into())
                            .disabled(assistant::busy)
                            .on_press(move || {
                                report(error, assistant::dismiss_pending(&dismiss_id))
                            }),
                    )
                    .into_element()
            })
        },
    )
}

fn questions(
    id: String,
    request: crate::domain::capture::AskUser,
    initial_answers: Vec<crate::domain::capture::AskAnswer>,
    error: Signal<Option<String>>,
) -> impl IntoElement {
    use crate::domain::capture::AskAnswer;
    let answers = signal(initial_answers);
    let pending_id = stored(id.clone());
    let submit_id = id.clone();
    let validation = request.clone();
    view()
        .gap_3()
        .pt_2()
        .child(hairline(0.0))
        .children(request.questions.into_iter().map(move |question| {
            view()
                .gap_2()
                .child(
                    text(question.text)
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child((!question.reason.is_empty()).then(|| {
                    text(question.reason)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                }))
                .children(question.options.into_iter().map(move |option| {
                    let question_id = question.id.clone();
                    let checked_question = question_id.clone();
                    let option_id = option.id;
                    let checked_option = option_id.clone();
                    let checked_question = stored(checked_question);
                    let checked_option = stored(checked_option);
                    let checked = move || {
                        answers.with(|answers| {
                            answers.iter().any(|answer| {
                                checked_question.with(|id| answer.question_id == *id)
                                    && checked_option
                                        .with(|id| answer.option_id.as_deref() == Some(id.as_str()))
                            })
                        })
                    };
                    nsh_base::toggle()
                        .pressed(checked)
                        .on_change(move |_: &bool| {
                            let was = checked();
                            answers.update(|answers| {
                                answers.retain(|answer| answer.question_id != question_id);
                                if !was {
                                    answers.push(AskAnswer {
                                        question_id: question_id.clone(),
                                        option_id: Some(option_id.clone()),
                                        text: String::new(),
                                    });
                                }
                            });
                            report(
                                error,
                                assistant::set_question_answers(
                                    &pending_id.get(),
                                    &answers.get_untracked(),
                                ),
                            );
                        })
                        .accessibility_label(Some(option.label.clone().into()))
                        .min_h(px(48.0))
                        .px_3()
                        .py_2()
                        .rounded(px(10.0))
                        .bg(color::SURFACE_2)
                        .style_when(checked, |style| style.bg(color::ACCENT_SOFT))
                        .child(text(option.label).typo(Type::Body).text_color(color::INK))
                        .child((!option.description.is_empty()).then(|| {
                            text(option.description)
                                .typo(Type::Caption)
                                .text_color(color::MUTED)
                        }))
                }))
        }))
        .child(
            text(|| {
                copy(
                    "Choose an option, or add your answer in the message below.",
                    "选择选项，或在下方输入补充回答。",
                )
            })
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(
            Btn::tonal()
                .label(|| copy("Continue", "继续").into())
                .disabled(assistant::busy)
                .on_press(move || {
                    let session = assistant::current_view();
                    let text = session
                        .as_ref()
                        .map(|session| session.composer.clone())
                        .unwrap_or_default();
                    let values = answers.get_untracked();
                    if validation
                        .validate_answers(
                            &values,
                            &text,
                            session.is_some_and(|session| !session.attachments.is_empty()),
                        )
                        .is_err()
                    {
                        error.set(Some(
                            copy(
                                "Answer the required questions or add a message.",
                                "请选择必填问题，或输入补充回答。",
                            )
                            .into(),
                        ));
                        return;
                    }
                    report(error, assistant::answer_questions(&submit_id, values, text));
                }),
        )
        .child(
            Btn::ghost()
                .size(Size::Small)
                .label(|| copy("Dismiss suggestion", "忽略建议").into())
                .disabled(assistant::busy)
                .on_press(move || report(error, assistant::dismiss_pending(&id))),
        )
}

fn history(panel: Signal<Panel>, error: Signal<Option<String>>) -> impl IntoElement {
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
            .child(
                Btn::ghost()
                    .icon(Icon::Bookmark)
                    .label(|| copy("Memory & search", "记忆与搜索").into())
                    .on_press(move || panel.set(Panel::Memory)),
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
                                                panel.set(Panel::Chat);
                                                error.set(None);
                                            }
                                            Err(problem) => error.set(Some(problem)),
                                        };
                                        change()
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

#[cfg(test)]
mod keyboard_tests {
    use super::keyboard_remainder;

    #[test]
    fn keyboard_padding_only_consumes_space_not_already_resized_by_the_host() {
        assert_eq!(keyboard_remainder(844.0, Some(844.0), 300.0), 300.0);
        assert_eq!(keyboard_remainder(844.0, Some(544.0), 300.0), 0.0);
        assert_eq!(keyboard_remainder(844.0, Some(700.0), 300.0), 156.0);
        assert_eq!(keyboard_remainder(844.0, Some(544.0), 0.0), 0.0);
        assert_eq!(keyboard_remainder(844.0, Some(844.0), 0.0), 0.0);
    }
}
