//! Today's real cash movements and unresolved financial work.
use crate::{
    finance::{FinanceRecord, RecordFilter, RecordKind},
    finance_ui as fui, ui,
};
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
    currencies: ui::RecordCurrencies,
    issues: Vec<FinancialIssue>,
    actions: Vec<PlanningAction>,
    totals: Vec<(String, Decimal, Decimal)>,
    records: Vec<FinanceRecord>,
    spending: Vec<naviwealth_finance::daily::DailySpending>,
    budgets: Vec<naviwealth_finance::planning::BudgetProgress>,
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
    let dialog_services = services.clone();
    // Capture opens in place: the workspace button bumps the shared intent
    // and this pane answers only when its own tab is the selected one.
    let open = signal(false);
    let intent = use_context::<crate::CaptureIntent>()
        .expect("capture intent")
        .0;
    let tab = use_context::<crate::ShellTab>().expect("tab").0;
    let seen_intent = signal(intent.get_untracked());
    effect(move || {
        let now = intent.get();
        if now != seen_intent.get_untracked() {
            seen_intent.set(now);
            if tab.get() == 0 {
                open.set(true);
            }
        }
    });
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
                let day = ui::date_to_secs(&ui::today_text()).ok_or("无效日期")?;
                let (wealth, issues, actions, totals, budgets, spending, records, accounts) = tokio::join!(
                    s.wealth_snapshot(now, base.clone()), s.finance_inbox(now),
                    s.finance_planning_actions(from,until), s.finance_monthly_totals(from,until),
                    s.finance_budgets(month), s.finance_daily_spending(from,until),
                    s.finance_records(RecordFilter {from:Some(day),until:Some(day+86400),..Default::default()},5,0),
                    s.finance_accounts(true)
                );
                let accounts=accounts?;
                let currencies = ui::RecordCurrencies {
                    base: wealth
                        .as_ref()
                        .map(|w| w.base_currency.clone())
                        .unwrap_or(base),
                    accounts: accounts
                        .into_iter()
                        .map(|(a, _)| (a.id, a.currency))
                        .collect(),
                };
                Ok(Today {
                    wealth: wealth?,
                    currencies,
                    issues: issues?,
                    actions: actions?,
                    totals: totals?,
                    records: records?,
                    spending: spending?,
                    budgets: budgets?,
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
    view()
        .flex_1()
        .child(fui::page(
            "今日",
            view()
                .gap_2()
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
                    ui::skeleton,
                ))
                .child(dynamic(move || {
                    let Some(data) = data.get() else {
                        return view().into_element();
                    };
                    summary::body(data)
                })),
        ))
        .child(super::record::record_dialog(
            dialog_services,
            open,
            version,
            "/today",
        ))
        .into_element()
}

#[path = "today/summary.rs"]
mod summary;
