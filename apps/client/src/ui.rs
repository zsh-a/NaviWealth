//! Shared design-system pieces: the 澄白 palette lives in `theme.json`;
//! these helpers keep surfaces, buttons and form fields consistent across
//! screens. Dense and task-oriented — no marketing chrome.
//!
//! Buttons are view-based press targets (role `button`) so every action
//! carries a `test_id` for the headless UI tests and disabled gating.

use nsh_base::{input, theme};
use nsh_core::prelude::*;

/// Radius token accessor (`radius-card` with a safe fallback).
pub fn card_radius() -> f32 {
    theme().number("radius-card").unwrap_or(14.0)
}

/// Primary action button (commit intent). `test_id` may be empty; pass a
/// signal in `disabled` to gate the action.
pub fn primary_button(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    test_id: &'static str,
    disabled: Option<Signal<bool>>,
) -> impl Element {
    let b = view()
        .role(AccessibilityRole::Button)
        .on_press(on_press)
        .items_center()
        .justify_center()
        .rounded(move || theme().radius)
        .bg(move || theme().primary)
        .px(px(16.0))
        .h(px(44.0))
        .active(|s| s.opacity(0.75))
        .child(
            text(label.into())
                .text_base()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(move || theme().primary_foreground),
        );
    let b = if test_id.is_empty() {
        b
    } else {
        b.test_id(test_id)
    };
    match disabled {
        Some(signal) => b.disabled(move || signal.get()),
        None => b,
    }
}

/// Quiet secondary action.
pub fn secondary_button(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    test_id: &'static str,
    disabled: Option<Signal<bool>>,
) -> impl Element {
    let b = view()
        .role(AccessibilityRole::Button)
        .on_press(on_press)
        .items_center()
        .justify_center()
        .rounded(move || theme().radius)
        .bg(move || theme().secondary)
        .px(px(16.0))
        .h(px(44.0))
        .active(|s| s.opacity(0.75))
        .child(
            text(label.into())
                .text_base()
                .text_color(move || theme().secondary_foreground),
        );
    let b = if test_id.is_empty() {
        b
    } else {
        b.test_id(test_id)
    };
    match disabled {
        Some(signal) => b.disabled(move || signal.get()),
        None => b,
    }
}

/// A small selectable chip (category/account pickers). `selected` is read
/// reactively so the highlight follows the pick.
pub fn chip(
    label: String,
    selected: impl Fn() -> bool + Clone + 'static,
    on_press: impl Fn() + 'static,
) -> impl Element {
    let selected_bg = selected.clone();
    let selected_text = selected;
    view()
        .role(AccessibilityRole::Button)
        .on_press(on_press)
        .rounded(px(999.0))
        .px(px(12.0))
        .py(px(6.0))
        .bg(move || {
            if selected_bg() {
                theme().primary
            } else {
                theme().muted
            }
        })
        .active(|s| s.opacity(0.75))
        .child(text(label).text_sm().text_color(move || {
            if selected_text() {
                theme().primary_foreground
            } else {
                theme().muted_foreground
            }
        }))
}

/// Labeled single-line field.
pub fn text_field(
    label: &'static str,
    placeholder: &'static str,
    value: Signal<String>,
    test_id: &'static str,
) -> impl IntoElement {
    labeled(
        label,
        input()
            .value(value)
            .on_change(move |text: &str| value.set(text.to_owned()))
            .placeholder(placeholder)
            .h(px(44.0))
            .px(px(12.0))
            .rounded(move || theme().radius)
            .bg(move || theme().card)
            .border_1()
            .border_color(move || theme().border)
            .text_base()
            .test_id(test_id),
    )
}

/// Labeled masked field (secrets).
pub fn secret_field(
    label: &'static str,
    placeholder: &'static str,
    value: Signal<String>,
    test_id: &'static str,
) -> impl IntoElement {
    labeled(
        label,
        input()
            .value(value)
            .on_change(move |text: &str| value.set(text.to_owned()))
            .placeholder(placeholder)
            .masked(true)
            .h(px(44.0))
            .px(px(12.0))
            .rounded(move || theme().radius)
            .bg(move || theme().card)
            .border_1()
            .border_color(move || theme().border)
            .text_base()
            .test_id(test_id),
    )
}

pub fn labeled(label: &'static str, field: impl IntoElement) -> impl IntoElement {
    view()
        .gap_1()
        .child(
            text(label)
                .text_sm()
                .text_color(move || theme().muted_foreground),
        )
        .child(field)
}

/// Error line for form failures.
pub fn error_line(message: Signal<String>) -> impl IntoElement {
    when(
        move || !message.get().is_empty(),
        move || {
            text(message.get())
                .text_sm()
                .text_color(move || theme().destructive)
        },
    )
}
