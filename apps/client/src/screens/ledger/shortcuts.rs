use super::*;

pub(super) fn render(
    category: Signal<String>,
    kind: Signal<Option<RecordKind>>,
    limit: Signal<i64>,
    search_open: Signal<bool>,
    categories: Signal<Vec<naviwealth_finance::daily::ExpenseCategory>>,
) -> impl Element {
    view()
        .flex_row()
        .items_center()
        .gap_1()
        .children(
            [
                ("", "全部"),
                ("dining", "餐饮"),
                ("transport", "交通"),
                ("shopping", "购物"),
            ]
            .map(|(value, label)| {
                ui::choice_button(
                    label,
                    move || {
                        if value.is_empty() {
                            category.get().is_empty()
                        } else {
                            categories.get().iter().any(|c| {
                                c.system_key.as_deref() == Some(value) && c.id == category.get()
                            })
                        }
                    },
                    move || {
                        if value.is_empty() {
                            category.set(String::new());
                        } else if let Some(c) = categories
                            .get()
                            .iter()
                            .find(|c| c.system_key.as_deref() == Some(value))
                        {
                            category.set(c.id.clone());
                        }
                        kind.set(None);
                        limit.set(50);
                    },
                    format!("ledger-category-{label}"),
                )
                .disabled(move || {
                    !value.is_empty()
                        && !categories
                            .get()
                            .iter()
                            .any(|c| c.system_key.as_deref() == Some(value))
                })
                .flex_1()
                .px_2()
            }),
        )
        .child(ui::icon_button(
            ui::Icon::Search,
            "搜索流水",
            "ledger-search-toggle",
            move || search_open.update(|v| *v = !*v),
        ))
}
