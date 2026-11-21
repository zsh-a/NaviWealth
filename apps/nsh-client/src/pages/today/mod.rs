//! Today: what the day adds up to (intake), three vitals, and today's
//! records. Only today: past days are in Records.

mod body;
mod garmin;
mod hero;
mod meal_list;
mod vitals;
mod week;
mod weight;

pub use body::body_overview;
pub use garmin::garmin_sheet;
pub use meal_list::{meal_title, slot_name};
pub use week::day_strip;
pub use weight::weight_editor;

use nsh_core::prelude::*;

use super::{drafts::drafts_section, home::Sheets};
use crate::{
    data::{clock, settings},
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, color, icon, sheet::bottom_sheet, space,
        surface::row_button,
    },
};

/// The Today tab's content.
pub fn today_tab() -> impl IntoElement {
    let day = clock::today;
    scroll().flex_1().child(
        view()
            .px(px(space::GUTTER))
            .pt_safe_area_plus(px(10.0))
            .pb_4()
            // Groups breathe more than their parts: 24 pt between the summary
            // groups, 32 pt before the day's records.
            .gap_6()
            .child(header())
            .child(hero::hero(day))
            .child(drafts_section(false))
            .child(vitals::vitals(day))
            .child(view().mt_2().child(meal_list::meal_list(day)))
            .child(setup_row()),
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
                .side(48.0)
                .on_press(|| nav::push(Route::Settings)),
        )
}

/// Shown until a model account can analyze photos.
fn setup_row() -> impl IntoElement {
    when(
        || settings::ready_account().is_none(),
        || {
            row_button(|| nav::push(Route::Settings))
                .min_h(px(48.0))
                .px_0()
                .accessibility_label(|| Some(s().setup_title.into()))
                .child(icon(Icon::Server, 20.0, color::MUTED))
                .child(
                    text(|| s().setup_title)
                        .flex_1()
                        .typo(Type::Subhead)
                        .text_color(color::BODY),
                )
                .child(icon(Icon::ChevronRight, 16.0, color::MUTED))
        },
    )
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
