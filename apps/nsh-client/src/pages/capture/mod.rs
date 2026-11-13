//! The capture sheet, the one way to record anything: a meal from a photo
//! (the system picker also takes photos) and weight as two large actions,
//! favorites as a row of photos, and a meal by hand.

mod favorites;

use nsh_base::{ButtonElement, button};
use nsh_core::prelude::*;

use super::home::Sheets;
use crate::{
    data::{clock, weights},
    i18n::s,
    ui::{
        Icon, Type, Typo, color, icon, motion, radius,
        surface::{hairline, row_button},
    },
};

pub fn capture_sheet(sheets: Sheets) -> impl IntoElement {
    let close = move || sheets.capture.set(false);
    view()
        .gap_5()
        .child(
            view()
                .flex_row()
                .gap_3()
                .child(
                    big_action(
                        true,
                        Icon::Photo,
                        || s().log_meal.into(),
                        || s().photo_or_library.into(),
                    )
                    .flex_grow(1.35)
                    .on_press(move || {
                        close();
                        sheets.log_photo();
                    }),
                )
                .child(
                    big_action(
                        false,
                        Icon::Scale,
                        || s().log_weight.into(),
                        || match weights::latest_until(clock::today()) {
                            Some(entry) => s().last_weight(entry.kg).into(),
                            None => s().tap_to_log.into(),
                        },
                    )
                    .flex_grow(1.0)
                    .on_press(move || {
                        close();
                        sheets.weight.set(Some(clock::today()));
                    }),
                ),
        )
        .child(favorites::favorites_row(close))
        .child(hairline(0.0))
        .child(
            row_button(move || {
                close();
                sheets.manual();
            })
            .px(px(4.0))
            .min_h(px(56.0))
            .mt(px(-8.0))
            .rounded(px(radius::FIELD))
            .accessibility_label(|| Some(s().add_manually.into()))
            .child(icon(Icon::Pencil, 22.0, color::INK))
            .child(
                text(|| s().add_manually)
                    .typo(Type::Headline)
                    .text_color(color::INK)
                    .flex_1(),
            )
            .child(icon(Icon::ChevronRight, 18.0, color::FAINT)),
        )
}

/// A large action: ink for the main one, a soft well for the other.
fn big_action(
    main: bool,
    glyph: Icon,
    title: impl Fn() -> SharedString + 'static,
    detail: impl Fn() -> SharedString + 'static,
) -> ButtonElement {
    let (fill, ink, disc) = if main {
        (
            color::ACTION,
            color::ON_ACTION,
            color::ON_ACTION.opacity(0.12),
        )
    } else {
        (color::SURFACE_2, color::INK, color::SURFACE)
    };
    let scale = animated_value(1.0);
    button()
        .on_press_down(move || {
            if !reduce_motion() {
                scale.spring(motion::PRESS_SCALE_CARD, motion::PRESS);
            }
        })
        .on_press_up(move || {
            scale.spring(1.0, motion::PRESS);
        })
        .bind_scale(&scale)
        .w(px(0.0))
        .min_h(px(132.0))
        .p(px(18.0))
        .justify_between()
        .rounded(px(radius::CARD))
        .bg(fill)
        .focus_visible(|s| s.outline(px(2.0)).outline_color(color::INK))
        .child(
            view()
                .size(px(44.0))
                .rounded_full()
                .items_center()
                .justify_center()
                .bg(disc)
                .child(icon(glyph, 22.0, ink)),
        )
        .child(
            view()
                .gap(px(2.0))
                .child(text(title).typo(Type::Headline).text_color(ink))
                .child(
                    text(detail)
                        .typo(Type::Caption)
                        .tabular_nums()
                        .text_color(ink.opacity(0.66))
                        .number_of_lines(1),
                ),
        )
}
