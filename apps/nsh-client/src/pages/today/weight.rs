//! Logging, correcting or deleting a day's weight, in a sheet.

use std::rc::Rc;

use nsh_core::prelude::*;

use crate::{
    data::{body_metrics, scale, settings, weights},
    domain::{
        format::{field_number, parse_number},
        meal::Day,
        weight::{rounded, valid_kg},
    },
    i18n::s,
    ui::{
        Btn, Icon, IconBtn, Type, Typo, Variant, color,
        field::{field, note, number_input},
        sheet::{retained, task_dismiss, task_sheet},
        toast::show_toast,
    },
};
use navi_health::bodycomp;

/// What the day already knows beyond the number: a scale estimate's three
/// shares, and the BMI of the weight as typed (or as kept).
fn scale_details(day: Day, typed: impl Fn() -> Option<f64> + Copy + 'static) -> impl IntoElement {
    let unchanged = move || {
        weights::on(day)
            .zip(typed())
            .is_some_and(|(entry, kg)| entry.kg == rounded(kg))
    };
    let estimate = move || {
        if !unchanged() {
            return None;
        }
        let legacy = body_metrics::on(day).map(|entry| entry.metrics);
        match scale::evidence_on(day) {
            scale::MeasurementEvidence::Legacy => legacy,
            scale::MeasurementEvidence::Confirmed(m) => m.metrics,
            scale::MeasurementEvidence::Rejected => None,
        }
    };
    let bmi_text = move || -> Option<String> {
        let kg = typed()
            .or_else(|| weights::on(day).map(|entry| entry.kg))
            .filter(|kg| valid_kg(*kg))?;
        let frozen = unchanged().then(|| scale::measurement_on(day)).flatten();
        let bmi = frozen.map_or_else(
            || settings::height_cm().and_then(|height| bodycomp::bmi(kg, height)),
            |m| m.summary().bmi,
        )?;
        Some(format!("{} {bmi}", s().bmi))
    };
    when(
        move || estimate().is_some() || bmi_text().is_some(),
        move || {
            view()
                .gap_1()
                .child(when(
                    move || estimate().is_some(),
                    move || {
                        let metrics = estimate().unwrap();
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
pub fn weight_editor(open: Signal<Option<Day>>, overview: Signal<Option<Day>>) -> impl IntoElement {
    retained(
        move || open.get(),
        move |day| editor(day, open, overview).into_element(),
    )
}

fn editor(day: Day, open: Signal<Option<Day>>, overview: Signal<Option<Day>>) -> impl IntoElement {
    let existing = weights::on(day);
    let start = existing
        .or_else(|| weights::latest_until(day))
        .map(|entry| field_number(entry.kg))
        .unwrap_or_default();
    let initial = stored(start.clone());
    let value = signal(start);
    let asking = signal(false);
    let close = move |whole: bool| {
        open.set(None);
        if whole {
            overview.set(None);
        }
    };
    let dirty = move || value.with_untracked(|v| initial.with(|start| v != start));
    let leave = move |whole: bool| {
        if dirty() {
            crate::ui::feedback::confirm_discard(asking, move || close(whole));
        } else {
            close(whole);
        }
    };
    task_dismiss(move || leave(true));
    let write_error = signal(None);
    let attempted = signal(false);
    let parsed = move || value.with(|v| parse_number(v));
    let error = move || attempted.get() && !parsed().is_some_and(valid_kg);
    let save = move || {
        attempted.set(true);
        if let Some(kg) = untracked(parsed).filter(|kg| valid_kg(*kg)) {
            if weights::set(day, kg) {
                open.set(None);
            } else {
                write_error.set(Some(s().error_transaction_storage));
            }
        }
    };
    let header = view()
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
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
            IconBtn::new(
                if overview.get_untracked().is_some() {
                    Icon::ChevronLeft
                } else {
                    Icon::Close
                },
                || s().back.into(),
            )
            .side(48.0)
            .on_press(move || leave(false)),
        );
    let body = view()
        .gap_5()
        .child(
            field(
                || s().weight,
                number_input(value, || "kg", || s().weight)
                    .style_when(error, |s| s.border_color(color::DANGER)),
            )
            .child(note(
                move || {
                    if error() {
                        Some(s().error_weight.into())
                    } else {
                        write_error.get().map(Into::into)
                    }
                },
                || true,
            )),
        )
        .child(scale_details(day, move || value.with(|v| parse_number(v))))
        .child(crate::scale::launch_action().map(|launch| {
            let launch = stored(launch);
            Btn::new(Variant::Tonal)
                .label(|| crate::scale::launch_label().into())
                .on_press(move || {
                    let connect = move || {
                        close(true);
                        launch.with(|open| open());
                    };
                    if dirty() {
                        crate::ui::feedback::confirm_discard(asking, connect);
                    } else {
                        connect();
                    }
                })
        }));
    let actions = view()
        .flex_row()
        .style_when(|| font_scale() > 1.2, |s| s.flex_col())
        .gap_3()
        .child(existing.map(|_| {
            Btn::new(Variant::Danger)
                .label(|| s().delete_weight.into())
                .on_press(move || {
                    if let Some(removed) = weights::remove(day) {
                        close(true);
                        show_toast(
                            s().weight_deleted,
                            Some((
                                s().undo.into(),
                                Rc::new(move || {
                                    undo_weight(removed);
                                }),
                            )),
                        );
                    } else {
                        write_error.set(Some(s().error_transaction_delete));
                    }
                })
                .flex_1()
                .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
        }))
        .child(
            Btn::primary()
                .label(|| s().save_weight.into())
                .on_press(save)
                .flex_1()
                .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto())),
        );
    task_sheet(
        move || open.get().is_some(),
        move || leave(false),
        header,
        body,
        actions,
    )
}

fn undo_weight(weight: crate::domain::weight::Weight) {
    match weights::restore_removed(weight) {
        Ok(true) => {}
        Ok(false) => show_toast(
            crate::i18n::catalog::copy(
                "This weight has changed. Your newer measurement was kept.",
                "体重记录已更改，已保留较新的测量。",
            ),
            None,
        ),
        Err(error) => {
            log::error!("weight undo: {error}");
            show_toast(
                s().error_transaction_restore,
                Some((s().try_again.into(), Rc::new(move || undo_weight(weight)))),
            )
        }
    }
}
