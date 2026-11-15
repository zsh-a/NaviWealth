//! Backup and restore: a WebDAV folder, its account, the backup passphrase,
//! and the restore list. It lives on its own page; Settings carries one row
//! that says whether the day is protected and when it was last backed up.

use nsh_base::{alert_dialog, nav_page};
use nsh_core::{
    element::{AutoCapitalize, KeyboardType, Screen},
    prelude::*,
};

use super::{
    parts::{status_bar, top_bar},
    settings::entry_row,
};
use crate::{
    data::{
        backup::{self, Failure, Status},
        clock, tasks,
        webdav::Folder,
    },
    domain::backup::{self as backup_file, MIN_PASSPHRASE},
    i18n::s,
    nav::{self, Route},
    ui::{
        Btn, Icon, Size, Type, Typo, color,
        feedback::{Tone, badge},
        field::{field, note, text_input},
        space,
        surface::{card, row_button},
    },
};

/// The most backups the restore list offers.
const LISTED: usize = 10;

pub fn failure_copy(failure: Failure) -> String {
    match failure {
        Failure::NotConfigured => s().backup_not_configured.to_owned(),
        Failure::Busy => s().backup_running.to_owned(),
        Failure::Network => s().backup_network.to_owned(),
        Failure::Unauthorized => s().backup_unauthorized.to_owned(),
        Failure::Server(status) => s().backup_server(status),
        Failure::WrongPassphrase => s().backup_wrong_passphrase.to_owned(),
        Failure::NotABackup => s().backup_not_backup.to_owned(),
        Failure::Newer => s().backup_newer.to_owned(),
        Failure::Storage => s().backup_storage.to_owned(),
    }
}

/// The backup's state, as Settings' one row carries it: what happened last,
/// tinted so an unprotected day shows without opening anything.
fn summary() -> String {
    match backup::status() {
        Status::Running => s().backup_running.to_owned(),
        Status::Failed(failure) => failure_copy(failure),
        Status::Idle => match backup::last_backup_ms() {
            Some(ms) => {
                let when = format!(
                    "{} {}",
                    s().long_date(clock::day_of(ms)),
                    clock::time_label(ms)
                );
                s().backup_last(&when)
            }
            None => s().backup_never.to_owned(),
        },
    }
}

fn tint() -> AdaptiveColor {
    match backup::status() {
        Status::Failed(_) => color::DANGER,
        Status::Idle if backup::last_backup_ms().is_none() => color::CAUTION,
        _ => color::MUTED,
    }
}

/// Settings' backup entry: one row, one state, onto its own page.
pub fn backup_row() -> impl IntoElement {
    entry_row(
        Icon::Lock,
        || s().backup,
        summary,
        tint,
        || nav::push(Route::BackupSettings),
    )
}

/// What the last restore or listing came to, said under the buttons.
#[derive(Clone, PartialEq)]
struct Note {
    text: String,
    ok: bool,
}

/// The backup page: the WebDAV folder, the passphrase, and the restore list.
pub fn backup_page() -> Screen {
    nav_page()
        .title(|| SharedString::from(s().backup))
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(|| s().backup.into(), nav::pop, None))
                .child(
                    scroll()
                        .flex_1()
                        .keyboard_dismiss_mode(KeyboardDismissMode::OnDrag)
                        .child(
                            view()
                                .px(px(space::GUTTER))
                                .pt_2()
                                .pb(move || px(safe_area().bottom.0 + 32.0))
                                .child(form()),
                        ),
                ),
        )
}

fn form() -> impl IntoElement {
    let kept = untracked(backup::folder);
    let url = signal(kept.url.clone());
    let username = signal(kept.username.clone());
    let password = signal(kept.password.clone());
    let passphrase = signal(String::new());
    // Backups in the folder, once listed for a restore.
    let listed = signal(None::<Vec<String>>);
    let listing = signal(false);
    let message = signal(None::<Note>);

    let save = move || {
        let folder = Folder {
            url: url.get_untracked().trim().to_owned(),
            username: username.get_untracked().trim().to_owned(),
            password: password.get_untracked(),
        };
        let new_passphrase = passphrase.get_untracked();
        let new_passphrase = (!new_passphrase.is_empty()).then_some(new_passphrase);
        if !folder.is_complete()
            || new_passphrase
                .as_ref()
                .is_some_and(|p| p.chars().count() < MIN_PASSPHRASE)
            || (new_passphrase.is_none() && !untracked(backup::has_passphrase))
        {
            message.set(Some(Note {
                text: s().backup_not_configured.to_owned(),
                ok: false,
            }));
            return;
        }
        backup::configure(folder, new_passphrase);
        passphrase.set(String::new());
        message.set(None);
        tasks::spawn_app(async {
            let _ = backup::backup_now(true).await;
        });
    };
    let passphrase_short =
        move || passphrase.with(|p| !p.is_empty() && p.chars().count() < MIN_PASSPHRASE);
    let list = move || {
        listing.set(true);
        message.set(None);
        spawn(async move {
            let found = backup::list().await;
            listing.set(false);
            match found {
                Ok(names) => listed.set(Some(names.into_iter().take(LISTED).collect())),
                Err(failure) => message.set(Some(Note {
                    text: failure_copy(failure),
                    ok: false,
                })),
            }
        });
    };

    card()
        .p(px(space::CARD))
        .gap_4()
        .child(field(
            || s().webdav_url,
            text_input(url)
                .placeholder(|| "https://dav.jianguoyun.com/dav/NaviWealth".to_owned())
                .keyboard_type(KeyboardType::Url)
                .auto_capitalize(AutoCapitalize::None)
                .auto_correct(false),
        ))
        .child(field(
            || s().webdav_user,
            text_input(username)
                .auto_capitalize(AutoCapitalize::None)
                .auto_correct(false),
        ))
        .child(field(
            || s().webdav_password,
            text_input(password)
                .masked(|| true)
                .auto_capitalize(AutoCapitalize::None)
                .auto_correct(false),
        ))
        .child(
            field(
                || s().backup_passphrase,
                text_input(passphrase)
                    .masked(|| true)
                    .auto_capitalize(AutoCapitalize::None)
                    .auto_correct(false)
                    .placeholder(move || {
                        if backup::has_passphrase() {
                            s().backup_passphrase_kept.to_owned()
                        } else {
                            String::new()
                        }
                    })
                    .style_when(passphrase_short, |s| s.border_color(color::DANGER)),
            )
            .child(note(
                || Some(s().backup_passphrase_note.into()),
                passphrase_short,
            )),
        )
        .child(
            text(|| s().backup_note)
                .typo(Type::Caption)
                .text_color(color::MUTED),
        )
        .child(
            view()
                .flex_row()
                .flex_wrap()
                .gap_2()
                .child(
                    // The page's main action: protect the day.
                    Btn::primary()
                        .size(Size::Small)
                        .label(|| s().backup_save.into())
                        .busy(|| backup::status() == Status::Running)
                        .disabled(passphrase_short)
                        .on_press(save),
                )
                .child(
                    Btn::secondary()
                        .size(Size::Small)
                        .label(|| s().restore.into())
                        .busy(move || listing.get())
                        .disabled(|| !backup::configured() || backup::status() == Status::Running)
                        .on_press(list),
                ),
        )
        .child(
            text(status_line)
                .typo(Type::Subhead)
                .text_color(|| match backup::status() {
                    Status::Failed(_) => color::DANGER,
                    _ => color::MUTED,
                }),
        )
        .child(when(
            move || message.with(Option::is_some),
            move || {
                text(move || message.get().map(|note| note.text).unwrap_or_default())
                    .typo(Type::Subhead)
                    .text_color(move || match message.get() {
                        Some(note) if note.ok => color::POSITIVE,
                        _ => color::INK,
                    })
            },
        ))
        .child(dynamic(move || {
            let names = listed.get();
            untracked(move || names.map(|names| restore_list(names, listed, message)))
        }))
}

fn status_line() -> String {
    match backup::status() {
        Status::Running => s().backup_running.to_owned(),
        Status::Failed(failure) => failure_copy(failure),
        Status::Idle => match backup::last_backup_ms() {
            Some(ms) => {
                let when = format!(
                    "{} {}",
                    s().long_date(clock::day_of(ms)),
                    clock::time_label(ms)
                );
                s().backup_last(&when)
            }
            None => s().backup_never.to_owned(),
        },
    }
}

fn restore_list(
    names: Vec<String>,
    listed: Signal<Option<Vec<String>>>,
    message: Signal<Option<Note>>,
) -> impl IntoElement {
    if names.is_empty() {
        return text(|| s().no_backups)
            .typo(Type::Subhead)
            .text_color(color::MUTED)
            .into_element();
    }
    view()
        .children(names.into_iter().map(|name| {
            // `11月13日 星期五 21:04`, or the name when it is not ours.
            let when_text = backup_file::created_ms(&name)
                .map(|ms| {
                    format!(
                        "{} {}",
                        s().long_date(clock::day_of(ms)),
                        clock::time_label(ms)
                    )
                })
                .unwrap_or_else(|| name.clone());
            let id = name.clone();
            let photos = backup_file::has_photos(&name);
            view().test_id(&id).child(
                row_button(move || confirm_restore(name.clone(), listed, message)).child(
                    view()
                        .flex_1()
                        .min_w(px(0.0))
                        .flex_row()
                        .items_center()
                        .gap_2()
                        .child(text(when_text).typo(Type::Body).text_color(color::INK))
                        .child(when(
                            move || photos,
                            move || badge(s().with_photos, Tone::Neutral, None),
                        )),
                ),
            )
        }))
        .into_element()
}

fn confirm_restore(
    name: String,
    listed: Signal<Option<Vec<String>>>,
    message: Signal<Option<Note>>,
) {
    let answer = alert_dialog()
        .title(s().restore_title)
        .description(s().restore_body)
        .cancel("keep", s().cancel)
        .destructive("restore", s().restore_confirm)
        .show();
    tasks::spawn_app(async move {
        if !answer
            .await
            .is_ok_and(|answer| answer.action.as_deref() == Some("restore"))
        {
            return;
        }
        match backup::restore(name).await {
            // The page may have closed meanwhile.
            Ok(()) => {
                listed.try_set(None);
                message.try_set(Some(Note {
                    text: s().restored.to_owned(),
                    ok: true,
                }));
            }
            // The status line says why.
            Err(_) => {
                message.try_set(None);
            }
        }
    });
}
