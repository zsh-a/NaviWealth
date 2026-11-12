//! Today: the day's energy and meals, and the one main action, logging a
//! meal from a photo. Past days are a tap away; the future is not.

mod hero;
mod meal_list;

pub use meal_list::slot_name;

use nsh_base::nav_page;
use nsh_core::{
    element::Screen,
    geometry::{DevicePixels, Percentage},
    picker::PickRequest,
    prelude::*,
};

use super::parts::{BOTTOM_BAR, bottom_bar, bottom_clearance, status_bar};
use crate::{
    data::{clock, photos, settings},
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color, icon, sheet::bottom_sheet, space,
        surface::card, toast::toast_host,
    },
};

/// The root page.
pub fn today_page() -> Screen {
    // Days back from today: 0 follows today across midnight.
    let offset = signal(0_i32);
    let day = move || clock::today().plus_days(offset.get());
    let setup_open = signal(false);
    let log = move || {
        if settings::ready_account().is_none() {
            setup_open.set(true);
            return;
        }
        let day = day();
        let mut request = PickRequest::new(false, 1);
        request.max_dimension = Some(DevicePixels(1600));
        request.quality = Some(Percentage(0.9));
        let picked = pick_images(request);
        spawn(async move {
            if let Some(file) = picked.await.into_iter().next() {
                let capture = photos::hold(file.data.to_vec());
                nav::push(Route::NewMeal {
                    day,
                    capture: Some(capture),
                });
            }
        });
    };
    let manual = move || {
        nav::push(Route::NewMeal {
            day: day(),
            capture: None,
        })
    };
    nav_page()
        .title(move || SharedString::from(s().today))
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(
                    scroll().flex_1().child(
                        view()
                            .px(px(space::GUTTER))
                            .pt_safe_area_plus(px(12.0))
                            .pb(move || px(bottom_clearance()))
                            .gap_6()
                            .child(header(day, offset))
                            .child(hero::hero(day))
                            .child(setup_card())
                            .child(meal_list::meal_list(day)),
                    ),
                )
                .child(bottom_bar(
                    view()
                        .flex_row()
                        .items_center()
                        .gap_3()
                        .child(
                            Btn::primary()
                                .size(Size::Large)
                                .capsule()
                                .icon(Icon::Photo)
                                .label(|| s().log_meal.into())
                                .on_press(log)
                                .flex_1(),
                        )
                        .child(
                            IconBtn::new(Icon::Pencil, || s().add_manually.into())
                                .variant(Variant::Secondary)
                                .side(56.0)
                                .on_press(manual),
                        ),
                ))
                .child(toast_host(|| BOTTOM_BAR + safe_area().bottom.0 + 8.0))
                .child(setup_sheet(setup_open, manual)),
        )
}

/// The day's title and date, the day controls and Settings.
fn header(
    day: impl Fn() -> crate::domain::meal::Day + Copy + 'static,
    offset: Signal<i32>,
) -> impl IntoElement {
    let is_today = move || offset.get() == 0;
    view()
        .flex_row()
        .items_start()
        .gap_2()
        .child(
            view()
                .flex_1()
                .min_w(px(0.0))
                .gap(px(2.0))
                .child(
                    text(move || s().long_date(day()))
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .number_of_lines(1),
                )
                .child(
                    text(move || s().day_title(day(), clock::today()))
                        .typo(Type::LargeTitle)
                        .text_color(color::INK)
                        .number_of_lines(1)
                        .role(AccessibilityRole::Header),
                ),
        )
        .child(
            view()
                .flex_row()
                .items_center()
                .mr(px(-10.0))
                .child(when(
                    move || !is_today(),
                    move || {
                        Btn::tonal()
                            .size(Size::Small)
                            .label(|| s().back_to_today.into())
                            .on_press(move || offset.set(0))
                            .mr_1()
                    },
                ))
                .child(
                    IconBtn::new(Icon::ChevronLeft, || s().previous_day.into())
                        .on_press(move || offset.update(|days| *days = (*days - 1).max(-3650))),
                )
                .child(
                    IconBtn::new(Icon::ChevronRight, || s().next_day.into())
                        .on_press(move || offset.update(|days| *days = (*days + 1).min(0)))
                        .disabled(is_today),
                )
                .child(
                    IconBtn::new(Icon::Sliders, || s().settings.into())
                        .on_press(|| nav::push(Route::Settings)),
                ),
        )
}

/// Shown until a model account can analyze photos.
fn setup_card() -> impl IntoElement {
    when(
        || settings::ready_account().is_none(),
        || {
            card()
                .p(px(space::CARD))
                .gap_3()
                .child(
                    view()
                        .flex_row()
                        .items_start()
                        .gap_3()
                        .child(
                            view()
                                .size(px(40.0))
                                .rounded_full()
                                .items_center()
                                .justify_center()
                                .bg(color::ACCENT_SOFT)
                                .child(icon(Icon::Sparkle, 20.0, color::ACCENT)),
                        )
                        .child(
                            view()
                                .flex_1()
                                .gap_1()
                                .child(
                                    text(|| s().setup_title)
                                        .typo(Type::Headline)
                                        .text_color(color::INK),
                                )
                                .child(
                                    text(|| s().setup_body)
                                        .typo(Type::Callout)
                                        .text_color(color::MUTED),
                                ),
                        ),
                )
                .child(
                    Btn::tonal()
                        .size(Size::Small)
                        .label(|| s().set_up.into())
                        .on_press(|| nav::push(Route::Settings))
                        .self_end(),
                )
        },
    )
}

/// Why photos need an account, from the main action, with both ways on.
fn setup_sheet(open: Signal<bool>, manual: impl Fn() + Copy + 'static) -> impl IntoElement {
    bottom_sheet(
        move || open.get(),
        move || open.set(false),
        view()
            .gap_4()
            .child(
                view()
                    .size(px(48.0))
                    .rounded_full()
                    .items_center()
                    .justify_center()
                    .bg(color::ACCENT_SOFT)
                    .child(icon(Icon::Sparkle, 24.0, color::ACCENT)),
            )
            .child(
                view()
                    .gap_2()
                    .child(
                        text(|| s().setup_title)
                            .typo(Type::Title)
                            .text_color(color::INK),
                    )
                    .child(
                        text(|| s().setup_body)
                            .typo(Type::Body)
                            .text_color(color::MUTED),
                    ),
            )
            .child(
                view()
                    .gap_2()
                    .child(
                        Btn::primary()
                            .label(|| s().set_up.into())
                            .on_press(move || {
                                open.set(false);
                                nav::push(Route::Settings);
                            }),
                    )
                    .child(Btn::secondary().label(|| s().add_manually.into()).on_press(
                        move || {
                            open.set(false);
                            manual();
                        },
                    )),
            ),
    )
}
