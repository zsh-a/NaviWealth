//! Form fields: a visible label, the control, and its description or error
//! right under it. Inputs share one height, inset and focus edge.

use nsh_base::input;
use nsh_core::{
    element::{Input, KeyboardType},
    prelude::*,
};

use super::{
    Typo,
    theme::{Type, color, radius, size},
};

/// `control` under its `label`.
pub fn field(label: impl IntoReactive<SharedString>, control: impl IntoElement) -> View {
    view()
        .gap(px(6.0))
        .child(
            text(label)
                .typo(Type::Subhead)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(color::MUTED),
        )
        .child(control)
}

/// A line under a field while `content` has one: an error in the danger
/// color when `error` reads true, else a description.
pub fn note(
    content: impl Fn() -> Option<SharedString> + Copy + 'static,
    error: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    when(
        move || content().is_some(),
        move || {
            text(move || content().unwrap_or_default())
                .typo(Type::Subhead)
                .text_color(move || if error() { color::DANGER } else { color::MUTED })
        },
    )
}

/// A single-line text input bound to `value`.
pub fn text_input(value: Signal<String>) -> Input {
    styled(
        input()
            .value(move || value.get())
            .on_change(move |text: &str| value.set(text.to_owned())),
    )
    .min_h(px(size::MEDIUM))
    .px_4()
    .bg(color::SUNKEN)
    .rounded(px(radius::CONTROL))
    .border_1()
    .border_color(AdaptiveColor::TRANSPARENT)
    .focus(|s| s.border_color(color::ACCENT).bg(color::SURFACE))
}

/// A decimal input bound to `value` (the text as typed), with its `unit`
/// inside the field's trailing edge.
pub fn number_input(
    value: Signal<String>,
    unit: impl IntoReactive<SharedString>,
    accessibility_label: impl IntoReactive<SharedString>,
) -> View {
    view()
        .flex_row()
        .items_center()
        .min_h(px(size::MEDIUM))
        .pr_4()
        .bg(color::SUNKEN)
        .rounded(px(radius::CONTROL))
        .border_1()
        .border_color(AdaptiveColor::TRANSPARENT)
        .focus_within(|s| s.border_color(color::ACCENT).bg(color::SURFACE))
        .child(
            styled(
                input()
                    .value(move || value.get())
                    .on_change(move |text: &str| value.set(text.to_owned())),
            )
            .keyboard_type(KeyboardType::Decimal)
            .label(accessibility_label)
            .flex_1()
            .min_w(px(0.0))
            .min_h(px(size::MEDIUM))
            .px_4()
            .tabular_nums(),
        )
        .child(text(unit).typo(Type::Callout).text_color(color::MUTED))
}

fn styled(input: Input) -> Input {
    input
        .typo(Type::Body)
        .text_color(color::INK)
        .placeholder_color(|| nsh_core::prelude::color(color::FAINT))
        .caret_color(|| nsh_core::prelude::color(color::ACCENT))
        .selection_color(|| nsh_core::prelude::color(color::ACCENT.opacity(0.25)))
}
