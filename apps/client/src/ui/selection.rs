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
    use nsh_base::SheetEvent;
    let open = signal(false);
    let current =
        move || options.with(|items| items.iter().find(|o| o.value == selected.get()).cloned());
    let value_name = move || {
        current()
            .map(|o| o.label)
            .unwrap_or_else(|| "请选择".into())
    };
    let value_currency = move || {
        current()
            .and_then(|o| o.trailing.or(o.currency))
            .unwrap_or_default()
    };
    view()
        .child(
            press_target(move || {
                dismiss_keyboard();
                open.set(true);
            })
            .test_id(id)
            .py_3()
            .gap_2()
            .child(quiet_text(label).style_when(move || compact, |s| s.hidden()))
            .child(
                view()
                    .flex_row()
                    .items_center()
                    .gap_2()
                    .child(
                        text(value_name)
                            .flex_1()
                            .min_w(px(0.0))
                            .truncate()
                            .text_size(move || px(token("type-body")))
                            .font_weight(FontWeight::MEDIUM),
                    )
                    .child(
                        text(value_currency)
                            .text_size(move || px(token("type-caption")))
                            .text_color(move || theme().muted_foreground),
                    )
                    .child(
                        icon(Icon::Arrow)
                            .w(px(16.0))
                            .h(px(16.0))
                            .text_color(move || theme().muted_foreground),
                    ),
            ),
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
                            |v: &SelectOption| v.value.clone(),
                            move |item: ReadSignal<SelectOption>, _| {
                                let option = item.get();
                                let label = option.display_label();
                                let value = option.value;
                                let flag = value.clone();
                                choice_button(
                                    label,
                                    move || selected.get() == flag,
                                    move || {
                                        selected.set(value.clone());
                                        open.set(false);
                                    },
                                    format!("{id}-{}", item.get().value),
                                )
                            },
                        )))
                        .child(secondary_button("取消", move || open.set(false), "", None)),
                ),
        )
}

#[cfg(test)]
#[path = "selection_tests.rs"]
mod tests;
