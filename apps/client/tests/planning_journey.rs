//! Complete native-engine planning paths using real local repositories.
use naviwealth_finance::{
    daily::{RecordDraft, RecordKind},
    models::{AccountCategory, NewAccount},
    planning::{Budget, FlowKind, Goal, OccurrenceState, Recurring},
};
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
use rust_decimal::Decimal;

fn pick(app: &mut Headless, id: &str, value: &str) {
    app.press(&format!("id:{id}")).unwrap();
    app.wait_for(&format!("id:{id}-{value}")).unwrap();
    app.press(&format!("id:{id}-{value}")).unwrap();
}
fn back(app: &mut Headless, n: usize) {
    for _ in 0..n {
        app.press("id:finance-back").unwrap();
    }
}

#[test]
fn budget_exact_drilldown_recurring_post_undo_fire_and_portfolio_tree() {
    naviwealth_client::enable_test_mode();
    let s = naviwealth_client::Services::shared();
    let now = lifeos::ids::now_secs();
    let month = chrono::Local::now().format("%Y-%m").to_string();
    let (account, category, entry, recurring) = s.runtime.block_on(async {
        let account = s
            .create_account(
                NewAccount::custody(AccountCategory::Bank, "规划验收资金", "CNY"),
                Some(Decimal::from(10000)),
            )
            .await
            .unwrap();
        let category = s
            .finance_categories(RecordKind::Expense)
            .await
            .unwrap()
            .remove(0)
            .0;
        s.save_finance_record(
            None,
            RecordDraft {
                kind: RecordKind::Expense,
                date: now,
                amount: "13.37".parse().unwrap(),
                account_id: account.id.clone(),
                category_id: Some(category.clone()),
                destination_account_id: None,
                destination_amount: None,
                payee: None,
                note: Some("预算真实支出".into()),
            },
        )
        .await
        .unwrap();
        let entry = s
            .finance_records(Default::default(), 10, 0)
            .await
            .unwrap()
            .into_iter()
            .find(|r| r.note.as_deref() == Some("预算真实支出"))
            .unwrap()
            .id;
        let recurring = s
            .save_finance_recurring(
                None,
                Recurring {
                    name: "规划验收账单".into(),
                    kind: FlowKind::Bill,
                    account_id: account.id.clone(),
                    category_id: category.clone(),
                    currency: "CNY".into(),
                    amount: Decimal::from(100),
                    first_due: now,
                    interval_months: 1,
                    end_due: None,
                    paused: false,
                },
            )
            .await
            .unwrap();
        (account, category, entry, recurring)
    });
    s.runtime
        .block_on(s.save_finance_goal(
            None,
            Goal {
                name: "规划验收备用金".into(),
                currency: "CNY".into(),
                target: Decimal::from(5000),
                target_date: now + 365 * 86400,
                monthly_contribution: Decimal::from(500),
                asset_id: None,
            },
        ))
        .unwrap();
    let mut app = Headless::start(EngineConfig::new(Root::of::<naviwealth_client::App>())).unwrap();
    app.wait_for("id:tab-plan").unwrap();
    app.press("id:tab-plan").unwrap();
    app.wait_for("id:plan-budgets").unwrap();
    app.wait_for("text:规划验收账单").unwrap();
    app.wait_for("text:0.00 / 5,000.00 CNY").unwrap();
    app.press("id:plan-budgets").unwrap();
    app.wait_for("id:budget-create").unwrap();
    app.press("id:budget-create").unwrap();
    app.wait_for("id:limit").unwrap();
    pick(&mut app, "category", &category);
    app.type_text("id:limit", "200").unwrap();
    app.back().unwrap();
    app.wait_for("id:finance-form-keep").unwrap();
    app.press("id:finance-form-keep").unwrap();
    app.wait_for("text:200").unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("text:13.37 CNY").unwrap();
    app.wait_for("text:额度已更新为 200.00 CNY；已花与剩余额度已重新核对。")
        .unwrap();
    app.press(&format!("id:budget-record-{entry}")).unwrap();
    app.wait_for("text:预算真实支出").unwrap();
    let budgets = s
        .runtime
        .block_on(s.finance_budgets(month.clone()))
        .unwrap();
    assert_eq!(budgets.len(), 1);
    assert_eq!(budgets[0].spent, "13.37".parse::<Decimal>().unwrap());
    let budget_id = budgets[0].id.clone();
    assert_eq!(budgets[0].entry_ids, vec![entry.clone()]);
    back(&mut app, 3);
    app.wait_for("text:可用 186.63 CNY").unwrap();
    app.press("id:plan-budgets").unwrap();
    app.wait_for(&format!("id:budget-{budget_id}")).unwrap();
    app.press(&format!("id:budget-{budget_id}")).unwrap();
    app.press("id:budget-edit").unwrap();
    app.wait_for("id:limit").unwrap();
    for field in ["month", "category", "currency"] {
        assert_eq!(app.screen().count(&format!("id:{field}")).unwrap(), 0);
    }
    app.clear("id:limit").unwrap();
    app.type_text("id:limit", "234.56").unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("text:额度已更新为 234.56 CNY；已花与剩余额度已重新核对。")
        .unwrap();
    let updated = s
        .runtime
        .block_on(s.finance_budget(budget_id.clone()))
        .unwrap();
    assert_eq!(updated.budget.month, month);
    assert_eq!(updated.budget.category_id, category);
    assert_eq!(updated.budget.currency, "CNY");
    assert_eq!(updated.remaining, "221.19".parse::<Decimal>().unwrap());
    back(&mut app, 2);
    app.press("id:plan-recurring").unwrap();
    app.wait_for(&format!("id:recurring-{recurring}")).unwrap();
    app.press(&format!("id:recurring-{recurring}")).unwrap();
    app.wait_for("id:recurring-post").unwrap();
    app.press("id:recurring-post >> nth=0").unwrap();
    app.wait_for("id:recurring-undo").unwrap();
    let posted = s
        .runtime
        .block_on(s.finance_occurrences(now, now + 1))
        .unwrap();
    assert_eq!(posted[0].state, OccurrenceState::Posted);
    app.press("id:recurring-undo").unwrap();
    app.wait_for("id:recurring-post").unwrap();
    assert_eq!(
        s.runtime
            .block_on(s.finance_occurrences(now, now + 1))
            .unwrap()[0]
            .state,
        OccurrenceState::Due
    );
    back(&mut app, 2);
    app.press("id:plan-fire").unwrap();
    app.wait_for("id:fire-create").unwrap();
    app.press("id:fire-create").unwrap();
    app.wait_for("id:capital").unwrap();
    app.type_text("id:name", "规划验收退休").unwrap();
    app.type_text("id:capital", "1000").unwrap();
    app.type_text("id:expense", "100").unwrap();
    app.type_text("id:income", "400").unwrap();
    app.type_text("id:contribution", "100").unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("text:目标资本").unwrap();
    app.wait_for("id:fire-scenario").unwrap();
    assert_eq!(s.runtime.block_on(s.finance_fire_plans()).unwrap().len(), 1);
    back(&mut app, 2);
    app.press("id:plan-portfolios").unwrap();
    app.wait_for("id:portfolio-create").unwrap();
    app.press("id:portfolio-create").unwrap();
    app.wait_for("id:portfolio").unwrap();
    app.type_text("id:name", "规划验收配置").unwrap();
    app.type_text("id:portfolio", "长期用途").unwrap();
    app.type_text("id:sleeve", "核心策略").unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("id:portfolio-include").unwrap();
    app.press("id:portfolio-include").unwrap();
    app.wait_for("id:quantity").unwrap();
    let plans = s.runtime.block_on(s.finance_portfolio_plans()).unwrap();
    let plan = &plans[0];
    let sleeve = &plan.data.portfolios[0].sleeves[0];
    let source = serde_json::to_string(&(account.id, None::<String>)).unwrap();
    pick(&mut app, "source", &source);
    pick(&mut app, "sleeve", &sleeve.id);
    app.type_text("id:quantity", "1000").unwrap();
    app.press("id:finance-form-save").unwrap();
    app.wait_for("text:1,000.00 CNY").unwrap();
    assert_eq!(
        s.runtime
            .block_on(s.finance_portfolio_snapshot(plan.id.clone(), now + 10))
            .unwrap()
            .total_value,
        Some(Decimal::from(1000))
    );
    // Existing saves update the same complete budget aggregate rather than making a duplicate.
    s.runtime
        .block_on(s.save_finance_budget(Budget {
            month,
            category_id: category,
            currency: "CNY".into(),
            limit: Decimal::from(300),
        }))
        .unwrap();
    // Correcting a source record closes its detail stack and returns to the
    // actual Activity business tab, with the linked budget recomputed.
    back(&mut app, 2);
    app.press("id:plan-budgets").unwrap();
    app.wait_for(&format!("id:budget-{budget_id}")).unwrap();
    app.press(&format!("id:budget-{budget_id}")).unwrap();
    app.press(&format!("id:budget-record-{entry}")).unwrap();
    app.wait_for("id:entry-delete").unwrap();
    app.press("id:entry-delete").unwrap();
    app.wait_for("id:finance-confirm-submit").unwrap();
    app.press("id:finance-confirm-submit").unwrap();
    app.wait_for("id:open-record").unwrap();
    app.wait_for_gone("id:finance-back", std::time::Duration::from_secs(3))
        .unwrap();
    assert!(s.runtime.block_on(s.finance_record(&entry)).is_err());
    assert_eq!(
        s.runtime
            .block_on(s.finance_budget(budget_id))
            .unwrap()
            .spent,
        Decimal::ZERO
    );
}
