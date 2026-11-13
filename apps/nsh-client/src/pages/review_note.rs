//! Personal notes stay on their date as the review window moves.
use crate::{
    data::notes,
    domain::meal::Day,
    i18n::s,
    ui::{
        Type, Typo, color,
        field::{field, text_input},
    },
};
use nsh_core::prelude::*;

pub fn note_editor(days: Memo<Vec<Day>>) -> impl IntoElement {
    dynamic(move || {
        let (first, last) = days.with(|d| (d[0], d[d.len() - 1]));
        untracked(move || {
            let entries = notes::between(first, last);
            let (day, initial) = entries.last().cloned().unwrap_or((last, String::new()));
            let value = signal(initial);
            view()
                .gap_3()
                .children(
                    entries
                        .into_iter()
                        .filter(|(d, _)| *d != day)
                        .map(|(d, t)| {
                            text(format!("{} · {}", s().long_date(d), t))
                                .typo(Type::Subhead)
                                .text_color(color::MUTED)
                        }),
                )
                .child(field(
                    || s().review_note,
                    text_input(value)
                        .label(|| s().review_note)
                        .on_change(move |text: &str| {
                            value.set(text.to_owned());
                            notes::set(day, text);
                        }),
                ))
                .child(
                    text(move || s().long_date(day))
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                )
                .child(
                    text(|| s().review_note_hint)
                        .typo(Type::Caption)
                        .text_color(color::MUTED),
                )
        })
    })
}
