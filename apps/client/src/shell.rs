use super::*;

pub(super) fn workspace_header(selected: Signal<u8>) -> AnyElement {
    let intent = use_context::<CaptureIntent>().expect("capture intent");
    view()
        .flex_row()
        .items_center()
        .px(move || px(ui::page_px()()))
        .min_h(move || px(ui::token("header-height")))
        .gap_1()
        .bg(move || theme().background)
        .child(
            text(move || match selected.get() {
                0 => "今日",
                1 => "流水",
                2 => "财富",
                _ => "规划",
            })
            .flex_1()
            .text_size(move || px(ui::token("type-page")))
            .font_weight(FontWeight::SEMIBOLD),
        )
        .child(when(
            move || selected.get() < 2,
            move || {
                ui::toolbar_action(ui::Icon::Plus, "记一笔", "open-record", move || {
                    intent.0.update(|v| *v += 1)
                })
            },
        ))
        .child(
            nsh_base::menu()
                .trigger(
                    view()
                        .test_id("workspace-more")
                        .size(px(44.0))
                        .items_center()
                        .justify_center()
                        .rounded_lg()
                        .child(ui::icon(ui::Icon::More)),
                )
                .popup_style(|s| {
                    s.min_w(px(200.0))
                        .p_1()
                        .bg(move || theme().popover)
                        .rounded_lg()
                        .border_1()
                        .border_color(move || theme().border)
                        .shadow_lg()
                })
                .children(
                    [
                        ("切换工作空间", "domain-switcher", "/domains"),
                        ("财务助手", "tab-chat", "/assistant"),
                        ("设置", "tab-settings", "/settings"),
                    ]
                    .map(|(label, id, path)| {
                        ui::NativeControl(
                            nsh_base::menu_item()
                                .accessibility_label(label)
                                .on_select(move |_: &()| finance_ui::navigate(path)),
                        )
                        .test_id(id)
                        .min_h(px(44.0))
                        .px_3()
                        .rounded_md()
                        .justify_center()
                        .hover(|s| s.bg(move || theme().accent))
                        .child(text(label).text_base())
                    }),
                ),
        )
        .into_element()
}

fn tab_item(
    index: u8,
    label: &'static str,
    id: &'static str,
    selected: Signal<u8>,
) -> impl Element {
    tab()
        .selected(move || selected.get() == index)
        .on_press(move |_: &()| {
            dismiss_keyboard();
            finance_ui::clear_acknowledgement();
            selected.set(index);
        })
        .flex_1()
        .min_h(move || px(ui::token("tab-height")))
        .items_center()
        .justify_center()
        .child(
            view()
                .test_id(id)
                .items_center()
                .gap_1()
                .child(
                    // The short selection line replaces a filled pill.
                    view()
                        .w(px(18.0))
                        .h(px(2.0))
                        .rounded(px(1.0))
                        .bg(move || theme().ring)
                        .opacity(move || {
                            if selected.get() == index {
                                1.0_f32
                            } else {
                                0.0_f32
                            }
                        }),
                )
                .child(
                    ui::icon(match index {
                        0 => ui::Icon::Today,
                        1 => ui::Icon::Ledger,
                        2 => ui::Icon::Wallet,
                        _ => ui::Icon::Plan,
                    })
                    .text_color(move || {
                        if selected.get() == index {
                            theme().ring
                        } else {
                            theme().muted_foreground
                        }
                    }),
                )
                .child(
                    text(label)
                        .text_size(move || px(crate::ui::token("type-caption")))
                        .font_weight(FontWeight::MEDIUM)
                        .text_color(move || {
                            if selected.get() == index {
                                theme().ring
                            } else {
                                theme().muted_foreground
                            }
                        }),
                ),
        )
}
pub(super) fn tab_bar(selected: Signal<u8>) -> impl IntoElement {
    view()
        .pb_safe_area_plus(px(2.0))
        .bg(move || theme().background)
        .child(
            tabs()
                .flex_row()
                .child(tab_item(0, "今日", "tab-today", selected))
                .child(tab_item(1, "流水", "tab-ledger", selected))
                .child(tab_item(2, "财富", "tab-accounts", selected))
                .child(tab_item(3, "规划", "tab-plan", selected)),
        )
}
