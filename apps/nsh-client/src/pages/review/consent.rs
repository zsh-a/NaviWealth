//! Asking before a photo leaves the device: where it goes (the account's
//! server and model, captured as the sheet opens, so a settings change
//! cannot redirect it), what is removed, and that NaviWealth never sees it.
//! Dismissing sends nothing.

use nsh_core::prelude::*;

use super::draft::Draft;
use crate::{
    data::settings,
    domain::account::ModelAccount,
    i18n::s,
    ui::{Btn, Icon, Type, Typo, color, icon, radius, surface::hairline, toggle::checkbox_row},
};

/// The sheet's content, made on each opening.
#[component]
pub fn ConsentSheet() -> impl IntoElement {
    let draft = use_context::<Draft>().expect("the review page provides its draft");
    let account = untracked(settings::ready_account);
    let dont_ask = signal(false);
    let cleartext = account.as_ref().is_some_and(ModelAccount::is_cleartext);
    let host = account.as_ref().map(ModelAccount::host).unwrap_or_default();
    let model = account
        .as_ref()
        .map(|account| account.model.trim().to_owned())
        .unwrap_or_default();
    view()
        .gap_4()
        .child(
            view()
                .gap_2()
                .child(
                    text(|| s().consent_title)
                        .typo(Type::Title)
                        .text_color(color::INK)
                        .role(AccessibilityRole::Header),
                )
                .child(
                    text(|| s().consent_body)
                        .typo(Type::Body)
                        .text_color(color::MUTED),
                ),
        )
        .child(
            view()
                .rounded(px(radius::CONTROL))
                .bg(color::SUNKEN)
                .px_4()
                .child(detail(Icon::Server, || s().consent_server, host))
                .child(hairline(30.0))
                .child(detail(Icon::Chip, || s().consent_model, model)),
        )
        .child(
            view()
                .flex_row()
                .items_start()
                .gap_2()
                .child(icon(Icon::Lock, 18.0, color::MUTED))
                .child(
                    text(|| s().consent_privacy)
                        .typo(Type::Subhead)
                        .text_color(color::MUTED)
                        .flex_shrink(1.0),
                ),
        )
        .child(cleartext.then(|| {
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(icon(Icon::Alert, 18.0, color::CAUTION))
                .child(
                    text(|| s().consent_cleartext)
                        .typo(Type::Subhead)
                        .text_color(color::CAUTION),
                )
        }))
        .child(checkbox_row(dont_ask, || s().dont_ask_again.into()))
        .child(
            view()
                .flex_row()
                .gap_3()
                .child(
                    Btn::secondary()
                        .label(|| s().cancel.into())
                        .on_press(move || draft.consent_declined())
                        .flex_1(),
                )
                .child(
                    Btn::primary()
                        .label(|| s().send_photo.into())
                        .disabled({
                            let ready = account.is_some();
                            move || !ready
                        })
                        .on_press(move || {
                            if let Some(account) = account.clone() {
                                draft.consent_given(account, dont_ask.get_untracked());
                            }
                        })
                        .flex_1(),
                ),
        )
}

fn detail(glyph: Icon, label: fn() -> &'static str, value: String) -> impl IntoElement {
    view()
        .flex_row()
        .items_center()
        .gap_3()
        .min_h(px(48.0))
        .child(icon(glyph, 18.0, color::MUTED))
        .child(text(label).typo(Type::Callout).text_color(color::MUTED))
        .child(
            text(value)
                .typo(Type::Callout)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(color::INK)
                .number_of_lines(1)
                .flex_1()
                .text_right(),
        )
}
