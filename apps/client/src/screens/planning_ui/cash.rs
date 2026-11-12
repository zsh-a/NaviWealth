use super::*;
use naviwealth_finance::{
    daily::RecordKind,
    models::{AccountCategory, AccountSide},
};

pub(super) fn render(p: Vec<String>) -> AnyElement {
    let area = p.get(1).map(String::as_str).unwrap_or("");
    let id = p.get(2).cloned();
    let action = p.get(3).map(String::as_str);
    match (area, id.as_deref(), action) {
        ("budgets", None, _) => budget_list(month()),
        ("budgets", Some("period"), Some(_)) => budget_list(p[3].clone()),
        ("budgets", Some("choose-month"), _) => budget_month_form(),
        ("budgets", Some("new"), _) => budget_form(None),
        ("budgets", Some(_), Some("edit")) => budget_form(id),
        ("budgets", Some(_), Some("delete")) => remove_page(
            "删除预算",
            PlanKind::Budget,
            id.unwrap(),
            "/plan/budgets".into(),
        ),
        ("budgets", Some(_), _) => budget_detail(id.unwrap()),
        ("recurring", None, _) => recurring_list(),
        ("recurring", Some("new"), _) => recurring_form(None),
        ("recurring", Some(_), Some("edit")) => recurring_form(id),
        ("recurring", Some(_), Some("delete")) => remove_page(
            "删除周期计划",
            PlanKind::Recurring,
            id.unwrap(),
            "/plan/recurring".into(),
        ),
        ("recurring", Some(_), _) => recurring_detail(id.unwrap()),
        ("liabilities", None, _) => loan_list(),
        ("liabilities", Some("new"), _) => loan_form(None),
        ("liabilities", Some(_), Some("edit")) => loan_form(id),
        ("liabilities", Some(_), Some("delete")) => loan_delete(id.unwrap()),
        ("liabilities", Some(_), Some("pay")) => loan_pay(
            id.unwrap(),
            p.get(4).and_then(|v| v.parse().ok()).unwrap_or(u32::MAX),
        ),
        ("liabilities", Some(_), _) => loan_detail(id.unwrap()),
        ("runway", Some("scenario"), Some("new")) => scenario_form(None),
        ("runway", Some("scenario"), Some(_)) => scenario_form(p.get(3).cloned()),
        ("runway", Some("currency"), Some(_)) => runway_page(p[3].clone()),
        ("runway", Some("select-currency"), _) => runway_currency_form(),
        ("runway", _, _) => runway_page("CNY".into()),
        _ => error_page(),
    }
}
#[path = "budgets.rs"]
mod budgets;
use budgets::*;

#[path = "recurring.rs"]
mod recurring;
use recurring::*;
#[path = "loans.rs"]
mod loans;
use loans::*;
#[path = "runway.rs"]
mod runway;
use runway::*;

pub(super) fn state(s: OccurrenceState) -> &'static str {
    match s {
        OccurrenceState::Due => "待处理",
        OccurrenceState::Posted => "已入账 / 已关联",
        OccurrenceState::Skipped => "已跳过",
    }
}
