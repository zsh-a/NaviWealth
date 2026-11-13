//! Settings' Garmin section: a personal API key to connect, or the
//! connection to end. It acts at once, apart from the page's Save.

use nsh_core::{element::AutoCapitalize, prelude::*};

use crate::{
    data::{garmin, tasks},
    domain::garmin::Region,
    i18n::s,
    ui::{
        Btn, Size, Type, Typo, color,
        field::{field, note, text_input},
        space,
        surface::card,
    },
};

/// Garmin: a personal API key to connect, or the connection to end. Acts
/// at once, apart from the page's Save.
pub fn garmin_section() -> impl IntoElement {
    let key = signal(String::new());
    let busy = signal(false);
    let failure = signal(None::<garmin::Failure>);
    let connect = move || {
        let entered = key.get_untracked();
        if entered.trim().is_empty() || busy.get_untracked() {
            return;
        }
        busy.set(true);
        failure.set(None);
        tasks::spawn_app(async move {
            let result = garmin::connect(entered).await;
            // The page may have closed meanwhile.
            busy.try_set(false);
            match result {
                Ok(_) => {
                    key.try_set(String::new());
                }
                Err(why) => {
                    failure.try_set(Some(why));
                }
            }
        });
    };
    card().p(px(space::CARD)).gap_4().child(
        when(garmin::connected, move || {
            view()
                .gap_3()
                .child(
                    text(|| {
                        let host = match garmin::region() {
                            Some(Region::China) => "garmin.cn",
                            _ => "garmin.com",
                        };
                        s().garmin_connected(host)
                    })
                    .typo(Type::Subhead)
                    .text_color(color::POSITIVE),
                )
                .child(
                    Btn::secondary()
                        .size(Size::Small)
                        .label(|| s().garmin_disconnect.into())
                        .on_press(garmin::disconnect)
                        .self_start(),
                )
        })
        .otherwise(move || {
            view()
                .gap_3()
                .child(field(
                    || s().garmin_key,
                    text_input(key)
                        .masked(|| true)
                        .auto_capitalize(AutoCapitalize::None)
                        .auto_correct(false)
                        .placeholder(|| s().garmin_key_placeholder.to_owned())
                        .style_when(
                            move || failure.get().is_some(),
                            |s| s.border_color(color::DANGER),
                        ),
                ))
                .child(note(
                    move || {
                        Some(
                            match failure.get() {
                                Some(garmin::Failure::KeyRejected) => s().garmin_key_rejected,
                                Some(garmin::Failure::Network) => s().garmin_network,
                                Some(garmin::Failure::Unreadable) => s().garmin_unreadable,
                                None => s().garmin_note,
                            }
                            .into(),
                        )
                    },
                    move || failure.get().is_some(),
                ))
                .child(
                    Btn::tonal()
                        .size(Size::Small)
                        .label(|| s().garmin_connect.into())
                        .busy(move || busy.get())
                        .disabled(move || key.with(|k| k.trim().is_empty()))
                        .on_press(connect)
                        .self_start(),
                )
        }),
    )
}
