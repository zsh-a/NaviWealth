//! One bounded conversation: the owner's description or photo is the
//! thread's first message, and results, questions and corrections are its
//! turns. Forms are an explicit manual fallback.
mod accounts;
mod attachments;
mod decisions;
mod details;
mod evidence;
mod favorites;
pub(in crate::pages) mod flight;
mod live_preview;
mod recent;
mod summary;
mod thread;

use super::home::Sheets;
use crate::{
    data::{capture, clock, photos, settings, vision},
    domain::{
        account::ModelAccount,
        capture::{Draft, MAX_ATTACHMENTS, MAX_INPUT, Question, Status, Turn},
    },
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Type, Typo, Variant, chip, color,
        feedback::{appear, spinner},
        field::{note, text_input},
        icon, radius,
        sheet::{conversation_sheet, initial_focus, retained},
        toast::{show_capture_receipt, show_toast},
        toggle::checkbox_row,
    },
};
use navi_health::consent::Consent;
use nsh_core::{picker::PickRequest, prelude::*};
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
    spawn(photos::load(initial.image_names()));
    let id = stored(initial.id.clone());
    let replying = signal(
        !initial.correction.is_empty()
            || initial.has_staged_images() && !initial.transcript.is_empty(),
    );
    let draft = signal(initial);
    let flight = flight::opened(&draft.get_untracked());
    summary::track_revisions(draft);
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
    let input_height = signal(48.0_f32);
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
            && d.image_names().is_empty()
            && let Err(cause) = capture::remove(&d.id)
        {
            log::error!("capture: {cause}");
            error.set(Some(s().error_transaction_storage.into()));
            return;
        }
        let retained = !d.input.trim().is_empty()
            || !d.image_names().is_empty()
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
        if let Some(request) = d.pending_ask_user()
            && request
                .validate_answers(&d.answers, &d.correction, d.has_staged_images())
                .is_err()
        {
            error.set(Some(s().capture_answer_needed.into()));
            return;
        }
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
                replying.set(false);
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
    let attach = move || attachments::pick(draft, id, picking, error);
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
    let focus = if draft.with_untracked(|d| d.transcript.is_empty()) {
        initial_focus()
    } else {
        element_ref()
    };
    let editing = move || choosing.get().is_none() && consenting.get().is_none();
    let first_turn = move || draft.with(|d| d.transcript.is_empty());
    let awaiting_answers = move || draft.with(|d| d.pending_ask_user().is_some());
    let send_disabled = move || {
        picking.get()
            || settings::ready_account().is_none()
            || draft.with(|d| {
                d.status == Status::Analyzing
                    || if let Some(request) = d.pending_ask_user() {
                        request
                            .validate_answers(&d.answers, &input.get(), d.has_staged_images())
                            .is_err()
                    } else {
                        input.get().trim().is_empty() && !d.has_staged_images()
                    }
            })
    };
    let entry_field = move || {
        text_input(input)
            .element_ref(&focus)
            .multiline(true)
            .min_h(px(48.0))
            .bg(AdaptiveColor::TRANSPARENT)
            .border(px(0.0))
            .focus(|s| s.bg(AdaptiveColor::TRANSPARENT).border(px(0.0)))
            .h(move || {
                px(if input.get().is_empty() {
                    48.0
                } else {
                    input_height.get()
                })
            })
            .on_content_size_change(move |size: &nsh_core::Size<Points>| {
                input_height.set((size.height.0 + 16.0).clamp(48.0, 120.0));
            })
            .min_w(px(0.0))
            .label(|| s().capture_prompt)
            .placeholder(move || {
                if draft.with(|d| d.transcript.is_empty()) {
                    s().capture_placeholder
                } else {
                    s().capture_reply_hint
                }
            })
    };
    let photo_button = move || {
        IconBtn::new(Icon::Photo, || s().capture_photo.into())
            .variant(Variant::Tonal)
            .on_press(attach)
            .disabled(move || {
                picking.get()
                    || draft.with(|d| {
                        d.status == Status::Analyzing || d.image_names().len() >= MAX_ATTACHMENTS
                    })
            })
    };
    let send_button = move || {
        when(
            move || !awaiting_answers(),
            move || {
                IconBtn::new(Icon::Send, || s().capture_send.into())
                    .variant(Variant::Primary)
                    .on_press(send)
                    .disabled(send_disabled)
            },
        )
    };
    let writing_surface = || view().bg(color::SURFACE_2).rounded(px(radius::WELL)).p_2();
    let composer = move || {
        writing_surface().child(entry_field().w_full()).child(
            view()
                .flex_row()
                .items_center()
                .justify_between()
                .child(photo_button())
                .child(send_button()),
        )
    };
    let reply_bar = move || {
        let empty = move || input.get().trim().is_empty() && !draft.with(|d| d.has_staged_images());
        writing_surface()
            .flex_row()
            .items_end()
            .child(photo_button())
            .child(entry_field().flex_1())
            .child(when(empty, move || {
                IconBtn::new(Icon::Close, || s().cancel.into())
                    .variant(Variant::Ghost)
                    .on_press(move || {
                        dismiss_keyboard();
                        replying.set(false);
                    })
            }))
            .child(when(move || !empty(), send_button))
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
                        error.set(None);
                        choosing.set(None);
                        consenting.set(None);
                    })
            },
        ))
        .child(
            text(move || {
                if let Some(choice) = choosing.get() {
                    match choice {
                        accounts::Choice::Value(_) => s().edit,
                        accounts::Choice::Account { .. } => s().capture_choose_account,
                        accounts::Choice::Category(_) => s().category,
                    }
                } else if awaiting_answers() {
                    s().capture_clarify
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
    // The composer lives at the bottom for the whole task: the first message
    // and every later correction are typed in the same place, in the thumb
    // zone, above the keyboard.
    let header = view().gap_2().child(header);
    let body = view()
        .gap_4()
        .child(live_preview::panel(
            sheets.capture,
            input,
            draft,
            consenting,
        ))
        .child(dynamic(move || {
            let consent = consenting.get();
            let choice = choosing.get();
            // Reading the draft here subscribes the thread to every turn.
            let d = draft.get();
            untracked(move || {
                if let Some(choice) = choice {
                    match choice {
                        accounts::Choice::Account { index, destination } => {
                            accounts::picker(draft, input, error, choosing, index, destination)
                                .into_element()
                        }
                        accounts::Choice::Category(index) => {
                            accounts::category_picker(draft, input, error, choosing, index)
                                .into_element()
                        }
                        accounts::Choice::Value(index) => {
                            summary::edit_value(draft, input, error, choosing, index)
                        }
                    }
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
                        .child(settings::capture_options(&account).recent_context.then(|| {
                            text(crate::i18n::catalog::copy(
                                "You also enabled recent records, favorites and held securities for this model.",
                                "你已允许这个模型参考最近记录、收藏餐食及所持证券。",
                            )).typo(Type::Subhead).text_color(color::BODY)
                        }))
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
                    let offer_manual = d.transcript.is_empty() || d.status == Status::Failed;
                    view()
                        .gap_4()
                        .child(thread::thread(
                            &d, draft, input, choosing, send, arrived, error,
                        ))
                        .child(
                            (!d.transcript.is_empty() && d.has_staged_images())
                                .then(|| thread::staged_images(&d, draft, input, error)),
                        )
                        .child(
                            (d.transcript.is_empty() && !d.has_staged_images())
                                .then(|| recent::list(input)),
                        )
                        .child(offer_manual.then(|| {
                            view()
                                .role(AccessibilityRole::Button)
                                .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
                                .active(|s| s.opacity(0.7))
                                .on_press(move || manual.update(|open| *open = !*open))
                                .min_h(px(48.0))
                                .self_start()
                                .flex_row()
                                .items_center()
                                .gap_1()
                                .optional_label(|| Some(s().capture_manual.into()))
                                .accessibility_state(move || AccessibilityState {
                                    expanded: Some(manual.get()),
                                    ..Default::default()
                                })
                                .child(
                                    text(|| s().capture_manual)
                                        .typo(Type::Subhead)
                                        .text_color(color::BODY),
                                )
                                .child(crate::ui::surface::disclosure_chevron(manual))
                        }))
                        .child(when(
                            move || offer_manual && manual.get(),
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
                        .child(first_turn().then(|| favorites::favorites_row(close)))
                        .into_element()
                }
            })
        }))
        .child(note(move || error.get().map(Into::into), || true));
    let ready_to_save = computed(move || {
        let mut d = draft.get();
        d.correction = input.get();
        capture::ready(&d)
    });
    let compact_save_row = move || {
        !dark()
            && window().width.0 >= 360.0
            && font_scale() <= 1.2
            && editing()
            && !first_turn()
            && !replying.get()
            && ready_to_save.get()
    };
    let review_actions = view()
        .gap_2()
        .style_when(compact_save_row, |s| {
            s.flex_row().items_center().gap(px(10.0))
        })
        .child(when(
            move || editing() && !first_turn() && draft.with(|d| d.status != Status::Analyzing),
            move || {
                view()
                    .min_w(px(0.0))
                    .style_when(compact_save_row, |s| s.flex_1())
                    .child(when(
                        move || !replying.get(),
                        move || {
                            // Shaped like the composer it opens, so the
                            // conversation reads as one continuing thread.
                            nsh_base::button()
                                .on_press(move || {
                                    replying.set(true);
                                    spawn(async move {
                                        next_frame().await;
                                        focus.focus();
                                    });
                                })
                                .accessibility_label(Some(s().capture_add_detail.into()))
                                .flex_row()
                                .items_center()
                                .gap(px(10.0))
                                .min_h(px(52.0))
                                .px(px(16.0))
                                .bg(color::SURFACE_2)
                                .rounded(px(radius::WELL))
                                .style_when(
                                    || !dark(),
                                    |s| s.min_h(px(48.0)).rounded_full().bg(color::SUNKEN),
                                )
                                .transition_colors()
                                .duration(crate::ui::motion::INSTANT)
                                .active(|s| s.bg(color::SUNKEN))
                                .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
                                .child(icon(Icon::Photo, 20.0, color::MUTED))
                                .child(
                                    text(|| s().capture_add_detail)
                                        .typo(Type::Body)
                                        .text_color(color::MUTED)
                                        .flex_1()
                                        .number_of_lines(1),
                                )
                        },
                    ))
                    .child(when(move || replying.get(), reply_bar))
            },
        ))
        .child(dynamic(move || {
            let status = draft.with(|d| d.status);
            let consent = consenting.get();
            let picking_account = choosing.get().is_some();
            let ready_now = ready_to_save.get();
            let light = !dark();
            let composing = replying.get();
            let pending_answers = awaiting_answers();
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
                if !connected && !ready_now {
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
                if pending_answers {
                    return Btn::primary()
                        .label(|| s().capture_submit_answers.into())
                        .disabled(send_disabled)
                        .on_press(send)
                        .into_element();
                }
                if ready_now && !composing {
                    let variant = if light {
                        Variant::CaptureSave
                    } else {
                        Variant::Primary
                    };
                    return Btn::new(variant)
                        .haptic_on_press(false)
                        .label(move || {
                            let n = draft.with(|d| d.records.len());
                            if n == 1 {
                                s().capture_confirm.into()
                            } else {
                                format!("{} ({n})", s().capture_confirm).into()
                            }
                        })
                        .on_press(move || {
                            let confirmed = current();
                            let still = reduce_motion();
                            match capture::confirm_review(&confirmed) {
                                Ok(undo) => {
                                    haptic(nsh_core::Haptic::Notification(
                                        nsh_core::HapticNotification::Success,
                                    ));
                                    if let Some(flight) = flight {
                                        flight::saved(flight, &confirmed, still);
                                    }
                                    dismiss_keyboard();
                                    sheets.capture.set(false);
                                    let destination = summary::saved_view(&confirmed, sheets);
                                    show_capture_receipt(
                                        summary::saved_message(&confirmed),
                                        (
                                            s().undo.into(),
                                            Rc::new(move || undo_save(&undo, flight)),
                                        ),
                                        (s().view_records.into(), Rc::new(destination)),
                                    );
                                }
                                Err(cause) => {
                                    log::error!("capture: confirmation failed: {cause}");
                                    error.set(Some(s().error_transaction_storage.into()));
                                }
                            }
                        })
                        .style_when(move || light, |s| s.min_h(px(48.0)))
                        .style_when(
                            move || light && !compact_save_row(),
                            |s| s.shadow(crate::ui::theme::shadow::CARD),
                        )
                        .into_element();
                }
                view().into_element()
            })
        }));
    let actions = view()
        .gap_2()
        .child(when(move || editing() && first_turn(), composer))
        .child(review_actions);
    conversation_sheet(
        move || sheets.capture.get(),
        move || {
            if choosing.get_untracked().is_some() || consenting.get_untracked().is_some() {
                error.set(None);
                choosing.set(None);
                consenting.set(None);
            } else {
                close();
            }
        },
        move || !first_turn() || !editing(),
        header,
        body,
        actions,
    )
}

fn undo_save(receipt: &capture::CaptureUndo, flight: Option<flight::CaptureFlight>) {
    use crate::i18n::catalog::copy;
    match capture::undo(receipt) {
        Ok(()) => {
            flight::cancel(flight);
            show_toast(copy("Save undone", "已撤销本次保存"), None);
        }
        Err(cause) => {
            log::warn!("capture: undo failed: {cause}");
            let receipt = receipt.clone();
            show_toast(
                copy(
                    "Could not undo this save. The records must still match.",
                    "未能撤销，记录须保留保存时的内容。",
                ),
                Some((
                    s().try_again.into(),
                    Rc::new(move || undo_save(&receipt, flight)),
                )),
            );
        }
    }
}
