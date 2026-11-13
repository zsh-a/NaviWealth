//! Logging, correcting or deleting a day's weight, in a sheet.

use std::rc::Rc;

use nsh_core::prelude::*;

use crate::{
    data::weights,
    domain::{
        format::{field_number, parse_number},
        meal::Day,
        weight::valid_kg,
    },
    i18n::s,
    ui::{
        Btn, Type, Typo, Variant, color,
        field::{field, note, number_input},
        toast::show_toast,
    },
};

/// Logs or corrects `day`'s weight; deletes it with Undo.
pub fn weight_editor(open: Signal<Option<Day>>) -> impl IntoElement {
    dynamic(move || match open.get() {
        None => view().into_element(),
        Some(day) => untracked(move || editor(day, open).into_element()),
    })
}

fn editor(day: Day, open: Signal<Option<Day>>) -> impl IntoElement {
    let existing = weights::on(day);
    let start = existing
        .or_else(|| weights::latest_until(day))
        .map(|entry| field_number(entry.kg))
        .unwrap_or_default();
    let value = signal(start);
    let attempted = signal(false);
    let parsed = move || value.with(|v| parse_number(v));
    let error = move || attempted.get() && !parsed().is_some_and(valid_kg);
    let save = move || {
        attempted.set(true);
        if let Some(kg) = untracked(parsed).filter(|kg| valid_kg(*kg))
            && weights::set(day, kg)
        {
            open.set(None);
        }
    };
    view()
        .gap_5()
        .child(
            view()
                .gap(px(2.0))
                .child(
                    text(|| s().weight)
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .role(AccessibilityRole::Header),
                )
                .child(
                    text(move || s().long_date(day))
                        .typo(Type::Subhead)
                        .text_color(color::MUTED),
                ),
        )
        .child(
            field(
                || s().weight,
                number_input(value, || "kg", || s().weight)
                    .style_when(error, |s| s.border_color(color::DANGER)),
            )
            .child(note(
                move || error().then(|| s().error_weight.into()),
                || true,
            )),
        )
        .child(
            view()
                .flex_row()
                .gap_3()
                .child(existing.map(|_| {
                    Btn::new(Variant::Danger)
                        .label(|| s().delete_weight.into())
                        .on_press(move || {
                            open.set(None);
                            if let Some(removed) = weights::remove(day) {
                                show_toast(
                                    s().weight_deleted,
                                    Some((
                                        s().undo.into(),
                                        Rc::new(move || {
                                            weights::set(removed.day, removed.kg);
                                        }),
                                    )),
                                );
                            }
                        })
                        .flex_1()
                }))
                .child(
                    Btn::primary()
                        .label(|| s().save_weight.into())
                        .on_press(save)
                        .flex_1(),
                ),
        )
}
