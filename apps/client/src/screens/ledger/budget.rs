use super::*;
use naviwealth_finance::planning::BudgetProgress;

#[derive(Clone, PartialEq)]
pub(super) struct Summary {
    currency: String,
    spent: Decimal,
    limit: Decimal,
    ratio: Decimal,
    status: u8,
    error: Option<String>,
}
fn error(message: &str) -> Vec<Summary> {
    vec![Summary {
        currency: String::new(),
        spent: Decimal::ZERO,
        limit: Decimal::ZERO,
        ratio: Decimal::ZERO,
        status: 2,
        error: Some(message.into()),
    }]
}
pub(super) fn summarize(result: Result<Vec<BudgetProgress>, String>) -> Vec<Summary> {
    let Ok(budgets) = result else {
        return error("预算暂不可用，点此重新查看");
    };
    let mut currencies = std::collections::BTreeMap::<String, (Decimal, Decimal)>::new();
    for budget in budgets {
        let row = currencies.entry(budget.budget.currency).or_default();
        if let (Some(spent), Some(limit)) = (
            row.0.checked_add(budget.spent),
            row.1.checked_add(budget.budget.limit),
        ) {
            *row = (spent, limit);
        } else {
            return error("预算合计超出范围，请查看分类明细");
        }
    }
    currencies
        .into_iter()
        .map(|(currency, (spent, limit))| {
            let ratio = if limit > Decimal::ZERO {
                spent.checked_div(limit).unwrap_or(Decimal::MAX)
            } else {
                Decimal::ZERO
            };
            let status = if ratio >= Decimal::ONE {
                2
            } else if ratio >= Decimal::new(9, 1) {
                1
            } else {
                0
            };
            Summary {
                currency,
                spent,
                limit,
                ratio,
                status,
                error: None,
            }
        })
        .collect()
}
pub(super) fn module(summary: Signal<Vec<Summary>>) -> impl IntoElement {
    when(
        move || !summary.get().is_empty(),
        move || {
            ui::press_target(|| fui::navigate("/plan/budgets"))
                .test_id("ledger-budget-context")
                .gap_3()
                .p_3()
                .rounded(px(12.0))
                .bg(move || theme().secondary)
                .child(each(
                    move || summary.get(),
                    |s: &Summary| s.currency.clone(),
                    move |s: ReadSignal<Summary>, _| {
                        dynamic(move || {
                            let s = s.get();
                            if let Some(message) = s.error {
                                return ui::quiet_text(message).into_element();
                            }
                            let status = ui::BudgetDisplay::new(s.spent, s.limit, &s.currency);
                            let label_color = status.clone();
                            let balance_color = status.clone();
                            view()
                                .gap_2()
                                .child(
                                    view()
                                        .flex_row()
                                        .flex_wrap()
                                        .gap_2()
                                        .items_baseline()
                                        .child(
                                            text(format!("分类预算 · {}", s.currency))
                                                .flex_1()
                                                .text_size(move || px(ui::token("type-caption"))),
                                        )
                                        .child(
                                            text(status.usage.clone())
                                                .tabular_nums()
                                                .text_size(move || px(ui::token("type-caption")))
                                                .text_color(move || label_color.tone()),
                                        ),
                                )
                                .child(ui::progress_bar_state(status.progress, status.alert))
                                .child(
                                    ui::quiet_text(format!(
                                        "{} · {} / {}",
                                        status.balance,
                                        ui::money_for(s.spent, &s.currency),
                                        ui::money_for(s.limit, &s.currency)
                                    ))
                                    .text_color(move || balance_color.tone()),
                                )
                                .into_element()
                        })
                    },
                ))
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use naviwealth_finance::planning::Budget;
    fn budget(currency: &str, spent: Decimal, limit: Decimal) -> BudgetProgress {
        BudgetProgress {
            id: String::new(),
            budget: Budget {
                month: "2026-11".into(),
                category_id: "food".into(),
                currency: currency.into(),
                limit,
            },
            spent,
            remaining: limit.checked_sub(spent).unwrap_or_default(),
            entry_ids: vec![],
        }
    }
    #[component]
    fn OverBudget() -> impl IntoElement {
        module(signal(summarize(Ok(vec![budget(
            "CNY",
            150.into(),
            100.into(),
        )]))))
    }
    #[test]
    fn ledger_budget_shows_unclamped_percentage_and_excess() {
        use nsh_engine::{EngineConfig, Root};
        use nsh_testing::Headless;
        let mut app = Headless::start(EngineConfig::new(Root::of::<OverBudget>())).unwrap();
        app.wait_for("text:150.0% 已用").unwrap();
        app.wait_for("text:超出 50.00 CNY · 150.00 / 100.00")
            .unwrap();
    }
    #[test]
    fn progress_keeps_currencies_separate_and_warns_at_ninety_percent() {
        let rows = summarize(Ok(vec![
            budget("CNY", 45.into(), 50.into()),
            budget("CNY", 45.into(), 50.into()),
            budget("JPY", 100.into(), 100.into()),
        ]));
        assert_eq!(rows.len(), 2);
        assert_eq!(
            (rows[0].spent, rows[0].limit, rows[0].status),
            (90.into(), 100.into(), 1)
        );
        assert_eq!((rows[1].currency.as_str(), rows[1].status), ("JPY", 2));
    }
    #[test]
    fn an_overflow_or_failed_read_never_displays_a_partial_budget() {
        let rows = summarize(Ok(vec![
            budget("CNY", Decimal::MAX, Decimal::MAX),
            budget("CNY", 1.into(), 1.into()),
        ]));
        assert_eq!(rows.len(), 1);
        assert!(rows[0].error.is_some());
        assert!(summarize(Err("unavailable".into()))[0].error.is_some());
    }
}
