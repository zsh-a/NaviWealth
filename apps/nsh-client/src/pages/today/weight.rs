//! The chosen day's weight: the latest entry up to that day, its change
//! over about a week and the last 30 days as a line; pressing it logs or
//! corrects the day's entry in a sheet.

use std::rc::Rc;

use nsh_base::plot::{Scale, line, plot};
use nsh_core::{
    element::{RowAccessor, Rows},
    prelude::*,
};

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
        surface::card_button,
        toast::show_toast,
    },
};

/// Days the line covers.
const TREND_DAYS: i32 = 30;

/// The weight card of `day`, and the sheet it opens.
pub fn weight_card(day: impl Fn() -> Day + Copy + 'static, open: Signal<bool>) -> impl IntoElement {
    let latest = move || weights::latest_until(day());
    let caption = move || match latest() {
        None => s().weight_hint.to_owned(),
        Some(entry) if entry.day == day() => weights::weekly_change(entry)
            .map(|delta| s().weight_change(delta))
            .unwrap_or_default(),
        Some(entry) => s().weight_days_ago(day().days_since(entry.day)),
    };
    card_button(move || open.set(true))
        .flex_row()
        .items_center()
        .gap_4()
        .px_5()
        .py_4()
        .accessibility_label(move || {
            let value = latest().map(|entry| format!("{} kg", s().kg(entry.kg)));
            Some(SharedString::from(format!(
                "{}, {}",
                s().weight,
                value.unwrap_or_else(|| s().weight_not_logged.to_owned())
            )))
        })
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap(px(2.0))
                .child(
                    text(|| s().weight)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED),
                )
                .child(
                    view()
                        .flex_row()
                        .items_baseline()
                        .gap_1()
                        .child(
                            text(move || match latest() {
                                Some(entry) => s().kg(entry.kg),
                                None => "—".to_owned(),
                            })
                            .typo(Type::Display)
                            .tabular_nums()
                            .text_color(color::INK),
                        )
                        .child(when(
                            move || latest().is_some(),
                            || text("kg").typo(Type::Callout).text_color(color::MUTED),
                        )),
                )
                .child(
                    text(caption)
                        .typo(Type::Caption)
                        .text_color(color::MUTED)
                        .number_of_lines(1),
                ),
        )
        .child(trend(day))
}

/// The last 30 days as a line, each entry at its day; nothing with fewer
/// than two entries.
fn trend(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let points = computed(move || {
        let day = day();
        weights::window(day, TREND_DAYS)
            .into_iter()
            .map(|entry| {
                (
                    f64::from(TREND_DAYS - 1 - day.days_since(entry.day)),
                    entry.kg,
                )
            })
            .collect::<Vec<_>>()
    });
    when(
        move || points.with(|p| p.len() >= 2),
        move || {
            dynamic(move || {
                let (days, kgs): (Vec<f64>, Vec<f64>) = points.get().into_iter().unzip();
                let low = kgs.iter().copied().fold(f64::INFINITY, f64::min);
                let high = kgs.iter().copied().fold(f64::NEG_INFINITY, f64::max);
                // At least 1 kg of range, so a flat week stays flat.
                let pad = ((1.0 - (high - low)) / 2.0).max(0.0) + 0.2;
                let rows =
                    Rows::from_columns(days.len(), [("day".into(), days), ("kg".into(), kgs)]);
                untracked(move || {
                    plot()
                        .w(px(112.0))
                        .h(px(48.0))
                        .data(rows)
                        .x(Some(RowAccessor::from("day")))
                        .y(Some(RowAccessor::from("kg")))
                        .x_scale(Scale::Linear {
                            domain: Some([0.0, f64::from(TREND_DAYS - 1)]),
                            reverse: false,
                        })
                        .y_scale(Scale::Linear {
                            domain: Some([low - pad, high + pad]),
                            reverse: false,
                        })
                        .interactive(false)
                        .child(line().text_color(color::INK).stroke_width(px(2.0)))
                })
            })
        },
    )
}

/// Logs or corrects `day`'s weight; deletes it with Undo.
pub fn weight_editor(
    day: impl Fn() -> Day + Copy + 'static,
    open: Signal<bool>,
) -> impl IntoElement {
    dynamic(move || {
        if !open.get() {
            return view().into_element();
        }
        untracked(move || editor(day(), open).into_element())
    })
}

fn editor(day: Day, open: Signal<bool>) -> impl IntoElement {
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
            open.set(false);
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
                            open.set(false);
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
