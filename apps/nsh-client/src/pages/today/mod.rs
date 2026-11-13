//! Today: what the day adds up to (intake), three vitals, and today's
//! records. Only today: past days are in Records.

mod garmin;
mod hero;
mod meal_list;
mod vitals;
mod week;
mod weight;

pub use garmin::garmin_sheet;
pub use meal_list::{meal_title, slot_name};
pub use week::day_strip;
pub use weight::weight_editor;

use nsh_core::prelude::*;

use super::{
    drafts::drafts_section,
    home::{Sheets, dock_clearance},
};
use crate::{
    data::{clock, settings},
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, Variant, color, icon, sheet::bottom_sheet, space,
        surface::card,
    },
};

/// The Today tab's content.
pub fn today_tab() -> impl IntoElement {
    let day = clock::today;
    scroll().flex_1().child(
        view()
            .px(px(space::GUTTER))
            .pt_safe_area_plus(px(10.0))
            .pb(move || px(dock_clearance()))
            .gap_5()
            .child(header())
            .child(drafts_section(false))
            .child(setup_card())
            .child(hero::hero(day))
            .child(vitals::vitals(day))
            .child(meal_list::meal_list(day)),
    )
}

/// Today's date and title, and Settings.
fn header() -> impl IntoElement {
    let day = clock::today;
    view()
        .flex_row()
        .items_center()
        .gap_3()
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
                    text(|| s().today)
                        .typo(Type::LargeTitle)
                        .text_color(color::INK)
                        .number_of_lines(1)
                        .role(AccessibilityRole::Header),
                ),
        )
        .child(
            IconBtn::new(Icon::Sliders, || s().settings.into())
                .variant(Variant::Secondary)
                .on_press(|| nav::push(Route::Settings)),
        )
}

/// Shown until a model account can analyze photos.
fn setup_card() -> impl IntoElement {
    when(
        || settings::ready_account().is_none(),
        || {
            card()
                .p(px(space::CARD))
                .gap_4()
                .child(
                    view()
                        .flex_row()
                        .items_start()
                        .gap(px(14.0))
                        .child(ai_mark(44.0))
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

/// The AI's mark: a sparkle on a soft disc of its light.
fn ai_mark(side: f32) -> impl IntoElement {
    view()
        .size(px(side))
        .rounded_full()
        .items_center()
        .justify_center()
        .bg_linear_to_br()
        .gradient_from(color::AI_FROM.opacity(0.16))
        .gradient_to(color::AI_TO.opacity(0.16))
        .child(icon(Icon::Sparkle, side * 0.48, color::AI_FROM))
}

/// Why photos need an account, from the main action, with both ways on.
pub fn setup_sheet(sheets: Sheets) -> impl IntoElement {
    let open = sheets.setup;
    let manual = move || sheets.manual();
    bottom_sheet(
        move || open.get(),
        move || open.set(false),
        view()
            .gap_5()
            .child(ai_mark(56.0))
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
                    .gap_3()
                    .child(
                        Btn::primary()
                            .size(Size::Large)
                            .label(|| s().set_up.into())
                            .on_press(move || {
                                open.set(false);
                                nav::push(Route::Settings);
                            }),
                    )
                    .child(
                        Btn::secondary()
                            .size(Size::Large)
                            .label(|| s().add_manually.into())
                            .on_press(move || {
                                open.set(false);
                                manual();
                            }),
                    ),
            ),
    )
}
