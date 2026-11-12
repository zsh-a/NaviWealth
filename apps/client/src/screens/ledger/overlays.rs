use super::*;
pub(super) fn overlays(
    filters_open: Signal<bool>,
    account_options: Signal<Vec<ui::SelectOption>>,
    account: Signal<String>,
    all_dates: Signal<bool>,
    kinds: impl IntoElement,
) -> impl IntoElement {
    view().child(
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

pub(super) fn tools_menu(filters_open: Signal<bool>) -> impl Element {
    nsh_base::menu()
        .trigger(
            view()
                .test_id("activity-tools")
                .size(px(44.0))
                .items_center()
                .justify_center()
                .child(ui::icon(ui::Icon::More)),
        )
        .popup_style(|s| {
            s.min_w(px(208.0))
                .p_1()
                .bg(move || theme().popover)
                .rounded_lg()
                .border_1()
                .border_color(move || theme().border)
                .shadow_lg()
        })
        .child(
            ui::NativeControl(
                nsh_base::menu_item().on_select(move |_: &()| filters_open.set(true)),
            )
            .test_id("ledger-filters")
            .min_h(px(44.0))
            .px_3()
            .justify_center()
            .hover(|s| s.bg(move || theme().accent))
            .child(text("筛选流水").text_base()),
        )
        .children(
            [
                ("导入账单", "/activity/import", "activity-import"),
                ("账户对账", "/activity/reconcile", "activity-reconcile"),
                ("月结复核", "/activity/close", "activity-close"),
            ]
            .map(|(label, path, id)| {
                ui::NativeControl(
                    nsh_base::menu_item().on_select(move |_: &()| fui::navigate(path)),
                )
                .test_id(id)
                .min_h(px(44.0))
                .px_3()
                .justify_center()
                .hover(|s| s.bg(move || theme().accent))
                .child(text(label).text_base())
            }),
        )
        .child(
            ui::NativeControl(nsh_base::menu_item())
                .test_id("activity-tools-cancel")
                .min_h(px(44.0))
                .px_3()
                .justify_center()
                .child(ui::quiet_text("取消")),
        )
}
