//! Record review stays in its conversation; saving replaces it with a receipt.
use super::{accounts, summary};
use crate::{
    data::{assistant, assistant_store::RecordStatus, capture},
    i18n::{catalog::copy, s},
    ui::{Btn, Size, Type, Typo, color},
};
use nsh_core::prelude::*;

pub(crate) fn inline_review(capture_id: String) -> impl IntoElement {
    let id = stored(capture_id);
    let error = signal(None::<String>);
    let available = computed(move || {
        id.with(|id| {
            capture::get(id).map(|draft| {
                (
                    !draft.records.is_empty(),
                    draft.status == crate::domain::capture::Status::Failed,
                )
            })
        })
    });
    view()
        .gap_3()
        .child(dynamic(move || {
            if let Some((has_records, failed)) = available.get() {
                if has_records && let Some(snapshot) = untracked(|| id.with(|id| capture::get(id))) {
                    return untracked(move || editor(snapshot, error)).into_element();
                }
                return if failed {
                    text(copy("The earlier attempt did not finish. Your input is kept; send it again to continue.", "上次识别未完成，输入已保留。重新发送即可继续。"))
                        .typo(Type::Subhead).text_color(color::MUTED).into_element()
                } else { view().into_element() };
            }
            let outcome = assistant::current_view().and_then(|session| {
                session
                    .record_actions
                    .into_iter()
                    .find(|action| id.with(|id| action.capture_id == *id))
            });
            let Some(outcome) = outcome else {
                return view().into_element();
            };
            let saved = outcome.status == RecordStatus::Saved;
            let label = match outcome.status {
                RecordStatus::Saved => s().capture_saved_count(outcome.records.len()),
                RecordStatus::Discarded => copy("Draft discarded", "草稿已丢弃").into(),
                RecordStatus::Undone => copy("Save undone", "已撤销保存").into(),
            };
            view()
                .gap_2()
                .py_2()
                .child(text(label).typo(Type::Subhead).text_color(color::MUTED))
                .child(saved.then(|| {
                    view()
                        .flex_row()
                        .flex_wrap()
                        .gap_2()
                        .child(
                            Btn::ghost()
                                .size(Size::Small)
                                .label(|| copy("View", "查看").into())
                                .on_press(move || {
                                    error.set(assistant::view_capture(&id.get()).err())
                                }),
                        )
                        .child(when(
                            move || id.with(|id| assistant::can_undo_capture(id)),
                            move || {
                                Btn::ghost()
                                    .size(Size::Small)
                                    .label(|| copy("Undo", "撤销").into())
                                    .disabled(assistant::busy)
                                    .on_press(move || {
                                        error.set(assistant::undo_capture(&id.get()).err())
                                    })
                            },
                        ))
                }))
                .into_element()
        }))
        .child(when(
            move || error.get().is_some(),
            move || {
                text(move || error.get().unwrap_or_default())
                    .typo(Type::Subhead)
                    .text_color(color::DANGER)
            },
        ))
}

fn editor(
    snapshot: crate::domain::capture::Draft,
    error: Signal<Option<String>>,
) -> impl IntoElement {
    let id = stored(snapshot.id.clone());
    let draft = signal(snapshot);
    effect(move || {
        if let Some(next) = id.with(|id| capture::get(id))
            && draft.get_untracked() != next
        {
            draft.set(next);
        }
    });
    let choosing = signal(None::<accounts::Choice>);
    let input = signal(String::new());
    summary::track_revisions(draft);
    view()
        .gap_3()
        .child(
            text(|| copy("Review before saving", "核对后保存"))
                .typo(Type::Caption)
                .text_color(color::MUTED),
        )
        .child(when(
            move || draft.with(|draft| draft.records.is_empty()),
            move || {
                let current = draft.get_untracked();
                let detail = capture::failure(&current.id)
                    .map(|failure| crate::pages::review::failure_copy(s(), &failure).1)
                    .unwrap_or_else(|| {
                        copy(
                            "Your input is kept here. Send a message to prepare this record.",
                            "输入已保留在这里，发送消息即可准备这条记录。",
                        )
                        .into()
                    });
                text(detail).typo(Type::Subhead).text_color(color::MUTED)
            },
        ))
        .child(dynamic(move || {
            let snapshot = draft.get();
            let choice = choosing.get();
            untracked(move || match choice {
                Some(accounts::Choice::Account { index, destination }) => {
                    accounts::picker(draft, input, error, choosing, index, destination)
                        .into_element()
                }
                Some(accounts::Choice::Category(index)) => {
                    accounts::category_picker(draft, input, error, choosing, index).into_element()
                }
                Some(accounts::Choice::Value(index)) => {
                    summary::edit_value(draft, input, error, choosing, index)
                }
                None => summary::records(&snapshot, choosing, draft, input, error),
            })
        }))
        .child(when(
            move || choosing.get().is_some(),
            move || {
                Btn::ghost()
                    .label(|| s().back.into())
                    .on_press(move || choosing.set(None))
            },
        ))
        .child(when(
            move || choosing.get().is_none(),
            move || {
                view()
                    .gap_2()
                    .child(
                        Btn::primary()
                            .label(|| copy("Confirm and save", "确认保存").into())
                            .disabled(move || assistant::busy() || !capture::ready(&draft.get()))
                            .on_press(move || {
                                error.set(assistant::confirm_capture(&draft.get_untracked()).err())
                            }),
                    )
                    .child(
                        view()
                            .flex_row()
                            .flex_wrap()
                            .gap_2()
                            .child(
                                Btn::ghost()
                                    .size(Size::Small)
                                    .label(|| copy("Modify this record", "修改这条记录").into())
                                    .disabled(assistant::busy)
                                    .on_press(move || {
                                        error.set(
                                            assistant::edit_capture(&draft.get_untracked().id)
                                                .err(),
                                        )
                                    }),
                            )
                            .child(
                                Btn::ghost()
                                    .size(Size::Small)
                                    .label(|| copy("Discard draft", "丢弃草稿").into())
                                    .disabled(assistant::busy)
                                    .on_press(move || {
                                        error.set(
                                            assistant::discard_capture(&draft.get_untracked().id)
                                                .err(),
                                        )
                                    }),
                            ),
                    )
            },
        ))
}
