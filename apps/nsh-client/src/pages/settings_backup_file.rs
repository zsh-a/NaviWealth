//! The backup page's file group: export an encrypted backup through the
//! share sheet (a save dialog on desktops) and restore one from a picked
//! file. Both use the page's passphrase field, else the kept passphrase, so
//! a fresh install without WebDAV can still be recovered.

use nsh_base::alert_dialog;
use nsh_core::{file_dialog::FileFilter, picker::FilePickRequest, prelude::*};

use super::settings_backup::{Note, failure_copy};
use crate::{
    data::{
        backup::{self, Status},
        backup_file::{self, Delivered},
        clock, tasks,
    },
    domain::backup::EXTENSION,
    i18n::s,
    ui::{Btn, Size, Type, Typo, color, space, surface::card, toggle::switch_row},
};

fn last_export() -> String {
    match backup::last_export_ms() {
        Some(ms) => s().backup_last_export(&format!(
            "{} {}",
            s().long_date(clock::day_of(ms)),
            clock::time_label(ms)
        )),
        None => s().backup_export_never().to_owned(),
    }
}

fn say(message: Signal<Option<Note>>, text: &str, ok: bool) {
    message.try_set(Some(Note {
        text: text.to_owned(),
        ok,
    }));
}

/// The file group, reading the page's `passphrase` field.
pub fn file_group(passphrase: Signal<String>) -> impl IntoElement {
    let photos = signal(true);
    let busy = signal(false);
    let message = signal(None::<Note>);
    // A missing passphrase is said before anything opens.
    let ready = move || match backup_file::passphrase(&passphrase.get_untracked()) {
        Ok(_) => true,
        Err(failure) => {
            say(message, &failure_copy(failure), false);
            false
        }
    };

    let export = move || {
        if busy.get_untracked() || !ready() {
            return;
        }
        busy.set(true);
        message.set(None);
        let (typed, with_photos) = (passphrase.get_untracked(), photos.get_untracked());
        tasks::spawn_app(async move {
            let result = match backup_file::export(typed, with_photos).await {
                Ok(file) => {
                    // The typed passphrase is kept now; the field shows it as kept.
                    passphrase.try_set(String::new());
                    backup_file::deliver(file).await
                }
                Err(failure) => Err(failure),
            };
            busy.try_set(false);
            match result {
                Ok(Delivered::Dismissed) => {}
                Ok(_) => say(message, s().backup_exported(), true),
                Err(failure) => say(message, &failure_copy(failure), false),
            }
        });
    };

    let restore = move || {
        if busy.get_untracked() || !ready() {
            return;
        }
        busy.set(true);
        message.set(None);
        tasks::spawn_app(async move {
            let request = FilePickRequest::default()
                .filter(FileFilter::new("NaviWealth backup", [EXTENSION]));
            let Some(file) = pick_files(request).await.into_iter().next() else {
                busy.try_set(false);
                return;
            };
            let answer = alert_dialog()
                .title(s().restore_title)
                .description(s().restore_body)
                .cancel("keep", s().cancel)
                .destructive("restore", s().restore_confirm)
                .show();
            if !answer
                .await
                .is_ok_and(|answer| answer.action.as_deref() == Some("restore"))
            {
                busy.try_set(false);
                return;
            }
            let typed = passphrase.try_get().unwrap_or_default();
            let result = backup_file::restore(file.data.bytes().to_vec(), typed).await;
            busy.try_set(false);
            match result {
                Ok(()) => {
                    passphrase.try_set(String::new());
                    say(message, s().restored, true);
                }
                Err(failure) => say(message, &failure_copy(failure), false),
            }
        });
    };

    let blocked = move || busy.get() || backup::status() == Status::Running;
    card()
        .p(px(space::CARD))
        .gap_3()
        .child(switch_row(photos, || s().backup_include_photos().into()))
        .child(
            view()
                .flex_row()
                .flex_wrap()
                .gap_2()
                .child(
                    Btn::primary()
                        .size(Size::Small)
                        .label(|| s().backup_export().into())
                        .busy(move || busy.get())
                        .disabled(blocked)
                        .on_press(export),
                )
                .child(
                    Btn::secondary()
                        .size(Size::Small)
                        .label(|| s().backup_restore_file().into())
                        .disabled(blocked)
                        .on_press(restore),
                ),
        )
        .child(
            text(last_export)
                .typo(Type::Subhead)
                .text_color(color::MUTED),
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
        .child(
            text(|| s().backup_file_note())
                .typo(Type::Caption)
                .text_color(color::MUTED),
        )
}
