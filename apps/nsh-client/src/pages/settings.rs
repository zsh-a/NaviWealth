//! Settings index: related rows share a surface and show their current state.

use nsh_base::{collapsible, nav_page};
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
        icon,
        segmented::{Segment, segmented},
        space,
        surface::{card, group_label, hairline, row_button},
        theme::motion,
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
                                .gap_6()
                                .child(settings_group(|| s().appearance, appearance_group()))
                                .child(settings_group(
                                    || s().body_and_weight,
                                    card()
                                        .overflow_hidden()
                                        .child(super::settings_body::profile_row())
                                        .child(hairline(space::CARD))
                                        .child(goal())
                                        .child(hairline(space::CARD))
                                        .child(super::settings_body::goal_weight()),
                                ))
                                .child(settings_group(
                                    || s().settings_connections,
                                    card()
                                        .overflow_hidden()
                                        .child(super::settings_body::scale_row().map(|row| {
                                            view().child(row).child(hairline(space::CARD))
                                        }))
                                        .child(super::settings_garmin::garmin_section()),
                                ))
                                .child(settings_group(|| s().recognition, recognition()))
                                .child(settings_group(
                                    || s().settings_data,
                                    super::settings_backup::backup_row(),
                                ))
                                .child(settings_group(
                                    || s().settings_about,
                                    super::settings_updates::updates_section(),
                                ))
                                .child(keyboard_diagnostics()),
                        ),
                ),
        )
}

fn settings_group(
    title: impl Fn() -> &'static str + 'static,
    content: impl IntoElement,
) -> impl IntoElement {
    view().gap_2().child(group_label(title)).child(content)
}

/// Light, dark, or the device's choice. Each press applies at once: the
/// root's effect hands the choice to the engine, and it is kept.
fn appearance_group() -> impl IntoElement {
    segmented(
        vec![
            Segment::new(settings::Appearance::System, || {
                s().appearance_system.into()
            }),
            Segment::new(settings::Appearance::Light, || s().appearance_light.into()),
            Segment::new(settings::Appearance::Dark, || s().appearance_dark.into()),
        ],
        settings::appearance,
        settings::save_appearance,
    )
}

/// An icon in its well: the fixed anchor every settings row leads with.
pub(super) fn icon_well(glyph: Icon) -> impl IntoElement {
    view()
        .size(px(36.0))
        .items_center()
        .justify_center()
        .rounded(px(12.0))
        .bg(color::SURFACE_2)
        .child(icon(glyph, 18.0, color::MUTED))
}

/// A row that opens another page: icon, name, tinted summary, chevron.
pub(super) fn entry_row(
    glyph: Icon,
    title: impl Fn() -> &'static str + Copy + 'static,
    summary: impl Fn() -> String + Copy + 'static,
    tint: impl Fn() -> AdaptiveColor + Copy + 'static,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    card()
        .overflow_hidden()
        .child(entry_list_row(glyph, title, summary, tint, press))
}

pub(super) fn entry_list_row(
    glyph: Icon,
    title: impl Fn() -> &'static str + Copy + 'static,
    summary: impl Fn() -> String + Copy + 'static,
    tint: impl Fn() -> AdaptiveColor + Copy + 'static,
    press: impl Fn() + 'static,
) -> impl IntoElement {
    row_button(press)
        .accessibility_label(move || Some(format!("{}, {}", title(), summary()).into()))
        .child(icon_well(glyph))
        .child(entry_text(title, summary, tint))
        .child(icon(Icon::ChevronRight, 18.0, color::MUTED))
}

fn entry_text(
    title: impl Fn() -> &'static str + 'static,
    summary: impl Fn() -> String + 'static,
    tint: impl Fn() -> AdaptiveColor + 'static,
) -> impl IntoElement {
    view()
        .flex_1()
        .min_w(px(0.0))
        .gap(px(2.0))
        .child(text(title).typo(Type::Headline).text_color(color::INK))
        .child(
            text(summary)
                .typo(Type::Subhead)
                .text_color(tint)
                .number_of_lines(2),
        )
}

/// Low-frequency configuration opens in place, retaining entered values.
/// The reveal springs the content's own height; the trigger carries the
/// expanded state for screen readers.
pub(super) fn setting_details(
    glyph: Icon,
    label: impl Fn() -> &'static str + Copy + 'static,
    summary: impl Fn() -> String + Copy + 'static,
    tint: impl Fn() -> AdaptiveColor + Copy + 'static,
    content: impl IntoElement,
) -> impl IntoElement {
    card().overflow_hidden().child(setting_details_row(
        glyph,
        label,
        summary,
        tint,
        signal(false),
        content,
    ))
}

/// A disclosure inside a shared settings surface.
pub(super) fn setting_details_row(
    glyph: Icon,
    label: impl Fn() -> &'static str + Copy + 'static,
    summary: impl Fn() -> String + Copy + 'static,
    tint: impl Fn() -> AdaptiveColor + Copy + 'static,
    open: Signal<bool>,
    content: impl IntoElement,
) -> impl IntoElement {
    collapsible()
        .open(move || open.get())
        .reveal(true)
        .content(
            view()
                .child(hairline(space::CARD))
                .child(view().p(px(space::CARD)).child(content)),
        )
        .child(
            view()
                .role(AccessibilityRole::Button)
                .on_press(move || {
                    dismiss_keyboard();
                    open.update(|v| *v = !*v);
                })
                .optional_label(move || Some(format!("{}, {}", label(), summary()).into()))
                .accessibility_state(move || AccessibilityState {
                    expanded: Some(open.get()),
                    ..AccessibilityState::default()
                })
                .flex_row()
                .items_center()
                .gap_3()
                .min_h(px(68.0))
                .px(px(space::CARD))
                .py_3()
                .transition_colors()
                .duration(motion::INSTANT)
                .hover(|s| s.bg(color::SURFACE_2))
                .active(|s| s.bg(color::SUNKEN))
                .focus_visible(|s| s.bg(color::SURFACE_2))
                .child(icon_well(glyph))
                .child(entry_text(label, summary, tint))
                .child(crate::ui::surface::disclosure_chevron(open)),
        )
}

/// The model account's row (its own page) and asking before each photo.
fn recognition() -> impl IntoElement {
    let account = move || settings::current().account;
    let ask = signal(untracked(|| {
        account().is_none_or(|a| !settings::all_recognition_trusted(&a))
    }));
    // Follows the kept account: a changed account is asked about again.
    effect(move || {
        let asks = account().is_none_or(|a| !settings::all_recognition_trusted(&a));
        if untracked(|| ask.get()) != asks {
            untracked(|| ask.set(asks));
        }
    });
    effect(move || {
        let asks = ask.get();
        if let Some(account) = untracked(account)
            && untracked(|| settings::all_recognition_trusted(&account)) == asks
        {
            untracked(|| settings::set_all_recognition_trusted(&account, !asks));
        }
    });
    let summary = move || match settings::ready_account() {
        Some(a) => {
            let provider = match a.provider {
                Provider::Anthropic => s().anthropic,
                Provider::OpenAiCompatible => s().openai_compatible,
                Provider::OpenAiResponses => s().openai_responses,
            };
            format!("{provider} · {}", a.model)
        }
        None => s().not_set_up.to_owned(),
    };
    let tint = move || {
        if settings::ready_account().is_some() {
            color::MUTED
        } else {
            color::CAUTION
        }
    };
    card()
        .overflow_hidden()
        .child(entry_list_row(
            Icon::Server,
            || s().vision_model,
            summary,
            tint,
            || nav::push(Route::ModelSettings),
        ))
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
    setting_details_row(
        Icon::Target,
        || s().daily_goal,
        || {
            settings::goal()
                .map(|goal| format!("{} {}", field_number(goal), s().kcal))
                .unwrap_or_else(|| s().goal_unset.into())
        },
        || color::MUTED,
        signal(false),
        view()
            .gap_3()
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
            )),
    )
}

/// Diagnostic builds only (`NW_DIAG=1`): what showing the keyboard cost, to
/// tell whether the environment reports it once or on every frame, and
/// whether frames came late while it moved. Show it a few times, then read.
fn keyboard_diagnostics() -> Option<impl IntoElement> {
    use crate::{data::keyboard, i18n::catalog::copy};
    keyboard::DIAGNOSTICS.then(|| {
        let line = |label: &'static str, value: Box<dyn Fn(keyboard::Report) -> String>| {
            view()
                .flex_row()
                .justify_between()
                .gap_3()
                .child(text(label).typo(Type::Subhead).text_color(color::MUTED))
                .child(
                    text(move || value(keyboard::current()))
                        .typo(Type::Subhead)
                        .tabular_nums()
                        .text_color(color::INK),
                )
        };
        view()
            .gap_3()
            .child(view().h_3())
            .child(group_label(|| copy("Keyboard diagnostics", "键盘诊断")))
            .child(
                card()
                    .p(px(space::CARD))
                    .gap_2()
                    .child(line(
                        copy("Shows", "弹出次数"),
                        Box::new(|r| r.shows.to_string()),
                    ))
                    .child(line(
                        copy("Height changes", "键盘高度变化"),
                        Box::new(|r| r.keyboard_changes.to_string()),
                    ))
                    .child(line(
                        copy("Window size changes", "窗口尺寸变化"),
                        Box::new(|r| r.window_changes.to_string()),
                    ))
                    .child(line(
                        copy("Safe area changes", "安全区变化"),
                        Box::new(|r| r.inset_changes.to_string()),
                    ))
                    .child(line(
                        copy("Last show: late frames", "上次弹出：迟到帧"),
                        Box::new(|r| format!("{} / {}", r.late, r.frames)),
                    ))
                    .child(line(
                        copy("Worst frame / refresh", "最长帧 / 刷新间隔"),
                        Box::new(|r| format!("{:.0} / {:.1} ms", r.worst_ms, r.refresh_ms)),
                    )),
            )
    })
}
