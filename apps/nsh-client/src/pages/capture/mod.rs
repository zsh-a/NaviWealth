//! One text/image composer. Results are records to review, with one natural
//! language correction box. Forms are an explicit manual fallback.
mod favorites;
mod summary;

use super::home::Sheets;
use crate::{
    data::{capture, clock, photos, settings, vision},
    domain::{
        account::ModelAccount,
        capture::{Draft, MAX_INPUT, Status},
    },
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color,
        feedback::spinner,
        field::{note, text_input},
        sheet::task_sheet,
        surface::{disclosure, hairline},
        toast::show_toast,
        toggle::checkbox_row,
    },
};
use health_core::consent::Consent;
use nsh_core::{
    geometry::{DevicePixels, Percentage},
    picker::PickRequest,
    prelude::*,
};
use std::rc::Rc;

pub fn capture_editor(sheets: Sheets) -> impl IntoElement {
    dynamic(move || {
        if !sheets.capture.get() {
            return view().into_element();
        }
        let id = sheets.capture_draft.get();
        untracked(move || {
            let kept = id
                .and_then(|id| capture::get(&id))
                .unwrap_or_else(capture::new);
            editor(sheets, kept).into_element()
        })
    })
}

fn editor(sheets: Sheets, initial: Draft) -> impl IntoElement {
    if let Some(photo) = initial.photo.clone() {
        spawn(photos::load(vec![photo]));
    }
    let id = stored(initial.id.clone());
    let draft = signal(initial);
    let error = signal(None::<String>);
    let manual = signal(false);
    let consenting = signal(None::<ModelAccount>);
    let remember = signal(false);
    let input = signal(if draft.with_untracked(|d| d.status == Status::Editing) {
        draft.with_untracked(|d| d.input.clone())
    } else {
        draft.with_untracked(|d| d.correction.clone())
    });
    let picking = signal(false);
    effect(move || {
        let kept = id.with(|id| capture::get(id));
        if let Some(kept) = kept {
            untracked(|| {
                if draft.with(|d| d.status == Status::Analyzing) && kept.status != Status::Analyzing
                {
                    input.set(kept.correction.clone());
                    draft.set(kept);
                }
            });
        }
    });
    let current = move || {
        let mut d = draft.get_untracked();
        if d.status == Status::Editing {
            d.input = input.get_untracked();
        } else {
            d.correction = input.get_untracked();
        }
        d
    };
    let close = move || {
        if consenting.get_untracked().is_some() {
            consenting.set(None);
            return;
        }
        let d = current();
        if d.status == Status::Editing
            && d.input.trim().is_empty()
            && d.photo.is_none()
            && let Err(cause) = capture::remove(&d.id)
        {
            log::error!("capture: {cause}");
            error.set(Some(s().error_transaction_storage.into()));
            return;
        }
        if d.status != Status::Analyzing
            && (!d.input.trim().is_empty() || d.photo.is_some() || !d.records.is_empty())
            && let Err(cause) = capture::put(d)
        {
            log::error!("capture: draft save failed: {cause}");
            error.set(Some(s().error_transaction_storage.into()));
            return;
        }
        dismiss_keyboard();
        sheets.capture.set(false);
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
    let header = view()
        .flex_row()
        .items_center()
        .gap_2()
        .child(
            text(move || {
                if draft.with(|d| d.records.is_empty()) {
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
        .child(
            Btn::ghost()
                .size(Size::Small)
                .label(|| s().done.into())
                .on_press(close),
        );
    let body = view()
        .gap_4()
        .child(dynamic(move || {
            let consent = consenting.get();
            untracked(move || {
                if let Some(account) = consent {
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
                    content(draft, input, manual, picking, attach, sheets, close).into_element()
                }
            })
        }))
        .child(note(move || error.get().map(Into::into), || true));
    let actions = dynamic(move || {
        let status = draft.with(|d| d.status);
        let consent = consenting.get();
        let correcting = !input.get().trim().is_empty();
        let has_records = draft.with(|d| !d.records.is_empty());
        let connected = settings::ready_account().is_some();
        untracked(move || {
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
            if status == Status::Ready && has_records && !correcting {
                return Btn::primary()
                    .label(move || {
                        let n = draft.with(|d| d.records.len());
                        if n == 1 {
                            s().capture_confirm.into()
                        } else {
                            format!("{} ({n})", s().capture_confirm).into()
                        }
                    })
                    .disabled(move || {
                        let mut d = draft.get();
                        d.correction = input.get();
                        !capture::ready(&d)
                    })
                    .on_press(move || {
                        let draft_id = id.with(|id| id.clone());
                        match capture::put(current()).and_then(|()| capture::confirm(&draft_id)) {
                            Ok(()) => {
                                dismiss_keyboard();
                                sheets.capture.set(false);
                                show_toast(s().capture_saved, None);
                            }
                            Err(cause) => {
                                log::error!("capture: confirmation failed: {cause}");
                                error.set(Some(s().error_transaction_storage.into()));
                            }
                        }
                    })
                    .into_element();
            }
            Btn::primary()
                .label(move || {
                    if status == Status::Failed {
                        s().capture_retry
                    } else if has_records {
                        s().capture_update
                    } else {
                        s().capture_generate
                    }
                    .into()
                })
                .disabled(move || {
                    picking.get()
                        || (input.get().trim().is_empty()
                            && draft.with(|d| d.photo.is_none() && d.input.trim().is_empty()))
                })
                .on_press(send)
                .into_element()
        })
    });
    task_sheet(move || sheets.capture.get(), close, header, body, actions)
}

fn content(
    draft: Signal<Draft>,
    input: Signal<String>,
    manual: Signal<bool>,
    picking: Signal<bool>,
    attach: impl Fn() + Copy + 'static,
    sheets: Sheets,
    close: impl Fn() + Copy + 'static,
) -> impl IntoElement {
    view()
        .gap_4()
        .child(
            when(
                move || draft.with(|d| d.status == Status::Analyzing),
                move || {
                    view()
                        .gap_3()
                        .py_4()
                        .child(spinner(24.0, color::INK))
                        .child(
                            text(|| s().capture_reading)
                                .typo(Type::Headline)
                                .text_color(color::INK),
                        )
                        .child(
                            text(|| s().capture_background)
                                .typo(Type::Body)
                                .text_color(color::MUTED),
                        )
                },
            )
            .otherwise(move || {
                view()
                    .gap_3()
                    .child(when(
                        move || draft.with(|d| d.status == Status::Failed),
                        move || {
                            view()
                                .gap_2()
                                .child(
                                    text(move || {
                                        draft
                                            .with(|d| capture::failure(&d.id))
                                            .map(|e| super::review::failure_copy(s(), &e).0)
                                            .unwrap_or(s().capture_failed)
                                    })
                                    .typo(Type::Headline)
                                    .text_color(color::CAUTION),
                                )
                                .child(Btn::ghost().label(|| s().open_settings.into()).on_press(
                                    move || {
                                        close();
                                        if !sheets.capture.get_untracked() {
                                            nav::push(Route::ModelSettings);
                                        }
                                    },
                                ))
                                .child(when(
                                    move || draft.with(|d| !d.records.is_empty()),
                                    move || {
                                        Btn::ghost()
                                            .label(|| s().capture_keep_result.into())
                                            .on_press(move || {
                                                input.set(String::new());
                                                draft.update(|d| {
                                                    d.status = Status::Ready;
                                                    d.correction.clear();
                                                });
                                                if let Err(e) = capture::put(draft.get_untracked())
                                                {
                                                    log::error!("capture: {e}");
                                                }
                                            })
                                    },
                                ))
                        },
                    ))
                    .child(when(
                        move || draft.with(|d| d.status != Status::Editing),
                        move || {
                            view()
                                .flex_row()
                                .gap_3()
                                .items_center()
                                .child(when(
                                    move || draft.with(|d| d.photo.is_some()),
                                    move || {
                                        image(move || {
                                            draft
                                                .with(|d| {
                                                    d.photo.as_ref().and_then(|n| photos::uri(n))
                                                })
                                                .unwrap_or_default()
                                        })
                                        .size(px(48.0))
                                        .object_fit(ResizeMode::Cover)
                                        .rounded(px(8.0))
                                    },
                                ))
                                .child(
                                    text(move || draft.with(|d| d.input.clone()))
                                        .typo(Type::Subhead)
                                        .text_color(color::MUTED)
                                        .number_of_lines(2)
                                        .flex_1(),
                                )
                        },
                    ))
                    .child(dynamic(move || {
                        let d = draft.get();
                        untracked(move || summary::records(&d))
                    }))
                    .child(when(
                        move || draft.with(|d| !d.question.is_empty()),
                        move || {
                            text(move || draft.with(|d| d.question.clone()))
                                .typo(Type::Body)
                                .text_color(color::INK)
                        },
                    ))
                    .child(
                        text(move || {
                            if draft.with(|d| d.status == Status::Editing) {
                                s().capture_prompt
                            } else {
                                s().capture_correction
                            }
                        })
                        .typo(Type::Headline)
                        .text_color(color::INK),
                    )
                    .child(
                        text_input(input)
                            .multiline(true)
                            .h(px(96.0))
                            .label(|| s().capture_prompt)
                            .placeholder(move || {
                                if draft.with(|d| d.status == Status::Editing) {
                                    s().capture_placeholder
                                } else {
                                    s().capture_correction_hint
                                }
                            }),
                    )
                    .child(when(
                        move || draft.with(|d| d.status == Status::Editing),
                        move || {
                            view()
                                .gap_3()
                                .child(when(
                                    move || draft.with(|d| d.photo.is_some()),
                                    move || {
                                        view()
                                            .flex_row()
                                            .items_center()
                                            .gap_3()
                                            .child(
                                                image(move || {
                                                    draft
                                                        .with(|d| {
                                                            d.photo
                                                                .as_ref()
                                                                .and_then(|n| photos::uri(n))
                                                        })
                                                        .unwrap_or_default()
                                                })
                                                .size(px(72.0))
                                                .object_fit(ResizeMode::Cover)
                                                .rounded(px(12.0)),
                                            )
                                            .child(
                                                Btn::ghost()
                                                    .label(|| s().capture_remove_photo.into())
                                                    .on_press(move || {
                                                        draft.update(|d| d.photo = None)
                                                    }),
                                            )
                                    },
                                ))
                                .child(
                                    Btn::tonal()
                                        .icon(Icon::Photo)
                                        .label(|| s().capture_photo.into())
                                        .disabled(move || picking.get())
                                        .on_press(attach),
                                )
                                .child(
                                    text(move || {
                                        if settings::ready_account().is_some() {
                                            s().capture_hint
                                        } else {
                                            s().capture_setup
                                        }
                                    })
                                    .typo(Type::Subhead)
                                    .text_color(color::MUTED),
                                )
                        },
                    ))
            }),
        )
        .child(hairline(0.0))
        .child(disclosure(manual, || s().capture_manual.into()))
        .child(when(
            move || manual.get(),
            move || {
                view()
                    .gap_2()
                    .child(
                        Btn::ghost()
                            .label(|| s().log_transaction.into())
                            .on_press(move || {
                                close();
                                if !sheets.capture.get_untracked() {
                                    sheets.finance.set(Some(String::new()));
                                }
                            }),
                    )
                    .child(
                        Btn::ghost()
                            .label(|| s().add_manually.into())
                            .on_press(move || {
                                close();
                                if !sheets.capture.get_untracked() {
                                    sheets.manual();
                                }
                            }),
                    )
                    .child(
                        Btn::ghost()
                            .label(|| s().log_weight.into())
                            .on_press(move || {
                                close();
                                if !sheets.capture.get_untracked() {
                                    sheets.weight.set(Some(clock::today()));
                                }
                            }),
                    )
            },
        ))
        .child(favorites::favorites_row(close))
        .child(when(
            move || draft.with(|d| d.status != Status::Editing || capture::get(&d.id).is_some()),
            move || {
                IconBtn::new(Icon::Trash, || s().discard_draft.into())
                    .variant(Variant::Ghost)
                    .on_press(move || {
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
                    })
            },
        ))
}
