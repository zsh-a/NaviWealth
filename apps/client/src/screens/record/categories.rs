use super::*;

/// Whole labels determine the column count. At large type the grid changes
/// columns; it never breaks a category name in the middle of a word.
pub(super) fn category_grid(state: Form) -> AnyElement {
    let columns_state = state.clone();
    let context = state.clone();
    let expanded = signal(false);
    let count = state.categories;
    view()
        .gap_2()
        .child(
            view()
                .flex_row()
                .items_center()
                .justify_between()
                .child(ui::quiet_text("分类"))
                .child(ui::text_button(
                    "全部分类",
                    "record-all-categories",
                    move || expanded.update(|v| *v = !*v),
                    false,
                )),
        )
        .child(
            nsh_base::radio_group().child(
                view()
                    .test_id("record-category")
                    .grid()
                    .grid_cols(move || {
                        columns(
                            window().width.0 - ui::page_px()() * 2.0,
                            font_scale(),
                            &columns_state.categories.get(),
                        )
                    })
                    .gap(px(8.0))
                    .child(each(
                        move || {
                            let categories = count.get();
                            if expanded.get()
                                || categories
                                    .iter()
                                    .skip(12)
                                    .any(|(id, _)| *id == state.category.get())
                            {
                                categories
                            } else {
                                categories.into_iter().take(12).collect()
                            }
                        },
                        |c: &(String, String)| c.0.clone(),
                        move |item: ReadSignal<(String, String)>, _| {
                            let (value, label) = item.get();
                            let category = state.category;
                            let active = value.clone();
                            let bg = value.clone();
                            let checked = value.clone();
                            let scale_value = value.clone();
                            let scale = ui::selection_scale(move || category.get() == scale_value);
                            ui::NativeControl(
                                nsh_base::radio()
                                    .checked(move || category.get() == active)
                                    .on_change(move |checked: &bool| {
                                        if *checked {
                                            category.set(value.clone());
                                        }
                                    })
                                    .accessibility_label(format!("{label}分类选项")),
                            )
                            .test_id(&format!("record-category-{}", item.get().0))
                            .bind_scale(&scale)
                            .min_h(move || px(ui::token("category-height")))
                            .px_1()
                            .py_2()
                            .gap_1()
                            .items_center()
                            .justify_center()
                            .rounded(move || theme().radius)
                            .bg(move || {
                                if category.get() == bg {
                                    crate::finance_ui::wash()
                                } else {
                                    theme().secondary
                                }
                            })
                            .child(ui::category_icon(&label).w(px(16.0)).h(px(16.0)))
                            .child(
                                text(label)
                                    .text_size(move || px(ui::token("type-caption")))
                                    .font_weight(FontWeight::MEDIUM),
                            )
                            .child(when(
                                move || category.get() == checked,
                                || {
                                    ui::icon(ui::Icon::Check)
                                        .absolute()
                                        .right(px(4.0))
                                        .top(px(4.0))
                                        .w(move || px(ui::token("icon-check-size")))
                                        .h(move || px(ui::token("icon-check-size")))
                                        .text_color(move || theme().primary)
                                },
                            ))
                        },
                    )),
            ),
        )
        .child(dynamic(move || {
            let category = context.category.get();
            let currency = context.currency(&context.account.get());
            let budget = context.budgets.get().into_iter().find(|b| {
                b.budget.category_id == category
                    && b.budget.currency == currency
                    && context.date.get().starts_with(&b.budget.month)
            });
            let Some(b) = budget else {
                return view().into_element();
            };
            budget_context(b.spent, b.budget.limit, &currency)
        }))
        .into_element()
}
fn budget_context(spent: Decimal, limit: Decimal, currency: &str) -> AnyElement {
    let status = ui::BudgetDisplay::new(spent, limit, currency);
    let tone = status.clone();
    view()
        .gap_2()
        .pt_4()
        .test_id("record-budget-context")
        .child(
            view()
                .flex_row()
                .justify_between()
                .child(ui::quiet_text("分类预算"))
                .child(ui::quiet_text(status.usage.clone()).text_color(move || tone.tone())),
        )
        .child(ui::progress_bar_state(status.progress, status.alert))
        .child(
            ui::quiet_text(format!(
                "{} · 总额 {} {}",
                status.balance,
                ui::money_for(limit, currency),
                currency
            ))
            .text_color(move || status.tone()),
        )
        .into_element()
}
fn columns(available: f32, scale: f32, categories: &[(String, String)]) -> u16 {
    let longest = categories
        .iter()
        .map(|(_, s)| s.chars().count())
        .max()
        .unwrap_or(4) as f32;
    let cell = longest * 12.0 * scale + 16.0;
    ((available + 8.0) / (cell + 8.0)).floor().clamp(1.0, 4.0) as u16
}
#[cfg(test)]
mod tests {
    use super::*;
    #[component]
    fn OverBudget() -> impl IntoElement {
        budget_context(150.into(), 100.into(), "CNY")
    }
    #[test]
    fn record_budget_shows_unclamped_percentage_and_excess() {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        let mut app = Headless::start(EngineConfig::new(Root::of::<OverBudget>())).unwrap();
        app.wait_for("text:150.0% 已用").unwrap();
        app.wait_for("text:超出 50.00 CNY · 总额 100.00 CNY")
            .unwrap();
    }
    #[test]
    fn labels_fit_at_narrow_large_type_and_long_custom_names() {
        let standard = vec![("id".into(), "公共交通".into())];
        assert_eq!(columns(312.0, 1.3, &standard), 3);
        assert_eq!(columns(334.0, 1.0, &standard), 4);
        assert_eq!(
            columns(312.0, 1.3, &[("id".into(), "自定义长分类名称".into())]),
            2
        );
    }
}
