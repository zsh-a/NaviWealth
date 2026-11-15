//! Settings' update section: what the running version is, whether a newer
//! `nsh-v*` release exists, and the release page. The check is read-only
//! (no credentials, nothing sent); it runs at most daily on open and when
//! asked.

use nsh_base::link;
use nsh_core::prelude::*;

use crate::{
    data::clock,
    data::updates::{self, Check},
    i18n::s,
    ui::{
        Btn, Icon, Size, Type, Typo, color,
        field::note,
        figures::{Scale, stat},
    },
};

/// The update row: the running version against the newest release.
pub fn updates_section() -> impl IntoElement {
    super::settings::setting_details(
        Icon::Refresh,
        || s().update,
        summary,
        tint,
        view()
            .gap_3()
            .child(stat(
                move || Some(format!("v{}", updates::current())),
                String::new,
                Scale::Tile,
            ))
            .child(when(
                move || updates::checked_at_ms().is_some(),
                move || {
                    let when = format!(
                        "{} {}",
                        s().long_date(clock::day_of(untracked(|| {
                            updates::checked_at_ms().unwrap_or_default()
                        }))),
                        clock::time_label(untracked(|| {
                            updates::checked_at_ms().unwrap_or_default()
                        })),
                    );
                    text(move || s().update_checked_at(&when))
                        .typo(Type::Caption)
                        .text_color(color::MUTED)
                        .into_element()
                },
            ))
            .child(dynamic(move || {
                let Some(release) = updates::latest() else {
                    return view().into_element();
                };
                let newer = release.is_newer_than(updates::current());
                let (version, notes, url) = (
                    release.version.clone(),
                    release.notes.clone(),
                    release.url.clone(),
                );
                view()
                    .gap_1()
                    .child(
                        text(move || {
                            if newer {
                                s().update_found(&version)
                            } else {
                                s().update_uptodate(&version)
                            }
                        })
                        .typo(Type::Headline)
                        .text_color(if newer {
                            color::CAUTION
                        } else {
                            color::MUTED
                        }),
                    )
                    .child(
                        text(move || notes.clone())
                            .typo(Type::Caption)
                            .text_color(color::MUTED)
                            .number_of_lines(6),
                    )
                    .child(
                        link()
                            .href(url.clone())
                            .title(|| SharedString::from(s().update))
                            .child(
                                text(|| s().update_open)
                                    .typo(Type::Body)
                                    .text_color(color::INK),
                            ),
                    )
                    .into_element()
            }))
            .child(
                Btn::tonal()
                    .size(Size::Small)
                    .icon(Icon::Refresh)
                    .label(|| s().update_check.into())
                    .busy(move || updates::status() == Check::Running)
                    .on_press(|| updates::check(true))
                    .self_start(),
            )
            .child(note(
                move || {
                    Some(match updates::status() {
                        Check::Failed(_) => s().update_failed.into(),
                        _ => s().update_note.into(),
                    })
                },
                move || matches!(updates::status(), Check::Failed(_)),
            )),
    )
}

/// The row's summary: what the owner needs at a glance.
fn summary() -> String {
    match updates::latest() {
        Some(release) if updates::update_available() => s().update_found(&release.version),
        Some(release) => s().update_uptodate(&release.version),
        None => s().update_never.into(),
    }
}

fn tint() -> AdaptiveColor {
    match updates::latest() {
        Some(_) if updates::update_available() => color::CAUTION,
        Some(_) => color::POSITIVE,
        None => color::MUTED,
    }
}
