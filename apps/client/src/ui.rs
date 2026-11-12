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
    s.outline(px(token("focus-width")))
        .outline_color(move || theme().ring)
}

#[path = "ui/controls.rs"]
mod controls;
pub use controls::*;
#[path = "ui/tokens.rs"]
mod tokens;
pub use tokens::*;

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
        .min_h(move || px(token("control-height")))
        .px(move || px(token("space-control")))
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
                .text_size(move || px(crate::ui::token("type-section")))
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
                .text_size(move || px(crate::ui::token("type-section")))
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

#[path = "ui/money.rs"]
mod money_format;
pub use money_format::*;

#[derive(Clone, Copy)]
pub enum Icon {
    Today,
    Plus,
    More,
    Plan,
    Ledger,
    Wallet,
    Arrow,
    Back,
    Close,
    Search,
    Check,
}

pub fn icon(kind: Icon) -> impl Element {
    let path = match kind {
        Icon::Plus => "<path d='M12 5v14M5 12h14'/>",
        Icon::More => {
            "<circle cx='5' cy='12' r='1'/><circle cx='12' cy='12' r='1'/><circle cx='19' cy='12' r='1'/>"
        }
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
        Icon::Back => "<path d='m15 6-6 6 6 6'/>",
        Icon::Close => "<path d='m6 6 12 12M18 6 6 18'/>",
        Icon::Arrow => "<path d='m9 6 6 6-6 6'/>",
        Icon::Check => "<path d='m5 12 4 4 10-10'/>",
        Icon::Search => "<circle cx='10.5' cy='10.5' r='6.5'/><path d='m16 16 5 5'/>",
    };
    svg(nsh_core::element::ImageSrc::svg_markup(&format!(
        "<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'>{path}</svg>"
    ))).w(move || px(token("icon-size"))).h(move || px(token("icon-size")))
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
    nsh_base::sheet().backdrop_style(|s| s.bg(hsla(0.0, 0.0, 0.0, token("opacity-scrim"))))
}

mod selection;
pub use selection::*;

pub fn divider() -> impl Element {
    view().h(px(1.0)).bg(move || theme().border)
}

#[cfg(test)]
#[path = "ui/tests.rs"]
mod tests;

#[path = "ui/layout.rs"]
mod layout;
pub use layout::*;

#[path = "ui/motion.rs"]
mod motion;
pub use motion::*;

#[path = "ui/workspace.rs"]
mod workspace;
pub use workspace::*;

pub fn money_field(
    label: &'static str,
    placeholder: &'static str,
    value: Signal<String>,
    id: &'static str,
    currency: impl Fn() -> String + 'static,
) -> impl IntoElement {
    labeled(
        label,
        field_input(
            money_input(value, currency)
                .label(label)
                .placeholder(placeholder)
                .keyboard_type(KeyboardType::Decimal),
        )
        .test_id(id),
    )
}

mod category_icons;
pub use category_icons::*;
mod insights;
pub use insights::*;

mod record_currency;
pub use record_currency::*;

mod budget;
pub use budget::*;

mod native;
pub use native::*;

mod plots;
pub use plots::*;
