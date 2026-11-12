//! The planning workspace uses actual budgets, due actions and contributions.
use super::*;
use naviwealth_finance::daily::RecordKind;

pub(super) fn hub() -> AnyElement {
    load(
        "规划",
        |s| {
            Box::pin(async move {
                let period = month();
                let (from, until) = month_bounds(&period).map_err(|e| e.to_string())?;
                let (budgets, categories, actions, goals, plans) = tokio::join!(
                    s.finance_budgets(period),
                    s.finance_categories(RecordKind::Expense),
                    s.finance_planning_actions(from, until),
                    s.finance_goals(),
                    s.finance_portfolio_plans()
                );
                Ok((budgets?, categories?, actions?, goals?, plans?))
            })
        },
        |(mut budgets, categories, actions, goals, plans)| {
            budgets.sort_by(|a, b| {
                ui::ratio(b.spent, b.budget.limit).total_cmp(&ui::ratio(a.spent, a.budget.limit))
            });
            let due_count = actions
                .iter()
                .filter(|a| a.state == OccurrenceState::Due && a.due <= today())
                .count();
            let mut body = view().gap(move || px(ui::token("space-group")));
            match ui::budget_totals(&budgets) {
                Some(totals) if !totals.is_empty() => {
                    for (currency, (spent, limit)) in totals {
                        body = body.child(
                            view()
                                .gap_3()
                                .child(ui::quiet_text("本月预算可用"))
                                .child(ui::amount_text(
                                    ui::money_for(limit - spent, &currency),
                                    currency.clone(),
                                    "type-surplus",
                                ))
                                .child(ui::progress_bar(ui::ratio(spent, limit)))
                                .child(ui::quiet_text(format!(
                                    "{} 项预算 · {} 项待确认 · {} 个目标",
                                    budgets.len(),
                                    due_count,
                                    goals.len()
                                ))),
                        );
                    }
                }
                Some(_) => {
                    body = body.child(ui::quiet_text("为这个月安排预算"));
                }
                None => {
                    body = body.child(ui::quiet_text("预算合计超出范围，请查看分类明细"));
                }
            }
            let mut budget_body = view().gap_3();
            for b in budgets.iter().take(2) {
                let name = categories
                    .iter()
                    .find(|(id, _)| id == &b.budget.category_id)
                    .map(|(_, name)| name.as_str())
                    .unwrap_or("支出分类");
                let route = format!("/plan/budgets/{}", b.id);
                let exceeded = b.remaining < Decimal::ZERO;
                budget_body = budget_body.child(
                    ui::press_target(move || fui::navigate(route.clone()))
                        .test_id(&format!("plan-budget-{}", b.id))
                        .gap_2()
                        .py_2()
                        .child(
                            view()
                                .flex_row()
                                .items_baseline()
                                .gap_2()
                                .child(
                                    text(name.to_owned())
                                        .flex_1()
                                        .text_size(move || px(ui::token("type-body"))),
                                )
                                .child(
                                    ui::quiet_text(format!(
                                        "{} {}",
                                        if exceeded { "超出" } else { "可用" },
                                        amount(b.remaining.abs(), &b.budget.currency)
                                    ))
                                    .text_color(move || {
                                        if exceeded {
                                            theme().destructive
                                        } else {
                                            theme().muted_foreground
                                        }
                                    }),
                                ),
                        )
                        .child(ui::progress_bar_state(
                            ui::ratio(b.spent, b.budget.limit),
                            exceeded,
                        ))
                        .child(ui::quiet_text(format!(
                            "已用 {} / {} {}",
                            ui::money_for(b.spent, &b.budget.currency),
                            ui::money_for(b.budget.limit, &b.budget.currency),
                            b.budget.currency
                        ))),
                );
            }
            budget_body =
                budget_body.child(fui::action("全部预算 →", "plan-budgets", || {
                    fui::navigate("/plan/budgets")
                }));
            body = body.child(group("分类预算", budget_body));
            let mut goals_body = view().gap_3();
            for goal in goals.iter().take(2) {
                let route = format!("/plan/goals/{}", goal.id);
                let progress = ui::ratio(goal.contributed, goal.goal.target);
                goals_body = goals_body.child(
                    ui::press_target(move || fui::navigate(route.clone()))
                        .test_id(&format!("plan-goal-{}", goal.id))
                        .gap_3()
                        .p_4()
                        .rounded(move || px(ui::card_radius()))
                        .bg(move || theme().card)
                        .child(
                            view()
                                .flex_row()
                                .items_center()
                                .gap_3()
                                .child(ui::category_icon("旅行"))
                                .child(
                                    text(goal.goal.name.clone())
                                        .flex_1()
                                        .text_size(move || px(ui::token("type-body"))),
                                )
                                .child(ui::quiet_text(format!("{:.0}%", progress * 100.0))),
                        )
                        .child(ui::progress_bar(progress))
                        .child(ui::quiet_text(format!(
                            "{} / {} {}",
                            ui::money_for(goal.contributed, &goal.goal.currency),
                            ui::money_for(goal.goal.target, &goal.goal.currency),
                            goal.goal.currency
                        ))),
                );
            }
            goals_body = goals_body.child(fui::action("全部目标 →", "plan-goals", || {
                fui::navigate("/plan/goals")
            }));
            body = body.child(group("正在积累", goals_body));
            let mut pending: Vec<_> = actions
                .into_iter()
                .filter(|a| a.state == OccurrenceState::Due)
                .collect();
            pending.sort_by_key(|a| a.due);
            let mut due_body = view();
            if pending.is_empty() {
                due_body = due_body.child(ui::quiet_text("本月安排已处理"));
            }
            for (index, action) in pending.into_iter().take(3).enumerate() {
                let route = crate::screens::today::planning_route(&action.source);
                due_body = due_body.child(fui::row(
                    action.name,
                    ui::ymd(action.due),
                    amount(action.amount, &action.currency),
                    format!("plan-due-{index}"),
                    move || fui::navigate(route.clone()),
                ));
            }
            due_body = due_body.child(fui::action("管理周期收支", "plan-recurring", || {
                fui::navigate("/plan/recurring")
            }));
            body = body.child(group("接下来", due_body));
            let tools = view()
                .child(fui::row(
                    "现金跑道".into(),
                    String::new(),
                    "模拟 →".into(),
                    "plan-runway".into(),
                    || fui::navigate("/plan/runway"),
                ))
                .child(fui::row(
                    "贷款与还款".into(),
                    String::new(),
                    "管理 →".into(),
                    "plan-liabilities".into(),
                    || fui::navigate("/wealth/liabilities"),
                ))
                .child(fui::row(
                    "定投计划".into(),
                    String::new(),
                    "查看 →".into(),
                    "plan-dca".into(),
                    || fui::navigate("/plan/dca"),
                ))
                .child(fui::row(
                    "FIRE 规划".into(),
                    String::new(),
                    "计算 →".into(),
                    "plan-fire".into(),
                    || fui::navigate("/plan/fire"),
                ))
                .child(fui::row(
                    "投资配置".into(),
                    String::new(),
                    format!("{} 套 →", plans.len()),
                    "plan-portfolios".into(),
                    || fui::navigate("/wealth/portfolios"),
                ));
            fui::page("规划", body.child(group("规划工具", tools)))
        },
    )
}
fn group(title: &str, body: impl IntoElement) -> impl Element {
    view()
        .gap_3()
        .child(
            text(title.to_owned())
                .text_size(move || px(ui::token("type-section")))
                .font_weight(FontWeight::SEMIBOLD),
        )
        .child(body)
}
