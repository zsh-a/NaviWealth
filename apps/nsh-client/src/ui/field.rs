//! Form fields: a visible label, the control, and its description or error
//! right under it. Inputs share one height, inset and focus edge (ink).

use nsh_base::{SelectElement, input, select};
use nsh_core::{
    element::{Input, KeyboardType},
    prelude::*,
};

use super::{
    Lift, Typo,
    icons::{Icon, icon},
    theme::{Type, color, radius, shadow, size},
};

/// `control` under its `label`.
pub fn field(label: impl IntoReactive<SharedString>, control: impl IntoElement) -> View {
    view()
        .gap(px(8.0))
        .child(
            text(label)
                .typo(Type::Subhead)
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(color::MUTED)
                .pl(px(4.0)),
        )
        .child(control)
}

/// A line under a field while `content` has one: an error in the danger
/// color, marked with an alert glyph, else a quiet description.
pub fn note(
    content: impl Fn() -> Option<SharedString> + Copy + 'static,
    error: impl Fn() -> bool + Copy + 'static,
) -> impl IntoElement {
    when(
        move || content().is_some(),
        move || {
            view()
                .flex_row()
                .items_start()
                .gap_1()
                .pl(px(4.0))
                .child(when(error, || {
                    icon(Icon::Alert, 14.0, color::DANGER).into_element()
                }))
                .child(
                    text(move || content().unwrap_or_default())
                        .typo(Type::Subhead)
                        .text_color(move || if error() { color::DANGER } else { color::MUTED })
                        // The row must constrain the text, or long notes
                        // run off the edge instead of wrapping.
                        .flex_1()
                        .min_w(px(0.0)),
                )
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
    .min_h(px(size::MEDIUM + 2.0))
    .px_4()
    .bg(color::SUNKEN)
    .rounded(px(radius::FIELD))
    .border(px(1.5))
    .border_color(AdaptiveColor::TRANSPARENT)
    .focus(|s| s.border_color(color::INK).bg(color::SURFACE))
}

/// A native select with the same surface and height as a text field.
/// Desktop uses an anchored list; Android presents the touch picker.
pub fn select_input(label: impl IntoReactive<SharedString>) -> SelectElement {
    select()
        .trigger(
            view()
                .flex_row()
                .items_center()
                .gap_3()
                .min_h(px(size::MEDIUM + 2.0))
                .px_4()
                .py_2()
                .bg(color::SUNKEN)
                .rounded(px(radius::FIELD))
                .border(px(1.5))
                .border_color(AdaptiveColor::TRANSPARENT)
                .focus_visible(|s| s.border_color(color::INK))
                .child(
                    text(label)
                        .typo(Type::Body)
                        .text_color(color::INK)
                        .flex_1()
                        .min_w(px(0.0)),
                )
                .child(icon(Icon::ChevronDown, 18.0, color::MUTED)),
        )
        .popup_style(|s| {
            s.bg(color::SURFACE)
                .rounded(px(radius::FIELD))
                .lift(&shadow::FLOAT)
                .dark(|s| s.border_1().border_color(color::LINE))
        })
        .list_style(|s| s.p_1())
        .backdrop_style(|s| s.bg(color::SCRIM.opacity(0.32)))
        .item_class("focus:outline-2")
        .item_style(|s| {
            s.min_h(px(52.0))
                .px_3()
                .py_3()
                .rounded(px(radius::BADGE))
                .typo(Type::Body)
                .text_color(color::INK)
                .selected(|s| s.bg(color::SUNKEN))
        })
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
        .min_h(px(size::MEDIUM + 2.0))
        .pr_4()
        .bg(color::SUNKEN)
        .rounded(px(radius::FIELD))
        .border(px(1.5))
        .border_color(AdaptiveColor::TRANSPARENT)
        .focus_within(|s| s.border_color(color::INK).bg(color::SURFACE))
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
        .placeholder_color(|| nsh_core::prelude::color(color::MUTED))
        .caret_color(|| nsh_core::prelude::color(color::INK))
        .selection_color(|| nsh_core::prelude::color(color::INK.opacity(0.2)))
}
