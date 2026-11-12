//! Task-first Finance planning routes. Shared native forms own dirty protection,
//! save feedback and keyboard safe areas; these pages own economic intent.
use crate::{finance_ui as fui, state::Services, ui};
use naviwealth_finance::planning::*;
use nsh_base::theme;
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::future::Future;

#[path = "planning_ui/cash.rs"]
mod cash;
#[path = "planning_ui/investing.rs"]
mod investing;
#[path = "planning_ui/portfolios.rs"]
mod portfolios;

#[path = "planning_ui/loader.rs"]
mod loader;
use loader::{load, load_form, load_mode};
type CommandFuture = std::pin::Pin<Box<dyn Future<Output = Result<(), String>>>>;

fn note(s: impl Into<String>) -> AnyElement {
    text(s.into())
        .text_sm()
        .text_color(move || theme().muted_foreground)
        .into_element()
}
fn metric(label: impl Into<String>, value: String, caption: String) -> AnyElement {
    fui::metric(label.into(), value, caption)
}
fn amount(value: Decimal, currency: &str) -> String {
    format!("{} {}", ui::money_for(value, currency), currency)
}
fn today() -> i64 {
    lifeos::ids::now_secs()
}
fn month() -> String {
    chrono::Local::now().format("%Y-%m").to_string()
}
fn nav(label: &'static str, path: impl Into<String>, id: &'static str) -> AnyElement {
    let path = path.into();
    fui::action(label, id, move || fui::navigate(path.clone()))
}
fn command(
    label: &'static str,
    id: &'static str,
    success: &'static str,
    run: impl Fn() -> CommandFuture + 'static,
) -> AnyElement {
    let busy = signal(false);
    fui::action(label, id, move || {
        if busy.get() {
            return;
        }
        busy.set(true);
        let future = run();
        spawn(async move {
            match future.await {
                Ok(()) => {
                    fui::notice(success);
                    fui::refresh();
                }
                Err(e) => fui::notice(e),
            }
            busy.set(false);
        });
    })
}
fn remove_page(title: &'static str, kind: PlanKind, id: String, destination: String) -> AnyElement {
    fui::form(
        title,
        vec![
            fui::Field::choice(
                "confirm",
                "确认操作",
                "keep",
                vec![
                    ("keep".into(), "保留计划".into()),
                    ("remove".into(), "删除此计划".into()),
                ],
            )
            .help("已有处理记录的计划须先撤销关联；周期计划可暂停保留历史。"),
        ],
        move |values| {
            let id = id.clone();
            let destination = destination.clone();
            Box::pin(async move {
                if fui::required(&values, "confirm", "确认操作")? != "remove" {
                    return Err("请选择删除，或返回保留计划".into());
                }
                fui::services().remove_finance_plan(kind, id).await?;
                Ok(Some(destination))
            })
        },
    )
}
fn error_page() -> AnyElement {
    fui::page(
        "计划不可用",
        view()
            .gap_3()
            .child(note("此计划可能已删除，返回列表选择现有计划。"))
            .child(nav("查看规划", "/plan", "plan-not-found"))
            .into_element(),
    )
}
pub fn render(path: String) -> AnyElement {
    let clean = path.split('?').next().unwrap_or("/plan");
    let parts = clean
        .trim_matches('/')
        .split('/')
        .map(str::to_owned)
        .collect::<Vec<_>>();
    match parts.get(1).map(String::as_str) {
        None => hub(),
        Some("budgets") | Some("recurring") | Some("runway") | Some("liabilities") => {
            cash::render(parts)
        }
        Some("goals") | Some("dca") | Some("fire") => investing::render(parts),
        Some("portfolios") => portfolios::render(parts),
        _ => error_page(),
    }
}
#[path = "planning_ui/hub.rs"]
mod hub;
use hub::hub;

#[cfg(test)]
mod draft_tests {
    use super::*;
    use crate::finance_ui::{Feedback, LeaveGuard, Navigation};
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    fn draft_harness(path: String) -> AnyElement {
        provide_context(Services::shared());
        let version = signal(0_u64);
        provide_context(crate::state::DataVersion(version));
        provide_context(Navigation(signal(vec![path.clone()])));
        provide_context(Feedback(signal(String::new())));
        provide_context(LeaveGuard(signal(None)));
        view()
            .flex_1()
            .child(fui::action(
                "模拟外部财务写入",
                "planning-external-refresh",
                move || version.update(|v| *v += 1),
            ))
            .child(text(move || format!("外部数据版本 {}", version.get())))
            .child(render(path))
            .into_element()
    }
    #[component]
    fn BudgetDraftHarness() -> impl IntoElement {
        draft_harness("/plan/budgets/new".into())
    }
    #[component]
    fn PortfolioDraftHarness() -> impl IntoElement {
        let services = Services::shared();
        let plan = services
            .runtime
            .block_on(services.finance_portfolio_plans())
            .unwrap()
            .into_iter()
            .find(|p| p.data.name == "草稿保护原生配置")
            .expect("seeded portfolio");
        draft_harness(format!(
            "/wealth/portfolios/{}/portfolio/{}/edit",
            plan.id, plan.data.portfolios[0].id
        ))
    }
    fn assert_draft_and_guard_after_external_refresh(app: &mut Headless, field: &str, draft: &str) {
        app.wait_for(&format!("id:{field}")).unwrap();
        app.clear(&format!("id:{field}")).unwrap();
        app.type_text(&format!("id:{field}"), draft).unwrap();
        app.press("id:planning-external-refresh").unwrap();
        app.wait_for("text:外部数据版本 1").unwrap();
        app.wait_for(&format!("id:{field}")).unwrap();
        app.wait_for(&format!("text:{draft}")).unwrap();
        app.press("id:finance-form-cancel").unwrap();
        app.wait_for("text:放弃未保存的修改？").unwrap();
        app.press("id:finance-form-keep").unwrap();
        app.wait_for(&format!("text:{draft}")).unwrap();
        app.wait_for("id:finance-form-save").unwrap();
    }
    #[test]
    fn budget_form_keeps_amount_and_dirty_guard_when_external_data_changes() {
        crate::enable_test_mode();
        let mut app = Headless::start(EngineConfig::new(Root::of::<BudgetDraftHarness>())).unwrap();
        assert_draft_and_guard_after_external_refresh(&mut app, "limit", "432.10");
    }
    #[test]
    fn portfolio_node_editor_keeps_authored_name_and_guard_when_external_data_changes() {
        crate::enable_test_mode();
        let services = Services::shared();
        services
            .runtime
            .block_on(services.save_finance_portfolio_plan(
                None,
                InvestmentPlan {
                    name: "草稿保护原生配置".into(),
                    currency: "CNY".into(),
                    portfolios: vec![Portfolio {
                        id: lifeos::ids::new_id(),
                        name: "初始用途".into(),
                        target_bps: 10000,
                        sleeves: vec![Sleeve {
                            id: lifeos::ids::new_id(),
                            name: "初始策略".into(),
                            target_bps: 10000,
                            tolerance_bps: 500,
                            targets: vec![AssetTarget {
                                asset_id: None,
                                weight_bps: 10000,
                            }],
                        }],
                    }],
                    inclusions: vec![],
                },
                today(),
            ))
            .unwrap();
        let mut app =
            Headless::start(EngineConfig::new(Root::of::<PortfolioDraftHarness>())).unwrap();
        assert_draft_and_guard_after_external_refresh(&mut app, "name", "保留我的配置草稿");
    }
}
