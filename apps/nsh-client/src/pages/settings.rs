//! Settings, kept as they change (there is no Save): the vision model (its
//! own page), the optional daily goal, whether to ask before each photo,
//! the Garmin connection and backups.

use nsh_base::nav_page;
use nsh_core::{element::Screen, prelude::*};

use super::parts::{status_bar, top_bar};
use crate::{
    data::settings,
    domain::{
        account::Provider,
        format::{field_number, parse_number},
    },
    i18n::s,
    nav::{self, Route},
    ui::{
        Icon, Type, Typo, color,
        field::{note, number_input},
        icon, space,
        surface::{card, group_label, row_button},
        toggle::switch_row,
    },
};

/// The settings page.
pub fn settings_page() -> Screen {
    nav_page()
        .title(|| SharedString::from(s().settings))
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(|| s().settings.into(), nav::pop, None))
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
                                .child(group_label(|| s().recognition))
                                .child(recognition())
                                .child(view().h_3())
                                .child(group_label(|| s().daily_goal))
                                .child(goal())
                                .child(view().h_3())
                                .child(group_label(|| s().garmin))
                                .child(super::settings_garmin::garmin_section())
                                .child(view().h_3())
                                .child(group_label(|| s().backup))
                                .child(super::settings_backup::backup_section()),
                        ),
                ),
        )
}

/// The model account's row (its own page) and asking before each photo.
fn recognition() -> impl IntoElement {
    let account = move || settings::current().account;
    let ask = signal(untracked(|| {
        account().is_none_or(|a| !settings::is_trusted(&a))
    }));
    // Follows the kept account: a changed account is asked about again.
    effect(move || {
        let asks = account().is_none_or(|a| !settings::is_trusted(&a));
        if untracked(|| ask.get()) != asks {
            untracked(|| ask.set(asks));
        }
    });
    effect(move || {
        let asks = ask.get();
        if let Some(account) = untracked(account)
            && untracked(|| settings::is_trusted(&account)) == asks
        {
            untracked(|| settings::set_trusted(&account, !asks));
        }
    });
    let summary = move || match settings::ready_account() {
        Some(a) => {
            let provider = match a.provider {
                Provider::Anthropic => s().anthropic,
                Provider::OpenAiCompatible => s().openai_compatible,
            };
            format!("{provider} · {}", a.model)
        }
        None => s().not_set_up.to_owned(),
    };
    card()
        .overflow_hidden()
        .child(
            row_button(|| nav::push(Route::ModelSettings))
                .accessibility_label(move || {
                    Some(format!("{}, {}", s().vision_model, summary()).into())
                })
                .child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .gap(px(2.0))
                        .child(
                            text(|| s().vision_model)
                                .typo(Type::Headline)
                                .text_color(color::INK),
                        )
                        .child(
                            text(summary)
                                .typo(Type::Subhead)
                                .text_color(move || {
                                    if settings::ready_account().is_some() {
                                        color::MUTED
                                    } else {
                                        color::CAUTION
                                    }
                                })
                                .number_of_lines(1),
                        ),
                )
                .child(icon(Icon::ChevronRight, 18.0, color::MUTED)),
        )
        .child(
            view()
                .px(px(space::CARD))
                .pt_1()
                .pb_3()
                .gap_1()
                .border_t(px(0.75))
                .border_color(color::LINE)
                .child(switch_row(ask, || s().ask_each_photo.into()))
                .child(note(|| Some(s().ask_each_photo_note.into()), || false)),
        )
}

/// The optional daily goal, kept once it is a goal in range or empty.
fn goal() -> impl IntoElement {
    let text_of = signal(
        untracked(settings::goal)
            .map(field_number)
            .unwrap_or_default(),
    );
    let value = move || -> Result<Option<f64>, ()> {
        text_of.with(|text| {
            if text.trim().is_empty() {
                return Ok(None);
            }
            parse_number(text)
                .filter(|value| settings::GOAL_RANGE.contains(value))
                .map(Some)
                .ok_or(())
        })
    };
    effect(move || {
        if let Ok(goal) = value()
            && untracked(settings::goal) != goal
        {
            untracked(|| settings::save_goal(goal));
        }
    });
    // Mid-typing ("2" on the way to "2000") is not an error yet.
    let error = move || {
        value().is_err()
            && text_of.with(|t| {
                t.trim().len() >= 4
                    || parse_number(t).is_none_or(|v| v > *settings::GOAL_RANGE.end())
            })
    };
    card()
        .p(px(space::CARD))
        .gap_2()
        .child(number_input(text_of, || s().kcal, || s().daily_goal))
        .child(note(
            move || {
                Some(
                    if error() {
                        s().error_goal
                    } else {
                        s().goal_note
                    }
                    .into(),
                )
            },
            error,
        ))
}
