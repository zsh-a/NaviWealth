//! The owner's own vision model: provider, address, model and key, kept as
//! they are typed (there is no Save). A field shows its problem once it has
//! text; Test connection checks the account as it stands. Photos go to a
//! changed account only after asking again.

use nsh_base::{SelectEntry, SelectItem, nav_page};
use nsh_core::{
    element::{AutoCapitalize, KeyboardType, Screen},
    prelude::*,
};

use super::parts::{status_bar, top_bar};
use crate::{
    data::{settings, vision},
    domain::{
        account::{AccountError, ModelAccount, Provider},
        recognition::Lang,
    },
    i18n::s,
    nav,
    pages::review_failure_copy,
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, color,
        field::{field, note, select_input, text_input},
        space,
        surface::card,
    },
};

#[derive(Clone, PartialEq)]
enum Test {
    Idle,
    Testing,
    Passed(String),
    Failed(String),
}

/// The model account page.
pub fn model_page() -> Screen {
    let account = untracked(settings::current)
        .account
        .unwrap_or_else(|| ModelAccount::new(Provider::Anthropic));
    let provider = signal(account.provider);
    let base_url = signal(account.base_url.clone());
    let model = signal(account.model.clone());
    let api_key = signal(account.api_key.clone());
    let show_key = signal(false);
    let test = signal(Test::Idle);
    let running = stored(None::<Spawned<()>>);

    let draft = move || ModelAccount {
        provider: provider.get(),
        base_url: base_url.get(),
        model: model.get(),
        api_key: api_key.get(),
    };
    // Kept as typed, normalized, whenever it differs from what is kept.
    effect(move || {
        let typed = draft();
        let kept = ModelAccount {
            base_url: typed.normalized_base_url(),
            model: typed.model.trim().to_owned(),
            api_key: typed.api_key.trim().to_owned(),
            ..typed
        };
        if untracked(settings::current).account.as_ref() != Some(&kept) {
            untracked(|| settings::save_account(kept));
            test.set(Test::Idle);
        }
    });
    // A problem shows once its field has text (an empty field says nothing
    // until Test connection is pressed).
    let tested = signal(false);
    let has_error = move |error: AccountError, filled: bool| {
        (filled || tested.get()) && draft().validate().contains(&error)
    };
    let url_error = move || has_error(AccountError::BaseUrl, !base_url.with(String::is_empty));
    let model_error = move || has_error(AccountError::Model, !model.with(String::is_empty));
    let key_error = move || has_error(AccountError::ApiKey, !api_key.with(String::is_empty));

    let choose_provider = move |next: Provider| {
        let previous = provider.get_untracked();
        if previous == next {
            return;
        }
        // Defaults follow the provider; what the user typed stays.
        if base_url
            .with_untracked(|url| url.trim().is_empty() || url == previous.default_base_url())
        {
            base_url.set(next.default_base_url().to_owned());
        }
        if model.with_untracked(|m| m.trim().is_empty() || m == previous.default_model()) {
            model.set(next.default_model().to_owned());
        }
        provider.set(next);
    };
    let run_test = move || {
        tested.set(true);
        let account = untracked(draft);
        if !account.is_ready() {
            return;
        }
        if let Some(task) = running.replace(None) {
            task.cancel();
        }
        test.set(Test::Testing);
        running.replace(Some(spawn(async move {
            let result = vision::ping(account).await;
            test.set(match result {
                Ok((model, seconds)) => Test::Passed(s().connected(&model, seconds)),
                Err(failure) => {
                    let (title, body) = review_failure_copy(s(), &failure);
                    let stop = if s().lang == Lang::Zh { "。" } else { ". " };
                    Test::Failed(format!("{title}{stop}{body}"))
                }
            });
        })));
    };

    let url = field(
        || s().base_url,
        text_input(base_url)
            .keyboard_type(KeyboardType::Url)
            .auto_capitalize(AutoCapitalize::None)
            .auto_correct(false)
            .placeholder(move || provider.get().default_base_url().to_owned())
            .style_when(url_error, |s| s.border_color(color::DANGER)),
    )
    .child(note(
        move || url_error().then(|| s().error_url.into()),
        || true,
    ));
    let model_field = field(
        || s().model,
        text_input(model)
            .auto_capitalize(AutoCapitalize::None)
            .auto_correct(false)
            .placeholder(|| s().model_placeholder.to_owned())
            .style_when(model_error, |s| s.border_color(color::DANGER)),
    )
    .child(note(
        move || model_error().then(|| s().error_model.into()),
        || true,
    ));
    let key = field(
        || s().api_key,
        view()
            .flex_row()
            .items_center()
            .gap_2()
            .child(
                text_input(api_key)
                    .masked(move || !show_key.get())
                    .auto_capitalize(AutoCapitalize::None)
                    .auto_correct(false)
                    .placeholder(move || {
                        if provider.get().requires_key() {
                            s().key_placeholder.to_owned()
                        } else {
                            s().key_optional.to_owned()
                        }
                    })
                    .style_when(key_error, |s| s.border_color(color::DANGER))
                    .flex_1()
                    .min_w(px(0.0)),
            )
            .child(dynamic(move || {
                let shown = show_key.get();
                untracked(|| {
                    IconBtn::new(if shown { Icon::EyeOff } else { Icon::Eye }, move || {
                        if shown { s().hide_key } else { s().show_key }.into()
                    })
                    .on_press(move || show_key.set(!shown))
                })
            })),
    )
    .child(note(
        move || key_error().then(|| s().error_key.into()),
        key_error,
    ));

    let protocol = field(
        || s().provider,
        select_input(move || provider_label(provider.get()))
            .accessibility_label(move || Some(s().provider.into()))
            .items(move || {
                Provider::ALL
                    .into_iter()
                    .enumerate()
                    .map(|(index, choice)| {
                        SelectItem::new(index.to_string(), provider_label(choice))
                    })
                    .collect::<Vec<_>>()
            })
            .value(move || {
                Some(SharedString::from(
                    provider_index(provider.get()).to_string(),
                ))
            })
            .on_change(move |value: &Option<SharedString>| {
                if let Some(choice) = value
                    .as_deref()
                    .and_then(|v| v.parse::<usize>().ok())
                    .and_then(|i| Provider::ALL.get(i))
                {
                    choose_provider(*choice);
                }
            })
            .render_item(|entry: &SelectEntry| {
                let choice = Provider::ALL[entry.index as usize];
                view()
                    .gap_1()
                    .child(
                        text(entry.title.clone())
                            .typo(Type::Body)
                            .text_color(color::INK),
                    )
                    .child(
                        text(provider_path(choice))
                            .typo(Type::Caption)
                            .text_color(color::MUTED),
                    )
            }),
    );
    let form = card()
        .p(px(space::CARD))
        .gap_4()
        .child(protocol)
        .child(url)
        .child(model_field)
        .child(key)
        .child(test_row(test, run_test))
        .child(
            text(|| s().key_note)
                .typo(Type::Caption)
                .text_color(color::MUTED),
        );
    nav_page()
        .title(|| SharedString::from(s().vision_model))
        .header_visible(false)
        .status_bar(status_bar)
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(|| s().vision_model.into(), nav::pop, None))
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
                                .child(form)
                                .child(dynamic(move || {
                                    let account = draft();
                                    account
                                        .is_ready()
                                        .then(|| untracked(|| capture_preferences(account)))
                                })),
                        ),
                ),
        )
}

fn provider_index(provider: Provider) -> usize {
    Provider::ALL
        .iter()
        .position(|p| *p == provider)
        .unwrap_or(0)
}

fn provider_label(provider: Provider) -> &'static str {
    match provider {
        Provider::Anthropic => s().anthropic,
        Provider::OpenAiCompatible => s().openai_compatible,
        Provider::OpenAiResponses => s().openai_responses,
    }
}

fn provider_path(provider: Provider) -> &'static str {
    match provider {
        Provider::Anthropic => "/messages",
        Provider::OpenAiCompatible => "/chat/completions",
        Provider::OpenAiResponses => "/responses",
    }
}

fn test_row(test: Signal<Test>, run: impl Fn() + 'static) -> impl IntoElement {
    view()
        .gap_2()
        .child(
            Btn::tonal()
                .size(Size::Small)
                .icon(Icon::Refresh)
                .label(|| s().test_connection.into())
                .busy(move || test.get() == Test::Testing)
                .on_press(run)
                .self_start(),
        )
        .child(dynamic(move || {
            let state = test.get();
            untracked(|| match state {
                Test::Passed(line) => {
                    Some(text(line).typo(Type::Subhead).text_color(color::POSITIVE))
                }
                Test::Failed(line) => {
                    Some(text(line).typo(Type::Subhead).text_color(color::DANGER))
                }
                Test::Idle | Test::Testing => None,
            })
        }))
}

fn capture_preferences(account: ModelAccount) -> impl IntoElement {
    use crate::i18n::capture_options::copy;
    use crate::ui::toggle::bound_switch;
    let account = stored(account);
    let options = move || account.with(|a| settings::capture_options(a));
    let typed = signal(options().preview_model);
    let invalid = move || {
        typed.with(|v| v.trim().chars().any(char::is_whitespace) || v.trim().chars().count() > 200)
    };
    card()
        .p(px(space::CARD))
        .gap_2()
        .child(
            text(|| copy().options)
                .typo(Type::Headline)
                .text_color(color::INK),
        )
        .child(bound_switch(
            move || options().live_text,
            move |on| account.with(|a| settings::save_capture_options(a, |o| o.live_text = on)),
            || copy().live.into(),
        ))
        .child(
            text(move || {
                let model = options().preview_model;
                account.with(|a| {
                    format!(
                        "{} · {} · {}",
                        copy().live_note,
                        a.host(),
                        if model.is_empty() { &a.model } else { &model }
                    )
                })
            })
            .typo(Type::Caption)
            .text_color(color::MUTED),
        )
        .child(field(
            || copy().fast,
            text_input(typed)
                .auto_capitalize(AutoCapitalize::None)
                .auto_correct(false)
                .label(|| copy().fast)
                .placeholder(|| copy().fast_default),
        ))
        .child(when(
            move || typed.get().trim() != options().preview_model,
            move || {
                Btn::tonal()
                    .size(Size::Small)
                    .label(|| s().done.into())
                    .disabled(invalid)
                    .on_press(move || {
                        let model = typed.get_untracked().trim().to_string();
                        account.with(|a| {
                            settings::save_capture_options(a, |o| {
                                o.preview_model = model;
                                o.live_text = false;
                            })
                        });
                    })
            },
        ))
        .child(bound_switch(
            move || options().recent_context,
            move |on| {
                account.with(|a| settings::save_capture_options(a, |o| o.recent_context = on))
            },
            || copy().context.into(),
        ))
        .child(
            text(|| copy().context_note)
                .typo(Type::Caption)
                .text_color(color::MUTED),
        )
}
