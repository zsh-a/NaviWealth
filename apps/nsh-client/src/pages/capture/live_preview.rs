//! Text-only, ephemeral interpretation of the first message. The pending
//! timer and the network future share the lifetime of the visible composer.
use super::summary;
use crate::{
    data::{capture_context, settings, vision},
    domain::{
        account::ModelAccount,
        capture::{Draft, MAX_INPUT, Record, Status},
    },
    i18n::{capture_options::copy, s},
    ui::{Type, Typo, color},
};
use navi_health::consent::Consent;
use nsh_core::prelude::*;
use std::time::Duration;

#[derive(Clone, Default, PartialEq)]
enum Preview {
    #[default]
    Hidden,
    Pending,
    Records(Vec<Record>),
    Question(String),
    Destination,
    Unavailable,
}

pub(super) fn panel(
    open: Signal<bool>,
    input: Signal<String>,
    draft: Signal<Draft>,
    consenting: Signal<Option<ModelAccount>>,
) -> impl IntoElement {
    let state = signal(Preview::Hidden);
    let seen = stored(0_usize);
    let task = stored(None::<Spawned<()>>);
    let original = input.get_untracked();
    let touched = stored(false);
    effect(move || {
        let typed = input.get();
        if typed != original {
            touched.replace(true);
        }
        let visible = open.get()
            && consenting.get().is_none()
            && draft.with(|d| d.status == Status::Editing && d.transcript.is_empty());
        let profile = settings::ready_account();
        let options = profile
            .as_ref()
            .map(settings::capture_options)
            .unwrap_or_default();
        if let Some(old) = task.replace(None) {
            old.cancel()
        }
        seen.replace(0);
        state.set(Preview::Hidden);
        if !visible
            || !touched.with(|v| *v)
            || !options.live_text
            || typed.trim().is_empty()
            || typed.chars().count() > MAX_INPUT
        {
            return;
        }
        let Some(mut account) = profile else { return };
        if !options.preview_model.is_empty() {
            account.model = options.preview_model;
        }
        if !account.is_ready() {
            return;
        }
        // Construct a fresh text-only envelope. Even an attached or shared
        // image must wait for an explicitly submitted recognition request.
        let mut query = draft.get_untracked();
        query.input = typed.clone();
        query.photo = None;
        query.attachments.clear();
        query.correction.clear();
        let lang = s().lang;
        task.replace(Some(spawn(async move {
            timer(Duration::from_millis(700)).await;
            let current = || {
                open.get_untracked()
                    && input.get_untracked() == typed
                    && consenting.get_untracked().is_none()
                    && draft
                        .with_untracked(|d| d.status == Status::Editing && d.transcript.is_empty())
            };
            if !current() {
                return;
            }
            let Ok(consent) = Consent::approve(vision::upload_target(&account), true) else {
                return;
            };
            state.set(Preview::Pending);
            let response = vision::recognize_record_stream(
                account,
                query,
                Vec::new(),
                lang,
                consent,
                capture_context::clock_context(),
                move |records| state.set(Preview::Records(records)),
            )
            .await;
            if !current() {
                return;
            }
            state.set(match response {
                Ok(vision::CaptureResponse::Records { records, .. }) if !records.is_empty() => {
                    Preview::Records(records)
                }
                Ok(vision::CaptureResponse::Records { .. }) => Preview::Destination,
                Ok(vision::CaptureResponse::AskUser { request, .. }) => request
                    .questions
                    .first()
                    .map_or(Preview::Hidden, |q| Preview::Question(q.text.clone())),
                Err(_) => Preview::Unavailable,
            });
        })));
    });
    dynamic(move || {
        let next = state.get();
        if next == Preview::Hidden {
            return view().into_element();
        }
        let detail = match next {
            Preview::Records(records) => summary::provisional(&records, seen),
            other => text(match other {
                Preview::Pending => copy().consulting.to_owned(),
                Preview::Question(question) => question,
                Preview::Destination => copy().open_destination.to_owned(),
                _ => copy().preview_failed.to_owned(),
            })
            .typo(Type::Caption)
            .text_color(color::MUTED)
            .into_element(),
        };
        view()
            .gap_1()
            .child(
                text(|| copy().preview_title)
                    .typo(Type::Caption)
                    .text_color(color::MUTED),
            )
            .child(detail)
            .into_element()
    })
}
