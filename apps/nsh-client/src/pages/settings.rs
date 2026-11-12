//! Settings: the user's own vision model (provider, address, model, key),
//! the optional daily goal, and whether to ask before each photo. Edits
//! stay a draft until Save; leaving with changes asks first.

use nsh_base::{alert_dialog, nav_page};
use nsh_core::{
    element::{AutoCapitalize, KeyboardType, Screen},
    prelude::*,
};

use super::parts::{bottom_bar, bottom_clearance, status_bar, top_bar};
use crate::{
    data::{settings, vision},
    domain::{
        account::{AccountError, ModelAccount, Provider},
        format::{field_number, parse_number},
        recognition::Lang,
    },
    i18n::s,
    nav,
    pages::review_failure_copy,
    ui::{
        Btn, Icon, IconBtn, Size, Type, Typo, color,
        field::{field, note, number_input, text_input},
        segmented::{Segment, segmented},
        space,
        surface::{card, group_label},
        toggle::switch_row,
    },
};

#[derive(Clone, PartialEq)]
enum Test {
    Idle,
    Testing,
    Passed(String),
    Failed(String),
}

#[derive(Clone, PartialEq)]
struct Form {
    account: ModelAccount,
    goal: String,
    ask: bool,
}

/// The settings page.
pub fn settings_page() -> Screen {
    let saved = untracked(settings::current);
    let account = saved
        .account
        .clone()
        .unwrap_or_else(|| ModelAccount::new(Provider::Anthropic));
    let initial = Form {
        ask: saved
            .account
            .as_ref()
            .is_none_or(|a| !untracked(|| settings::is_trusted(a))),
        goal: saved.goal_kcal.map(field_number).unwrap_or_default(),
        account: account.clone(),
    };
    let provider = signal(account.provider);
    let base_url = signal(account.base_url.clone());
    let model = signal(account.model.clone());
    let api_key = signal(account.api_key.clone());
    let goal = signal(initial.goal.clone());
    let ask = signal(initial.ask);
    let show_key = signal(false);
    let attempted = signal(false);
    let test = signal(Test::Idle);
    let running = stored(None::<Spawned<()>>);

    let draft = move || ModelAccount {
        provider: provider.get(),
        base_url: base_url.get(),
        model: model.get(),
        api_key: api_key.get(),
    };
    let form = move || Form {
        account: draft(),
        goal: goal.get(),
        ask: ask.get(),
    };
    let has_error =
        move |error: AccountError| attempted.get() && draft().validate().contains(&error);
    let goal_value = move || -> Result<Option<f64>, ()> {
        goal.with(|text| {
            if text.trim().is_empty() {
                return Ok(None);
            }
            parse_number(text)
                .filter(|value| settings::GOAL_RANGE.contains(value))
                .map(Some)
                .ok_or(())
        })
    };
    let goal_error = move || attempted.get() && goal_value().is_err();
    let dirty = {
        let initial = initial.clone();
        move || form() != initial
    };

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
        test.set(Test::Idle);
    };
    let run_test = move || {
        attempted.set(true);
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
    let save = move || {
        attempted.set(true);
        let account = untracked(draft);
        let Ok(goal) = untracked(goal_value) else {
            return;
        };
        if !account.is_ready() {
            return;
        }
        let account = ModelAccount {
            base_url: account.normalized_base_url(),
            model: account.model.trim().to_owned(),
            api_key: account.api_key.trim().to_owned(),
            ..account
        };
        settings::save(account.clone(), goal);
        settings::set_trusted(&account, !ask.get_untracked());
        nav::pop();
    };
    let back = {
        let dirty = dirty.clone();
        move || {
            if !untracked(&dirty) {
                nav::pop();
                return;
            }
            let answer = alert_dialog()
                .title(s().unsaved_title)
                .cancel("keep", s().keep_editing)
                .destructive("discard", s().discard_changes)
                .show();
            spawn(async move {
                if answer
                    .await
                    .is_ok_and(|answer| answer.action.as_deref() == Some("discard"))
                {
                    nav::pop();
                }
            });
        }
    };

    nav_page()
        .title(|| SharedString::from(s().settings))
        .header_visible(false)
        .status_bar(status_bar)
        .pop_on_back({
            let dirty = dirty.clone();
            move || !dirty()
        })
        .on_back_press(back.clone())
        .child(
            view()
                .flex_1()
                .bg(color::CANVAS)
                .child(top_bar(|| s().settings.into(), back, None))
                .child(
                    scroll()
                        .flex_1()
                        .keyboard_dismiss_mode(KeyboardDismissMode::OnDrag)
                        .child(
                            view()
                                .px(px(space::GUTTER))
                                .pt_2()
                                .pb(move || px(bottom_clearance()))
                                .gap_3()
                                .child(group_label(|| s().vision_model))
                                .child(
                                    card()
                                        .p(px(space::CARD))
                                        .gap_5()
                                        .child(field(
                                            || s().provider,
                                            segmented(
                                                vec![
                                                    Segment::new(Provider::Anthropic, || {
                                                        s().anthropic.into()
                                                    }),
                                                    Segment::new(
                                                        Provider::OpenAiCompatible,
                                                        || s().openai_compatible.into(),
                                                    ),
                                                ],
                                                move || provider.get(),
                                                choose_provider,
                                            ),
                                        ))
                                        .child(
                                            field(
                                                || s().base_url,
                                                text_input(base_url)
                                                    .keyboard_type(KeyboardType::Url)
                                                    .auto_capitalize(AutoCapitalize::None)
                                                    .auto_correct(false)
                                                    .placeholder(move || {
                                                        provider.get().default_base_url().to_owned()
                                                    })
                                                    .style_when(
                                                        move || has_error(AccountError::BaseUrl),
                                                        |s| s.border_color(color::DANGER),
                                                    ),
                                            )
                                            .child(
                                                note(
                                                    move || {
                                                        has_error(AccountError::BaseUrl)
                                                            .then(|| s().error_url.into())
                                                    },
                                                    || true,
                                                ),
                                            ),
                                        )
                                        .child(
                                            field(
                                                || s().model,
                                                text_input(model)
                                                    .auto_capitalize(AutoCapitalize::None)
                                                    .auto_correct(false)
                                                    .placeholder(|| {
                                                        s().model_placeholder.to_owned()
                                                    })
                                                    .style_when(
                                                        move || has_error(AccountError::Model),
                                                        |s| s.border_color(color::DANGER),
                                                    ),
                                            )
                                            .child(
                                                note(
                                                    move || {
                                                        has_error(AccountError::Model)
                                                            .then(|| s().error_model.into())
                                                    },
                                                    || true,
                                                ),
                                            ),
                                        )
                                        .child(
                                            field(
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
                                                            .style_when(
                                                                move || {
                                                                    has_error(AccountError::ApiKey)
                                                                },
                                                                |s| s.border_color(color::DANGER),
                                                            )
                                                            .flex_1()
                                                            .min_w(px(0.0)),
                                                    )
                                                    .child(dynamic(move || {
                                                        let shown = show_key.get();
                                                        untracked(|| {
                                                            IconBtn::new(
                                                                if shown {
                                                                    Icon::EyeOff
                                                                } else {
                                                                    Icon::Eye
                                                                },
                                                                move || {
                                                                    if shown {
                                                                        s().hide_key
                                                                    } else {
                                                                        s().show_key
                                                                    }
                                                                    .into()
                                                                },
                                                            )
                                                            .on_press(move || show_key.set(!shown))
                                                        })
                                                    })),
                                            )
                                            .child(
                                                note(
                                                    move || {
                                                        Some(if has_error(AccountError::ApiKey) {
                                                            s().error_key.into()
                                                        } else {
                                                            s().key_note.into()
                                                        })
                                                    },
                                                    move || has_error(AccountError::ApiKey),
                                                ),
                                            ),
                                        )
                                        .child(test_row(test, run_test)),
                                )
                                .child(view().h_3())
                                .child(group_label(|| s().daily_goal))
                                .child(
                                    card()
                                        .p(px(space::CARD))
                                        .gap_2()
                                        .child(number_input(goal, || s().kcal, || s().daily_goal))
                                        .child(note(
                                            move || {
                                                Some(
                                                    if goal_error() {
                                                        s().error_goal
                                                    } else {
                                                        s().goal_note
                                                    }
                                                    .into(),
                                                )
                                            },
                                            goal_error,
                                        )),
                                )
                                .child(view().h_3())
                                .child(group_label(|| s().privacy))
                                .child(
                                    card()
                                        .px(px(space::CARD))
                                        .py_3()
                                        .gap_1()
                                        .child(switch_row(ask, || s().ask_each_photo.into()))
                                        .child(note(
                                            || Some(s().ask_each_photo_note.into()),
                                            || false,
                                        )),
                                ),
                        ),
                )
                .child(bottom_bar(
                    Btn::primary()
                        .size(Size::Large)
                        .label(|| s().save.into())
                        .on_press(save),
                )),
        )
}

fn test_row(test: Signal<Test>, run: impl Fn() + 'static) -> impl IntoElement {
    view()
        .gap_2()
        .child(
            Btn::secondary()
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
