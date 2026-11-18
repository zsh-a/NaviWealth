//! Settings' body section: the height, age and sex the BMI and the scale
//! estimates need, and the optional goal weight. Changes are kept at once.

use nsh_core::prelude::*;

use crate::{
    data::settings,
    domain::format::{field_number, parse_number},
    i18n::s,
    ui::{
        Icon, color,
        field::{field, note, number_input},
        segmented::{Segment, segmented},
    },
};
use navi_health::bodycomp::Sex;

#[derive(Clone, Default, PartialEq)]
struct ProfileOpen(bool);

/// Opens the body profile whether Settings is already visible or not.
pub(crate) fn open_body_profile() {
    global::<ProfileOpen>().set(ProfileOpen(true));
    crate::nav::push(crate::nav::Route::Settings);
}

/// The body profile and the goal weight, kept as they change.
pub fn body_section() -> impl IntoElement {
    view().gap_3().child(profile()).child(goal_weight())
}

/// Height, age and sex, each kept once it is in range or empty.
fn profile() -> impl IntoElement {
    let requested = global::<ProfileOpen>();
    let open = signal(false);
    effect(move || {
        if requested.get().0 {
            open.set(true);
            requested.set(ProfileOpen::default());
        }
    });
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
    let summary = move || match (
        settings::height_cm(),
        settings::age_years(),
        settings::sex(),
    ) {
        (None, None, None) => s().goal_unset.into(),
        (height, age, sex) => {
            let mut parts: Vec<String> = Vec::new();
            if let Some(height) = height {
                parts.push(format!("{} cm", height));
            }
            if let Some(age) = age {
                parts.push(age.to_string());
            }
            if let Some(sex) = sex {
                parts.push(match sex {
                    Sex::Male => s().male.into(),
                    Sex::Female => s().female.into(),
                });
            }
            parts.join(" · ")
        }
    };
    super::settings::controlled_setting_details(
        Icon::Sliders,
        || s().body_profile,
        summary,
        || color::MUTED,
        open,
        view()
            .gap_3()
            .child(
                field(
                    || s().height,
                    number_input(height, || "cm", || s().height)
                        .style_when(height_error, |s| s.border_color(color::DANGER)),
                )
                .child(note(
                    move || {
                        Some(if height_error() {
                            s().error_height.into()
                        } else {
                            s().body_profile_note.into()
                        })
                    },
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
            )),
    )
}

/// The optional goal weight, kept once it is a weight in range or empty.
fn goal_weight() -> impl IntoElement {
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
    super::settings::setting_details(
        Icon::Scale,
        || s().goal_weight,
        || {
            settings::goal_kg()
                .map(|goal| format!("{} kg", field_number(goal)))
                .unwrap_or_else(|| s().goal_unset.into())
        },
        || color::MUTED,
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
