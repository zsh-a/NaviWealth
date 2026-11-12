use super::*;
use nsh_core::LineHeight;

/// One paragraph keeps the exact full amount searchable and accessible. The
/// currency is a baseline-aligned span, not a competing large number.
pub fn amount_text(value: String, currency: String, size: &'static str) -> impl Element {
    amount_live(move || value.clone(), currency, size)
}
pub fn amount_live(
    value: impl Fn() -> String + 'static,
    currency: String,
    size: &'static str,
) -> impl Element {
    let value = std::rc::Rc::new(value);
    let for_color = value.clone();
    let for_size = value.clone();
    text(move || value())
        .font_family(number_font)
        .tabular_nums()
        .font_weight(FontWeight::NORMAL)
        .text_color(move || money_tone(&for_color()))
        .text_size(move || {
            let available = if size == "type-mini" {
                (window().width.0 - page_px()() * 2.0 - token("space-control")) / 2.0
                    - token("space-control") * 2.0
                    - 4.0
            } else {
                window().width.0 - page_px()() * 2.0 - 34.0
            };
            let units = for_size().chars().count() as f32 * 0.60;
            px(token(size).min(available / units.max(1.0) / font_scale()))
        })
        .letter_spacing(move || {
            px(if token(size) >= token("type-net-worth") {
                token("tracking-display")
            } else {
                0.0
            })
        })
        .line_height(LineHeight::Multiple(1.15))
        .child(
            text(format!(" {currency}"))
                .text_size(move || px(token("type-caption")))
                .letter_spacing(px(0.0))
                .text_color(move || theme().muted_foreground),
        )
}
/// Sign carries cash direction; balances without a plus remain neutral.
pub fn money_tone(formatted: &str) -> AdaptiveColor {
    if formatted.starts_with('-') {
        theme().destructive
    } else if formatted.starts_with('+') {
        crate::finance_ui::gain()
    } else {
        theme().foreground
    }
}

pub fn quiet_text(value: impl Into<String>) -> impl Element {
    text(value.into())
        .text_size(move || px(token("type-caption")))
        .line_height(LineHeight::Multiple(1.45))
        .text_color(move || theme().muted_foreground)
}
pub fn skeleton() -> impl Element {
    view()
        .test_id("workspace-skeleton")
        .gap_4()
        .py_4()
        .child(
            view()
                .w(px(96.0))
                .h(px(12.0))
                .rounded(px(6.0))
                .bg(move || theme().muted),
        )
        .child(
            view()
                .w(px(200.0))
                .h(px(36.0))
                .rounded(px(8.0))
                .bg(move || theme().muted),
        )
        .child(
            view()
                .h(px(56.0))
                .rounded(px(12.0))
                .bg(move || theme().muted),
        )
}
