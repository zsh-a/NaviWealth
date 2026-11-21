use super::*;

/// The conversation so far: owner messages on the right, the model's turns
/// on the left with its light. While it works, the thread shows it waiting;
/// a failure is one of its turns, with the ways back.
pub(super) fn thread(
    draft: &Draft,
    signal_draft: Signal<Draft>,
    input: Signal<String>,
    choosing: Signal<Option<accounts::Choice>>,
    send: impl Fn() + Copy + 'static,
    arrived: Stored<usize>,
    error: Signal<Option<String>>,
) -> impl IntoElement {
    if draft.transcript.is_empty() {
        arrived.replace(0);
        return empty_composer(draft, signal_draft).into_element();
    }
    let ready = capture::ready(draft);
    let latest = draft.transcript.len() - 1;
    // The latest turn that proposed records shows the live record cards;
    // earlier ones collapse to an updated line.
    let live = draft
        .transcript
        .iter()
        .rposition(|turn| matches!(turn, Turn::Assistant { records, .. } if *records > 0));
    let count = draft.transcript.len();
    let from = if count > arrived.get() {
        arrived.get()
    } else {
        count
    };
    arrived.replace(count);
    let exchange_start = draft
        .transcript
        .iter()
        .rposition(|turn| matches!(turn, Turn::Owner { .. } | Turn::ToolAnswer { .. }))
        .unwrap_or(0);
    let mut earlier = Vec::new();
    let mut items: Vec<AnyElement> = Vec::new();
    for (index, turn) in draft.transcript.iter().enumerate() {
        let element = match turn {
            Turn::Owner {
                text,
                photo,
                images,
            } => {
                let mut names = images.clone();
                if names.is_empty() && *photo && index == 0 {
                    names.extend(draft.photo.iter().cloned());
                }
                owner_turn(text, &names)
            }
            Turn::AskUser { request } => {
                let open = index == latest && draft.status == Status::Ready;
                view()
                    .flex_row()
                    .gap_2()
                    .items_stretch()
                    .child(ai_mark())
                    .child(decisions::questions(
                        request,
                        draft,
                        signal_draft,
                        input,
                        error,
                        open,
                    ))
                    .into_element()
            }
            Turn::ToolAnswer {
                call_id,
                answers,
                text,
                images,
            } => {
                let request = draft.transcript[..index]
                    .iter()
                    .rev()
                    .find_map(|turn| match turn {
                        Turn::AskUser { request } if &request.call_id == call_id => Some(request),
                        _ => None,
                    });
                let mut lines = Vec::new();
                if let Some(request) = request {
                    for answer in answers {
                        if let Some(question) = request
                            .questions
                            .iter()
                            .find(|q| q.id == answer.question_id)
                        {
                            let choice = answer
                                .option_id
                                .as_ref()
                                .and_then(|id| question.options.iter().find(|o| &o.id == id));
                            let label = choice.map(|o| o.label.as_str()).unwrap_or(&answer.text);
                            lines.push(format!("{}: {}", question.text, label));
                        }
                    }
                }
                if !text.trim().is_empty() {
                    lines.push(text.clone());
                }
                if lines.is_empty() && images.is_empty() {
                    lines.push(s().capture_skipped_optional.to_owned());
                }
                owner_turn(&lines.join("\n"), images)
            }
            Turn::Assistant {
                records, questions, ..
            } => {
                let column = view().gap_2().flex_1().min_w(px(0.0));
                let column = if *records > 0 && live == Some(index) && index >= exchange_start {
                    column.child(summary::records(draft, choosing))
                } else if *records > 0 {
                    column.child(badge(
                        s().capture_thread_updated(*records),
                        Tone::Ai,
                        Some(Icon::Sparkle),
                    ))
                } else {
                    column
                };
                let column = column.children(questions.iter().map(|question| {
                    question_turn(question, index == latest && !ready, input, send)
                }));
                view()
                    .flex_row()
                    .gap_2()
                    .items_stretch()
                    .child(ai_mark())
                    .child(column)
                    .into_element()
            }
        };
        if index < exchange_start {
            earlier.push(element);
            continue;
        }
        items.push(if index >= from {
            appear((index - from) as u32, element).into_element()
        } else {
            element
        });
    }
    if draft.status == Status::Analyzing {
        let sweep = shimmer();
        items.push(
            view()
                .flex_row()
                .gap_2()
                .items_stretch()
                .child(ai_mark())
                .child(
                    view()
                        .gap_3()
                        .flex_1()
                        .min_w(px(0.0))
                        .child(
                            text(|| s().capture_reading)
                                .typo(Type::Headline)
                                .text_color(color::INK),
                        )
                        .children((0..2).map(|_| {
                            card()
                                .p_4()
                                .gap_3()
                                .accessibility_elements_hidden(true)
                                .child(skeleton(Some(140.0), 16.0, sweep))
                                .child(skeleton(None, 24.0, sweep))
                                .child(skeleton(Some(180.0), 12.0, sweep))
                        }))
                        .child(
                            text(|| s().capture_background)
                                .typo(Type::Subhead)
                                .text_color(color::MUTED),
                        ),
                )
                .into_element(),
        );
    }
    if draft.status == Status::Failed {
        let failure = capture::failure(&draft.id);
        let copy = failure
            .map(|e| crate::pages::review::failure_copy(s(), &e).0)
            .unwrap_or(s().capture_failed);
        items.push(
            view()
                .flex_row()
                .gap_2()
                .items_stretch()
                .child(ai_mark())
                .child(
                    view()
                        .gap_2()
                        .flex_1()
                        .child(text(copy).typo(Type::Headline).text_color(color::CAUTION))
                        .child(
                            view()
                                .flex_row()
                                .flex_wrap()
                                .gap_2()
                                .child(
                                    Btn::ghost()
                                        .label(|| s().capture_retry.into())
                                        .on_press(send),
                                )
                                .child(Btn::ghost().label(|| s().open_settings.into()).on_press(
                                    || {
                                        let sheets = Sheets::get();
                                        sheets.capture.set(false);
                                        if !sheets.capture.get_untracked() {
                                            nav::push(Route::ModelSettings);
                                        }
                                    },
                                ))
                                .child(
                                    (!draft.records.is_empty()
                                        && !capture::awaiting_tool_resolution(draft))
                                    .then(|| {
                                        Btn::ghost()
                                            .label(|| s().capture_keep_result.into())
                                            .on_press(move || {
                                                input.set(String::new());
                                                signal_draft.update(|d| {
                                                    d.status = Status::Ready;
                                                    d.correction.clear();
                                                });
                                                if let Err(e) =
                                                    capture::put(signal_draft.get_untracked())
                                                {
                                                    log::error!("capture: {e}");
                                                }
                                            })
                                    }),
                                ),
                        ),
                )
                .into_element(),
        );
    }
    if draft.status == Status::Ready
        && !draft.records.is_empty()
        && live.is_none_or(|index| index < exchange_start)
        && draft.pending_ask_user().is_none()
    {
        items.push(summary::records(draft, choosing));
    }
    let history = signal(false);
    view()
        .gap_5()
        .children(items)
        .child((!earlier.is_empty()).then(|| {
            nsh_base::collapsible()
                .open(move || history.get())
                .content(view().gap_4().children(earlier))
                .child(crate::ui::surface::disclosure(history, || {
                    s().capture_history.into()
                }))
        }))
        .into_element()
}

/// The model's light as a hairline edge beside its turns.
fn ai_mark() -> impl IntoElement {
    view()
        .w(px(2.0))
        .self_stretch()
        .min_h(px(16.0))
        .rounded_full()
        .bg_linear_to_b()
        .gradient_from(color::AI_FROM)
        .gradient_to(color::AI_TO)
        .accessibility_elements_hidden(true)
}

/// The owner's message: its photo beside an ink pill, on the right.
fn owner_turn(message: &str, images: &[String]) -> AnyElement {
    let mut row = view()
        .flex_row()
        .flex_wrap()
        .justify_end()
        .items_center()
        .gap_2();
    for name in images {
        let name = name.clone();
        row = row.child(
            image(move || photos::uri(&name).unwrap_or_default())
                .size(px(48.0))
                .object_fit(ResizeMode::Cover)
                .rounded(px(radius::THUMB)),
        );
    }
    let body = message.trim();
    if !body.is_empty() {
        row = row.child(
            view()
                .max_w(px(300.0))
                .bg(color::ACTION)
                .rounded(px(18.0))
                .px(px(14.0))
                .py(px(9.0))
                .child(
                    text(body.to_owned())
                        .typo(Type::Body)
                        .text_color(color::ON_ACTION),
                ),
        );
    }
    row.into_element()
}

/// One question of the model, with its tap-first answers while it is the
/// one still waiting.
fn question_turn(
    question: &Question,
    open: bool,
    input: Signal<String>,
    send: impl Fn() + Copy + 'static,
) -> AnyElement {
    let asked = view()
        .bg(color::SURFACE_2)
        .rounded(px(18.0))
        .px(px(14.0))
        .py(px(9.0))
        .child(
            text(question.text.clone())
                .typo(Type::Title)
                .text_color(color::INK),
        )
        .into_element();
    if !open || question.options.is_empty() {
        return asked;
    }
    let options = question.options.clone();
    view()
        .gap_2()
        .child(asked)
        .child(
            view()
                .flex_row()
                .flex_wrap()
                .gap_2()
                .children(options.into_iter().map(move |option| {
                    let label = option.clone();
                    chip(
                        move || label.clone().into(),
                        || false,
                        move || {
                            input.set(option.clone());
                            send();
                        },
                    )
                })),
        )
        .into_element()
}

/// The hints before the first message: the attached photo and, without a
/// model account, where to connect one. Manual entry and favorites stay
/// below the thread.
fn empty_composer(draft: &Draft, signal_draft: Signal<Draft>) -> impl IntoElement {
    view()
        .gap_3()
        .child(
            draft
                .has_staged_images()
                .then(|| staged_images(draft, signal_draft)),
        )
        .child(when(
            || settings::ready_account().is_none(),
            || {
                text(|| s().capture_setup)
                    .typo(Type::Subhead)
                    .text_color(color::MUTED)
            },
        ))
}

/// Unsent evidence stays removable; sent evidence belongs to its thread turn.
pub(super) fn staged_images(draft: &Draft, signal_draft: Signal<Draft>) -> impl IntoElement {
    let names = draft.staged_images();
    view()
        .gap_2()
        .child((!names.is_empty()).then(|| {
            text(|| s().capture_image_hint)
                .typo(Type::Caption)
                .text_color(color::MUTED)
        }))
        .children(names.into_iter().map(|name| {
            let image_name = name.clone();
            view()
                .flex_row()
                .items_center()
                .gap_3()
                .child(
                    image(move || photos::uri(&image_name).unwrap_or_default())
                        .size(px(64.0))
                        .object_fit(ResizeMode::Contain)
                        .rounded(px(radius::THUMB)),
                )
                .child(
                    Btn::ghost()
                        .label(|| s().capture_remove_photo.into())
                        .on_press(move || {
                            signal_draft.update(|d| {
                                d.attachments.retain(|kept| kept != &name);
                                if d.transcript.is_empty() && d.photo.as_ref() == Some(&name) {
                                    d.photo = d.attachments.first().cloned();
                                }
                            })
                        }),
                )
        }))
}
