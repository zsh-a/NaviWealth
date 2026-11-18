//! Body profile and weight goals. Valid changes are kept as they are made.

use nsh_base::nav_page;
use nsh_core::{element::Screen, prelude::*};

use super::parts::{status_bar, top_bar};

use crate::{
    data::settings,
    domain::format::{field_number, parse_number},
    i18n::s,
    nav::{self, Route},
    ui::{
        Icon, Type, Typo, color,
        field::{field, note, number_input},
        icon,
        segmented::{Segment, segmented},
        space,
        surface::{card, row_button},
    },
};
use navi_health::bodycomp::Sex;

/// Open the editor directly from Settings or the scale sheet.
pub(crate) fn open_body_profile() {
    nav::push(Route::BodyProfile);
}

pub(super) fn profile_row() -> impl IntoElement {
    super::settings::entry_list_row(
        Icon::Sliders,
        || s().body_profile,
        || {
            let complete = settings::height_cm().is_some()
                && settings::age_years().is_some()
                && settings::sex().is_some();
            if complete {
                s().body_profile_complete
            } else {
                s().body_profile_incomplete
            }
            .into()
        },
        || color::MUTED,
        open_body_profile,
    )
}

/// The scale sheet launches as a task from the device group.
pub(super) fn scale_row() -> Option<impl IntoElement> {
    crate::scale::launch_action().map(|open| {
        let label = crate::scale::launch_label;
        row_button(open)
            .accessibility_label(move || Some(label().into()))
            .child(super::settings::icon_well(Icon::Scale))
            .child(
                text(label)
                    .flex_1()
                    .min_w(px(0.0))
                    .typo(Type::Headline)
                    .text_color(color::INK),
            )
            .child(icon(Icon::ChevronRight, 18.0, color::MUTED))
    })
}

/// Height, age and sex, each kept once it is in range or empty.
pub(crate) fn body_profile_page() -> Screen {
    nav_page()
        .title(|| SharedString::from(s().body_profile))
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(|| s().body_profile.into(), nav::pop, None))
                .child(
                    scroll()
                        .flex_1()
                        .keyboard_dismiss_mode(KeyboardDismissMode::OnDrag)
                        .child(
                            view()
                                .px(px(space::GUTTER))
                                .pt_2()
                                .pb(move || px(safe_area().bottom.0 + 32.0))
                                .gap_3()
                                .child(card().p(px(space::CARD)).child(profile_form())),
                        ),
                ),
        )
}

fn profile_form() -> impl IntoElement {
    let height = signal(
        untracked(settings::height_cm)
            .map(|h| h.to_string())
            .unwrap_or_default(),
    );
    let age = signal(
        untracked(settings::age_years)
            .map(|a| a.to_string())
            .unwrap_or_default(),
    );
    let height_value = move || whole(&height, |v| settings::HEIGHT_RANGE.contains(v));
    let age_value = move || whole(&age, |v| settings::AGE_RANGE.contains(v));
    effect(move || {
        if let Ok(height) = height_value()
            && untracked(settings::height_cm) != height
        {
            untracked(|| settings::save_height(height));
        }
    });
    effect(move || {
        if let Ok(age) = age_value()
            && untracked(settings::age_years) != age
        {
            untracked(|| settings::save_age(age));
        }
    });
    // Mid-typing ("1" on the way to "175") is not an error yet.
    let height_error = move || {
        height_value().is_err()
            && height.with(|t| t.trim().len() >= 3 || parse_number(t).is_none_or(|v| v > 230.0))
    };
    let age_error = move || {
        age_value().is_err()
            && age.with(|t| t.trim().len() >= 2 || parse_number(t).is_none_or(|v| v > 120.0))
    };
    view()
        .gap_4()
        .child(
            text(|| s().body_profile_note)
                .typo(Type::Subhead)
                .text_color(color::MUTED),
        )
        .child(
            field(
                || s().height,
                number_input(height, || "cm", || s().height)
                    .style_when(height_error, |s| s.border_color(color::DANGER)),
            )
            .child(note(
                move || height_error().then(|| s().error_height.into()),
                height_error,
            )),
        )
        .child(
            field(
                || s().age_years,
                number_input(age, || "", || s().age_years)
                    .style_when(age_error, |s| s.border_color(color::DANGER)),
            )
            .child(note(
                move || age_error().then(|| s().error_age.into()),
                age_error,
            )),
        )
        .child(field(
            || s().sex,
            segmented(
                vec![
                    Segment::new(Some(Sex::Male), || s().male.into()),
                    Segment::new(Some(Sex::Female), || s().female.into()),
                ],
                settings::sex,
                settings::save_sex,
            ),
        ))
}

/// The optional goal weight, kept once it is a weight in range or empty.
pub(super) fn goal_weight() -> impl IntoElement {
    let text_of = signal(
        untracked(settings::goal_kg)
            .map(field_number)
            .unwrap_or_default(),
    );
    let value = move || -> Result<Option<f64>, ()> {
        text_of.with(|text| {
            if text.trim().is_empty() {
                return Ok(None);
            }
            parse_number(text)
                .filter(|value| crate::domain::weight::valid_kg(*value))
                .map(Some)
                .ok_or(())
        })
    };
    effect(move || {
        if let Ok(goal) = value()
            && untracked(settings::goal_kg) != goal
        {
            untracked(|| settings::save_goal_kg(goal));
        }
    });
    let error = move || {
        value().is_err()
            && text_of.with(|t| {
                t.trim().len() >= 4
                    || parse_number(t).is_none_or(|v| v > crate::domain::weight::MAX_KG)
            })
    };
    super::settings::setting_details_row(
        Icon::Chart,
        || s().goal_weight,
        || {
            settings::goal_kg()
                .map(|goal| format!("{} kg", field_number(goal)))
                .unwrap_or_else(|| s().goal_unset.into())
        },
        || color::MUTED,
        signal(false),
        view()
            .gap_3()
            .child(number_input(text_of, || "kg", || s().goal_weight))
            .child(note(
                move || {
                    Some(if error() {
                        s().error_weight.into()
                    } else {
                        s().goal_weight_note.into()
                    })
                },
                error,
            )),
    )
}

/// The whole number in `text`, or `None` when empty; `Err` when it is not a
/// whole number in range.
fn whole(text: &Signal<String>, in_range: impl Fn(&u16) -> bool) -> Result<Option<u16>, ()> {
    text.with(|text| {
        if text.trim().is_empty() {
            return Ok(None);
        }
        parse_number(text)
            .filter(|value| (1.0..=u16::MAX as f64).contains(value))
            .and_then(|value| {
                let whole = value.floor();
                (whole == value).then_some(whole as u16)
            })
            .filter(|value| in_range(value))
            .map(Some)
            .ok_or(())
    })
}
