use super::*;

/// Primary action button (commit intent). `test_id` may be empty; pass a
/// signal in `disabled` to gate the action.
pub fn primary_button(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    test_id: &'static str,
    disabled: Option<Signal<bool>>,
) -> impl Element {
    action_button(
        label,
        on_press,
        (!test_id.is_empty()).then(|| test_id.to_owned()),
        disabled,
        ButtonKind::Primary,
    )
}

/// [`primary_button`] with a runtime-built test id (per-index rows such as
/// confirm cards).
pub fn primary_button_dyn(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    test_id: String,
    disabled: Option<Signal<bool>>,
) -> impl Element {
    action_button(
        label,
        on_press,
        Some(test_id),
        disabled,
        ButtonKind::Primary,
    )
}

/// Quiet secondary action.
pub fn secondary_button(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    test_id: &'static str,
    disabled: Option<Signal<bool>>,
) -> impl Element {
    action_button(
        label,
        on_press,
        (!test_id.is_empty()).then(|| test_id.to_owned()),
        disabled,
        ButtonKind::Secondary,
    )
}

/// [`secondary_button`] with a runtime-built test id.
pub fn secondary_button_dyn(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    test_id: String,
    disabled: Option<Signal<bool>>,
) -> impl Element {
    action_button(
        label,
        on_press,
        Some(test_id),
        disabled,
        ButtonKind::Secondary,
    )
}

enum ButtonKind {
    Primary,
    Secondary,
}

fn action_button(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    test_id: Option<String>,
    disabled: Option<Signal<bool>>,
    kind: ButtonKind,
) -> impl Element {
    let label = label.into();
    let primary = matches!(kind, ButtonKind::Primary);
    let b = press_target(on_press)
        .border_1()
        .border_color(move || theme().border)
        .shadow_sm()
        .items_center()
        .justify_center()
        .rounded(move || theme().radius)
        .bg(move || {
            if primary {
                theme().primary
            } else {
                theme().secondary
            }
        })
        .px(move || px(token("space-control")))
        .child(
            text(label)
                .text_size(move || px(token("type-action")))
                .font_weight(FontWeight::MEDIUM)
                .text_color(move || {
                    if primary {
                        theme().primary_foreground
                    } else {
                        theme().secondary_foreground
                    }
                }),
        );
    let b = match test_id {
        Some(id) => b.test_id(&id),
        None => b,
    };
    match disabled {
        Some(signal) => b.disabled(move || signal.get()),
        None => b,
    }
}

/// Small press target whose label follows the state (a toggle, a
/// check-off). `filled` picks the primary vs secondary palette.
pub fn state_button(
    label: impl Fn() -> String + 'static,
    on_press: impl Fn() + 'static,
    test_id: &'static str,
    filled: bool,
) -> impl Element {
    let b = press_target(on_press)
        .items_center()
        .justify_center()
        .rounded(move || theme().radius)
        .bg(move || {
            if filled {
                theme().primary
            } else {
                theme().secondary
            }
        })
        .px(move || px(token("space-control")))
        .child(
            text(label)
                .text_size(move || px(token("type-action")))
                .text_color(move || {
                    if filled {
                        theme().primary_foreground
                    } else {
                        theme().secondary_foreground
                    }
                }),
        );
    if test_id.is_empty() {
        b
    } else {
        b.test_id(test_id)
    }
}

/// A small selectable chip. Selected reads as the quiet wash + ink; no
/// shared track behind the group.
pub fn chip(
    label: String,
    selected: impl Fn() -> bool + Clone + 'static,
    on_press: impl Fn() + 'static,
) -> impl Element {
    let selected_bg = selected.clone();
    let selected_text = selected.clone();
    NativeControl(
        nsh_base::toggle()
            .pressed(selected.clone())
            .on_change(move |_: &bool| on_press()),
    )
    .rounded(px(999.0))
    .px(px(12.0))
    .py(px(6.0))
    .bg(move || {
        if selected_bg() {
            crate::finance_ui::wash()
        } else {
            theme().muted
        }
    })
    .child(
        text(label)
            .text_size(move || px(token("type-action")))
            .text_color(move || {
                if selected_text() {
                    theme().foreground
                } else {
                    theme().muted_foreground
                }
            }),
    )
}

pub fn choice_button(
    label: impl Into<String>,
    selected: impl Fn() -> bool + Clone + 'static,
    on_press: impl Fn() + 'static,
    id: impl Into<String>,
) -> NativeToggle {
    let scale = selection_scale(selected.clone());
    let semantic = selected.clone();
    let bg = selected.clone();
    NativeControl(
        nsh_base::toggle()
            .pressed(semantic)
            .on_change(move |_: &bool| on_press()),
    )
    .bind_scale(&scale)
    .test_id(&id.into())
    .min_h(move || px(token("control-height")))
    .px_3()
    .py_2()
    .rounded(move || px(theme().number("radius").unwrap_or(10.0)))
    .items_center()
    .justify_center()
    .bg(move || {
        if bg() {
            crate::finance_ui::wash()
        } else {
            theme().secondary
        }
    })
    .child(
        text(label.into())
            .text_size(move || px(token("type-action")))
            .font_weight(FontWeight::MEDIUM)
            .text_color(move || {
                if selected() {
                    theme().foreground
                } else {
                    theme().muted_foreground
                }
            }),
    )
}

pub fn danger_button(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    id: &'static str,
    busy: Signal<bool>,
) -> impl Element {
    press_target(on_press)
        .test_id(id)
        .disabled(move || busy.get())
        .min_h(move || px(token("control-height")))
        .px_4()
        .py_3()
        .rounded(move || theme().radius)
        .items_center()
        .justify_center()
        .bg(move || theme().destructive)
        .child(
            text(label.into())
                .text_base()
                .font_weight(FontWeight::MEDIUM)
                .text_color(move || {
                    color(
                        theme()
                            .color("destructive-foreground")
                            .unwrap_or_else(|| theme().primary_foreground),
                    )
                }),
        )
}

pub fn icon_button(
    kind: Icon,
    label: &'static str,
    id: &'static str,
    on_press: impl Fn() + 'static,
) -> impl Element {
    press_target(on_press)
        .label(label)
        .test_id(id)
        .w(px(48.0))
        .h(px(48.0))
        .items_center()
        .justify_center()
        .rounded(move || px(theme().number("radius").unwrap_or(10.0)))
        .child(icon(kind).text_color(move || theme().muted_foreground))
}

/// A single press/focus primitive for buttons, rows and icon targets.
pub fn press_target(on_press: impl Fn() + 'static) -> NativeButton {
    let scale = animated_value(1.0);
    let down = scale;
    let up = scale;
    NativeControl(
        nsh_base::button()
            .on_press(move |_: &()| on_press())
            .on_press_down(move |_: &()| {
                if !reduce_motion() {
                    down.spring(0.97, settle_spring());
                }
            })
            .on_press_up(move |_: &()| {
                if !reduce_motion() {
                    up.spring(1.0, settle_spring());
                } else {
                    up.set(1.0);
                }
            })
            .bind_scale(&scale),
    )
    .min_h(move || px(token("control-height")))
    .hover(|s| s.opacity(0.9))
    .active(|s| s.opacity(0.88))
    .focus_visible(focus_ring)
    .disabled_style(|s| s.opacity(0.4))
}

/// Quiet inline action, including safe destructive exits.
pub fn text_button(
    label: impl Into<String>,
    id: &str,
    on_press: impl Fn() + 'static,
    destructive: bool,
) -> impl Element {
    press_target(on_press)
        .test_id(id)
        .px_3()
        .justify_center()
        .items_center()
        .rounded(move || theme().radius)
        .child(
            text(label.into())
                .text_size(move || px(token("type-action")))
                .text_color(move || {
                    if destructive {
                        theme().destructive
                    } else {
                        theme().primary
                    }
                }),
        )
}

/// Toolbar commit uses the same stroke, target and radius as icon controls.
pub fn toolbar_action(
    kind: Icon,
    label: &'static str,
    id: &'static str,
    on_press: impl Fn() + 'static,
) -> impl Element {
    press_target(on_press)
        .test_id(id)
        .label(label)
        .flex_row()
        .items_center()
        .justify_center()
        .gap_2()
        .px_3()
        .rounded(move || theme().radius)
        .bg(move || theme().primary)
        .text_color(move || theme().primary_foreground)
        .child(icon(kind))
        .child(
            text(label)
                .text_size(move || px(token("type-action")))
                .font_weight(FontWeight::MEDIUM),
        )
}
