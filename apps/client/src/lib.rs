//! NaviWealth nsh client: app root, tab shell and screen wiring.

mod ai;
mod bridge;
mod domains;
pub mod finance;
mod finance_operations;
mod finance_planning;
mod finance_ui;
mod finance_wealth;
mod native_files;
mod screens;
mod state;
mod ui;

use domains::DomainsState;
use nsh_base::{tab, tabs, theme};
use nsh_core::prelude::*;

pub use state::{Services, enable_test_mode, is_test_mode};

#[derive(Clone, Copy)]
pub(crate) struct ShellTab(pub Signal<u8>);

/// Bumped by the workspace capture button; the Today and Ledger panes open
/// their own editor in place when their tab is the selected one.
#[derive(Clone, Copy)]
pub(crate) struct CaptureIntent(pub Signal<u64>);

#[derive(Clone, Copy)]
pub(crate) struct FinanceNavigation {
    pub account: Signal<String>,
    pub all_dates: Signal<bool>,
}

#[native_module("naviwealth/native")]
fn native(registry: &mut Registry) {
    registry.register::<App>().assets(assets!());
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
    provide_context(finance_ui::PageKind::Root);
    let enabled_domains = services.enabled_domain_keys();
    provide_context(services);
    provide_context(state::DataVersion(signal(0)));
    let domains_signal = signal(enabled_domains);
    provide_context(DomainsState(domains_signal));
    let selected = signal(1_u8);
    provide_context(ShellTab(selected));
    provide_context(FinanceNavigation {
        account: signal(String::new()),
        all_dates: signal(false),
    });
    let routes = signal(Vec::<String>::new());
    provide_context(finance_ui::Navigation(routes));
    let feedback = signal(String::new());
    provide_context(finance_ui::Feedback(feedback));
    provide_context(finance_ui::ChangedFact(signal(None)));
    provide_context(finance_ui::UndoOffer {
        pending: signal(None),
        busy: signal(false),
        error: signal(String::new()),
    });
    provide_context(CaptureIntent(signal(0)));
    effect(move || {
        let current = feedback.get();
        if !current.is_empty() {
            set_timeout(std::time::Duration::from_secs(8), move || {
                if feedback.get() == current {
                    feedback.set(String::new());
                }
            });
        }
    });
    nsh_base::nav_stack()
        .flex_1()
        .child(
            nsh_base::nav_page()
                .key("finance-home")
                .header_visible(false)
                .child(
                    view()
                        .flex_1()
                        .pt_safe_area()
                        .bg(move || theme().background)
                        .child(workspace_header(selected))
                        .child(
                            view()
                                .flex_1()
                                .child(
                                    view()
                                        .flex_1()
                                        .style_when(move || selected.get() != 0, |s| s.hidden())
                                        .child(screens::today::render()),
                                )
                                .child(
                                    view()
                                        .flex_1()
                                        .style_when(move || selected.get() != 1, |s| s.hidden())
                                        .child(screens::ledger::LedgerScreen()),
                                )
                                .child(
                                    view()
                                        .flex_1()
                                        .style_when(move || selected.get() != 2, |s| s.hidden())
                                        .child(screens::wealth::render("/wealth".into())),
                                )
                                .child(
                                    view()
                                        .flex_1()
                                        .style_when(move || selected.get() != 3, |s| s.hidden())
                                        .child(screens::plan::render("/plan".into())),
                                ),
                        )
                        .child(tab_bar(selected))
                        .child(finance_ui::feedback_overlay(62.0))
                        .child(finance_ui::undo_pill(62.0)),
                ),
        )
        .child(each(
            move || routes.get(),
            |route: &String| route.clone(),
            move |route: ReadSignal<String>, _| {
                provide_context(finance_ui::PageKind::Detail);
                let guard = signal(None::<finance_ui::GuardCallback>);
                provide_context(finance_ui::LeaveGuard(guard));
                let back_path = route.get();
                let dismiss_path = back_path.clone();
                nsh_base::nav_page()
                    .key(route.get())
                    .header_visible(false)
                    // A form owns Back for its whole lifetime. Native Back uses
                    // cached props and cannot synchronously await a dirty veto.
                    .pop_on_back(move || guard.get().is_none())
                    .pop_on_swipe(move || guard.get().is_none())
                    .animation(move || {
                        if reduce_motion() {
                            ScreenAnimation::None
                        } else {
                            ScreenAnimation::Default
                        }
                    })
                    .on_back_press(move || {
                        if let Some(guard) = guard.get()
                            && !(guard.check)()
                        {
                            finance_ui::dismiss_route(&back_path);
                        }
                    })
                    .on_dismiss(move || finance_ui::dismiss_route(&dismiss_path))
                    .child(
                        view()
                            .flex_1()
                            .pt_safe_area()
                            .bg(move || theme().background)
                            .child(render_route(route.get()))
                            .child(finance_ui::undo_pill(16.0)),
                    )
            },
        ))
}
/// The top workspace: one full-width quiet bar owning capture. The dock rule
/// keeps 记一笔 on the two capture surfaces (Today / Ledger) and out of the
/// way on Wealth / Plan.
#[path = "shell.rs"]
mod shell;
use shell::{tab_bar, workspace_header};

fn render_route(path: String) -> AnyElement {
    if path.starts_with("/wealth/accounts") {
        return screens::accounts::account_route(path);
    }
    if path.starts_with("/plan")
        || path.starts_with("/wealth/liabilities")
        || path.starts_with("/wealth/portfolios")
    {
        return screens::plan::render(path);
    }
    if path.starts_with("/wealth") {
        return screens::wealth::render(path);
    }
    if path.starts_with("/activity/import")
        || path.starts_with("/activity/reconcile")
        || path.starts_with("/activity/close")
        || path.starts_with("/today/inbox")
    {
        return screens::operations::render(path);
    }
    if let Some(id) = path.strip_prefix("/activity/entry/") {
        return screens::ledger::entry_route(id.into());
    }
    match path.as_str() {
        "/activity/new" => screens::ledger::capture_route(),
        "/settings" => view()
            .flex_1()
            .child(route_header("设置"))
            .child(screens::settings::SettingsScreen())
            .into_element(),
        "/assistant" => view()
            .flex_1()
            .child(route_header("助手"))
            .child(screens::chat::ChatScreen())
            .into_element(),
        "/domains" => domain_picker(),
        "/domains/knowledge" => view()
            .flex_1()
            .child(route_header("知识"))
            .child(screens::knowledge::KnowledgeScreen())
            .into_element(),
        "/domains/execution" => view()
            .flex_1()
            .child(route_header("执行"))
            .child(screens::execution::ExecutionScreen())
            .into_element(),
        "/domains/health" => view()
            .flex_1()
            .child(route_header("健康"))
            .child(screens::health::HealthScreen())
            .into_element(),
        _ => finance_ui::page("页面不可用", text("请返回并选择现有财务记录。")),
    }
}
fn route_header(title: &'static str) -> AnyElement {
    view()
        .flex_row()
        .items_center()
        .px_4()
        .min_h(px(52.0))
        .child(ui::icon_button(
            ui::Icon::Back,
            "返回",
            "finance-back",
            finance_ui::back,
        ))
        .child(text(title).text_lg().font_weight(FontWeight::SEMIBOLD))
        .into_element()
}
fn domain_picker() -> AnyElement {
    let enabled = use_context::<DomainsState>().expect("domains").0;
    finance_ui::page(
        "工作空间",
        view()
            .child(finance_ui::row(
                "FinanceOS".into(),
                "财务 · 始终开启".into(),
                "打开".into(),
                "domain-finance".into(),
                finance_ui::back,
            ))
            .child(each(
                move || enabled.get(),
                |key: &&'static str| (*key).to_owned(),
                move |key: ReadSignal<&'static str>, _| {
                    let spec = domains::OPTIONAL_DOMAINS
                        .iter()
                        .find(|s| s.key == key.get());
                    let title = spec.map(|s| s.tab_label).unwrap_or("工作空间");
                    finance_ui::row(
                        title.into(),
                        "已启用".into(),
                        "打开".into(),
                        format!("domain-{}", key.get()),
                        move || finance_ui::navigate(format!("/domains/{}", key.get())),
                    )
                },
            ))
            .child(finance_ui::action(
                "管理工作空间",
                "domain-settings",
                || finance_ui::navigate("/settings"),
            )),
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
