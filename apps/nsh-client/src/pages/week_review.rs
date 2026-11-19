//! The Review tab: a week or a calendar month in review. The daily average
//! intake and its change from the period before, a bar per day against the
//! goal for a week (days past it in amber, today in ink, nothing for a day
//! without meals) or a calendar for a month, the weight's change and line,
//! and Garmin's averages. Earlier periods are a step back; a short personal
//! note is kept on its day.

use std::rc::Rc;

use nsh_core::prelude::*;

use super::{
    home::Sheets,
    review_calendar::{Pick, calendar, month_days},
    review_charts::{chart, macros, trend, trend_percent},
};
use crate::{
    data::{body_metrics, clock, garmin, meals, settings, weights},
    domain::{
        format,
        meal::Day,
        review::{self, Intake, Period},
    },
    i18n::s,
    nav::{self, Tab},
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
            .pb_4()
            .gap_4()
            .child(
                text(|| s().review)
                    .typo(Type::LargeTitle)
                    .text_color(color::INK)
                    .role(AccessibilityRole::Header),
            )
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
            .child(header(period, back, days))
            .child(summary(period, days, before))
            .child(intake_card(period, days))
            .child(super::finance_review::spending_section(
                days, before, period,
            ))
            .child(weight_card(days))
            .child(super::review_note::note_editor(days))
            .child(recovery_card(days)),
    )
}

/// The span over the title, and the steps to other periods.
fn header(period: Signal<Period>, back: Signal<i32>, days: Memo<Vec<Day>>) -> impl IntoElement {
    let month = move || period.get() == Period::Month;
    view().gap_2().px(px(4.0)).pt_2().child(
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

fn intake_of(days: Vec<Day>) -> Intake {
    let summaries: Vec<_> = days.into_iter().map(meals::summary).collect();
    review::intake(&summaries)
}

/// The period in one sentence: the daily average against the period
/// before, and the weight trend.
fn summary(
    period: Signal<Period>,
    days: Memo<Vec<Day>>,
    before: Memo<Vec<Day>>,
) -> impl IntoElement {
    let line = computed(move || {
        let current_days = days.get();
        let previous_days = before.get();
        let from = current_days[0];
        let to = *current_days.last().unwrap();
        let full_end = if period.get() == Period::Month {
            from.0.last_of_month()
        } else {
            from.plus_days(6).0
        };
        let previous_to = navi_finance::review::comparison_end(
            from.0,
            full_end,
            previous_days[0].0,
            previous_days.last().unwrap().0,
            clock::today().0,
        );
        let average = intake_of(current_days).average.map(|a| a.kcal);
        let previous = intake_of(
            previous_days
                .into_iter()
                .filter(|d| d.0 <= previous_to)
                .collect(),
        )
        .average
        .map(|a| a.kcal);
        let change = average.zip(previous).map(|(a, p)| a - p);
        let weight = review::weight_change(&weights::all(), from, to);
        let entries = crate::data::finance::transactions_snapshot();
        let spending: Vec<_> = navi_finance::currency::Currency::ALL
            .into_iter()
            .filter_map(|currency| {
                let value = navi_finance::review::spending_in(&entries, from.0, to.0, currency);
                (value.records > 0).then(|| crate::ui::currency::format(value.total, currency))
            })
            .collect();
        s().review_summary(average, change, weight, &spending)
    });
    when(
        move || line.with(Option::is_some),
        move || {
            text(move || line.get().unwrap_or_default())
                .typo(Type::Headline)
                .text_color(color::INK)
                .px(px(4.0))
        },
    )
}

fn intake_card(period: Signal<Period>, days: Memo<Vec<Day>>) -> impl IntoElement {
    let intake = computed(move || intake_of(days.get()));
    let goal = computed(settings::goal);
    let average = move || intake.with(|i| i.average.map(|a| a.kcal));
    card()
        .p(px(space::CARD))
        .gap_4()
        .child(
            view()
                .gap(px(6.0))
                .child(label(|| s().daily_intake))
                .child(when(
                    move || average().is_some(),
                    move || {
                        stat(
                            move || average().map(format::kcal),
                            || s().kcal.to_owned(),
                            Scale::Hero,
                        )
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
                                    let sheets = Sheets::get();
                                    // A day opens in Records.
                                    let pick: Pick = Rc::new(move |day| {
                                        nav::select(Tab::Records);
                                        sheets.jump_to.set(Some(day));
                                    });
                                    calendar(
                                        month_days(&days, &kcal, &weighed),
                                        goal,
                                        start,
                                        Some(pick),
                                    )
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
                                let caption_goal = if period.get() == Period::Month {
                                    goal.get()
                                } else {
                                    None // The weekly chart already labels its goal line.
                                };
                                s().intake_caption(caption_goal, over, logged, of)
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

/// The chart windows the weight card offers, ending at the period's last day.
#[derive(Debug, Clone, Copy, PartialEq)]
enum WeightRange {
    D30,
    D90,
}

impl WeightRange {
    fn days(self) -> i32 {
        match self {
            WeightRange::D30 => 30,
            WeightRange::D90 => 90,
        }
    }
}

fn weight_card(days: Memo<Vec<Day>>) -> impl IntoElement {
    let range = signal(WeightRange::D30);
    let entries = computed(move || {
        let (first, last) = days.with(|d| (d[0], d[d.len() - 1]));
        weights::window(last, last.days_since(first) + 1)
    });
    let latest = move || entries.with(|e| e.last().copied());
    when(
        move || latest().is_some(),
        move || {
            view()
                .px(px(4.0))
                .pt_2()
                .gap_3()
                .child(label(|| s().weight_week))
                .child(stat(
                    move || latest().map(|w| s().kg(w.kg)),
                    || "kg".to_owned(),
                    Scale::Tile,
                ))
                .child(segmented(
                    vec![
                        Segment::new(WeightRange::D30, || s().range_30d.into()),
                        Segment::new(WeightRange::D90, || s().range_90d.into()),
                    ],
                    move || range.get(),
                    move |r| range.set(r),
                ))
                .child(dynamic(move || {
                    let history = weights::all();
                    let span = days
                        .with(|d| d.last().copied())
                        .map(|last| (last, range.get_untracked().days()));
                    let Some((last, days_span)) = span else {
                        return view().into_element();
                    };
                    let first = last.plus_days(1 - days_span);
                    let points: Vec<crate::domain::weight::Weight> = (0..days_span)
                        .filter_map(|offset| {
                            let day = first.plus_days(offset);
                            crate::domain::weight::trend_weight(&history, day).map(|kg| {
                                crate::domain::weight::Weight {
                                    day,
                                    kg,
                                    logged_at_ms: 0,
                                }
                            })
                        })
                        .collect();
                    let goal = settings::goal_kg();
                    // A model switch is not a change in the body. Keep each
                    // algorithm's observations in its own labelled curve.
                    let mut fat = std::collections::BTreeMap::<String, Vec<(Day, f64)>>::new();
                    for metric in body_metrics::window(last, days_span) {
                        let algorithm =
                            navi_health::bodycomp::Algorithm::from_model_id(&metric.metrics.model);
                        let key = algorithm
                            .map(|a| a.id())
                            .unwrap_or(&metric.metrics.model)
                            .to_owned();
                        fat.entry(key)
                            .or_default()
                            .push((metric.day, metric.metrics.body_fat_percent));
                    }
                    let fat: Vec<_> = fat
                        .into_iter()
                        .filter(|(_, points)| points.len() >= 2)
                        .collect();
                    untracked(move || {
                        let charts = view().gap_4().child(trend(
                            first,
                            f64::from(days_span.max(1)),
                            points,
                            goal,
                        ));
                        match fat.is_empty() {
                            true => charts.into_element(),
                            false => charts
                                .child(
                                    text(|| s().body_fat)
                                        .typo(Type::Caption)
                                        .text_color(color::MUTED),
                                )
                                .children(fat.into_iter().map(move |(model, points)| {
                                    let label = navi_health::bodycomp::Algorithm::from_id(&model)
                                        .map(crate::scale::algorithm_name)
                                        .unwrap_or(s().scale_estimate);
                                    view()
                                        .mt_2()
                                        .gap_1()
                                        .child(
                                            text(label)
                                                .typo(Type::Caption)
                                                .text_color(color::MUTED),
                                        )
                                        .child(trend_percent(
                                            first,
                                            f64::from(days_span.max(1)),
                                            points,
                                        ))
                                }))
                                .into_element(),
                        }
                    })
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
