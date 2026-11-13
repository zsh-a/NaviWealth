//! The meal's photo as the page's header: full-bleed under the status bar,
//! drifting slower than the page as it scrolls and stretching when pulled
//! (both natively, from the scroll offset). While the model works, the AI's
//! light passes over the photo and a frosted caption says what is
//! happening; when it is done, the caption lifts and the result is named.

use std::time::Duration;

use nsh_core::{element::AnimatedValue, prelude::*};

use super::draft::{Draft, Phase};
use crate::{
    i18n::s,
    ui::{
        Icon, Type, Typo, color,
        feedback::{appear, spinner},
        icon, motion,
    },
};

/// How far the content panel rises over the photo's bottom edge.
pub const OVERLAP: f32 = 28.0;

/// The photo's height for a window `width` wide.
pub fn header_height(width: f32) -> f32 {
    (width * 0.95).round().clamp(240.0, 560.0)
}

/// The header, while there is a photo or one is being prepared; made again
/// for the window's width (it is not known before the first layout).
pub fn photo_header(draft: Draft, scroll: AnimatedValue) -> impl IntoElement {
    dynamic(move || {
        let height = header_height(window().width.0);
        untracked(|| header(draft, scroll, height))
    })
}

fn header(draft: Draft, scroll: AnimatedValue, height: f32) -> impl IntoElement {
    let analyzing = move || draft.phase.get() == Phase::Analyzing;
    let veil = animated_value(0.0);
    let scan = animated_value(0.0);
    effect(move || {
        let on = analyzing();
        let still = untracked(reduce_motion);
        if still {
            veil.set(if on { 1.0 } else { 0.0 });
            return;
        }
        veil.timing(if on { 1.0 } else { 0.0 }, motion::SLOW, motion::SETTLE);
        if on {
            // The effect's next run (the analysis ending) stops the loop.
            spawn(async move {
                loop {
                    scan.set(0.0);
                    let _ = scan.timing(1.0, 2000.0, Easing::EaseInOut).await;
                    timer(Duration::from_millis(200)).await;
                }
            });
        }
    });
    let uri = move || draft.photo.with(|p| p.as_ref().map(|p| p.uri.clone()));
    let wide = [-400.0, 0.0, 1200.0];
    view()
        .w_full()
        .h(px(height))
        .overflow_hidden()
        .bg(color::PHOTO_WELL)
        .child(
            view()
                .absolute()
                .inset_0()
                .bind_translate_y(&scroll.interpolate(&wide, &[0.0, 0.0, 540.0]))
                .when(!reduce_motion(), |v| {
                    v.bind_scale(&scroll.interpolate(&wide, &[1.6, 1.0, 1.0]))
                })
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
                            .child(spinner(24.0, color::MUTED))
                            .child(
                                text(|| s().preparing_photo)
                                    .typo(Type::Subhead)
                                    .text_color(color::MUTED),
                            )
                    }),
                ),
        )
        // Keeps the status bar and the back button legible on any photo.
        .child(
            view()
                .absolute()
                .top_0()
                .left_0()
                .right_0()
                .h(px(140.0))
                .bg_linear_to_b()
                .gradient_from(color::MEDIA_SCRIM.opacity(0.45))
                .gradient_to(color::MEDIA_SCRIM.opacity(0.0))
                .pointer_events(PointerEvents::None),
        )
        .child(beam(scan, veil, height))
        .child(caption(draft, veil))
        .child(result_chip(draft))
}

/// The AI's light passing over the photo while analyzing.
fn beam(scan: AnimatedValue, veil: AnimatedValue, height: f32) -> impl IntoElement {
    let band = (height * 0.5).max(80.0);
    view()
        .absolute()
        .left_0()
        .right_0()
        .top_0()
        .h(px(band))
        .bind_opacity(&veil)
        .bind_translate_y(&scan.interpolate(&[0.0, 1.0], &[-band, height]))
        .bg_linear_to_b()
        .gradient_from(color::AI_FROM.opacity(0.0))
        .gradient_via(color::AI_TO.opacity(0.34))
        .gradient_to(color::AI_FROM.opacity(0.0))
        .pointer_events(PointerEvents::None)
}

/// The frosted caption while analyzing.
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
        .left_4()
        .right_4()
        .bottom(px(OVERLAP + 14.0))
        .flex_row()
        .items_center()
        .gap_3()
        .px_4()
        .py_3()
        .rounded(px(20.0))
        .bg(color::MEDIA_SCRIM.opacity(0.42))
        .backdrop_blur(px(18.0))
        .bind_opacity(&veil)
        .bind_translate_y(&veil.interpolate(&[0.0, 1.0], &[10.0, 0.0]))
        .pointer_events(PointerEvents::None)
        .child(spinner(20.0, color::ON_MEDIA))
        .child(
            view()
                .flex_1()
                .gap(px(1.0))
                .child(
                    text(|| s().analyzing)
                        .typo(Type::Headline)
                        .text_color(color::ON_MEDIA),
                )
                .child(dynamic(move || {
                    let line = line();
                    untracked(|| {
                        appear(
                            0,
                            text(line)
                                .typo(Type::Subhead)
                                .text_color(color::ON_MEDIA.opacity(0.8)),
                        )
                    })
                })),
        )
}

/// "3 foods" over the photo once the model has answered.
fn result_chip(draft: Draft) -> impl IntoElement {
    let found = move || {
        draft.phase.get() == Phase::Ready
            && draft.model.with(Option::is_some)
            && !draft.is_saved_meal()
    };
    when(found, move || {
        view()
            .absolute()
            .left_4()
            .bottom(px(OVERLAP + 14.0))
            .child(appear(
                0,
                view()
                    .flex_row()
                    .items_center()
                    .gap(px(6.0))
                    .px_3()
                    .py(px(7.0))
                    .rounded_full()
                    .bg(color::MEDIA_SCRIM.opacity(0.42))
                    .backdrop_blur(px(18.0))
                    .child(icon(Icon::Sparkle, 15.0, color::ON_MEDIA))
                    .child(
                        text(move || s().food_count(draft.foods.with(Vec::len)))
                            .typo(Type::Caption)
                            .text_color(color::ON_MEDIA),
                    ),
            ))
    })
}
