use super::*;
pub(super) fn overlays(
    tools_open: Signal<bool>,
    filters_open: Signal<bool>,
    account_options: Signal<Vec<ui::SelectOption>>,
    account: Signal<String>,
    all_dates: Signal<bool>,
    kinds: impl IntoElement,
) -> impl IntoElement {
    view()
        .child(
            ui::app_sheet()
                .open(move || Some(tools_open.get()))
                .on_open_change(move |e: &SheetEvent| {
                    if let SheetEvent::OpenChange(next, _) = e {
                        tools_open.set(*next);
                    }
                })
                .child(
                    view()
                        .p_5()
                        .pb_safe_area_plus(px(20.0))
                        .gap_2()
                        .bg(move || theme().background)
                        .child(text("流水管理").text_lg().font_weight(FontWeight::SEMIBOLD))
                        .child(fui::action("筛选流水", "ledger-filters", move || {
                            tools_open.set(false);
                            filters_open.set(true);
                        }))
                        .children(
                            [
                                ("导入账单", "/activity/import", "activity-import"),
                                ("账户对账", "/activity/reconcile", "activity-reconcile"),
                                ("月结复核", "/activity/close", "activity-close"),
                            ]
                            .map(move |(label, path, id)| {
                                fui::action(label, id, move || {
                                    tools_open.set(false);
                                    fui::navigate(path);
                                })
                            }),
                        )
                        .child(fui::action("取消", "activity-tools-cancel", move || {
                            tools_open.set(false)
                        })),
                ),
        )
        .child(
            ui::app_sheet()
                .open(move || Some(filters_open.get()))
                .on_open_change(move |e: &SheetEvent| {
                    if let SheetEvent::OpenChange(next, _) = e {
                        filters_open.set(*next);
                    }
                })
                .child(
                    view()
                        .p_5()
                        .pb_safe_area_plus(px(20.0))
                        .gap_4()
                        .bg(move || theme().background)
                        .child(text("筛选流水").text_lg().font_weight(FontWeight::SEMIBOLD))
                        .child(kinds)
                        .child(view().bg(move || theme().card).rounded(px(12.0)).child(
                            ui::select_field("账户", account_options, account, "ledger-account"),
                        ))
                        .child(
                            view()
                                .flex_row()
                                .gap_2()
                                .child(
                                    ui::choice_button(
                                        "所选月份",
                                        move || !all_dates.get(),
                                        move || all_dates.set(false),
                                        "ledger-month-only",
                                    )
                                    .flex_1(),
                                )
                                .child(
                                    ui::choice_button(
                                        "全部时间",
                                        move || all_dates.get(),
                                        move || all_dates.set(true),
                                        "ledger-all-dates",
                                    )
                                    .flex_1(),
                                ),
                        )
                        .child(ui::primary_button(
                            "完成",
                            move || filters_open.set(false),
                            "ledger-filters-done",
                            None,
                        )),
                ),
        )
}
