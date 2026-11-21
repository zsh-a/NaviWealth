//! The meal's photo as the page's header: full-bleed under the status bar,
//! drifting slower than the page as it scrolls and stretching when pulled
//! (both natively, from the scroll offset). A caption shows recognition status.

use nsh_core::{element::AnimatedValue, prelude::*};

use super::draft::{Draft, Phase};
use crate::{
    i18n::s,
    ui::{
        Type, Typo, color,
        feedback::{appear, spinner},
        theme::material,
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
        .child(when(analyzing, move || caption(draft)))
        .child(result_chip(draft))
}

/// A single status line while the estimate is pending.
fn caption(draft: Draft) -> impl IntoElement {
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
        .bg(color::MEDIA_SCRIM.opacity(material::MEDIA_OPACITY))
        .backdrop_blur(px(18.0))
        .pointer_events(PointerEvents::None)
        .child(spinner(20.0, color::ON_MEDIA))
        .child(
            text(move || {
                if draft.slow.get() {
                    s().still_working
                } else {
                    s().analyzing
                }
            })
            .typo(Type::Body)
            .text_color(color::ON_MEDIA),
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
                    .bg(color::MEDIA_SCRIM.opacity(material::MEDIA_OPACITY))
                    .backdrop_blur(px(18.0))
                    .child(
                        text(move || s().food_count(draft.foods.with(Vec::len)))
                            .typo(Type::Caption)
                            .text_color(color::ON_MEDIA),
                    ),
            ))
    })
}
