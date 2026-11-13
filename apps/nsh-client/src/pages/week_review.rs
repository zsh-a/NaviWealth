//! The week in review: seven days of intake (a bar per day, nothing for a
//! day without meals), the week's weight change and Garmin's averages.
//! Earlier weeks are a step back; nothing here can be edited.

use nsh_base::{
    nav_page,
    plot::{BandScale, Scale, bar, plot},
};
use nsh_core::{
    element::{RowAccessor, Rows, Screen},
    geometry::Percentage,
    prelude::*,
};

use super::parts::{bottom_clearance, status_bar, top_bar};
use crate::{
    data::{clock, garmin, meals, weights},
    domain::{
        format,
        meal::Day,
        review::{self, DAYS},
    },
    i18n::s,
    nav,
    ui::{Icon, IconBtn, Type, Typo, Variant, color, space, surface::card},
};

pub fn week_review_page() -> Screen {
    // Weeks back from the seven days ending today.
    let weeks_back = signal(0_i32);
    let last = move || clock::today().plus_days(-DAYS * weeks_back.get());
    let days = computed(move || review::days_ending(last()));
    nav_page()
        .title(|| SharedString::from(s().week_review))
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(|| s().week_review.into(), nav::pop, None))
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pt_2()
                            .pb(move || px(bottom_clearance()))
                            .gap_4()
                            .child(week_picker(weeks_back, days))
                            .child(intake_card(days))
                            .child(weight_card(days))
                            .child(recovery_card(days)),
                    ),
                ),
        )
}

fn week_picker(weeks_back: Signal<i32>, days: Memo<Vec<Day>>) -> impl IntoElement {
    view()
        .flex_row()
        .items_center()
        .justify_between()
        .child(
            IconBtn::new(Icon::ChevronLeft, || s().previous_week.into())
                .variant(Variant::Secondary)
                .on_press(move || weeks_back.update(|w| *w += 1)),
        )
        .child(
            text(move || days.with(|d| s().week_span(d[0], d[d.len() - 1])))
                .typo(Type::Headline)
                .text_color(color::INK),
        )
        .child(
            // No later week than the current one: a spacer instead.
            when(
                move || weeks_back.get() > 0,
                move || {
                    IconBtn::new(Icon::ChevronRight, || s().next_week.into())
                        .variant(Variant::Secondary)
                        .on_press(move || weeks_back.update(|w| *w = (*w - 1).max(0)))
                },
            )
            .otherwise(|| view().size(px(44.0))),
        )
}

fn heading(title: fn() -> &'static str) -> impl IntoElement {
    text(title)
        .typo(Type::Headline)
        .text_color(color::INK)
        .role(AccessibilityRole::Header)
}

fn figure(
    value: impl Fn() -> String + 'static,
    caption: impl Fn() -> String + 'static,
) -> impl IntoElement {
    view()
        .gap(px(2.0))
        .child(
            text(value)
                .typo(Type::Display)
                .tabular_nums()
                .text_color(color::INK),
        )
        .child(text(caption).typo(Type::Caption).text_color(color::MUTED))
}

fn intake_card(days: Memo<Vec<Day>>) -> impl IntoElement {
    let intake = computed(move || {
        let summaries: Vec<_> = days.get().into_iter().map(meals::summary).collect();
        review::intake(&summaries)
    });
    card()
        .p(px(space::CARD))
        .gap_4()
        .child(heading(|| s().intake))
        .child(
            when(
                move || intake.with(|i| i.average.is_some()),
                move || {
                    view()
                        .gap_4()
                        .child(figure(
                            move || {
                                intake.with(|i| format::kcal(i.average.map_or(0.0, |a| a.kcal)))
                            },
                            move || {
                                format!(
                                    "{} · {}",
                                    s().per_logged_day,
                                    s().logged_days(intake.with(|i| i.logged_days))
                                )
                            },
                        ))
                        .child(dynamic(move || {
                            let kcal = intake.with(|i| i.kcal.clone());
                            untracked(move || bars(kcal))
                        }))
                        .child(
                            // Under each bar its weekday: bands centered on
                            // sevenths (outer padding half the inner).
                            view()
                                .flex_row()
                                .mt(px(-8.0))
                                .children((0..DAYS as usize).map(move |i| {
                                    text(move || days.with(|d| s().weekday_short(d[i])))
                                        .typo(Type::Caption)
                                        .text_color(color::MUTED)
                                        .text_center()
                                        .flex_1()
                                })),
                        )
                        .child(
                            text(move || {
                                let a = intake.with(|i| i.average.unwrap_or_default());
                                format!(
                                    "{} {} g · {} {} g · {} {} g",
                                    s().protein,
                                    format::grams(a.protein),
                                    s().carbs,
                                    format::grams(a.carbs),
                                    s().fat,
                                    format::grams(a.fat)
                                )
                            })
                            .typo(Type::Subhead)
                            .tabular_nums()
                            .text_color(color::MUTED),
                        )
                },
            )
            .otherwise(|| {
                text(|| s().no_week_data)
                    .typo(Type::Subhead)
                    .text_color(color::MUTED)
            }),
        )
}

/// A bar per day; a day without meals has none (not a zero bar).
fn bars(kcal: Vec<Option<f64>>) -> impl IntoElement {
    let values: Vec<f64> = kcal.iter().map(|k| k.unwrap_or(f64::NAN)).collect();
    let rows = Rows::from_columns(values.len(), [("kcal".into(), values)]);
    let mut band = BandScale::default();
    band.padding_inner = Percentage(0.4);
    band.padding_outer = Percentage(0.2);
    plot()
        .h(px(120.0))
        .data(rows)
        .y(Some(RowAccessor::from("kcal")))
        .x_scale(Scale::Band(band))
        .interactive(false)
        .child(bar().text_color(color::INK).corner_radii(px(4.0)))
}

fn weight_card(days: Memo<Vec<Day>>) -> impl IntoElement {
    let change = computed(move || {
        let last = days.with(|d| d[d.len() - 1]);
        review::weight_change(&weights::window(last, DAYS))
    });
    when(
        move || change.with(Option::is_some),
        move || {
            card()
                .p(px(space::CARD))
                .gap_3()
                .child(heading(|| s().weight_week))
                .child(figure(
                    move || {
                        change.with(|c| {
                            c.map(|(_, last, _)| format!("{} kg", s().kg(last.kg)))
                                .unwrap_or_default()
                        })
                    },
                    move || {
                        change.with(|c| {
                            c.map(|(_, _, delta)| s().weight_change(delta))
                                .unwrap_or_default()
                        })
                    },
                ))
        },
    )
}

fn recovery_card(days: Memo<Vec<Day>>) -> impl IntoElement {
    let week = computed(move || {
        let measured: Vec<_> = days.get().into_iter().filter_map(garmin::on).collect();
        review::recovery(&measured)
    });
    when(
        move || week.with(|w| w.days > 0),
        move || {
            let line = |label: fn() -> &'static str, value: Box<dyn Fn() -> Option<String>>| {
                view()
                    .flex_row()
                    .justify_between()
                    .py(px(6.0))
                    .child(text(label).typo(Type::Body).text_color(color::BODY))
                    .child(
                        text(move || value().unwrap_or_else(|| "—".into()))
                            .typo(Type::Body)
                            .tabular_nums()
                            .text_color(color::INK),
                    )
            };
            card()
                .p(px(space::CARD))
                .gap_1()
                .child(heading(|| s().recovery))
                .child(line(
                    || s().avg_sleep,
                    Box::new(move || {
                        week.with(|w| w.sleep_seconds.map(|v| s().sleep_time(v as u32)))
                    }),
                ))
                .child(line(
                    || s().avg_sleep_score,
                    Box::new(move || week.with(|w| w.sleep_score.map(|v| format!("{v:.0}")))),
                ))
                .child(line(
                    || s().resting_hr,
                    Box::new(move || week.with(|w| w.resting_hr.map(|v| format!("{v:.0} bpm")))),
                ))
                .child(line(
                    || s().hrv,
                    Box::new(move || week.with(|w| w.hrv_ms.map(|v| format!("{v:.0} ms")))),
                ))
                .child(line(
                    || s().steps,
                    Box::new(move || week.with(|w| w.steps.map(format::kcal))),
                ))
        },
    )
}
