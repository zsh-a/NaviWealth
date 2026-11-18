//! Logging, correcting or deleting a day's weight, in a sheet.

use std::rc::Rc;

use nsh_core::prelude::*;

use crate::{
    data::{body_metrics, settings, weights},
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
use navi_health::bodycomp;

/// What the day already knows beyond the number: a scale estimate's three
/// shares, and the BMI of the weight as typed (or as kept).
fn scale_details(day: Day, typed: impl Fn() -> Option<f64> + Copy + 'static) -> impl IntoElement {
    let estimate = move || body_metrics::on(day);
    let bmi_text = move || -> Option<String> {
        let kg = typed()
            .or_else(|| weights::on(day).map(|entry| entry.kg))
            .filter(|kg| valid_kg(*kg))?;
        let height = settings::height_cm()?;
        Some(format!("{} {}", s().bmi, bodycomp::bmi(kg, height)?))
    };
    when(
        move || estimate().is_some() || bmi_text().is_some(),
        move || {
            view()
                .gap_1()
                .child(when(
                    move || estimate().is_some(),
                    move || {
                        let metrics = estimate().unwrap().metrics;
                        text(format!(
                            "{} · {} {:.1}% · {} {:.1}% · {} {:.1}%",
                            s().scale_estimate,
                            s().body_fat,
                            metrics.body_fat_percent,
                            s().muscle,
                            metrics.muscle_percent,
                            s().water,
                            metrics.water_percent,
                        ))
                        .typo(Type::Subhead)
                        .tabular_nums()
                        .text_color(color::MUTED)
                        .number_of_lines(2)
                        .into_element()
                    },
                ))
                .child(when(
                    move || bmi_text().is_some(),
                    move || {
                        text(move || bmi_text().unwrap_or_default())
                            .typo(Type::Subhead)
                            .tabular_nums()
                            .text_color(color::MUTED)
                            .into_element()
                    },
                ))
        },
    )
}

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
        .child(scale_details(day, move || value.with(|v| parse_number(v))))
        .child(crate::scale::launch_button(move || open.set(None)))
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
                                            weights::restore_removed(removed);
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
