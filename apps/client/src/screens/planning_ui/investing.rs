use super::cash::state;
use super::*;
use naviwealth_finance::{
    models::{AccountCategory, AccountSide},
    wealth::OperationKind,
};

pub(super) fn render(p: Vec<String>) -> AnyElement {
    let area = p.get(1).map(String::as_str).unwrap_or("");
    let id = p.get(2).cloned();
    let action = p.get(3).map(String::as_str);
    match (area, id.as_deref(), action) {
        ("goals", None, _) => goal_list(),
        ("goals", Some("new"), _) => goal_form(None),
        ("goals", Some(_), Some("edit")) => goal_form(id),
        ("goals", Some(_), Some("contribute")) => contribution_form(id.unwrap()),
        ("goals", Some(_), Some("delete")) => remove_page(
            "删除目标",
            PlanKind::Goal,
            id.unwrap(),
            "/plan/goals".into(),
        ),
        ("goals", Some(_), _) => goal_detail(id.unwrap()),
        ("dca", None, _) => dca_list(),
        ("dca", Some("new"), _) => dca_form(None),
        ("dca", Some(_), Some("edit")) => dca_form(id),
        ("dca", Some(_), Some("link")) => dca_link(
            id.unwrap(),
            p.get(4).and_then(|s| s.parse().ok()).unwrap_or(0),
        ),
        ("dca", Some(_), Some("delete")) => remove_page(
            "删除定投计划",
            PlanKind::Dca,
            id.unwrap(),
            "/plan/dca".into(),
        ),
        ("dca", Some(_), _) => dca_detail(id.unwrap()),
        ("fire", None, _) => fire_list(),
        ("fire", Some("new"), _) => fire_form(None, false),
        ("fire", Some(_), Some("edit")) => fire_form(id, false),
        ("fire", Some(_), Some("scenario")) => fire_form(id, true),
        ("fire", Some(_), Some("delete")) => remove_page(
            "删除 FIRE 规划",
            PlanKind::Fire,
            id.unwrap(),
            "/plan/fire".into(),
        ),
        ("fire", Some(_), _) => fire_detail(id.unwrap()),
        _ => error_page(),
    }
}

#[path = "goals.rs"]
mod goals;
use goals::*;
#[path = "dca.rs"]
mod dca;
use dca::*;
#[path = "fire.rs"]
mod fire;
use fire::*;
