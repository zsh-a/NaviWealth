//! The foods of the meal under review: skeleton rows while the model
//! works, the editable foods once they arrive, the total, and a card that
//! says what to do whenever there is nothing to review.

use std::rc::Rc;

use nsh_core::{
    geometry::{DevicePixels, Percentage},
    picker::PickRequest,
    prelude::*,
};

use super::draft::{Draft, Editing, Phase};
use crate::{
    data::photos,
    domain::{
        VisionFailure, format,
        nutrition::{Food, FoodSource, Nutrients, total},
        wire::ProviderError,
    },
    i18n::{Strings, s},
    nav::{self, Route},
    ui::{
        Btn, Icon, Size, Type, Typo, color,
        feedback::{Tone, appear, badge, skeleton},
        icon,
        ring::SEGMENT_COLORS,
        space,
        surface::{card, hairline, row_button, section_header},
    },
};

/// The section under the photo.
pub fn foods_section(draft: Draft) -> impl IntoElement {
    let phase = move || draft.phase.get();
    let has_foods = move || draft.foods.with(|foods| !foods.is_empty());
    let working = move || matches!(phase(), Phase::Preparing | Phase::Analyzing);
    view()
        .gap_3()
        .child(section_header(
            || s().foods,
            Some(
                view()
                    .child(when(
                        move || !working() && has_foods(),
                        move || {
                            Btn::ghost()
                                .size(Size::Small)
                                .icon(Icon::Plus)
                                .label(|| s().add_food.into())
                                .on_press(move || draft.editing.set(Some(Editing::New)))
                        },
                    ))
                    .into_element(),
            ),
        ))
        .child(when(working, skeleton_rows).otherwise(move || {
            view()
                .gap_3()
                .child(when(move || !has_foods(), move || state_card(draft)))
                .child(when(has_foods, move || food_list(draft)))
                .child(when(
                    move || draft.skipped.get() > 0 && has_foods(),
                    move || {
                        text(move || s().skipped(draft.skipped.get()))
                            .typo(Type::Subhead)
                            .text_color(color::MUTED)
                            .px_1()
                    },
                ))
                .child(when(has_foods, move || total_card(draft)))
        }))
}

fn skeleton_rows() -> impl IntoElement {
    card().px(px(space::CARD)).children((0..3).map(|index| {
        view().child((index > 0).then(|| hairline(0.0))).child(
            view()
                .flex_row()
                .items_center()
                .gap_3()
                .py_4()
                .child(
                    view()
                        .flex_1()
                        .gap_2()
                        .child(skeleton(Some([150.0, 120.0, 170.0][index]), 16.0))
                        .child(skeleton(Some(90.0), 12.0)),
                )
                .child(skeleton(Some(44.0), 16.0)),
        )
    }))
}

fn food_list(draft: Draft) -> impl IntoElement {
    card().overflow_hidden().child(each(
        draft.foods,
        |food: &Food| food.id,
        move |food, index| food_row(draft, food, index),
    ))
}

fn food_row(draft: Draft, food: ReadSignal<Food>, index: ReadSignal<usize>) -> impl IntoElement {
    let id = food.with_untracked(|food| food.id);
    appear(
        index.get_untracked() as u32,
        view()
            .child(when(move || index.get() > 0, || hairline(space::CARD)))
            .child(
                row_button(move || draft.editing.set(Some(Editing::Food(id))))
                    .child(
                        view()
                            .flex_1()
                            .min_w(px(0.0))
                            .gap_1()
                            .child(
                                text(move || food.with(|f| f.name.clone()))
                                    .typo(Type::Headline)
                                    .text_color(color::INK)
                                    .number_of_lines(2),
                            )
                            .child(
                                view()
                                    .flex_row()
                                    .items_center()
                                    .flex_wrap()
                                    .gap_2()
                                    .child(
                                        text(move || {
                                            food.with(|f| {
                                                format!(
                                                    "{} {}",
                                                    format::grams(f.grams),
                                                    s().grams_unit
                                                )
                                            })
                                        })
                                        .typo(Type::Subhead)
                                        .tabular_nums()
                                        .text_color(color::MUTED),
                                    )
                                    .child(dynamic(move || {
                                        let (source, check) =
                                            food.with(|f| (f.source.clone(), f.needs_check()));
                                        untracked(|| source_badge(&source, check))
                                    })),
                            ),
                    )
                    .child(
                        view()
                            .items_end()
                            .child(
                                text(move || food.with(|f| format::kcal(f.amount().kcal)))
                                    .typo(Type::Headline)
                                    .tabular_nums()
                                    .text_color(color::INK),
                            )
                            .child(
                                text(|| s().kcal)
                                    .typo(Type::Caption)
                                    .text_color(color::MUTED),
                            ),
                    )
                    .child(icon(Icon::ChevronRight, 16.0, color::FAINT)),
            ),
    )
}

fn source_badge(source: &FoodSource, check: bool) -> AnyElement {
    match (source, check) {
        (_, true) => badge(|| s().badge_check, Tone::Caution, Some(Icon::Alert)).into_element(),
        (FoodSource::Estimate, false) => {
            badge(|| s().badge_estimate, Tone::Accent, Some(Icon::Sparkle)).into_element()
        }
        (FoodSource::Catalog { .. }, false) => badge("USDA", Tone::Neutral, None).into_element(),
        (FoodSource::Manual, false) => {
            badge(|| s().badge_edited, Tone::Neutral, Some(Icon::Pencil)).into_element()
        }
    }
}

/// The meal's total: energy, where it comes from, and the grams of each.
fn total_card(draft: Draft) -> impl IntoElement {
    let sum = computed(move || draft.foods.with(|foods| total(foods)));
    let shares = move || sum.get().energy_split().shares();
    card()
        .p(px(space::CARD))
        .gap_3()
        .child(
            view()
                .flex_row()
                .items_end()
                .justify_between()
                .child(
                    text(|| s().total)
                        .typo(Type::Headline)
                        .text_color(color::INK),
                )
                .child(
                    view()
                        .flex_row()
                        .items_end()
                        .gap_1()
                        .child(
                            text(move || format::kcal(sum.get().kcal))
                                .typo(Type::Title)
                                .tabular_nums()
                                .text_color(color::INK),
                        )
                        .child(
                            text(|| s().kcal)
                                .typo(Type::Subhead)
                                .text_color(color::MUTED)
                                .pb(px(2.0)),
                        ),
                ),
        )
        .child(
            view()
                .flex_row()
                .h(px(8.0))
                .gap(px(2.0))
                .rounded_full()
                .overflow_hidden()
                .bg(color::TRACK)
                .children((0..4).map(move |part| {
                    view()
                        .flex_grow(move || shares()[part] as f32)
                        .w(px(0.0))
                        .bg(SEGMENT_COLORS[part])
                })),
        )
        .child(
            view()
                .flex_row()
                .flex_wrap()
                .gap_4()
                .child(macro_value(|| s().protein, 0, move || sum.get()))
                .child(macro_value(|| s().carbs, 1, move || sum.get()))
                .child(macro_value(|| s().fat, 2, move || sum.get())),
        )
}

fn macro_value(
    label: fn() -> &'static str,
    part: usize,
    sum: impl Fn() -> Nutrients + Copy + 'static,
) -> impl IntoElement {
    let grams = move || {
        let sum = sum();
        [sum.protein, sum.carbs, sum.fat][part]
    };
    view()
        .flex_row()
        .items_center()
        .gap_2()
        .child(view().size(px(8.0)).rounded_full().bg(SEGMENT_COLORS[part]))
        .child(text(label).typo(Type::Subhead).text_color(color::MUTED))
        .child(
            text(move || format!("{} g", format::grams(grams())))
                .typo(Type::Subhead)
                .font_weight(FontWeight::SEMIBOLD)
                .tabular_nums()
                .text_color(color::INK),
        )
}

/// The title and copy that explain `failure`.
pub fn failure_copy(strings: &'static Strings, failure: &VisionFailure) -> (&'static str, String) {
    let pair = |(title, body): (&'static str, &'static str)| (title, body.to_owned());
    match failure {
        VisionFailure::Offline(_) => pair(strings.failure_offline),
        VisionFailure::Timeout => pair(strings.failure_timeout),
        VisionFailure::Truncated | VisionFailure::Unreadable => pair(strings.failure_unreadable),
        VisionFailure::Refused => pair(strings.failure_refused),
        VisionFailure::Photo => pair(strings.failure_photo),
        VisionFailure::Provider(error) => match error {
            ProviderError::Unauthorized => pair(strings.failure_unauthorized),
            ProviderError::Forbidden => pair(strings.failure_forbidden),
            ProviderError::NotFound => pair(strings.failure_not_found),
            ProviderError::RateLimited => pair(strings.failure_rate_limited),
            ProviderError::Overloaded | ProviderError::Server(_) => pair(strings.failure_busy),
            ProviderError::Decode => pair(strings.failure_unreadable),
            ProviderError::Rejected { message, .. } => {
                let (title, hint) = strings.failure_rejected;
                let body = if message.is_empty() {
                    hint.to_owned()
                } else {
                    format!("{hint} {message}")
                };
                (title, body)
            }
        },
    }
}

/// What to do when there is nothing to review.
fn state_card(draft: Draft) -> impl IntoElement {
    dynamic(move || {
        let phase = draft.phase.get();
        untracked(|| state_card_for(draft, phase))
    })
}

/// A recovery action: its label and what it does.
type Action = Option<(&'static str, Rc<dyn Fn()>)>;

fn state_card_for(draft: Draft, phase: Phase) -> AnyElement {
    let strings = s();
    let manual: Rc<dyn Fn()> = Rc::new(move || draft.editing.set(Some(Editing::New)));
    let (glyph, tone, title, body, primary): (Icon, Tone, String, String, Action) = match &phase {
        Phase::NeedsAccount => (
            Icon::Sparkle,
            Tone::Accent,
            strings.setup_title.into(),
            strings.setup_body.into(),
            Some((strings.set_up, Rc::new(|| nav::push(Route::Settings)))),
        ),
        Phase::NotSent | Phase::Consent => (
            Icon::Lock,
            Tone::Neutral,
            strings.not_sent_title.into(),
            strings.not_sent_body.into(),
            Some((strings.send_photo_ellipsis, Rc::new(move || draft.begin()))),
        ),
        Phase::NoFood => (
            Icon::Photo,
            Tone::Neutral,
            strings.no_food_title.into(),
            strings.no_food_body.into(),
            Some((
                strings.choose_another,
                Rc::new(move || choose_another(draft)),
            )),
        ),
        Phase::Failed(failure) => {
            let (title, body) = failure_copy(strings, failure);
            let action: Action = if *failure == VisionFailure::Photo {
                Some((
                    strings.choose_another,
                    Rc::new(move || choose_another(draft)),
                ))
            } else if failure.points_to_settings() {
                Some((
                    strings.open_settings,
                    Rc::new(|| nav::push(Route::Settings)),
                ))
            } else if failure.is_retryable() {
                Some((strings.try_again, Rc::new(move || draft.retry())))
            } else {
                None
            };
            (Icon::Alert, Tone::Danger, title.into(), body, action)
        }
        Phase::Ready | Phase::Preparing | Phase::Analyzing => (
            Icon::Utensils,
            Tone::Accent,
            strings.add_food.into(),
            strings.empty_body.into(),
            None,
        ),
    };
    let (fill, ink) = match tone {
        Tone::Danger => (color::DANGER_SOFT, color::DANGER),
        Tone::Neutral => (color::SUNKEN, color::MUTED),
        _ => (color::ACCENT_SOFT, color::ACCENT),
    };
    appear(
        0,
        card()
            .p(px(space::CARD))
            .gap_4()
            .child(
                view()
                    .flex_row()
                    .items_start()
                    .gap_3()
                    .child(
                        view()
                            .size(px(40.0))
                            .rounded_full()
                            .items_center()
                            .justify_center()
                            .bg(fill)
                            .child(icon(glyph, 20.0, ink)),
                    )
                    .child(
                        view()
                            .flex_1()
                            .gap_1()
                            .child(text(title).typo(Type::Headline).text_color(color::INK))
                            .child(text(body).typo(Type::Callout).text_color(color::MUTED)),
                    ),
            )
            .child(
                view()
                    .flex_row()
                    .flex_wrap()
                    .justify_end()
                    .gap_2()
                    .child({
                        let manual = manual.clone();
                        Btn::ghost()
                            .size(Size::Small)
                            .icon(Icon::Pencil)
                            .label(|| s().add_manually.into())
                            .on_press(move || manual())
                    })
                    .child(primary.map(|(label, run)| {
                        let label: SharedString = label.into();
                        Btn::tonal()
                            .size(Size::Small)
                            .label(move || label.clone())
                            .on_press(move || run())
                    })),
            ),
    )
    .into_element()
}

/// Picks another photo for this meal and starts over with it.
pub fn choose_another(draft: Draft) {
    let mut request = PickRequest::new(false, 1);
    request.max_dimension = Some(DevicePixels(1600));
    request.quality = Some(Percentage(0.9));
    let picked = pick_images(request);
    spawn(async move {
        if let Some(file) = picked.await.into_iter().next() {
            let capture = photos::hold(file.data.to_vec());
            draft.prepare(capture);
        }
    });
}
