use super::*;
use crate::ui;

pub fn row(
    title: String,
    subtitle: String,
    trailing: String,
    id: String,
    on_press: impl Fn() + 'static,
) -> AnyElement {
    let has_subtitle = !subtitle.is_empty();
    let tone = trailing.clone();
    let title_units: f32 = title
        .chars()
        .map(|c| if c.is_ascii() { 0.6 } else { 1.0 })
        .sum();
    ui::press_target(on_press)
        .label(format!("{title}，{subtitle}，{trailing}"))
        .test_id(&id)
        .min_h(move || px(token("row-height")))
        .py(move || px(token("space-row")))
        .gap_1()
        .child(
            view()
                .flex_row()
                .flex_wrap()
                .items_baseline()
                .gap_2()
                .child(
                    text(title)
                        .flex_1()
                        .min_w(move || {
                            px((title_units * token("type-body") * font_scale() + 8.0)
                                .min(window().width.0 - page_px()() * 2.0))
                        })
                        .text_size(move || px(token("type-body")))
                        .font_weight(FontWeight::MEDIUM),
                )
                .child(
                    text(trailing)
                        .flex_grow(1.0)
                        .text_color(move || money_tone(&tone))
                        .tabular_nums()
                        .text_right()
                        .text_size(move || px(token("type-body"))),
                ),
        )
        .child(when(
            move || has_subtitle,
            move || quiet_text(subtitle.clone()),
        ))
        .into_element()
}
pub fn metric(label: String, value: String, caption: String) -> AnyElement {
    metric_sized(label, value, caption, "type-expense")
}
pub fn metric_sized(
    label: String,
    value: String,
    caption: String,
    size: &'static str,
) -> AnyElement {
    let tone = value.clone();
    view()
        .gap_2()
        .py_3()
        .child(
            text(label)
                .text_size(move || px(crate::ui::token("type-section")))
                .text_color(move || theme().muted_foreground),
        )
        .child(
            text(value)
                .text_color(move || money_tone(&tone))
                .text_size(move || px(ui::token(size)))
                .font_weight(FontWeight::MEDIUM)
                .tabular_nums(),
        )
        .child(
            text(caption)
                .text_size(move || px(crate::ui::token("type-caption")))
                .text_color(move || theme().muted_foreground),
        )
        .into_element()
}

/// Page gutter: 22px, 18px below 370 CSS px.
pub fn page_px() -> impl Fn() -> f32 + Clone + 'static {
    move || {
        if window().width.0 <= 370.0 {
            ui::token("space-page-narrow")
        } else {
            ui::token("space-page")
        }
    }
}
