//! Owner decisions remain staged until an explicit submission resumes the tool.
use nsh_core::prelude::*;

use crate::{
    data::capture,
    domain::capture::{AskAnswer, AskUser, Draft},
    i18n::s,
    ui::{Icon, Type, Typo, color, icon, radius, surface::row_button},
};

pub fn questions(
    request: &AskUser,
    snapshot: &Draft,
    draft: Signal<Draft>,
    input: Signal<String>,
    error: Signal<Option<String>>,
    open: bool,
) -> impl IntoElement {
    let call_id = request.call_id.clone();
    let current = snapshot
        .pending_ask_user()
        .is_some_and(|ask| ask.call_id == call_id);
    view()
        .gap_5()
        .flex_1()
        .min_w(px(0.0))
        .children(request.questions.iter().map(|question| {
            let question_id = question.id.clone();
            let call_id = call_id.clone();
            let selected = snapshot
                .answers
                .iter()
                .find(|answer| answer.question_id == question.id)
                .and_then(|answer| answer.option_id.clone());
            view()
                .gap_2()
                .child(
                    view()
                        .gap_1()
                        .child(
                            text(question.text.clone())
                                .typo(Type::Headline)
                                .text_color(color::INK),
                        )
                        .child(current.then(|| {
                            let status = if question.required {
                                s().capture_required
                            } else {
                                s().capture_optional
                            };
                            let detail = if question.reason.is_empty() {
                                status.to_owned()
                            } else {
                                format!("{status} · {}", question.reason)
                            };
                            text(detail).typo(Type::Subhead).text_color(color::MUTED)
                        })),
                )
                .child(open.then(|| {
                    view()
                        .gap_1()
                        .children(question.options.iter().map(move |option| {
                            let call_id = call_id.clone();
                            let question_id = question_id.clone();
                            let option_id = option.id.clone();
                            let checked = selected.as_ref() == Some(&option.id);
                            let label = option.label.clone();
                            row_button(move || {
                                let mut next = draft.get_untracked();
                                if next
                                    .pending_ask_user()
                                    .is_none_or(|ask| ask.call_id != call_id)
                                {
                                    return;
                                }
                                next.answers
                                    .retain(|answer| answer.question_id != question_id);
                                if !checked {
                                    next.answers.push(AskAnswer {
                                        question_id: question_id.clone(),
                                        option_id: Some(option_id.clone()),
                                        text: String::new(),
                                    });
                                }
                                next.correction = input.get_untracked();
                                match capture::put(next.clone()) {
                                    Ok(()) => {
                                        error.set(None);
                                        draft.set(next);
                                    }
                                    Err(_) => error.set(Some(s().error_transaction_storage.into())),
                                }
                            })
                            .min_h(px(48.0))
                            .px_3()
                            .py_2()
                            .accessibility_label(Some(label.clone().into()))
                            .selected(checked)
                            .bg(if checked {
                                color::SUNKEN
                            } else {
                                color::SURFACE_2
                            })
                            .rounded(px(radius::FIELD))
                            .child(
                                view()
                                    .gap_1()
                                    .flex_1()
                                    .min_w(px(0.0))
                                    .child(text(label).typo(Type::Body).text_color(color::INK))
                                    .child((!option.description.is_empty()).then(|| {
                                        text(option.description.clone())
                                            .typo(Type::Subhead)
                                            .text_color(color::MUTED)
                                    })),
                            )
                            .child(checked.then(|| icon(Icon::Check, 20.0, color::INK)))
                        }))
                }))
        }))
        .child(open.then(|| {
            text(|| s().capture_answer_hint)
                .typo(Type::Caption)
                .text_color(color::MUTED)
        }))
}
