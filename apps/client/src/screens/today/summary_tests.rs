use super::*;
use nsh_engine::{EngineConfig, Root};
use nsh_testing::Headless;
fn data() -> Today {
    Today {
        wealth: WealthSnapshot {
            as_of: 0,
            base_currency: "CNY".into(),
            holdings: vec![],
            currencies: vec![],
            missing_prices: vec![],
            missing_fx: vec![],
            net_worth: Some(0.into()),
        },
        currencies: Default::default(),
        issues: vec![],
        actions: vec![],
        totals: vec![],
        records: vec![],
        spending: vec![],
        budgets: vec![],
    }
}
#[component]
fn BudgetProbe() -> impl IntoElement {
    let mut data = data();
    data.budgets = vec![naviwealth_finance::planning::BudgetProgress {
        id: "food".into(),
        budget: naviwealth_finance::planning::Budget {
            month: "2026-11".into(),
            category_id: "dining".into(),
            currency: "CNY".into(),
            limit: 100.into(),
        },
        spent: 150.into(),
        remaining: (-50).into(),
        entry_ids: vec![],
    }];
    mini_pair(&data, "CNY")
}
#[component]
fn EmptyPeakProbe() -> impl IntoElement {
    mini_pair(&data(), "CNY")
}
#[test]
fn today_budget_shows_unclamped_percentage_and_excess() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<BudgetProbe>())).unwrap();
    app.wait_for("text:150.0% 已用").unwrap();
    app.wait_for("text:超出 50.00 CNY").unwrap();
}
#[test]
fn no_spending_card_has_no_peak_date_or_highlight() {
    let mut app = Headless::start(EngineConfig::new(Root::of::<EmptyPeakProbe>())).unwrap();
    app.wait_for("text:本月暂无支出").unwrap();
    app.wait_for("text:单日最高").unwrap();
    assert_eq!(app.screen().count("id:spending-day-0").unwrap(), 0);
}
