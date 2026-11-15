//! One bounded conversation: the owner's description or photo is the
//! thread's first message, and results, questions and corrections are its
//! turns. Forms are an explicit manual fallback.
mod accounts;
mod favorites;
mod summary;

use super::home::Sheets;
use crate::{
    data::{capture, clock, photos, settings, vision},
    domain::{
        account::ModelAccount,
        capture::{Draft, MAX_INPUT, Question, Status, Turn},
    },
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Type, Typo, Variant, chip, color,
        feedback::{Tone, appear, badge, spinner},
        field::{note, text_input},
        radius,
        sheet::{fitted_task_sheet, initial_focus, retained},
        surface::{disclosure, hairline},
        toast::{show_receipt, show_toast},
        toggle::checkbox_row,
    },
};
use navi_health::consent::Consent;
use nsh_core::{
    geometry::{DevicePixels, Percentage},
    picker::PickRequest,
    prelude::*,
};
use std::rc::Rc;

pub fn capture_editor(sheets: Sheets) -> impl IntoElement {
    retained(
        move || sheets.capture.get().then(|| sheets.capture_draft.get()),
        move |id| {
            untracked(move || {
                let kept = id
                    .and_then(|id| capture::get(&id))
                    .unwrap_or_else(capture::new);
                editor(sheets, kept).into_element()
            })
        },
    )
}

fn editor(sheets: Sheets, initial: Draft) -> impl IntoElement {
    crate::ui::toast::clear_notice();
    if let Some(photo) = initial.photo.clone() {
        spawn(photos::load(vec![photo]));
    }
    let id = stored(initial.id.clone());
    let draft = signal(initial);
    let error = signal(None::<String>);
    let manual = signal(false);
    let consenting = signal(None::<ModelAccount>);
    let remember = signal(false);
    let choosing = signal(None::<accounts::Choice>);
    // The composer holds the next message: the first entry while the thread
    // is empty, otherwise the staged answer to the pending questions.
    let input = signal(draft.with_untracked(|d| {
        if d.transcript.is_empty() {
            d.input.clone()
        } else {
            d.correction.clone()
        }
    }));
    let picking = signal(false);
    // How many thread turns have already been shown, so only new ones
    // arrive with the entrance.
    let arrived = stored(0usize);
    effect(move || {
        let kept = id.with(|id| capture::get(id));
        if let Some(kept) = kept {
            untracked(|| {
                if draft.with(|d| d.status == Status::Analyzing) && kept.status != Status::Analyzing
                {
                    // A message composed while the model worked stays.
                    if input.get_untracked().trim().is_empty() {
                        input.set(kept.correction.clone());
                    }
                    draft.set(kept);
                }
            });
        }
    });
    let current = move || {
        let mut d = draft.get_untracked();
        if d.transcript.is_empty() {
            d.input = input.get_untracked();
        } else {
            d.correction = input.get_untracked();
        }
        d
    };
    let close = move || {
        let d = current();
        if d.transcript.is_empty()
            && d.input.trim().is_empty()
            && d.photo.is_none()
            && let Err(cause) = capture::remove(&d.id)
        {
            log::error!("capture: {cause}");
            error.set(Some(s().error_transaction_storage.into()));
            return;
        }
        let retained = !d.input.trim().is_empty()
            || d.photo.is_some()
            || !d.records.is_empty()
            || !d.transcript.is_empty();
        if d.status != Status::Analyzing
            && retained
            && let Err(cause) = capture::put(d)
        {
            log::error!("capture: draft save failed: {cause}");
            error.set(Some(s().error_transaction_storage.into()));
            return;
        }
        dismiss_keyboard();
        sheets.capture.set(false);
        if retained {
            show_toast(s().capture_retained, None);
        }
    };
    let run = move |account: ModelAccount| {
        error.set(None);
        let d = current();
        if input.get_untracked().chars().count() > MAX_INPUT {
            error.set(Some(s().capture_too_long.into()));
            return;
        }
        let Ok(consent) = Consent::approve(vision::upload_target(&account), true) else {
            return;
        };
        match capture::recognize(d, account, consent, s().lang) {
            Ok(()) => {
                if let Some(kept) = id.with(|id| capture::get(id)) {
                    draft.set(kept);
                }
                // The sent message now lives in the thread.
                input.set(String::new());
                consenting.set(None);
                dismiss_keyboard();
            }
            Err(cause) => {
                log::error!("capture: could not start: {cause}");
                error.set(Some(s().error_transaction_storage.into()));
            }
        }
    };
    let send = move || {
        if let Some(account) = settings::ready_account() {
            if settings::capture_trusted(&account) {
                run(account);
            } else {
                dismiss_keyboard();
                consenting.set(Some(account));
            }
        }
    };
    let attach = move || {
        picking.set(true);
        let mut request = PickRequest::new(false, 1);
        request.max_dimension = Some(DevicePixels(1600));
        request.quality = Some(Percentage(0.9));
        let picked = pick_images(request);
        spawn(async move {
            if let Some(file) = picked.await.into_iter().next() {
                let bytes = file.data.to_vec();
                let prepared = blocking(move || photos::prepare(&bytes))
                    .await
                    .ok()
                    .flatten();
                if let Some((upload, _)) = prepared {
                    let name = id.with(|id| format!("{id}.jpg"));
                    photos::keep(&name, &upload);
                    draft.update(|d| d.photo = Some(name));
                } else {
                    error.set(Some(s().failure_photo.0.into()));
                }
            }
            picking.set(false);
        });
    };
    let discard = move || {
        let mut kept = draft.get_untracked();
        if let Err(error) = capture::remove(&kept.id) {
            log::error!("capture: {error}");
            show_toast(s().error_transaction_storage, None);
            return;
        }
        if kept.status == Status::Analyzing {
            kept.status = Status::Failed;
        }
        sheets.capture.set(false);
        show_toast(
            s().draft_discarded,
            Some((
                s().undo.into(),
                Rc::new(move || {
                    if let Err(error) = capture::put(kept.clone()) {
                        log::error!("capture: {error}");
                        show_toast(s().error_transaction_storage, None);
                    }
                }),
            )),
        );
    };
    let header = view()
        .flex_row()
        .items_center()
        .gap_2()
        .child(when(
            move || choosing.get().is_some() || consenting.get().is_some(),
            move || {
                IconBtn::new(Icon::ChevronLeft, || s().back.into())
                    .variant(Variant::Ghost)
                    .on_press(move || {
                        choosing.set(None);
                        consenting.set(None);
                    })
            },
        ))
        .child(
            text(move || {
                if choosing.get().is_some() {
                    s().capture_choose_account
                } else if draft.with(|d| d.records.is_empty()) {
                    s().new_entry
                } else {
                    s().capture_review
                }
            })
            .typo(Type::Title)
            .text_color(color::INK)
            .flex_1()
            .role(AccessibilityRole::Header),
        )
        .child(when(
            move || {
                draft.with(|d| !d.transcript.is_empty()) || id.with(|id| capture::get(id).is_some())
            },
            move || {
                IconBtn::new(Icon::Trash, || s().discard_draft.into())
                    .variant(Variant::Ghost)
                    .on_press(discard)
            },
        ))
        .child(
            IconBtn::new(Icon::Close, || s().close.into())
                .variant(Variant::Ghost)
                .on_press(close),
        );
    let body = view()
        .gap_4()
        .child(dynamic(move || {
            let consent = consenting.get();
            let choice = choosing.get();
            // Reading the draft here subscribes the thread to every turn.
            let d = draft.get();
            untracked(move || {
                if let Some(choice) = choice {
                    accounts::picker(draft, input, error, choosing, choice).into_element()
                } else if let Some(account) = consent {
                    view()
                        .gap_4()
                        .child(
                            text(|| s().capture_consent)
                                .typo(Type::Headline)
                                .text_color(color::INK),
                        )
                        .child(
                            text(|| s().capture_consent_body)
                                .typo(Type::Body)
                                .text_color(color::BODY),
                        )
                        .child(
                            text(account.host())
                                .typo(Type::Headline)
                                .text_color(color::INK),
                        )
                        .child(
                            text(account.model.clone())
                                .typo(Type::Callout)
                                .text_color(color::MUTED),
                        )
                        .child(account.is_cleartext().then(|| {
                            text(|| s().consent_cleartext)
                                .typo(Type::Subhead)
                                .text_color(color::CAUTION)
                        }))
                        .child(checkbox_row(remember, || s().dont_ask_again.into()))
                        .into_element()
                } else {
                    let sheets = Sheets::get();
                    view()
                        .gap_4()
                        .child(thread(&d, draft, input, choosing, send, arrived))
                        .child(hairline(0.0))
                        .child(disclosure(manual, || s().capture_manual.into()))
                        .child(when(
                            move || manual.get(),
                            move || {
                                view()
                                    .gap_2()
                                    .child(
                                        Btn::ghost().label(|| s().log_transaction.into()).on_press(
                                            move || {
                                                close();
                                                if !sheets.capture.get_untracked() {
                                                    sheets.finance.set(Some(String::new()));
                                                }
                                            },
                                        ),
                                    )
                                    .child(Btn::ghost().label(|| s().add_manually.into()).on_press(
                                        move || {
                                            close();
                                            if !sheets.capture.get_untracked() {
                                                sheets.manual();
                                            }
                                        },
                                    ))
                                    .child(Btn::ghost().label(|| s().log_weight.into()).on_press(
                                        move || {
                                            close();
                                            if !sheets.capture.get_untracked() {
                                                sheets.weight.set(Some(clock::today()));
                                            }
                                        },
                                    ))
                            },
                        ))
                        .child(favorites::favorites_row(close))
                        .into_element()
                }
            })
        }))
        .child(note(move || error.get().map(Into::into), || true));
    // The composer is the one stable input, so typing never rebuilds it.
    // The row above it swaps the task's current action. Focus follows an
    // editing draft's sheet opening only.
    let focus = if draft.with_untracked(|d| d.transcript.is_empty()) {
        initial_focus()
    } else {
        element_ref()
    };
    let actions = view()
        .gap_2()
        .child(dynamic(move || {
            let status = draft.with(|d| d.status);
            let consent = consenting.get();
            let picking_account = choosing.get().is_some();
            let ready_now = {
                let mut d = draft.get_untracked();
                d.correction = input.get_untracked();
                capture::ready(&d)
            };
            let connected = settings::ready_account().is_some();
            untracked(move || {
                if picking_account {
                    return view().into_element();
                }
                if let Some(account) = consent {
                    return Btn::primary()
                        .label(|| s().capture_generate.into())
                        .on_press(move || {
                            if remember.get_untracked() {
                                settings::trust_capture(&account);
                            }
                            run(account.clone());
                        })
                        .into_element();
                }
                if status == Status::Analyzing {
                    return Btn::secondary()
                        .label(|| s().capture_later.into())
                        .on_press(close)
                        .into_element();
                }
                if !connected {
                    return Btn::primary()
                        .label(|| s().set_up.into())
                        .on_press(move || {
                            close();
                            if !sheets.capture.get_untracked() {
                                nav::push(Route::ModelSettings);
                            }
                        })
                        .into_element();
                }
                if ready_now {
                    return Btn::primary()
                        .label(move || {
                            let n = draft.with(|d| d.records.len());
                            if n == 1 {
                                s().capture_confirm.into()
                            } else {
                                format!("{} ({n})", s().capture_confirm).into()
                            }
                        })
                        .on_press(move || {
                            let draft_id = id.with(|id| id.clone());
                            let confirmed = current();
                            match capture::put(confirmed.clone())
                                .and_then(|()| capture::confirm(&draft_id))
                            {
                                Ok(()) => {
                                    dismiss_keyboard();
                                    sheets.capture.set(false);
                                    let day = summary::common_day(&confirmed);
                                    show_receipt(
                                        summary::saved_message(&confirmed),
                                        (
                                            s().view_records.into(),
                                            Rc::new(move || {
                                                sheets.jump_to.set(day);
                                                sheets.records_all.set(day.is_none());
                                                nav::select(crate::nav::Tab::Records);
                                            }),
                                        ),
                                    );
                                }
                                Err(cause) => {
                                    log::error!("capture: confirmation failed: {cause}");
                                    error.set(Some(s().error_transaction_storage.into()));
                                }
                            }
                        })
                        .into_element();
                }
                view().into_element()
            })
        }))
        .child(when(
            move || choosing.get().is_none() && consenting.get().is_none(),
            move || {
                view()
                    .flex_row()
                    .gap_2()
                    .items_center()
                    .child(when(
                        move || draft.with(|d| d.transcript.is_empty()),
                        move || {
                            IconBtn::new(Icon::Photo, || s().capture_photo.into())
                                .variant(Variant::Tonal)
                                .on_press(attach)
                                .disabled(move || picking.get())
                        },
                    ))
                    .child(
                        text_input(input)
                            .element_ref(&focus)
                            .multiline(true)
                            .h(px(72.0))
                            .label(|| s().capture_prompt)
                            .placeholder(move || {
                                if draft.with(|d| d.transcript.is_empty()) {
                                    s().capture_placeholder
                                } else {
                                    s().capture_reply_hint
                                }
                            }),
                    )
                    .child(
                        IconBtn::new(Icon::Send, || s().capture_send.into())
                            .variant(Variant::Primary)
                            .side(44.0)
                            .on_press(send)
                            .disabled(move || {
                                picking.get()
                                    || draft.with(|d| d.status == Status::Analyzing)
                                    || input.get().trim().is_empty()
                                        && draft
                                            .with(|d| d.transcript.is_empty() && d.photo.is_none())
                            }),
                    )
            },
        ));
    fitted_task_sheet(
        move || sheets.capture.get(),
        move || {
            if choosing.get_untracked().is_some() || consenting.get_untracked().is_some() {
                choosing.set(None);
                consenting.set(None);
            } else {
                close();
            }
        },
        header,
        body,
        actions,
    )
}

/// The conversation so far: owner messages on the right, the model's turns
/// on the left with its light. While it works, the thread shows it waiting;
/// a failure is one of its turns, with the ways back.
fn thread(
    draft: &Draft,
    signal_draft: Signal<Draft>,
    input: Signal<String>,
    choosing: Signal<Option<accounts::Choice>>,
    send: impl Fn() + Copy + 'static,
    arrived: Stored<usize>,
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
    let mut items: Vec<AnyElement> = Vec::new();
    for (index, turn) in draft.transcript.iter().enumerate() {
        let element = match turn {
            Turn::Owner { text, photo } => {
                owner_turn(text, *photo && index == 0, draft.photo.as_deref())
            }
            Turn::Assistant {
                records, questions, ..
            } => {
                let column = view().gap_2().flex_1().min_w(px(0.0));
                let column = if *records > 0 && live == Some(index) {
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
        items.push(if index >= from {
            appear((index - from) as u32, element).into_element()
        } else {
            element
        });
    }
    if draft.status == Status::Analyzing {
        items.push(
            view()
                .flex_row()
                .gap_2()
                .items_stretch()
                .child(ai_mark())
                .child(
                    view()
                        .gap_1()
                        .child(
                            view()
                                .flex_row()
                                .items_center()
                                .gap_2()
                                .child(spinner(16.0, color::AI_FROM))
                                .child(
                                    text(|| s().capture_reading)
                                        .typo(Type::Headline)
                                        .text_color(color::INK),
                                ),
                        )
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
            .map(|e| super::review::failure_copy(s(), &e).0)
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
                                .child((!draft.records.is_empty()).then(|| {
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
                                })),
                        ),
                )
                .into_element(),
        );
    }
    view().gap_4().children(items).into_element()
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
fn owner_turn(message: &str, photo: bool, photo_name: Option<&str>) -> AnyElement {
    let mut row = view().flex_row().justify_end().items_center().gap_2();
    if let Some(name) = photo_name.filter(|_| photo).map(str::to_owned) {
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
        .self_start()
        .max_w(px(320.0))
        .bg(color::SURFACE_2)
        .rounded(px(18.0))
        .px(px(14.0))
        .py(px(9.0))
        .child(
            text(question.text.clone())
                .typo(Type::Body)
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
        .child(draft.photo.as_ref().map(|name| {
            let name = name.clone();
            view()
                .flex_row()
                .items_center()
                .gap_3()
                .child(
                    image(move || photos::uri(&name).unwrap_or_default())
                        .size(px(72.0))
                        .object_fit(ResizeMode::Cover)
                        .rounded(px(12.0)),
                )
                .child(
                    Btn::ghost()
                        .label(|| s().capture_remove_photo.into())
                        .on_press(move || signal_draft.update(|d| d.photo = None)),
                )
        }))
        .child(when(
            || settings::ready_account().is_none(),
            || {
                text(|| s().capture_setup)
                    .typo(Type::Subhead)
                    .text_color(color::MUTED)
            },
        ))
}
