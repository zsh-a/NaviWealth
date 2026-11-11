//! NaviWealth nsh client: app root, tab shell and screen wiring.

mod ai;
mod bridge;
mod domains;
pub mod finance;
mod native_files;
mod screens;
mod state;
mod ui;

use domains::{DomainsState, OPTIONAL_DOMAINS};
use nsh_base::{tab, tabs, theme};
use nsh_core::prelude::*;

pub use state::{Services, enable_test_mode, is_test_mode};

#[derive(Clone, Copy)]
pub(crate) struct ShellTab(pub Signal<u8>);

#[derive(Clone, Copy)]
pub(crate) struct FinanceNavigation {
    pub account: Signal<String>,
    pub all_dates: Signal<bool>,
}

#[native_module("naviwealth/native")]
fn native(registry: &mut Registry) {
    registry.register::<App>();
}

/// The application's root component: the base four tabs (账户 / 账本 /
/// 智能 / 设置) plus one tab per enabled opt-in domain.
#[component]
pub fn App() -> impl IntoElement {
    startup(state::Services::try_shared)
}

fn startup(
    initialize: impl Fn() -> Result<std::sync::Arc<Services>, String> + 'static,
) -> impl IntoElement {
    let attempt = signal(0_u64);
    view()
        .flex_1()
        .bg(move || theme().background)
        .text_color(move || theme().foreground)
        .child(dynamic(move || {
            attempt.get();
            match initialize() {
                Ok(services) => app_shell(services).into_element(),
                Err(_) => view()
                    .flex_1()
                    .p_safe_area()
                    .child(
                        view()
                            .p_6()
                            .gap_4()
                            .child(text("无法打开本地数据").text_xl())
                            .child(
                                text(
                                    "请检查设备可用空间，然后重试。若仍无法启动，请重新打开应用。",
                                )
                                .text_base()
                                .text_color(move || theme().muted_foreground),
                            )
                            .child(
                                ui::primary_button(
                                    "重试",
                                    move || attempt.update(|n| *n += 1),
                                    "startup-retry",
                                    None,
                                )
                                .min_h(px(48.0)),
                            ),
                    )
                    .test_id("startup-error")
                    .into_element(),
            }
        }))
}

fn app_shell(services: std::sync::Arc<Services>) -> impl IntoElement {
    let enabled_domains = services.enabled_domain_keys();
    provide_context(services);

    let data_version: Signal<u64> = signal(0);
    provide_context(state::DataVersion(data_version));

    // The enabled opt-in domains, seeded from Services (which loaded the
    // settings KV at init).
    let domains_signal: Signal<Vec<&'static str>> = signal(enabled_domains);
    provide_context(DomainsState(domains_signal));

    let tab: Signal<u8> = signal(1);
    provide_context(ShellTab(tab));
    provide_context(FinanceNavigation {
        account: signal(String::new()),
        all_dates: signal(false),
    });
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
                .pt_safe_area()
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
                ))
                .child(when(
                    move || {
                        tab.get() == domains::KNOWLEDGE.tab_index
                            && domains_signal.get().contains(&"knowledge")
                    },
                    move || screens::knowledge::KnowledgeScreen(),
                ))
                .child(when(
                    move || {
                        tab.get() == domains::EXECUTION.tab_index
                            && domains_signal.get().contains(&"execution")
                    },
                    move || screens::execution::ExecutionScreen(),
                ))
                .child(when(
                    move || {
                        tab.get() == domains::HEALTH.tab_index
                            && domains_signal.get().contains(&"health")
                    },
                    move || screens::health::HealthScreen(),
                )),
        )
        .child(tab_bar(tab, domains_signal))
}

fn tab_item(
    index: u8,
    label: &'static str,
    test_id: &'static str,
    selected: Signal<u8>,
) -> impl Element {
    let is_selected = move || selected.get() == index;
    tab()
        .selected(is_selected)
        .on_press(move |_: &()| selected.set(index))
        .flex_1()
        .min_h(px(64.0))
        .py_2()
        .items_center()
        .justify_center()
        .child(
            view()
                .test_id(test_id)
                .items_center()
                .gap_1()
                .child(
                    ui::icon(match index {
                        0 => ui::Icon::Wallet,
                        1 | 4 | 5 => ui::Icon::Ledger,
                        2 => ui::Icon::Chat,
                        _ => ui::Icon::Settings,
                    })
                    .text_color(move || {
                        if is_selected() {
                            theme().primary
                        } else {
                            theme().muted_foreground
                        }
                    }),
                )
                .child(text(label).text_sm().text_color(move || {
                    if is_selected() {
                        theme().primary
                    } else {
                        theme().muted_foreground
                    }
                })),
        )
}

fn tab_bar(selected: Signal<u8>, domains: Signal<Vec<&'static str>>) -> impl IntoElement {
    // Opt-in tabs append after the base four, so base indices stay stable
    // for tests and shortcuts. Each is a reactive region so the tab list
    // follows the settings switches.
    view()
        .pb_safe_area_plus(px(6.0))
        .border_t_1()
        .border_color(move || theme().border)
        .bg(move || theme().card)
        .child(
            tabs()
                .flex_row()
                .p_1()
                .child(tab_item(1, "流水", "tab-ledger", selected))
                .child(tab_item(0, "账户", "tab-accounts", selected))
                .child(tab_item(2, "智能", "tab-chat", selected))
                .child(when(
                    move || domains.get().contains(&"knowledge"),
                    move || {
                        tab_item(
                            OPTIONAL_DOMAINS[0].tab_index,
                            OPTIONAL_DOMAINS[0].tab_label,
                            OPTIONAL_DOMAINS[0].tab_test_id,
                            selected,
                        )
                    },
                ))
                .child(when(
                    move || domains.get().contains(&"execution"),
                    move || {
                        tab_item(
                            OPTIONAL_DOMAINS[1].tab_index,
                            OPTIONAL_DOMAINS[1].tab_label,
                            OPTIONAL_DOMAINS[1].tab_test_id,
                            selected,
                        )
                    },
                ))
                .child(when(
                    move || domains.get().contains(&"health"),
                    move || {
                        tab_item(
                            OPTIONAL_DOMAINS[2].tab_index,
                            OPTIONAL_DOMAINS[2].tab_label,
                            OPTIONAL_DOMAINS[2].tab_test_id,
                            selected,
                        )
                    },
                ))
                .child(tab_item(3, "设置", "tab-settings", selected)),
        )
}

#[cfg(test)]
mod startup_tests {
    use super::*;
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;
    use std::cell::Cell;

    #[component]
    fn RecoverableStartup() -> impl IntoElement {
        enable_test_mode();
        let attempts = Cell::new(0);
        startup(move || {
            attempts.set(attempts.get() + 1);
            if attempts.get() == 1 {
                Err("private initialization detail".to_owned())
            } else {
                Services::try_shared()
            }
        })
    }

    #[test]
    fn startup_failure_renders_and_retry_mounts_shell() {
        let mut app = Headless::start(EngineConfig::new(Root::of::<RecoverableStartup>())).unwrap();
        app.wait_for("id:startup-error").unwrap();
        app.wait_for("text:无法打开本地数据").unwrap();
        app.press("id:startup-retry").unwrap();
        app.wait_for("id:tab-accounts").unwrap();
        app.wait_for_gone("id:startup-error", std::time::Duration::from_secs(2))
            .unwrap();
    }
}
