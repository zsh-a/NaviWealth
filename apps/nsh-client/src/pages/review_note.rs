//! A single-line note on its own day, shared by Review and capture receipts.
use crate::{
    data::notes,
    domain::meal::Day,
    i18n::s,
    ui::{
        Btn, Type, Typo, color,
        field::{note, text_input},
        surface::section,
    },
};
use nsh_core::prelude::*;
use std::collections::BTreeMap;

/// Retain failed writes while navigating within the app, including a failed removal.
#[derive(Clone, Default, PartialEq)]
struct Unsaved(BTreeMap<Day, String>);

pub fn note_editor(days: Memo<Vec<Day>>) -> impl IntoElement {
    dynamic(move || {
        let (first, last) = days.with(|d| (d[0], d[d.len() - 1]));
        untracked(move || {
            let day = global::<Unsaved>()
                .with(|v| v.0.range(first..=last).next_back().map(|(d, _)| *d))
                .or_else(|| notes::between(first, last).last().map(|(d, _)| *d))
                .unwrap_or(last);
            section()
                .gap_3()
                .child(
                    text(move || format!("{} · {}", s().review_note, s().long_date(day)))
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(dynamic(move || {
                    view().gap_2().children(
                        notes::between(first, last)
                            .into_iter()
                            .filter(|(d, _)| *d != day)
                            .map(|(d, line)| {
                                text(format!("{} · {}", s().long_date(d), line))
                                    .typo(Type::Subhead)
                                    .text_color(color::MUTED)
                            }),
                    )
                }))
                .child(input(day))
        })
    })
}

pub(super) fn input(day: Day) -> impl IntoElement {
    let drafts = global::<Unsaved>();
    let value = signal(String::new());
    let failed = computed(move || drafts.with(|v| v.0.contains_key(&day)));
    effect(move || {
        let pending = drafts.with(|v| v.0.get(&day).cloned());
        let saved = notes::between(day, day)
            .pop()
            .map(|(_, s)| s)
            .unwrap_or_default();
        if let Some(pending) = pending {
            value.set(pending);
        } else if value.with_untracked(|v| v.trim() != saved) {
            value.set(saved);
        }
    });
    let save = move |line: &str| {
        if notes::set(day, line) {
            if failed.get_untracked() {
                drafts.update(|v| {
                    v.0.remove(&day);
                });
            }
        } else {
            drafts.update(|v| {
                v.0.insert(day, line.to_owned());
            });
        }
    };
    let count = computed(move || value.with(|v| v.chars().count()));
    view()
        .gap_2()
        .child(
            text_input(value)
                .label(|| s().review_note)
                .placeholder(|| s().review_note_hint)
                .max_length(notes::MAX_CHARS as u32)
                .on_change(move |raw: &str| {
                    let line = raw.replace(['\n', '\r'], " ");
                    value.set(line.clone());
                    save(&line);
                }),
        )
        .child(when(
            move || count.get() >= notes::MAX_CHARS - 20,
            move || {
                text(move || format!("{} / {}", count.get(), notes::MAX_CHARS))
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_right()
                    .text_color(color::MUTED)
            },
        ))
        .child(note(
            move || failed.get().then(|| s().error_transaction_storage.into()),
            || true,
        ))
        .child(when(
            move || failed.get(),
            move || {
                Btn::ghost()
                    .label(|| s().try_again.into())
                    .on_press(move || save(&value.get_untracked()))
            },
        ))
}
