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
    theme().number("radius-card").unwrap_or(18.0)
}
/// Field corner radius (`radius-field`).
pub fn field_radius() -> f32 {
    theme().number("radius-field").unwrap_or(9.0)
}
/// Row highlight corner radius (`radius-row`).
pub fn row_radius() -> f32 {
    theme().number("radius-row").unwrap_or(7.0)
}

/// Keyboard focus ring: a 2px steel outline outside the border, taking no
/// space. Shared so every press target rings the same way.
pub fn focus_ring(s: nsh_core::element::StyleRefinement) -> nsh_core::element::StyleRefinement {
    s.outline(px(2.0)).outline_color(move || theme().ring)
}

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
    let b = view()
        .role(AccessibilityRole::Button)
        .on_press(on_press)
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
        .px(px(16.0))
        .min_h(px(48.0))
        .active(|s| {
            s.opacity(0.82)
                .scale(if reduce_motion() { 1.0 } else { 0.985 })
        })
        .focus(focus_ring)
        .transition_transform()
        .duration(if reduce_motion() { 0.0 } else { 100.0 })
        .ease_out()
        .child(
            text(label)
                .text_size(px(13.0))
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
    let bg = move || {
        if filled {
            theme().primary
        } else {
            theme().secondary
        }
    };
    let fg = move || {
        if filled {
            theme().primary_foreground
        } else {
            theme().secondary_foreground
        }
    };
    let b = view()
        .role(AccessibilityRole::Button)
        .on_press(on_press)
        .items_center()
        .justify_center()
        .rounded(move || theme().radius)
        .bg(bg)
        .px(px(12.0))
        .min_h(px(48.0))
        .active(|s| s.opacity(0.75))
        .focus(focus_ring)
        .child(text(label).text_sm().text_color(fg));
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
    let selected_text = selected;
    view()
        .role(AccessibilityRole::Button)
        .on_press(on_press)
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
        .active(|s| s.opacity(0.75))
        .focus(focus_ring)
        .child(text(label).text_sm().text_color(move || {
            if selected_text() {
                theme().foreground
            } else {
                theme().muted_foreground
            }
        }))
}

/// Native inputs do not reliably inherit the surrounding text or hint color.
pub fn themed_input() -> nsh_core::element::Input {
    input()
        .text_color(move || theme().foreground)
        .placeholder_color(move || color(theme().muted_foreground))
        .caret_color(move || color(theme().ring))
        .selection_color(move || color(theme().accent))
        .focus(focus_ring)
}

/// Shared geometry for form fields: canvas fill, field radius, visible focus.
fn field_input(input: nsh_core::element::Input) -> nsh_core::element::Input {
    input
        .min_h(px(48.0))
        .px(px(12.0))
        .rounded(move || px(field_radius()))
        .bg(move || theme().background)
        .border_1()
        .border_color(move || theme().border)
        .text_base()
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
        field_input(
            themed_input()
                .label(label)
                .value(value)
                .on_change(move |text: &str| value.set(text.to_owned()))
                .placeholder(placeholder),
        )
        .test_id(test_id),
    )
}

/// [`text_field`] where Enter runs the form's primary action, so the last
/// step stays on the keyboard.
pub fn text_field_submit(
    label: &'static str,
    placeholder: &'static str,
    value: Signal<String>,
    test_id: &'static str,
    on_submit: impl Fn() + 'static,
) -> impl IntoElement {
    labeled(
        label,
        field_input(
            themed_input()
                .label(label)
                .value(value)
                .on_change(move |text: &str| value.set(text.to_owned()))
                .placeholder(placeholder)
                .on_submit(move |_: &str| on_submit()),
        )
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
        field_input(
            themed_input()
                .label(label)
                .value(value)
                .on_change(move |text: &str| value.set(text.to_owned()))
                .placeholder(placeholder)
                .masked(true),
        )
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

/// Parse `yyyy-mm-dd` into epoch seconds at UTC midnight (days-from-civil;
/// the inverse of [`ymd`]). Rejects impossible months/days.
pub fn date_to_secs(text: &str) -> Option<i64> {
    let date = chrono::NaiveDate::parse_from_str(text.trim(), "%Y-%m-%d").ok()?;
    Some(date.and_hms_opt(0, 0, 0)?.and_utc().timestamp())
}

/// Local calendar date for capture defaults; stored record dates remain civil UTC labels.
pub fn today_text() -> String {
    chrono::Local::now()
        .date_naive()
        .format("%Y-%m-%d")
        .to_string()
}

/// yyyy-mm-dd for a timestamp in epoch seconds (civil-from-days; the same
/// calendar math as the record form).
pub fn ymd(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}")
}

/// Exact decimal display, with at least two places and no floating-point conversion.
pub fn money(value: rust_decimal::Decimal) -> String {
    let normalized = value.normalize().to_string();
    let (whole, fraction) = normalized.split_once('.').unwrap_or((&normalized, ""));
    let fraction = match fraction.len() {
        0 => "00".to_owned(),
        1 => format!("{fraction}0"),
        _ => fraction.to_owned(),
    };
    format!("{whole}.{fraction}")
}

#[derive(Clone, Copy)]
pub enum Icon {
    Today,
    Plan,
    Ledger,
    Wallet,
    Chat,
    Settings,
    Arrow,
    Back,
    Close,
    Search,
    Transfer,
    Income,
    Expense,
    Check,
}

pub fn icon(kind: Icon) -> impl Element {
    let path = match kind {
        Icon::Today => {
            "<rect x='3' y='5' width='18' height='16' rx='3'/><path d='M7 3v4M17 3v4M3 11h18M8 16h3'/>"
        }
        Icon::Plan => "<path d='M4 20V10m7 10V4m7 16v-7M3 4h3M17 7h4'/>",
        Icon::Ledger => {
            "<rect x='5' y='3' width='14' height='18' rx='3'/><path d='M9 8h6M9 12h6M9 16h3'/>"
        }
        Icon::Wallet => {
            "<path d='M20 8V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-2'/><path d='M21 8h-7v8h7zM16 12h1'/>"
        }
        Icon::Chat => {
            "<path d='M21 11a8 8 0 0 1-8 8H6l-4 3V11a8 8 0 0 1 8-8h3a8 8 0 0 1 8 8Z'/><path d='M7 10h9M7 14h6'/>"
        }
        Icon::Settings => {
            "<path d='M4 7h16M4 17h16'/><circle cx='9' cy='7' r='3'/><circle cx='16' cy='17' r='3'/>"
        }
        Icon::Back => "<path d='m15 6-6 6 6 6'/>",
        Icon::Close => "<path d='m6 6 12 12M18 6 6 18'/>",
        Icon::Arrow => "<path d='m9 6 6 6-6 6'/>",
        Icon::Search => "<circle cx='10.5' cy='10.5' r='6.5'/><path d='m16 16 5 5'/>",
        Icon::Transfer => "<path d='M4 8h16m-4-4 4 4-4 4M20 16H4m4-4-4 4 4 4'/>",
        Icon::Income => "<path d='M12 4v16m-6-6 6 6 6-6'/>",
        Icon::Expense => "<path d='M12 20V4m-6 6 6-6 6 6'/>",
        Icon::Check => "<path d='m5 13 4.5 4.5L19 7'/>",
    };
    svg(nsh_core::element::ImageSrc::svg_markup(&format!(
        "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>{path}</svg>"
    ))).w(px(22.0)).h(px(22.0))
}

pub fn empty_state(title: &'static str, description: &'static str) -> impl Element {
    view()
        .gap_2()
        .py_6()
        .child(text(title).text_lg().font_weight(FontWeight::SEMIBOLD))
        .child(
            text(description)
                .text_base()
                .text_color(move || theme().muted_foreground),
        )
}

pub fn choice_button(
    label: impl Into<String>,
    selected: impl Fn() -> bool + Clone + 'static,
    on_press: impl Fn() + 'static,
    id: impl Into<String>,
) -> impl Element {
    let bg = selected.clone();
    view()
        .role(AccessibilityRole::Button)
        .on_press(on_press)
        .test_id(&id.into())
        .min_h(px(48.0))
        .px_3()
        .py_2()
        .rounded(move || px(theme().number("radius").unwrap_or(10.0)))
        .items_center()
        .justify_center()
        .bg(move || {
            if bg() {
                crate::finance_ui::wash()
            } else {
                theme().card
            }
        })
        .active(|s| s.opacity(0.8))
        .focus(focus_ring)
        .child(
            text(label.into())
                .text_sm()
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

/// Scroll content contains real actions, even while an input keeps focus.
/// Android's default `Never` swallows non-input taps based on focus, including
/// after the IME hides in a dialog. `Handled` delivers buttons/pickers normally
/// and still dismisses the keyboard when unhandled background is tapped.
pub fn interactive_scroll() -> nsh_core::element::Scroll {
    scroll().keyboard_taps(KeyboardTaps::Handled)
}

/// Shared native sheet: dim the underlying task and reserve system navigation space
/// in each content footer. nsh-base sheets are deliberately unstyled.
pub fn app_sheet() -> nsh_base::SheetElement {
    nsh_base::sheet().backdrop_style(|s| s.bg(hsla(0.0, 0.0, 0.0, 0.36)))
}

/// Compact field which opens a scrollable choice sheet on touch screens.
pub fn select_field(
    label: &'static str,
    options: Signal<Vec<(String, String)>>,
    selected: Signal<String>,
    id: &'static str,
) -> impl IntoElement {
    use nsh_base::SheetEvent;
    let open = signal(false);
    let selected_label = move || {
        options.with(|items| {
            items
                .iter()
                .find(|(value, _)| *value == selected.get())
                .map(|(_, label)| label.clone())
                .unwrap_or_else(|| "请选择".to_owned())
        })
    };
    view()
        .child(
            view()
                .role(AccessibilityRole::Button)
                .test_id(id)
                .on_press(move || {
                    dismiss_keyboard();
                    open.set(true);
                })
                .min_h(px(56.0))
                .flex_row()
                .items_center()
                .gap_3()
                .px_4()
                .py_3()
                .focus(focus_ring)
                .child(text(label).text_base())
                .child(
                    text(selected_label)
                        .flex_1()
                        .min_w(px(0.0))
                        .truncate()
                        .text_right()
                        .text_base()
                        .text_color(move || theme().muted_foreground),
                )
                .child(icon(Icon::Arrow).text_color(move || theme().muted_foreground)),
        )
        .child(
            app_sheet()
                .open(move || Some(open.get()))
                .on_open_change(move |event: &SheetEvent| {
                    if let SheetEvent::OpenChange(next, _) = event {
                        open.set(*next);
                    }
                })
                .child(
                    view()
                        .p_5()
                        .pb_safe_area_plus(px(20.0))
                        .gap_3()
                        .h(move || px((window().height.0 * 0.75).clamp(240.0, 480.0)))
                        .max_h(px(560.0))
                        .bg(move || theme().background)
                        .child(text(label).text_lg().font_weight(FontWeight::SEMIBOLD))
                        .child(interactive_scroll().flex_1().child(each(
                            move || options.get(),
                            |v: &(String, String)| v.0.clone(),
                            move |item: ReadSignal<(String, String)>, _| {
                                let (value, label) = item.get();
                                let flag = value.clone();
                                choice_button(
                                    label,
                                    move || selected.get() == flag,
                                    move || {
                                        selected.set(value.clone());
                                        open.set(false);
                                    },
                                    format!("{id}-{}", item.get().0),
                                )
                            },
                        )))
                        .child(secondary_button("取消", move || open.set(false), "", None)),
                ),
        )
}

pub fn divider() -> impl Element {
    view().h(px(1.0)).bg(move || theme().border)
}

pub fn danger_button(
    label: impl Into<String>,
    on_press: impl Fn() + 'static,
    id: &'static str,
    busy: Signal<bool>,
) -> impl Element {
    view()
        .role(AccessibilityRole::Button)
        .test_id(id)
        .on_press(on_press)
        .disabled(move || busy.get())
        .min_h(px(48.0))
        .px_4()
        .py_3()
        .rounded(move || theme().radius)
        .items_center()
        .justify_center()
        .focus(focus_ring)
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
    view()
        .role(AccessibilityRole::Button)
        .label(label)
        .test_id(id)
        .on_press(on_press)
        .w(px(48.0))
        .h(px(48.0))
        .items_center()
        .justify_center()
        .rounded(move || px(theme().number("radius").unwrap_or(10.0)))
        .active(|s| {
            s.opacity(0.65)
                .scale(if reduce_motion() { 1.0 } else { 0.96 })
        })
        .focus(focus_ring)
        .transition_transform()
        .duration(if reduce_motion() { 0.0 } else { 100.0 })
        .ease_out()
        .child(icon(kind).text_color(move || theme().muted_foreground))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dates_reject_impossible_days() {
        assert!(date_to_secs("2026-02-29").is_none());
        assert!(date_to_secs("2026-04-31").is_none());
        assert_eq!(ymd(date_to_secs("2024-02-29").unwrap()), "2024-02-29");
    }
    #[test]
    fn amounts_keep_small_values_exact() {
        assert_eq!(money("0.000001".parse().unwrap()), "0.000001");
        assert_eq!(money("42.5".parse().unwrap()), "42.50");
    }

    #[component]
    fn KeyboardTapProbe() -> impl IntoElement {
        let open = signal(false);
        let value = signal(String::new());
        let kind = signal("支出".to_owned());
        view()
            .child(primary_button(
                "打开",
                move || {
                    kind.set("支出".to_owned());
                    open.set(true);
                },
                "tap-open",
                None,
            ))
            .child(when(
                move || open.get(),
                move || {
                    nsh_base::dialog()
                        .on_cancel(move || open.set(false))
                        .child(
                            interactive_scroll()
                                .flex_1()
                                .test_id("tap-scroll")
                                .child(
                                    input()
                                        .value(value)
                                        .on_change(move |v: &str| value.set(v.to_owned()))
                                        .test_id("tap-input"),
                                )
                                .child(choice_button(
                                    "收入",
                                    move || kind.get() == "收入",
                                    move || kind.set("收入".to_owned()),
                                    "tap-income",
                                ))
                                .child(choice_button(
                                    "转账",
                                    move || kind.get() == "转账",
                                    move || kind.set("转账".to_owned()),
                                    "tap-transfer",
                                ))
                                .child(text(move || format!("当前类型：{}", kind.get()))),
                        )
                        .child(secondary_button(
                            "关闭",
                            move || open.set(false),
                            "tap-close",
                            None,
                        ))
                },
            ))
    }

    #[test]
    fn interactive_scroll_keeps_handled_taps_with_focused_input_across_reopens() {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        use std::sync::{Arc, Mutex};
        let observed = Arc::new(Mutex::new(Vec::new()));
        let capture = observed.clone();
        let mut app = Headless::start(EngineConfig::new(Root::of::<KeyboardTapProbe>())).unwrap();
        app.observe(move |_, batch| {
            for item in &batch.items {
                if let nsh_core::MountItem::ScrollBehavior { behavior, .. } = item {
                    capture.lock().unwrap().push(behavior.keyboard_taps);
                }
            }
        });
        app.wait_for("id:tap-open").unwrap();
        for _ in 0..4 {
            app.press("id:tap-open").unwrap();
            app.type_text("id:tap-input", "1").unwrap();
            app.press("id:tap-income").unwrap();
            app.wait_for("text:当前类型：收入").unwrap();
            app.press("id:tap-transfer").unwrap();
            app.wait_for("text:当前类型：转账").unwrap();
            app.press("id:tap-close").unwrap();
        }
        let taps = observed.lock().unwrap();
        assert!(
            taps.len() >= 4,
            "each newly mounted native scroll receives its tap policy"
        );
        assert!(taps.iter().all(|taps| *taps == KeyboardTaps::Handled));
    }
}
