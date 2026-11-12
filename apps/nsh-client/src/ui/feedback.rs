//! Waiting and state: spinners, skeletons, badges, empty states, and the
//! entrance every arriving piece of content shares.

use nsh_core::{
    element::{ImageSrc, Timing},
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

/// A placeholder block of a known shape, pulsing slowly while its content
/// loads.
pub fn skeleton(width: Option<f32>, height: f32) -> View {
    view()
        .h(px(height))
        .when_some(width, |v, w| v.w(px(w)))
        .rounded(px(radius::BADGE))
        .bg(color::SUNKEN)
        .when(!reduce_motion(), |v| v.animate_pulse())
}

/// What a badge says.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tone {
    Neutral,
    Accent,
    Caution,
    Danger,
}

impl Tone {
    fn colors(self) -> (AdaptiveColor, AdaptiveColor) {
        match self {
            Tone::Neutral => (color::SUNKEN, color::MUTED),
            Tone::Accent => (color::ACCENT_SOFT, color::ACCENT),
            Tone::Caution => (color::CAUTION_SOFT, color::CAUTION),
            Tone::Danger => (color::DANGER_SOFT, color::DANGER),
        }
    }
}

/// A short state or classification, with an optional glyph.
pub fn badge(
    content: impl IntoReactive<SharedString>,
    tone: Tone,
    glyph: Option<Icon>,
) -> impl IntoElement {
    let (fill, ink) = tone.colors();
    view()
        .flex_row()
        .items_center()
        .gap_1()
        .px_2()
        .py(px(3.0))
        .rounded(px(radius::BADGE))
        .bg(fill)
        .self_start()
        .child(glyph.map(|glyph| icon(glyph, 13.0, ink)))
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
        .gap_3()
        .px_6()
        .py_8()
        .child(
            view()
                .size(px(56.0))
                .rounded_full()
                .items_center()
                .justify_center()
                .bg(color::ACCENT_SOFT)
                .child(icon(glyph, 26.0, color::ACCENT)),
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
