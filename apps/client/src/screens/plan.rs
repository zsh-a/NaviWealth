//! Task-first Finance planning routes. Shared native forms own dirty protection,
//! save feedback and keyboard safe areas; these pages own economic intent.
use crate::{finance_ui as fui, state::Services, ui};
use naviwealth_finance::planning::*;
use nsh_base::theme;
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::{future::Future, pin::Pin, rc::Rc, sync::Arc};

#[path = "planning_ui/cash.rs"]
mod cash;
#[path = "planning_ui/investing.rs"]
mod investing;
#[path = "planning_ui/portfolios.rs"]
mod portfolios;

type LoadFuture<T> = Pin<Box<dyn Future<Output = Result<T, String>>>>;
type CommandFuture = Pin<Box<dyn Future<Output = Result<(), String>>>>;
fn load<T: Clone + PartialEq + 'static>(
    title: &'static str,
    fetch: impl Fn(Arc<Services>) -> LoadFuture<T> + 'static,
    draw: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    load_mode(title, false, fetch, draw)
}
/// Load a form's entry snapshot once, retaining explicit retry on read failure.
/// External writes refresh read views but never replace an authored draft.
fn load_form<T: Clone + PartialEq + 'static>(
    title: &'static str,
    fetch: impl Fn(Arc<Services>) -> LoadFuture<T> + 'static,
    draw: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    load_mode(title, true, fetch, draw)
}
fn load_mode<T: Clone + PartialEq + 'static>(
    title: &'static str,
    freeze_draft: bool,
    fetch: impl Fn(Arc<Services>) -> LoadFuture<T> + 'static,
    draw: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    let data: Signal<Option<T>> = signal(None);
    let error = signal(String::new());
    let loading = signal(true);
    let retry = signal(0_u64);
    let generation = Rc::new(std::cell::Cell::new(0_u64));
    let version = use_context::<crate::state::DataVersion>()
        .expect("data version")
        .0;
    let fetch = Rc::new(fetch);
    let services = fui::services();
    effect(move || {
        if !freeze_draft {
            version.get();
        }
        retry.get();
        let n = generation.get() + 1;
        generation.set(n);
        let generation = generation.clone();
        let future = fetch(services.clone());
        loading.set(true);
        spawn(async move {
            let result = future.await;
            if generation.get() != n {
                return;
            }
            match result {
                Ok(value) => {
                    data.set(Some(value));
                    error.set(String::new());
                }
                Err(e) => error.set(e),
            }
            loading.set(false);
        });
    });
    dynamic(move || {
        if loading.get() {
            return fui::page(
                title,
                text("正在读取本地财务资料…").text_sm().into_element(),
            );
        }
        if !error.get().is_empty() {
            return fui::page(
                title,
                view()
                    .gap_3()
                    .child(text(error.get()).text_color(move || theme().destructive))
                    .child(fui::action("重新读取", "plan-load-retry", move || {
                        retry.update(|n| *n += 1)
                    }))
                    .into_element(),
            );
        }
        match data.get() {
            Some(value) => draw(value),
            None => fui::page(title, note("暂无资料，请重新读取。")),
        }
    })
    .into_element()
}
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
    format!("{} {}", ui::money(value), currency)
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
fn hub() -> AnyElement {
    load(
        "规划",
        |s| {
            Box::pin(async move {
                let (from, until) = month_bounds(&month()).map_err(|e| e.to_string())?;
                let (actions, goals, plans) = tokio::join!(
                    s.finance_planning_actions(from, until),
                    s.finance_goals(),
                    s.finance_portfolio_plans()
                );
                Ok((actions?, goals?, plans?))
            })
        },
        |(actions, goals, plans)| {
            let due = actions
                .iter()
                .filter(|a| a.state == OccurrenceState::Due && a.due <= today())
                .count();
            let mut body = view().gap_3().child(
                view()
                    .gap_1()
                    .child(
                        text(format!("本月待处理 {due} 项"))
                            .text_base()
                            .font_weight(FontWeight::MEDIUM)
                            .tabular_nums(),
                    )
                    .child(note("到期安排经你确认后计入流水。")),
            );
            body = body.child(fui::section(
                "现金安全",
                view()
                    .child(fui::row(
                        "分类预算".into(),
                        "本月额度、已花与对应流水".into(),
                        "查看".into(),
                        "plan-budgets".into(),
                        || fui::navigate("/plan/budgets"),
                    ))
                    .child(fui::row(
                        "周期收支".into(),
                        "到期确认、跳过与暂停".into(),
                        "查看".into(),
                        "plan-recurring".into(),
                        || fui::navigate("/plan/recurring"),
                    ))
                    .child(fui::row(
                        "现金跑道".into(),
                        "30 / 90 天计划与情景比较".into(),
                        "模拟".into(),
                        "plan-runway".into(),
                        || fui::navigate("/plan/runway"),
                    ))
                    .child(fui::row(
                        "贷款与还款".into(),
                        "本金、利息、还款账户和撤销".into(),
                        "管理".into(),
                        "plan-liabilities".into(),
                        || fui::navigate("/wealth/liabilities"),
                    ))
                    .into_element(),
            ));
            body = body.child(fui::section(
                "目标与投入",
                view()
                    .child(fui::row(
                        "储蓄目标".into(),
                        format!("{} 个目标 · 进度只来自真实投入", goals.len()),
                        "查看".into(),
                        "plan-goals".into(),
                        || fui::navigate("/plan/goals"),
                    ))
                    .child(fui::row(
                        "定投计划".into(),
                        "到期后关联手动买入成交".into(),
                        "查看".into(),
                        "plan-dca".into(),
                        || fui::navigate("/plan/dca"),
                    ))
                    .child(fui::row(
                        "FIRE 规划".into(),
                        "明确提取率、投入与回报假设".into(),
                        "计算".into(),
                        "plan-fire".into(),
                        || fui::navigate("/plan/fire"),
                    ))
                    .into_element(),
            ));
            body = body.child(fui::section(
                "资本配置",
                fui::row(
                    "投资配置与再平衡".into(),
                    format!("{} 套配置 · 纳入资产与实际成交相连", plans.len()),
                    "管理".into(),
                    "plan-portfolios".into(),
                    || fui::navigate("/wealth/portfolios"),
                ),
            ));
            fui::page("规划", body.into_element())
        },
    )
}

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
