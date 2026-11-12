use super::*;

pub(super) fn rebalance_form(id: String) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "关联再平衡成交",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let p = s
                    .finance_portfolio_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("配置不存在")?;
                let ops = s
                    .wealth_operations(None)
                    .await?
                    .into_iter()
                    .filter(|o| matches!(o.details.kind, OperationKind::Buy | OperationKind::Sell))
                    .collect::<Vec<_>>();
                Ok((p, ops))
            })
        },
        |(p, ops)| {
            let choices = ops
                .into_iter()
                .map(|o| {
                    (
                        o.id,
                        format!(
                            "{} · {} · {} · {}",
                            ui::ymd(o.details.date),
                            o.details.kind.label(),
                            o.details.quantity,
                            amount(o.cash_amount.abs(), &o.currency)
                        ),
                    )
                })
                .collect();
            fui::form("关联再平衡成交",vec![fui::Field::choice("operation","手动成交记录","",choices).help("只关联已记录买卖，并更新唯一对应策略的纳入持仓与现金。系统不会向券商下单。")],move|v|{let id=p.id.clone();Box::pin(async move{fui::services().link_finance_rebalance_trade(id.clone(),fui::required(&v,"operation","成交记录")?).await?;Ok(Some(format!("/wealth/portfolios/{id}")))})})
        },
    )
}
pub(super) fn unlink_form(id: String, operation: String) -> AnyElement {
    let destination = id.clone();
    fui::form(
        "撤销再平衡关联",
        vec![
            fui::Field::choice(
                "restore",
                "纳入配置处理",
                "restore",
                vec![
                    ("restore".into(), "恢复关联前的纳入配置".into()),
                    ("keep".into(), "仅解除关联，保留当前纳入配置".into()),
                ],
            )
            .help("真实买卖记录保留。配置已修改时不能覆盖新修改，可明确选择仅解除关联。"),
        ],
        move |v| {
            let id = destination.clone();
            let operation = operation.clone();
            Box::pin(async move {
                fui::services()
                    .unlink_finance_rebalance_trade(
                        id.clone(),
                        operation,
                        fui::value(&v, "restore") == "restore",
                    )
                    .await?;
                Ok(Some(format!("/wealth/portfolios/{id}")))
            })
        },
    )
}
