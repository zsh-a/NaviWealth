//! The meal's photo at the top of the review. While the model works, a
//! band of light passes over the photo and a shaded caption says what is
//! happening; when it finishes the shade lifts and the result is named.

use std::time::Duration;

use nsh_core::{element::AnimatedValue, prelude::*};

use super::draft::{Draft, Phase};
use crate::{
    i18n::s,
    ui::{
        Icon, Type, Typo, color,
        feedback::{appear, spinner},
        icon, motion, radius,
    },
};

/// The photo card, while there is a photo or one is being prepared.
pub fn photo_card(draft: Draft) -> impl IntoElement {
    when(
        move || draft.photo.with(Option::is_some) || draft.phase.get() == Phase::Preparing,
        move || card(draft),
    )
}

fn card(draft: Draft) -> impl IntoElement {
    let analyzing = move || draft.phase.get() == Phase::Analyzing;
    let veil = animated_value(0.0);
    let scan = animated_value(0.0);
    let height = signal(0.0_f32);
    effect(move || {
        let on = analyzing();
        let still = untracked(reduce_motion);
        if still {
            veil.set(if on { 1.0 } else { 0.0 });
            return;
        }
        veil.timing(if on { 1.0 } else { 0.0 }, motion::SLOW, Easing::EaseOut);
        if on {
            // The effect's next run (the analysis ending) stops the loop.
            spawn(async move {
                loop {
                    scan.set(0.0);
                    let _ = scan.timing(1.0, 1900.0, Easing::EaseInOut).await;
                    timer(Duration::from_millis(250)).await;
                }
            });
        }
    });
    let uri = move || draft.photo.with(|p| p.as_ref().map(|p| p.uri.clone()));
    view()
        .w_full()
        .aspect_ratio(4.0 / 3.0)
        .rounded(px(radius::PHOTO))
        .overflow_hidden()
        .bg(color::PHOTO_WELL)
        .on_layout(move |bounds: &Bounds<Points>| height.set(bounds.size.height.0))
        .child(
            when(
                move || uri().is_some(),
                move || {
                    image(move || uri().unwrap_or_default())
                        .object_fit(ResizeMode::Cover)
                        .absolute()
                        .inset_0()
                        .label(|| s().photo_label)
                },
            )
            .otherwise(|| {
                view()
                    .absolute()
                    .inset_0()
                    .items_center()
                    .justify_center()
                    .gap_2()
                    .child(spinner(22.0, color::MUTED))
                    .child(
                        text(|| s().preparing_photo)
                            .typo(Type::Subhead)
                            .text_color(color::MUTED),
                    )
            }),
        )
        .child(dynamic(move || {
            let height = height.get();
            untracked(|| beam(scan, veil, height))
        }))
        .child(caption(draft, veil))
        .child(result_chip(draft))
}

/// The band of light that passes over the photo while analyzing.
fn beam(scan: AnimatedValue, veil: AnimatedValue, height: f32) -> impl IntoElement {
    let band = (height * 0.45).max(60.0);
    view()
        .absolute()
        .left_0()
        .right_0()
        .top_0()
        .h(px(band))
        .bind_opacity(&veil.mul(0.55))
        .bind_translate_y(&scan.interpolate(&[0.0, 1.0], &[-band, height]))
        .bg_linear_to_b()
        .gradient_from(color::ON_MEDIA.opacity(0.0))
        .gradient_via(color::ON_MEDIA.opacity(0.32))
        .gradient_to(color::ON_MEDIA.opacity(0.0))
        .pointer_events(PointerEvents::None)
}

/// The shaded caption while analyzing.
fn caption(draft: Draft, veil: AnimatedValue) -> impl IntoElement {
    let step = signal(0_usize);
    set_interval(Duration::from_millis(2400), move || {
        step.update(|step| *step = (*step + 1).min(2));
    });
    effect(move || {
        if draft.phase.get() == Phase::Analyzing {
            step.set(0);
        }
    });
    let line = move || {
        if draft.slow.get() {
            s().still_working
        } else {
            s().analyzing_steps[step.get()]
        }
    };
    view()
        .absolute()
        .left_0()
        .right_0()
        .bottom_0()
        .pt_8()
        .pb_4()
        .px_4()
        .gap(px(2.0))
        .bind_opacity(&veil)
        .bg_linear_to_t()
        .gradient_from(color::MEDIA_SCRIM.opacity(0.72))
        .gradient_to(color::MEDIA_SCRIM.opacity(0.0))
        .pointer_events(PointerEvents::None)
        .child(
            view()
                .flex_row()
                .items_center()
                .gap_2()
                .child(spinner(16.0, color::ON_MEDIA))
                .child(
                    text(|| s().analyzing)
                        .typo(Type::Headline)
                        .text_color(color::ON_MEDIA),
                ),
        )
        .child(dynamic(move || {
            let line = line();
            untracked(|| {
                appear(
                    0,
                    text(line)
                        .typo(Type::Subhead)
                        .text_color(color::ON_MEDIA.opacity(0.82))
                        .pl(px(24.0)),
                )
            })
        }))
}

/// "3 foods" over the photo's corner once the model has answered.
fn result_chip(draft: Draft) -> impl IntoElement {
    let found = move || {
        draft.phase.get() == Phase::Ready
            && draft.model.with(Option::is_some)
            && !draft.is_saved_meal()
    };
    when(found, move || {
        view().absolute().top_3().left_3().child(appear(
            0,
            view()
                .flex_row()
                .items_center()
                .gap_1()
                .px_2()
                .py_1()
                .rounded(px(radius::SMALL))
                .bg(color::MEDIA_SCRIM.opacity(0.55))
                .child(icon(Icon::Sparkle, 14.0, color::ON_MEDIA))
                .child(
                    text(move || s().food_count(draft.foods.with(Vec::len)))
                        .typo(Type::Caption)
                        .text_color(color::ON_MEDIA),
                ),
        ))
    })
}
