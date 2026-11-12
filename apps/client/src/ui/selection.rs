use super::*;
/// Labels are opaque text. Metadata is supplied explicitly, never parsed.
#[derive(Clone, Debug, PartialEq)]
pub struct SelectOption {
    pub value: String,
    pub label: String,
    pub trailing: Option<String>,
    pub currency: Option<String>,
}
impl SelectOption {
    pub fn new(value: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            value: value.into(),
            label: label.into(),
            trailing: None,
            currency: None,
        }
    }
    pub fn account(a: &naviwealth_finance::models::Account) -> Self {
        let label = format!("{}{}", a.name, if a.archived { " · 已归档" } else { "" });
        Self {
            currency: Some(a.currency.clone()),
            ..Self::new(&a.id, label)
        }
    }
    fn display_label(&self) -> String {
        let mut parts = vec![self.label.clone()];
        for extra in [&self.trailing, &self.currency].into_iter().flatten() {
            if !extra.is_empty() && !parts.contains(extra) {
                parts.push(extra.clone());
            }
        }
        parts.join(" · ")
    }
}
impl From<(String, String)> for SelectOption {
    fn from((value, label): (String, String)) -> Self {
        Self::new(value, label)
    }
}
/// Compact field which opens a scrollable choice sheet on touch screens.
pub fn select_field(
    label: &'static str,
    options: Signal<Vec<SelectOption>>,
    selected: Signal<String>,
    id: &'static str,
) -> impl IntoElement {
    select_field_mode(label, options, selected, id, false)
}
pub fn compact_select_field(
    label: &'static str,
    options: Signal<Vec<SelectOption>>,
    selected: Signal<String>,
    id: &'static str,
) -> impl IntoElement {
    select_field_mode(label, options, selected, id, true)
}
fn select_field_mode(
    label: &'static str,
    options: Signal<Vec<SelectOption>>,
    selected: Signal<String>,
    id: &'static str,
    compact: bool,
) -> impl IntoElement {
    use nsh_base::{SelectEntry, SelectItem, select};
    let current =
        move || options.with(|items| items.iter().find(|o| o.value == selected.get()).cloned());
    let value_name = move || {
        current()
            .map(|o| o.label)
            .unwrap_or_else(|| "请选择".into())
    };
    let value_unit = move || {
        current()
            .and_then(|o| o.trailing.or(o.currency))
            .unwrap_or_default()
    };
    view()
        .gap_1()
        .child(quiet_text(label).style_when(move || compact, |s| s.hidden()))
        .child(
            select()
                .items(move || {
                    options
                        .get()
                        .into_iter()
                        .map(|o| SelectItem::new(o.value.clone(), o.display_label()))
                        .collect::<Vec<_>>()
                })
                .value(move || Some(SharedString::from(selected.get())))
                .on_change(move |value: &Option<SharedString>| {
                    selected.set(value.as_ref().map(ToString::to_string).unwrap_or_default())
                })
                .on_open(dismiss_keyboard)
                .accessibility_label(label)
                .searchable(move || options.get().len() > 8)
                .search_placeholder("搜索选项")
                .search_accessibility_label(format!("搜索{label}"))
                .search_test_id(format!("{id}-search"))
                .search_style(|s| {
                    s.min_h(px(44.0))
                        .px_3()
                        .text_base()
                        .text_color(move || theme().foreground)
                        .bg(move || theme().background)
                })
                .popup_style(|s| {
                    s.bg(move || theme().popover)
                        .text_color(move || theme().popover_foreground)
                        .rounded_lg()
                        .border_1()
                        .border_color(move || theme().border)
                        .shadow_lg()
                        .p_1()
                })
                .item_style(|s| s.min_h(px(44.0)).px_3().py_2().rounded_md())
                .item_class("focus:bg-accent selected:bg-accent")
                .render_item(move |entry: &SelectEntry| {
                    view()
                        .test_id(&format!("{id}-{}", entry.value))
                        .child(text(entry.title.clone()).text_base())
                })
                .trigger(
                    view()
                        .test_id(id)
                        .min_h(px(44.0))
                        .py_2()
                        .flex_row()
                        .items_center()
                        .gap_2()
                        .child(
                            text(value_name)
                                .flex_1()
                                .min_w(px(0.0))
                                .truncate()
                                .text_base()
                                .font_weight(FontWeight::MEDIUM),
                        )
                        .child(
                            text(value_unit)
                                .text_sm()
                                .text_color(move || theme().muted_foreground),
                        )
                        .child(icon(Icon::Arrow).w(px(16.0)).h(px(16.0))),
                ),
        )
        .into_element()
}
#[cfg(test)]
#[path = "selection_tests.rs"]
mod tests;
