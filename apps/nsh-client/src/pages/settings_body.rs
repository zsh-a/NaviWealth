//! Body profile and weight goals. Valid changes are kept as they are made.

use nsh_base::{CalendarEntry, CalendarItemKind, DateTime, PickedDate, date_picker, nav_page};
use nsh_core::{element::Screen, prelude::*};

use super::parts::{status_bar, top_bar};

use crate::{
    data::{clock, settings},
    domain::{
        format::{field_number, parse_number},
        meal::Day,
    },
    i18n::s,
    nav::{self, Route},
    ui::{
        Icon, Type, Typo, color,
        field::{field, note, number_input, text_input},
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
                && settings::birth_date().is_some()
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

/// Height, birth date and sex, kept when valid or empty.
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
    let birth_date = signal(
        untracked(settings::birth_date)
            .map(|date| date.to_string())
            .unwrap_or_default(),
    );
    let height_value = move || whole(&height, |v| settings::HEIGHT_RANGE.contains(v));
    let date_value = move || -> Result<Option<Day>, ()> {
        birth_date.with(|text| {
            if text.trim().is_empty() {
                return Ok(None);
            }
            text.parse::<Day>()
                .ok()
                .filter(|date| settings::age_on(*date, clock::today()).is_some())
                .map(Some)
                .ok_or(())
        })
    };
    effect(move || {
        if let Ok(height) = height_value()
            && untracked(settings::height_cm) != height
        {
            untracked(|| settings::save_height(height));
        }
    });
    effect(move || {
        if let Ok(date) = date_value()
            && untracked(settings::birth_date) != date
        {
            let _ = untracked(|| settings::save_birth_date(date));
        }
    });
    // Mid-typing ("1" on the way to "175") is not an error yet.
    let height_error = move || {
        height_value().is_err()
            && height.with(|t| t.trim().len() >= 3 || parse_number(t).is_none_or(|v| v > 230.0))
    };
    let date_error = move || date_value().is_err();
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
                || s().birth_date,
                view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .child(
                        text_input(birth_date)
                            .label(|| s().birth_date)
                            .placeholder("YYYY-MM-DD")
                            .flex_1()
                            .min_w(px(0.0))
                            .style_when(date_error, |s| s.border_color(color::DANGER)),
                    )
                    .child(birth_date_picker(birth_date)),
            )
            .child(note(
                move || {
                    Some(if date_error() {
                        s().error_birth_date.into()
                    } else if settings::birth_date().is_none()
                        && let Some(age) = settings::age_years()
                    {
                        format!("{}: {age}. {}", s().legacy_age, s().birth_date_legacy_note).into()
                    } else if let Ok(Some(date)) = date_value()
                        && let Some(age) = settings::age_on(date, clock::today())
                    {
                        format!("{}: {age}. {}", s().age_years, s().birth_date_note).into()
                    } else {
                        s().birth_date_note.into()
                    })
                },
                date_error,
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

/// Native calendar popup/sheet with a year selector; typing an ISO date is
/// also available for birthdays decades before today. No date is preselected
/// or persisted when an empty picker opens.
fn birth_date_picker(date: Signal<String>) -> impl IntoElement {
    date_picker()
        .accessibility_label(|| Some(s().pick_birth_date.into()))
        .value(move || {
            DateTime::Single(
                nsh_base::Date::Single(date.with(|text| text.parse().ok()))
                    .start()
                    .and_then(|day| day.and_hms_opt(0, 0, 0)),
            )
        })
        .disabled_matcher(Some(nsh_base::Matcher::Custom(std::rc::Rc::new(|day| {
            day.to_string()
                .parse::<Day>()
                .ok()
                .is_none_or(|day| settings::age_on(day, clock::today()).is_none())
        }))))
        .year_range(move || {
            Some(nsh_base::YearRange::new(
                i32::from(clock::today().0.year()) - 121,
                i32::from(clock::today().0.year()) - 4,
            ))
        })
        .first_day_of_week(|| {
            if s().week_start() == crate::domain::review::WeekStart::Monday {
                1u32
            } else {
                0u32
            }
        })
        .previous_accessibility_label(|| Some(s().previous_month.into()))
        .next_accessibility_label(|| Some(s().next_month.into()))
        .trigger(
            view()
                .min_w(px(48.0))
                .min_h(px(48.0))
                .items_center()
                .justify_center()
                .bg(color::SUNKEN)
                .rounded(px(12.0))
                .child(icon(Icon::Calendar, 20.0, color::INK)),
        )
        .popup_style(|s| s.bg(color::SURFACE).p_3().rounded(px(12.0)))
        .header_style(|s| s.gap_2().pb_3())
        .row_style(|s| s.gap_1())
        .month_style(|s| s.gap_1())
        .item_style(|s| {
            s.min_h(px(48.0))
                .rounded(px(8.0))
                .typo(Type::Body)
                .text_color(color::INK)
                .selected(|s| s.bg(color::SURFACE_2))
        })
        .render_item(|item: &CalendarEntry| match item.kind {
            CalendarItemKind::Previous => icon(Icon::ChevronLeft, 18.0, color::INK).into_element(),
            CalendarItemKind::Next => icon(Icon::ChevronRight, 18.0, color::INK).into_element(),
            CalendarItemKind::Weekday => {
                text(s().weekday_short(Day(jiff::civil::date(2026, 11, 1)).plus_days(item.value)))
                    .typo(Type::Caption)
                    .text_color(color::MUTED)
                    .into_element()
            }
            CalendarItemKind::MonthToggle => text(format!("{}-{:02}", item.year, item.month))
                .typo(Type::Subhead)
                .into_element(),
            CalendarItemKind::Month => text(format!("{:02}", item.month))
                .typo(Type::Body)
                .into_element(),
            _ => text(item.value.to_string())
                .typo(Type::Body)
                .tabular_nums()
                .into_element(),
        })
        .on_change(move |picked: &PickedDate| {
            if let Some(day) = picked.value.start() {
                date.set(day.date().to_string());
            }
        })
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
