//! A compact, dated body summary, with composition disclosed on demand.

use nsh_core::prelude::*;

use crate::{
    data::{body_metrics, scale, settings, weights},
    domain::{meal::Day, weight::Weight},
    i18n::s,
    pages::home::Sheets,
    ui::{
        Btn, Icon, IconBtn, Type, Typo, Variant, color,
        figures::{Scale, stat},
        icon,
        sheet::task_sheet,
        space,
        surface::{HAIRLINE, disclosure, row_button},
    },
};

#[derive(Clone, PartialEq)]
struct Snapshot {
    weight: Weight,
    metrics: Option<navi_health::bodycomp::BodyMetrics>,
    measurement: Option<navi_health::scale::Measurement>,
    bmi: Option<f64>,
}

/// Join only on the kept weight's day. A newer manual weight must never
/// borrow composition from an older measurement. Provenance freezes BMI's
/// height; manual weights use the current profile.
fn snapshot(day: Day) -> Option<Snapshot> {
    let weight = weights::latest_until(day)?;
    // Read the mirror to track replacements, but trust frozen composition
    // only after its evidence validates against both persisted records.
    let legacy = body_metrics::on(weight.day).map(|entry| entry.metrics);
    let (metrics, measurement) = match scale::evidence_on(weight.day) {
        scale::MeasurementEvidence::Legacy => (legacy, None),
        scale::MeasurementEvidence::Confirmed(m) => (m.metrics.clone(), Some(m)),
        scale::MeasurementEvidence::Rejected => (None, None),
    };
    let bmi = measurement.as_ref().map_or_else(
        || settings::height_cm().and_then(|h| navi_health::bodycomp::bmi(weight.kg, h)),
        |m| m.summary().bmi,
    );
    Some(Snapshot {
        weight,
        metrics,
        measurement,
        bmi,
    })
}

pub fn summary(day: impl Fn() -> Day + Copy + 'static) -> impl IntoElement {
    let sheets = Sheets::get();
    let data = computed(move || snapshot(day()));
    let value = move || data.with(|d| d.as_ref().map(|d| s().kg(d.weight.kg)));
    let date = move || {
        data.with(|d| match d.as_ref() {
            Some(d) if d.weight.day == day() => s().today.to_owned(),
            Some(d) if d.weight.day.0.year() != day().0.year() => d.weight.day.to_string(),
            Some(d) => s().short_date(d.weight.day),
            None => String::new(),
        })
    };
    row_button(move || {
        if data.with(Option::is_some) {
            sheets.body.set(Some(day()));
        } else {
            sheets.weight.set(Some(day()));
        }
    })
    .flex_col()
    .items_stretch()
    .px(px(space::CARD))
    .py_2()
    .gap_3()
    .min_w(px(0.0))
    .accessibility_label(move || {
        let detail = value().map_or_else(
            || s().tap_to_log.to_owned(),
            |kg| format!("{kg} kg, {}", date()),
        );
        Some(format!("{}, {detail}", s().body_metrics).into())
    })
    .child(
        view()
            .flex_row()
            .items_center()
            .gap_2()
            .child(
                text(|| s().body_metrics)
                    .typo(Type::Headline)
                    .text_color(color::INK)
                    .flex_1()
                    .min_w(px(0.0)),
            )
            .child(when(
                move || data.with(Option::is_some),
                || {
                    view()
                        .flex_row()
                        .items_center()
                        .gap_2()
                        .child(
                            text(|| s().body_overview)
                                .typo(Type::Caption)
                                .text_color(color::MUTED),
                        )
                        .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
                },
            )),
    )
    .child(
        view()
            .test_id("body-primary")
            .flex_row()
            .items_start()
            .gap_3()
            .style_when(|| font_scale() > 1.2, |s| s.flex_col())
            .child(
                view()
                    .flex_grow(2.0)
                    .basis(px(0.0))
                    .min_w(px(0.0))
                    .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
                    .gap_1()
                    .child(
                        text(|| s().weight)
                            .typo(Type::Caption)
                            .text_color(color::MUTED),
                    )
                    .child(
                        view()
                            .flex_row()
                            .items_baseline()
                            .flex_wrap()
                            .gap_2()
                            .child(stat(value, || "kg".into(), Scale::Tile))
                            .child(
                                text(move || {
                                    let mut parts = Vec::new();
                                    if data
                                        .with(|d| d.as_ref().is_some_and(|d| d.weight.day < day()))
                                    {
                                        parts.push(date());
                                    }
                                    if let Some(delta) = data.with(|d| {
                                        d.as_ref().and_then(|d| weights::weekly_change(d.weight))
                                    }) {
                                        parts.push(s().week_change(delta));
                                    }
                                    parts.join(" · ")
                                })
                                .typo(Type::Caption)
                                .tabular_nums()
                                .text_color(color::MUTED),
                            ),
                    ),
            )
            .child(fact(
                || s().body_fat,
                move || {
                    data.with(|d| {
                        d.as_ref()
                            .and_then(|d| d.metrics.as_ref())
                            .map(|m| format!("{:.1}%", m.body_fat_percent))
                    })
                },
            ))
            .child(fact(
                || s().bmi,
                move || data.with(|d| d.as_ref().and_then(|d| d.bmi).map(|v| format!("{v:.1}"))),
            )),
    )
    .child(when(
        move || data.with(Option::is_none),
        || {
            // Looks like what it does: the whole summary opens entry.
            view()
                .flex_row()
                .items_center()
                .gap(px(6.0))
                .child(icon(Icon::Plus, 16.0, color::INK))
                .child(
                    text(|| s().tap_to_log)
                        .typo(Type::Subhead)
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(color::INK),
                )
        },
    ))
}

fn fact(
    label: fn() -> &'static str,
    value: impl Fn() -> Option<String> + 'static,
) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap_1()
        .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
        .child(
            text(move || value().unwrap_or_else(|| "—".into()))
                .typo(Type::Figure)
                .tabular_nums()
                .text_color(color::INK),
        )
}

pub fn body_overview(day: Day) -> impl IntoElement {
    let sheets = Sheets::get();
    let data = computed(move || snapshot(day));
    let more = signal(false);
    let close = move || sheets.body.set(None);
    let header = view()
        .flex_row()
        .items_center()
        .gap_3()
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap_1()
                .child(
                    text(|| s().body_metrics)
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .role(AccessibilityRole::Header),
                )
                .child(
                    text(move || {
                        data.with(|d| {
                            d.as_ref()
                                .map(|d| s().long_date(d.weight.day))
                                .unwrap_or_else(|| s().long_date(day))
                        })
                    })
                    .typo(Type::Caption)
                    .text_color(color::MUTED),
                ),
        )
        .child(
            IconBtn::new(Icon::Close, || s().back.into())
                .side(48.0)
                .on_press(close),
        );
    let body = view()
        .gap_4()
        .child(when(
            move || data.with(|d| d.as_ref().and_then(|d| d.measurement.as_ref()).is_some()),
            move || {
                detail(
                    || s().scale_algorithm,
                    move || {
                        data.with(|d| {
                            d.as_ref()
                                .and_then(|d| d.measurement.as_ref())
                                .and_then(|m| m.algorithm())
                                .map(|algorithm| {
                                    if algorithm.experimental() {
                                        format!(
                                            "{} · {}",
                                            crate::scale::algorithm_name(algorithm),
                                            s().algorithm_experimental
                                        )
                                    } else {
                                        crate::scale::algorithm_name(algorithm).to_owned()
                                    }
                                })
                        })
                    },
                )
            },
        ))
        .child(detail(
            || s().weight,
            move || data.with(|d| d.as_ref().map(|d| format!("{} kg", s().kg(d.weight.kg)))),
        ))
        .child(pair(
            detail(
                || s().body_fat,
                move || {
                    data.with(|d| {
                        d.as_ref()
                            .and_then(|d| d.metrics.as_ref())
                            .map(|m| format!("{:.1}%", m.body_fat_percent))
                    })
                },
            ),
            detail(
                || s().bmi,
                move || data.with(|d| d.as_ref().and_then(|d| d.bmi).map(|v| format!("{v:.1}"))),
            ),
        ))
        .child(pair(
            detail(
                || s().muscle,
                move || {
                    data.with(|d| {
                        d.as_ref()
                            .and_then(|d| d.metrics.as_ref())
                            .map(|m| format!("{:.1}%", m.muscle_percent))
                    })
                },
            ),
            detail(
                || s().water,
                move || {
                    data.with(|d| {
                        d.as_ref()
                            .and_then(|d| d.metrics.as_ref())
                            .map(|m| format!("{:.1}%", m.water_percent))
                    })
                },
            ),
        ))
        .child(when(
            move || data.with(|d| d.as_ref().and_then(|d| d.metrics.as_ref()).is_none()),
            || {
                text(|| s().body_missing)
                    .typo(Type::Subhead)
                    .text_color(color::MUTED)
            },
        ))
        .child(when(
            move || data.with(|d| d.as_ref().and_then(|d| d.metrics.as_ref()).is_some()),
            || {
                text(|| s().scale_estimate)
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
            },
        ))
        .child(when(
            move || {
                data.with(|d| {
                    d.as_ref()
                        .and_then(|d| weights::weekly_change(d.weight))
                        .is_some()
                })
            },
            move || {
                text(move || {
                    data.with(|d| {
                        d.as_ref()
                            .and_then(|d| weights::weekly_change(d.weight))
                            .map(|v| s().week_change(v))
                            .unwrap_or_default()
                    })
                })
                .typo(Type::Subhead)
                .tabular_nums()
                .text_color(color::MUTED)
            },
        ))
        .child(when(
            move || settings::goal_kg().is_some() && data.with(Option::is_some),
            move || {
                detail(
                    || s().goal_weight,
                    move || {
                        data.with(|d| {
                            d.as_ref().zip(settings::goal_kg()).map(|(d, goal)| {
                                format!("{} kg · {}", s().kg(goal), s().to_goal(d.weight.kg - goal))
                            })
                        })
                    },
                )
            },
        ))
        .child(when(
            move || data.with(|d| d.as_ref().is_some_and(|d| d.measurement.is_some())),
            move || {
                view()
                    .gap_3()
                    .child(disclosure(more, || s().body_more.into()))
                    .child(when(
                        move || more.get(),
                        move || {
                            provenance(move || {
                                data.with(|d| d.as_ref().and_then(|d| d.measurement.clone()))
                            })
                        },
                    ))
            },
        ));
    let actions = view()
        .gap_2()
        .child(crate::scale::launch_button(move || {
            sheets.weight.set(None);
            close();
        }))
        .child(
            Btn::new(Variant::Tonal)
                .label(move || {
                    if weights::on(day).is_some() {
                        s().edit_weight.into()
                    } else {
                        s().log_weight.into()
                    }
                })
                .on_press(move || sheets.weight.set(Some(day))),
        );
    task_sheet(
        move || sheets.body.get().is_some(),
        close,
        header,
        body,
        actions,
    )
}

/// Details are formatted from the original confirmed measurement, never
/// from today's profile or a different manual weight.
fn provenance(
    measurement: impl Fn() -> Option<navi_health::scale::Measurement> + Copy + 'static,
) -> impl IntoElement {
    view()
        .gap_4()
        .child(detail(
            || s().fat_mass,
            move || {
                measurement()
                    .and_then(|m| m.summary().fat_mass_kg)
                    .map(|v| format!("{v:.2} kg"))
            },
        ))
        .child(detail(
            || s().fat_free_mass,
            move || {
                measurement()
                    .and_then(|m| m.summary().fat_free_mass_kg)
                    .map(|v| format!("{v:.2} kg"))
            },
        ))
        .child(detail(
            || s().muscle_mass,
            move || {
                measurement()
                    .and_then(|m| m.summary().muscle_mass_kg)
                    .map(|v| format!("{v:.2} kg"))
            },
        ))
        .child(detail(
            || s().water_mass,
            move || {
                measurement()
                    .and_then(|m| m.summary().water_mass_kg)
                    .map(|v| format!("{v:.2} kg"))
            },
        ))
        .child(detail(
            || s().resistance,
            move || {
                measurement()
                    .and_then(|m| m.resistance_ohm)
                    .map(|v| format!("{v:.1} Ω"))
            },
        ))
        .child(detail(
            || s().measurement_profile,
            move || {
                measurement().map(|m| {
                    format!(
                        "{:.0} cm · {} {}",
                        m.profile.height_cm,
                        s().age_years,
                        m.profile.age_years
                    )
                })
            },
        ))
}

fn pair(a: impl IntoElement, b: impl IntoElement) -> impl IntoElement {
    view()
        .flex_row()
        .gap_4()
        .style_when(|| font_scale() > 1.2, |s| s.flex_col())
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
                .child(a),
        )
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .style_when(|| font_scale() > 1.2, |s| s.flex_grow(0.0).basis(auto()))
                .child(b),
        )
}

fn detail(
    label: fn() -> &'static str,
    value: impl Fn() -> Option<String> + 'static,
) -> impl IntoElement {
    view()
        .gap_1()
        .pb_3()
        .border_b(px(HAIRLINE))
        .border_color(color::LINE)
        .child(text(label).typo(Type::Caption).text_color(color::MUTED))
        .child(
            text(move || value().unwrap_or_else(|| "—".into()))
                .typo(Type::Headline)
                .tabular_nums()
                .text_color(color::INK),
        )
}
