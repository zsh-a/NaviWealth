//! Today's real cash movements and unresolved financial work.
use crate::{finance_ui as fui, ui};
use naviwealth_finance::{
    operations::FinancialIssue,
    planning::{OccurrenceState, PlanningAction, PlanningSource},
    wealth::WealthSnapshot,
};
use nsh_base::theme;
use nsh_core::prelude::*;
use rust_decimal::Decimal;

#[derive(Clone, PartialEq)]
struct Today {
    wealth: WealthSnapshot,
    issues: Vec<FinancialIssue>,
    actions: Vec<PlanningAction>,
    totals: Vec<(String, Decimal, Decimal)>,
}
pub fn planning_route(source: &PlanningSource) -> String {
    match source {
        PlanningSource::Recurring { template_id, .. } => format!("/plan/recurring/{template_id}"),
        PlanningSource::Liability { liability_id, .. }
        | PlanningSource::LiabilityOpening { liability_id } => {
            format!("/wealth/liabilities/{liability_id}")
        }
        PlanningSource::Dca { plan_id, .. } => format!("/plan/dca/{plan_id}"),
    }
}
pub fn render() -> AnyElement {
    let data = signal(None::<Today>);
    let loading = signal(true);
    let error = signal(String::new());
    let version = use_context::<crate::state::DataVersion>()
        .expect("version")
        .0;
    let generation = signal(0_u64);
    let services = fui::services();
    effect(move || {
        version.get();
        generation.update(|v| *v += 1);
        let n = generation.get_untracked();
        let s = services.clone();
        loading.set(true);
        spawn(async move {
            let result: Result<Today, String> = async {
                let now = lifeos::ids::now_secs();
                let month = chrono::Local::now().format("%Y-%m").to_string();
                let (from, until) = naviwealth_finance::planning::month_bounds(&month)
                    .map_err(|e| e.to_string())?;
                let base = s
                    .settings_get("finance.base_currency")
                    .await
                    .unwrap_or_else(|| "CNY".into());
                let (wealth, issues, actions, totals) = tokio::join!(
                    s.wealth_snapshot(now, base),
                    s.finance_inbox(now),
                    s.finance_planning_actions(from, until),
                    s.finance_monthly_totals(from, until)
                );
                Ok(Today {
                    wealth: wealth?,
                    issues: issues?,
                    actions: actions?,
                    totals: totals?,
                })
            }
            .await;
            if generation.get_untracked() != n {
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
    fui::page(
        "今日",
        view()
            .gap_2()
            .child(
                view()
                    .flex_row()
                    .gap_2()
                    .child(ui::primary_button(
                        "记一笔",
                        || fui::navigate("/activity/new"),
                        "today-capture",
                        None,
                    ))
                    .child(fui::action("导入账单", "today-import", || {
                        fui::navigate("/activity/import")
                    })),
            )
            .child(ui::error_line(error))
            .child(when(
                move || !error.get().is_empty(),
                move || {
                    fui::action("重新读取", "today-retry", move || {
                        version.update(|v| *v += 1)
                    })
                },
            ))
            .child(when(
                move || loading.get() && data.get().is_none(),
                || {
                    text("正在汇总本地财务…")
                        .text_sm()
                        .text_color(move || theme().muted_foreground)
                },
            ))
            .child(dynamic(move || {
                let Some(data) = data.get() else {
                    return view().into_element();
                };
                let mut body = view().gap_2();
                let no_totals = data.totals.is_empty();
                body = body.child(fui::section(
                    "本月收支",
                    view()
                        .gap_2()
                        .child(when(
                            move || no_totals,
                            || {
                                text("本月暂无收支记录")
                                    .text_sm()
                                    .text_color(move || theme().muted_foreground)
                            },
                        ))
                        .children(data.totals.into_iter().map(|(currency, income, expense)| {
                            view()
                                .gap_2()
                                .child(text(currency).text_sm().font_weight(FontWeight::MEDIUM))
                                .child(
                                    view()
                                        .flex_row()
                                        .gap_3()
                                        .child(cash_metric("收入", income))
                                        .child(cash_metric("支出", expense))
                                        .child(cash_metric("结余", income - expense)),
                                )
                        })),
                ));
                body = body.child(
                    text("本金转移、投资申赎与期初余额不计入收支。")
                        .text_xs()
                        .text_color(move || theme().muted_foreground),
                );
                let count = data.issues.len();
                body = body.child(fui::section(
                    "财务收件箱",
                    fui::row(
                        if count == 0 {
                            "目前没有待处理事项".into()
                        } else {
                            format!("{count} 项待处理")
                        },
                        "账单复核、到期安排与估值缺口".into(),
                        "查看".into(),
                        "today-inbox".into(),
                        || fui::navigate("/today/inbox"),
                    ),
                ));
                let pending: Vec<_> = data
                    .actions
                    .into_iter()
                    .filter(|a| a.state == OccurrenceState::Due)
                    .collect();
                let mut actions = view();
                if pending.is_empty() {
                    actions = actions.child(
                        text("本月到期安排已处理。可在规划中添加周期账单、贷款或定投。")
                            .text_sm()
                            .text_color(move || theme().muted_foreground),
                    );
                }
                for a in pending.into_iter().take(8) {
                    let path = planning_route(&a.source);
                    actions = actions.child(fui::row(
                        a.name,
                        format!("{} · 待确认", ui::ymd(a.due)),
                        format!("{} {}", ui::money(a.amount), a.currency),
                        format!("today-action-{path}-{}", a.due),
                        move || fui::navigate(path.clone()),
                    ));
                }
                body = body.child(fui::section("本月安排", actions));
                let w = data.wealth;
                let summary = w
                    .net_worth
                    .map(|v| format!("{} {}", ui::money(v), w.base_currency))
                    .unwrap_or_else(|| "等待完整估值".into());
                body = body.child(fui::section(
                    "财富状态",
                    fui::row(
                        "查看资产与负债".into(),
                        format!(
                            "{} 项持仓 · 缺 {} 项价格 / {} 组汇率",
                            w.holdings.len(),
                            w.missing_prices.len(),
                            w.missing_fx.len()
                        ),
                        summary,
                        "today-wealth".into(),
                        || fui::navigate("/wealth"),
                    ),
                ));
                body = body.child(fui::row(
                    "完成月结".into(),
                    "复核来源、现金安全与下一步安排".into(),
                    "进入".into(),
                    "today-close".into(),
                    || fui::navigate("/activity/close"),
                ));
                body.into_element()
            })),
    )
}
fn cash_metric(label: &'static str, value: Decimal) -> AnyElement {
    view()
        .flex_1()
        .gap_1()
        .child(
            text(label)
                .text_xs()
                .text_color(move || theme().muted_foreground),
        )
        .child(
            text(ui::money(value))
                .text_size(px(19.0))
                .tabular_nums()
                .font_weight(FontWeight::SEMIBOLD),
        )
        .into_element()
}
