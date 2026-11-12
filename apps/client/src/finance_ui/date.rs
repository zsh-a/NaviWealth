use super::*;
pub fn date_field(label: &'static str, id: &'static str, value: Signal<String>) -> AnyElement {
    date_field_mode(label, id, value, false)
}
pub fn compact_date_field(
    label: &'static str,
    id: &'static str,
    value: Signal<String>,
) -> AnyElement {
    date_field_mode(label, id, value, true)
}
fn date_field_mode(
    label: &'static str,
    id: &'static str,
    value: Signal<String>,
    compact: bool,
) -> AnyElement {
    use nsh_base::{CalendarEntry, CalendarItemKind};
    view()
        .style_when(
            move || compact,
            |s| s.flex_row().items_center().justify_between(),
        )
        .gap_1()
        .child(
            text(label)
                .text_size(move || px(crate::ui::token("type-caption")))
                .text_color(move || theme().muted_foreground),
        )
        .child(
            date_picker()
                .value(move || {
                    DatePickerValue::Controlled(
                        chrono::NaiveDate::parse_from_str(&value.get(), "%Y-%m-%d")
                            .ok()
                            .map(Into::into)
                            .unwrap_or_default(),
                    )
                })
                .on_change(move |e: &PickedDate| {
                    if let Some(date) = e.value.start() {
                        value.set(date.format("%Y-%m-%d").to_string());
                    }
                })
                .accessibility_label(label)
                .date_format("%Y年%m月%d日")
                .first_day_of_week(1_u32)
                .previous_accessibility_label("上个月")
                .next_accessibility_label("下个月")
                .backdrop_style(|s| s.bg(hsla(0.0, 0.0, 0.0, 0.36)))
                .popup_style(|s| {
                    s.bg(move || theme().card)
                        .px_2()
                        .py_4()
                        .pb_safe_area_plus(px(20.0))
                        .rounded_t(px(16.0))
                })
                .calendar_style(|s| s.w_full().gap_2())
                .header_style(|s| s.min_h(px(48.0)).items_center().gap_1())
                .row_style(|s| s.gap_0())
                .item_style(|s| {
                    s.min_h(px(48.0))
                        .min_w(px(48.0))
                        .px_1()
                        .items_center()
                        .justify_center()
                        .rounded(px(8.0))
                        .text_size(move || px(crate::ui::token("type-body")))
                        .text_color(move || theme().foreground)
                        .selected(|s| {
                            s.bg(move || theme().primary)
                                .text_color(move || theme().primary_foreground)
                        })
                })
                .render_item(|entry: &CalendarEntry| -> AnyElement {
                    match entry.kind {
                        CalendarItemKind::Previous => ui::icon(ui::Icon::Back).into_element(),
                        CalendarItemKind::Next => ui::icon(ui::Icon::Arrow).into_element(),
                        CalendarItemKind::Weekday => text(
                            ["日", "一", "二", "三", "四", "五", "六"]
                                [entry.value.clamp(0, 6) as usize],
                        )
                        .text_size(move || px(crate::ui::token("type-caption")))
                        .into_element(),
                        CalendarItemKind::MonthToggle | CalendarItemKind::Month => {
                            text(format!("{}月", entry.value))
                                .text_size(move || px(crate::ui::token("type-caption")))
                                .into_element()
                        }
                        _ => text(entry.value.to_string())
                            .text_size(move || px(crate::ui::token("type-caption")))
                            .tabular_nums()
                            .opacity(if entry.outside { 0.45 } else { 1.0 })
                            .into_element(),
                    }
                })
                .trigger(
                    ui::state_button(
                        move || {
                            let raw = value.get();
                            if compact {
                                chrono::NaiveDate::parse_from_str(&raw, "%Y-%m-%d")
                                    .map(|d| {
                                        format!(
                                            "{}{}",
                                            if raw == ui::today_text() {
                                                "今天 · "
                                            } else {
                                                ""
                                            },
                                            d.format("%-m月%-d日")
                                        )
                                    })
                                    .unwrap_or(raw)
                            } else {
                                raw
                            }
                        },
                        dismiss_keyboard,
                        id,
                        false,
                    )
                    .style_when(move || compact, |s| s.bg(move || theme().background)),
                ),
        )
        .into_element()
}
