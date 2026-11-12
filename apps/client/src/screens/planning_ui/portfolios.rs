use super::*;
use naviwealth_finance::planning::Stored;
use naviwealth_finance::wealth::OperationKind;
use rust_decimal::prelude::ToPrimitive;

pub(super) fn render(p: Vec<String>) -> AnyElement {
    let id = p.get(2).cloned();
    let section = p.get(3).map(String::as_str);
    let node = p.get(4).cloned();
    let action = p.get(5).cloned();
    match (id.as_deref(), section) {
        (None, _) => list_page(),
        (Some("new"), _) => create_form(),
        (Some(_), Some("edit")) => plan_form(id.unwrap()),
        (Some(_), Some("delete")) => remove_page(
            "删除投资配置",
            PlanKind::Portfolio,
            id.unwrap(),
            "/wealth/portfolios".into(),
        ),
        (Some(_), Some("portfolio")) => match node.as_deref() {
            Some("new") => add_portfolio(id.unwrap()),
            Some(_) => portfolio_node(id.unwrap(), node.unwrap(), action),
            None => error_page(),
        },
        (Some(_), Some("sleeve")) => match node.as_deref() {
            Some("new") => add_sleeve(id.unwrap(), action.unwrap_or_default()),
            Some(_) => sleeve_node(id.unwrap(), node.unwrap(), action),
            None => error_page(),
        },
        (Some(_), Some("target")) => target_form(id.unwrap(), node.unwrap_or_default(), action),
        (Some(_), Some("include")) => {
            inclusion_form(id.unwrap(), node.and_then(|i| i.parse().ok()))
        }
        (Some(_), Some("rebalance")) => rebalance_form(id.unwrap()),
        (Some(_), Some("remove-purpose")) => {
            remove_node_form(id.unwrap(), true, node.unwrap_or_default())
        }
        (Some(_), Some("remove-sleeve")) => {
            remove_node_form(id.unwrap(), false, node.unwrap_or_default())
        }
        (Some(_), Some("unlink")) => unlink_form(id.unwrap(), node.unwrap_or_default()),
        (Some(_), _) => detail(id.unwrap()),
    }
}

#[path = "portfolios/overview.rs"]
mod overview;
use overview::*;

#[path = "portfolios/nodes.rs"]
mod nodes;
use nodes::*;

#[path = "portfolios/targets.rs"]
mod targets;
use targets::*;

#[path = "portfolios/capital.rs"]
mod capital;
use capital::*;

#[path = "portfolios/receipts.rs"]
mod receipts;
use receipts::*;

#[path = "portfolios/removal.rs"]
mod removal;
use removal::*;
