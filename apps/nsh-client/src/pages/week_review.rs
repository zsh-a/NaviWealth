//! The Review tab: a week or a calendar month in review. The daily average
//! intake and its change from the period before, a bar per day against the
//! goal for a week (days past it in amber, today in ink, nothing for a day
//! without meals) or a calendar for a month, the weight's change and line,
//! and Garmin's averages. Earlier periods are a step back; a short personal
//! note is kept on its day.

use nsh_core::prelude::*;

use super::{
    home::dock_clearance,
    review_calendar::{calendar, month_days},
    review_charts::{chart, macros, trend},
};
use crate::{
    data::{clock, garmin, meals, settings, weights},
    domain::{
        format,
        meal::Day,
        review::{self, Intake, Period},
    },
    i18n::s,
    ui::{
        Icon, IconBtn, Type, Typo, color,
        figures::{Scale, stat},
        segmented::{Segment, segmented},
        space,
        surface::card,
    },
};

/// The Review tab's content.
pub fn review_tab() -> impl IntoElement {
    let period = signal(Period::Week);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if crate::preview::review_month() {
        period.set(Period::Month);
    }
    // Periods back from the current one.
    let back = signal(0_i32);
    let days = computed(move || {
        review::period_days_starting(period.get(), clock::today(), back.get(), s().week_start())
    });
    let before = computed(move || {
        review::period_days_starting(
            period.get(),
            clock::today(),
            back.get() + 1,
            s().week_start(),
        )
    });
    scroll().flex_1().child(
        view()
            .px(px(space::GUTTER))
            .pt_safe_area_plus(px(10.0))
            .pb(move || px(dock_clearance()))
            .gap_4()
            .child(header(period, back, days))
            .child(segmented(
                vec![
                    Segment::new(Period::Week, || s().this_week.into()),
                    Segment::new(Period::Month, || s().this_month.into()),
                ],
                move || period.get(),
                move |p| {
                    period.set(p);
                    back.set(0);
                },
            ))
            .child(intake_card(period, days, before))
            .child(super::review_note::note_editor(days))
            .child(weight_card(days))
            .child(recovery_card(days)),
    )
}

/// The span over the title, and the steps to other periods.
fn header(period: Signal<Period>, back: Signal<i32>, days: Memo<Vec<Day>>) -> impl IntoElement {
    let month = move || period.get() == Period::Month;
    view()
        .gap_2()
        .px(px(4.0))
        .pt_2()
        .child(
            text(|| s().review)
                .typo(Type::LargeTitle)
                .text_color(color::INK)
                .role(AccessibilityRole::Header),
        )
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(
                    IconBtn::new(Icon::ChevronLeft, move || {
                        if month() {
                            s().previous_month
                        } else {
                            s().previous_week
                        }
                        .into()
                    })
                    .on_press(move || back.update(|b| *b += 1)),
                )
                .child(
                    text(move || {
                        days.with(|d| {
                            if month() {
                                s().month_name(d[0])
                            } else {
                                s().week_span(d[0], d[d.len() - 1])
                            }
                        })
                    })
                    .flex_1()
                    .text_center()
                    .typo(Type::Subhead)
                    .tabular_nums()
                    .text_color(color::BODY),
                )
                .child(
                    IconBtn::new(Icon::ChevronRight, move || {
                        if month() {
                            s().next_month
                        } else {
                            s().next_week
                        }
                        .into()
                    })
                    .on_press(move || back.update(|b| *b = (*b - 1).max(0)))
                    .disabled(move || back.get() == 0),
                ),
        )
}

fn label(title: fn() -> &'static str) -> impl IntoElement {
    text(title)
        .typo(Type::Caption)
        .font_weight(FontWeight::SEMIBOLD)
        .text_color(color::MUTED)
}

/// A quiet pill with a change.
fn delta_pill(text_of: impl Fn() -> String + 'static) -> impl IntoElement {
    view()
        .px(px(10.0))
        .py(px(4.0))
        .rounded_full()
        .bg(color::SURFACE_2)
        .child(
            text(text_of)
                .typo(Type::Caption)
                .font_weight(FontWeight::SEMIBOLD)
                .tabular_nums()
                .text_color(color::MUTED),
        )
}

fn intake_of(days: Vec<Day>) -> Intake {
    let summaries: Vec<_> = days.into_iter().map(meals::summary).collect();
    review::intake(&summaries)
}

fn intake_card(
    period: Signal<Period>,
    days: Memo<Vec<Day>>,
    before: Memo<Vec<Day>>,
) -> impl IntoElement {
    let intake = computed(move || intake_of(days.get()));
    let previous = computed(move || intake_of(before.get()).average.map(|a| a.kcal));
    let goal = computed(settings::goal);
    let average = move || intake.with(|i| i.average.map(|a| a.kcal));
    let delta = move || Some(average()? - previous.get()?).filter(|d| d.is_finite());
    card()
        .p(px(space::CARD))
        .gap_4()
        .child(
            view()
                .flex_row()
                .items_start()
                .justify_between()
                .gap_3()
                .child(
                    view()
                        .gap(px(6.0))
                        .child(label(|| s().daily_intake))
                        .child(stat(
                            move || average().map(format::kcal),
                            || s().kcal.to_owned(),
                            Scale::Hero,
                        )),
                )
                .child(when(
                    move || delta().is_some(),
                    move || {
                        delta_pill(move || {
                            s().vs_previous(delta().unwrap_or(0.0), period.get() == Period::Month)
                        })
                    },
                )),
        )
        .child(
            when(
                move || average().is_some(),
                move || {
                    view()
                        .gap_3()
                        .child(dynamic(move || {
                            let kcal = intake.with(|i| i.kcal.clone());
                            let (days, goal) = (days.get(), goal.get());
                            if period.get() == Period::Month {
                                let weighed: Vec<bool> =
                                    days.iter().map(|&d| weights::on(d).is_some()).collect();
                                let start = s().week_start();
                                untracked(move || {
                                    calendar(month_days(&days, &kcal, &weighed), goal, start, None)
                                        .into_element()
                                })
                            } else {
                                untracked(move || chart(days, kcal, goal).into_element())
                            }
                        }))
                        .child(
                            text(move || {
                                let (over, logged, of) = intake.with(|i| {
                                    (
                                        goal.get().map_or(0, |g| review::over_goal(&i.kcal, g)),
                                        i.logged_days,
                                        i.kcal.len(),
                                    )
                                });
                                s().intake_caption(goal.get(), over, logged, of)
                            })
                            .typo(Type::Caption)
                            .tabular_nums()
                            .text_color(color::MUTED),
                        )
                        .child(macros(intake))
                },
            )
            .otherwise(|| {
                text(|| s().no_week_data)
                    .typo(Type::Subhead)
                    .text_color(color::MUTED)
            }),
        )
}

fn weight_card(days: Memo<Vec<Day>>) -> impl IntoElement {
    let entries = computed(move || {
        let (first, last) = days.with(|d| (d[0], d[d.len() - 1]));
        weights::window(last, last.days_since(first) + 1)
    });
    let change = computed(move || {
        days.with(|d| review::weight_change(&weights::all(), d[0], d[d.len() - 1]))
    });
    let latest = move || entries.with(|e| e.last().copied());
    when(
        move || latest().is_some(),
        move || {
            view()
                .px(px(4.0))
                .pt_2()
                .gap_3()
                .child(
                    view()
                        .flex_row()
                        .items_center()
                        .justify_between()
                        .child(label(|| s().weight_week))
                        .child(when(
                            move || change.with(Option::is_some),
                            move || {
                                delta_pill(move || {
                                    let d = change.with(|c| c.unwrap_or(0.0));
                                    format!("{} kg", s().signed_kg(d))
                                })
                            },
                        )),
                )
                .child(stat(
                    move || latest().map(|w| s().kg(w.kg)),
                    || "kg".to_owned(),
                    Scale::Hero,
                ))
                .child(dynamic(move || {
                    let history = weights::all();
                    let (first, points) = days.with(|d| {
                        (
                            d[0],
                            d.iter()
                                .filter_map(|&day| {
                                    crate::domain::weight::trend_weight(&history, day).map(|kg| {
                                        crate::domain::weight::Weight {
                                            day,
                                            kg,
                                            logged_at_ms: 0,
                                        }
                                    })
                                })
                                .collect(),
                        )
                    });
                    let span = days.with(|d| d.len()) as f64;
                    untracked(move || trend(first, span, points))
                }))
        },
    )
}

fn recovery_card(days: Memo<Vec<Day>>) -> impl IntoElement {
    let averages = computed(move || {
        let measured: Vec<_> = days.get().into_iter().filter_map(garmin::on).collect();
        review::recovery(&measured)
    });
    let tile = |name: fn() -> &'static str,
                value: Box<dyn Fn() -> Option<(String, String)>>,
                detail: Box<dyn Fn() -> Option<String>>| {
        view()
            .flex_1()
            .min_w(px(0.0))
            .py(px(10.0))
            .gap(px(6.0))
            .child(label(name))
            .child({
                let value = computed(value);
                stat(
                    move || value.get().map(|(v, _)| v),
                    move || value.get().map(|(_, u)| u).unwrap_or_default(),
                    Scale::Tile,
                )
            })
            .child(
                text(move || detail().unwrap_or_default())
                    .typo(Type::Caption)
                    .tabular_nums()
                    .text_color(color::MUTED)
                    .number_of_lines(1),
            )
    };
    when(
        move || averages.with(|a| a.days > 0),
        move || {
            view()
                .gap(px(10.0))
                .child(
                    view()
                        .flex_row()
                        .gap(px(10.0))
                        .child(tile(
                            || s().avg_sleep,
                            Box::new(move || {
                                averages.with(|a| {
                                    a.sleep_seconds
                                        .map(|v| (s().sleep_time(v as u32), String::new()))
                                })
                            }),
                            Box::new(move || {
                                averages.with(|a| {
                                    a.sleep_score.map(|v| s().sleep_score(v.round() as u8))
                                })
                            }),
                        ))
                        .child(tile(
                            || s().resting_hr,
                            Box::new(move || {
                                averages.with(|a| {
                                    a.resting_hr.map(|v| (format!("{v:.0}"), "bpm".to_owned()))
                                })
                            }),
                            Box::new(|| None),
                        )),
                )
                .child(
                    view()
                        .flex_row()
                        .gap(px(10.0))
                        .child(tile(
                            || s().hrv,
                            Box::new(move || {
                                averages.with(|a| {
                                    a.hrv_ms.map(|v| (format!("{v:.0}"), "ms".to_owned()))
                                })
                            }),
                            Box::new(|| None),
                        ))
                        .child(tile(
                            || s().steps,
                            Box::new(move || {
                                averages.with(|a| a.steps.map(|v| (format::kcal(v), String::new())))
                            }),
                            Box::new(|| None),
                        )),
                )
        },
    )
}
