//! Waiting and state: spinners, shimmering placeholders, badges, empty
//! states, and the entrance every arriving piece of content shares.

use std::time::Duration;

use nsh_core::{
    element::{AnimatedValue, ImageSrc, Timing},
    prelude::*,
};

use super::{
    Typo,
    icons::{Icon, icon},
    theme::{Type, color, motion, radius},
};

const SPINNER: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 3.2a8.8 8.8 0 1 1-8.8 8.8"/></svg>"#;

/// An indeterminate spinner `size` points wide; still, with reduced motion.
pub fn spinner(size: f32, tint: impl IntoReactive<AdaptiveColor>) -> impl IntoElement {
    svg(ImageSrc::svg_markup(SPINNER))
        .size(px(size))
        .flex_shrink_0()
        .text_color(tint)
        .when(!reduce_motion(), |s| s.animate_spin())
        .accessibility_elements_hidden(true)
}

/// A light that keeps passing over placeholders while content loads (0 to
/// 1, then again); it rests at 0 with reduced motion. Make one per group of
/// placeholders, so they shimmer together.
pub fn shimmer() -> AnimatedValue {
    let sweep = animated_value(0.0);
    if !reduce_motion() {
        spawn(async move {
            loop {
                sweep.set(0.0);
                let _ = sweep.timing(1.0, 1300.0, Easing::EaseInOut).await;
                timer(Duration::from_millis(250)).await;
            }
        });
    }
    sweep
}

/// A placeholder block of a known shape, with the `sweep` light passing.
pub fn skeleton(width: Option<f32>, height: f32, sweep: AnimatedValue) -> View {
    let travel = width.unwrap_or(360.0);
    view()
        .h(px(height))
        .when_some(width, |v, w| v.w(px(w)))
        .rounded(px((height / 2.0).min(radius::BADGE)))
        .bg(color::SUNKEN)
        .overflow_hidden()
        .child(
            view()
                .absolute()
                .top_0()
                .bottom_0()
                .w(px(140.0))
                .bind_translate_x(&sweep.interpolate(&[0.0, 1.0], &[-140.0, travel + 140.0]))
                .bg_linear_to_r()
                .gradient_from(color::SURFACE.opacity(0.0))
                .gradient_via(color::SURFACE.opacity(0.75))
                .gradient_to(color::SURFACE.opacity(0.0)),
        )
}

/// What a badge says.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    /// A classification: neutral.
    Neutral,
    /// The model's estimate: neutral, with the AI's light on its glyph.
    Ai,
    /// Worth a look.
    Caution,
}

impl Tone {
    fn colors(self) -> (AdaptiveColor, AdaptiveColor, AdaptiveColor) {
        match self {
            Tone::Neutral => (color::SURFACE_2, color::MUTED, color::MUTED),
            Tone::Ai => (color::SURFACE_2, color::MUTED, color::AI_FROM),
            Tone::Caution => (color::CAUTION_SOFT, color::CAUTION, color::CAUTION),
        }
    }
}

/// A short state or classification in a pill, with an optional glyph.
pub fn badge(
    content: impl IntoReactive<SharedString>,
    tone: Tone,
    glyph: Option<Icon>,
) -> impl IntoElement {
    let (fill, ink, mark) = tone.colors();
    view()
        .flex_row()
        .items_center()
        .gap_1()
        .pl(px(if glyph.is_some() { 7.0 } else { 9.0 }))
        .pr(px(9.0))
        .py(px(3.0))
        .rounded_full()
        .bg(fill)
        .self_start()
        .child(glyph.map(|glyph| icon(glyph, 13.0, mark)))
        .child(
            text(content)
                .typo(Type::Caption)
                .text_color(ink)
                .number_of_lines(1),
        )
}

/// A quiet explanation where content would be: a glyph in a soft circle,
/// a title and what to do next.
pub fn empty_state(
    glyph: Icon,
    title: impl IntoReactive<SharedString>,
    body: impl IntoReactive<SharedString>,
) -> View {
    view()
        .items_center()
        .gap_4()
        .px_6()
        .py_8()
        .child(
            view()
                .size(px(64.0))
                .rounded_full()
                .items_center()
                .justify_center()
                .bg(color::SURFACE_2)
                .child(icon(glyph, 28.0, color::INK)),
        )
        .child(
            view()
                .items_center()
                .gap_1()
                .child(
                    text(title)
                        .typo(Type::Headline)
                        .text_color(color::INK)
                        .text_center(),
                )
                .child(
                    text(body)
                        .typo(Type::Callout)
                        .text_color(color::MUTED)
                        .text_center(),
                ),
        )
}

/// Wraps `child` so it fades in rising a few points when it is made;
/// `index` staggers siblings arriving together. Nothing moves with reduced
/// motion.
pub fn appear(index: u32, child: impl IntoElement) -> View {
    let still = reduce_motion();
    let shown = animated_value(if still { 1.0 } else { 0.0 });
    if !still {
        shown.timing_with(
            1.0,
            Timing {
                delay_ms: index.min(8) as f32 * motion::STAGGER,
                ..motion::ENTER
            },
        );
    }
    view()
        .bind_opacity(&shown)
        .bind_translate_y(&shown.interpolate(&[0.0, 1.0], &[motion::RISE, 0.0]))
        .child(child)
}
