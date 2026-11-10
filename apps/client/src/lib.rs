//! NaviWealth nsh client: app root, tab shell and screen wiring.

mod ai;
mod bridge;
mod screens;
mod state;
mod ui;

use nsh_base::{tab, tabs, theme};
use nsh_core::prelude::*;

pub use state::{Services, enable_test_mode, is_test_mode};

#[native_module("naviwealth/native")]
fn native(registry: &mut Registry) {
    registry.register::<App>();
}

/// The application's root component: the four-tab shell (账户 / 账本 /
/// 智能 / 设置).
#[component]
pub fn App() -> impl IntoElement {
    let services = state::Services::shared();
    provide_context(services);

    let data_version: Signal<u64> = signal(0);
    provide_context(state::DataVersion(data_version));

    let tab: Signal<u8> = signal(0);
    // The closures stay: the screen fns' return types satisfy IntoElement,
    // not IntoElements, so the fn items cannot be passed directly.
    #[allow(clippy::redundant_closure)]

    view()
        .flex_1()
        .bg(move || theme().background)
        .text_color(move || theme().foreground)
        .child(
            view()
                .flex_1()
                .p_safe_area()
                .child(when(
                    move || tab.get() == 0,
                    move || screens::accounts::AccountsScreen(),
                ))
                .child(when(
                    move || tab.get() == 1,
                    move || screens::ledger::LedgerScreen(),
                ))
                .child(when(
                    move || tab.get() == 2,
                    move || screens::chat::ChatScreen(),
                ))
                .child(when(
                    move || tab.get() == 3,
                    move || screens::settings::SettingsScreen(),
                )),
        )
        .child(tab_bar(tab))
}

fn tab_item(
    index: u8,
    label: &'static str,
    test_id: &'static str,
    selected: Signal<u8>,
) -> impl IntoElement {
    let is_selected = move || selected.get() == index;
    tab()
        .selected(is_selected)
        .on_press(move |_: &()| selected.set(index))
        .flex_1()
        .py_2()
        .items_center()
        .justify_center()
        .child(
            view()
                .test_id(test_id)
                .items_center()
                .child(text(label).text_sm().text_color(move || {
                    if is_selected() {
                        theme().primary
                    } else {
                        theme().muted_foreground
                    }
                })),
        )
}

fn tab_bar(selected: Signal<u8>) -> impl IntoElement {
    view()
        .border_t_1()
        .border_color(move || theme().border)
        .bg(move || theme().card)
        .child(
            tabs()
                .flex_row()
                .p_1()
                .child(tab_item(0, "账户", "tab-accounts", selected))
                .child(tab_item(1, "账本", "tab-ledger", selected))
                .child(tab_item(2, "智能", "tab-chat", selected))
                .child(tab_item(3, "设置", "tab-settings", selected)),
        )
}
