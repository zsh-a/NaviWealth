//! The Review tab: a week or a calendar month in review. The daily average
//! intake and its change from the period before, a bar per day against the
//! goal for a week (days past it in amber, today in ink, nothing for a day
//! without meals) or a calendar for a month, recorded spending, the
//! net-worth change and its parts, the weight's change and line, and
//! Garmin's averages. Earlier periods are a step back; a short personal
//! note is kept on its day.

use std::rc::Rc;

use navi_finance::{attribution::Outcome, currency::Currency};
use nsh_core::prelude::*;

use super::{
    home::Sheets,
    review_calendar::{Pick, calendar, month_days},
    review_charts::{chart, health_trend},
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
        Icon, IconBtn, Type, Typo, chip, color,
        feedback::appear,
        figures::{Scale, counted, macro_tiles, stat},
        segmented::{Segment, segmented},
        space,
        surface::section,
    },
};

#[derive(Clone, Default, PartialEq)]
struct RequestedWeek(Option<Day>);

pub(super) fn locate(day: Day) {
    global::<RequestedWeek>().set(RequestedWeek(Some(day)));
}

/// The Review tab's content.
pub fn review_tab() -> impl IntoElement {
    let period = signal(Period::Week);
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if crate::preview::review_month() {
        period.set(Period::Month);
    }
    // Periods back from the current one.
    let back = signal(0_i32);
    effect(move || {
        if let Some(day) = global::<RequestedWeek>().get().0 {
            untracked(|| {
                let today = clock::today();
                let start =
                    review::period_days_starting(Period::Week, today, 0, s().week_start())[0];
                back.set((start.days_since(day) + 6).div_euclid(7).max(0));
                period.set(Period::Week);
                global::<RequestedWeek>().set(RequestedWeek(None));
            });
        }
    });
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
            .pb(move || px(crate::pages::home::dock_top_inset() + 12.0))
            // Sections breathe at 24: the page reads as chapters, not a stack.
            .gap(px(24.0))
            .child(
                view()
                    .flex_row()
                    .flex_wrap()
                    .items_center()
                    .justify_between()
                    .gap_2()
                    .child(
                        text(|| s().review)
                            .typo(Type::LargeTitle)
                            .text_color(color::INK)
                            .role(AccessibilityRole::Header),
                    )
                    .child(
                        view()
                            .w(|| px(112.0 * font_scale().max(1.0)))
                            .max_w(relative(1.0))
                            .ml(auto())
                            .child(segmented(
                                vec![
                                    Segment::new(Period::Week, || s().week_label.into()),
                                    Segment::new(Period::Month, || s().month_label.into()),
                                ],
                                move || period.get(),
                                move |p| {
                                    period.set(p);
                                    back.set(0);
                                },
                            )),
                    ),
            )
            .child(header(period, back, days))
            .child(summary(period, days, before))
            .child(intake_card(period, days))
            .child(super::finance_review::spending_section(
                days, before, period,
            ))
            .child(super::net_worth_review::net_worth_section(days))
            .child(weight_card(days))
            .child(recovery_card(days))
            .child(super::review_note::note_editor(days)),
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
                // The period switcher is navigation, not metadata: it reads
                // like one, with the touch targets its chevrons already have.
                .typo(Type::Headline)
                .tabular_nums()
                .text_color(color::INK),
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

/// One measured change across the period.
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
        let net_worth = super::net_worth_review::period_outcome(&current_days);
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
        // Health leads; a ledger-only period still gets its one change.
        s().review_summary(change, weight)
            .or_else(|| match net_worth {
                Some(Outcome::Complete(a)) if a.change() != 0 => Some(s().net_worth_summary(
                    &crate::ui::currency::format(a.change().abs(), Currency::CNY),
                    a.change() > 0,
                )),
                _ => None,
            })
    });
    when(
        move || line.with(Option::is_some),
        move || {
            // The period's one observed change leads the page as a
            // statement, a step above section headers.
            text(move || line.get().unwrap_or_default())
                .typo(Type::Title)
                .text_color(color::INK)
                .px(px(4.0))
        },
    )
}

fn intake_card(period: Signal<Period>, days: Memo<Vec<Day>>) -> impl IntoElement {
    let intake = computed(move || intake_of(days.get()));
    let goal = computed(settings::goal);
    let average = move || intake.with(|i| i.average.map(|a| a.kcal));
    section()
        .gap_4()
        .child(
            view()
                .gap(px(6.0))
                // The card's title speaks in the page's voice, not a caption's.
                .child(
                    text(|| s().daily_intake)
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(when(
                    move || average().is_some(),
                    move || {
                        view()
                            .gap_1()
                            .child(stat(
                                move || average().map(format::kcal),
                                || s().kcal_per_logged_day.to_owned(),
                                Scale::Hero,
                            ))
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
                                    // The calendar fades in on arrival, the
                                    // same entrance the bars grow with.
                                    appear(
                                        0,
                                        calendar(
                                            month_days(&days, &kcal, &weighed),
                                            goal,
                                            start,
                                            Some(pick),
                                        ),
                                    )
                                    .into_element()
                                })
                            } else {
                                untracked(move || chart(days, kcal, goal).into_element())
                            }
                        }))
                        // The macros speak the meal preview's language; the
                        // small nutrients fold into one quiet line.
                        .child(macro_tiles(
                            [|| s().protein, || s().carbs, || s().fat],
                            move || intake.with(|i| i.average.unwrap_or_default()),
                            move || intake.with(|i| i.average.is_some()),
                        ))
                        .child(when(
                            move || {
                                intake.with(|i| i.average.as_ref().and_then(|a| a.extra).is_some())
                            },
                            move || {
                                text(move || {
                                    let extra = intake
                                        .with(|i| i.average.as_ref().and_then(|a| a.extra))
                                        .unwrap_or_default();
                                    // The average cannot know each day's food
                                    // completeness; it claims neither way.
                                    s().extras_line(&extra, true)
                                })
                                .typo(Type::Caption)
                                .tabular_nums()
                                .text_color(color::MUTED)
                            },
                        ))
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
    // The card's lead figure rolls to each new reading instead of jumping;
    // it lives here so an edit animates across the card's lifetime.
    let shown = counted(move || latest().map(|w| w.kg).unwrap_or(0.0));
    when(
        move || latest().is_some(),
        move || {
            section()
                .gap_3()
                .child(
                    text(|| s().weight_week)
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(stat(
                    move || latest().is_some().then(|| s().kg(shown.get())),
                    || "kg".to_owned(),
                    Scale::Section,
                ))
                .child(
                    view()
                        .flex_row()
                        .gap_2()
                        .child(chip(
                            || s().range_30d.into(),
                            move || range.get() == WeightRange::D30,
                            move || range.set(WeightRange::D30),
                        ))
                        .child(chip(
                            || s().range_90d.into(),
                            move || range.get() == WeightRange::D90,
                            move || range.set(WeightRange::D90),
                        )),
                )
                .child(dynamic(move || {
                    let last = days.with(|d| d[d.len() - 1]).min(clock::today());
                    let days_span = range.get().days();
                    // The first plotted mean also needs the preceding six days.
                    let history = weights::window(last, days_span + 6);
                    let first = last.plus_days(1 - days_span);
                    let points = (0..days_span)
                        .map(|offset| {
                            let day = first.plus_days(offset);
                            (day, crate::domain::weight::trend_weight(&history, day))
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
                        let charts = view().gap_4().child(health_trend(
                            s().trend_average.into(),
                            first,
                            last,
                            points,
                            goal,
                            color::ACCENT,
                            |v| format!("{} kg", s().kg(v)),
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
                                    // The fat curves stay a step lighter than the
                                    // weight line: one ink family, depth instead of hue.
                                    health_trend(
                                        label.into(),
                                        first,
                                        last,
                                        points.into_iter().map(|(d, v)| (d, Some(v))).collect(),
                                        None,
                                        color::ACCENT.opacity(0.55),
                                        |v| format!("{v:.1}%"),
                                    )
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
            section()
                .gap_2()
                .child(
                    text(|| s().recovery)
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
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
