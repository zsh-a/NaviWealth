use super::*;

pub(super) fn inclusion_form(id: String, index: Option<usize>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "纳入资产",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let p = s
                    .finance_portfolio_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("配置不存在")?;
                let (snapshot, cash) = tokio::join!(
                    s.wealth_snapshot(today(), p.data.currency.clone()),
                    s.wealth_cash_balances(today())
                );
                Ok((p, snapshot?, cash?))
            })
        },
        move |(p, snapshot, cash)| {
            let old = index.and_then(|i| p.data.inclusions.get(i));
            let mut options = Vec::new();
            for h in snapshot
                .holdings
                .iter()
                .filter(|h| h.quantity > Decimal::ZERO)
            {
                options.push((
                    serde_json::to_string(&(h.account_id.clone(), Some(h.asset_id.clone())))
                        .unwrap(),
                    format!("{} · 持仓 {}", h.name, h.quantity),
                ));
            }
            for c in cash
                .iter()
                .filter(|c| !c.liability && c.amount > Decimal::ZERO)
            {
                options.push((
                    serde_json::to_string(&(c.account_id.clone(), None::<String>)).unwrap(),
                    format!("{} · {}", c.name, amount(c.amount, &c.currency)),
                ));
            }
            let sleeves = p
                .data
                .portfolios
                .iter()
                .flat_map(|p| {
                    p.sleeves
                        .iter()
                        .map(|s| (s.id.clone(), format!("{} / {}", p.name, s.name)))
                })
                .collect();
            let selected = old
                .map(|i| {
                    serde_json::to_string(&(i.account_id.clone(), i.asset_id.clone())).unwrap()
                })
                .unwrap_or_default();
            let source = fui::Field::choice("source", "真实持仓或现金", selected, options);
            let selected_source = source.value;
            let fields = vec![
                source,
                fui::Field::choice(
                    "sleeve",
                    "纳入策略",
                    old.map(|i| i.sleeve_id.clone()).unwrap_or_default(),
                    sleeves,
                ),
                fui::Field::decimal(
                    "quantity",
                    "纳入数量或现金金额",
                    old.map(|i| i.quantity.to_string()).unwrap_or_default(),
                )
                .quantity_or_money(move || {
                    let (account, asset): (String, Option<String>) =
                        serde_json::from_str(&selected_source.get()).ok()?;
                    if asset.is_some() {
                        return None;
                    }
                    cash.iter()
                        .find(|c| c.account_id == account)
                        .map(|c| c.currency.clone())
                })
                .help("允许部分持仓；其他投资配置已纳入的数量仍占用真实可用量。"),
                fui::Field::choice(
                    "remove",
                    "处理方式",
                    "keep",
                    vec![
                        ("keep".into(), "保存纳入配置".into()),
                        ("remove".into(), "移除此纳入项，保留真实资产".into()),
                    ],
                )
                .show_when(move || index.is_some()),
            ];
            fui::form("纳入资产", fields, move |v| {
                let mut data = p.data.clone();
                let id = p.id.clone();
                Box::pin(async move {
                    if fui::value(&v, "remove") == "remove" {
                        let i = index.ok_or("新增项不能移除")?;
                        if i >= data.inclusions.len() {
                            return Err("纳入项已改变，请重新打开".into());
                        }
                        data.inclusions.remove(i);
                    } else {
                        let (account_id, asset_id): (String, Option<String>) =
                            serde_json::from_str(&fui::required(&v, "source", "真实资产")?)
                                .map_err(|_| "请选择有效资产")?;
                        let sleeve_id = fui::required(&v, "sleeve", "纳入策略")?;
                        let portfolio_id = data
                            .portfolios
                            .iter()
                            .find(|p| p.sleeves.iter().any(|s| s.id == sleeve_id))
                            .map(|p| p.id.clone())
                            .ok_or("策略已删除")?;
                        let inclusion = CapitalInclusion {
                            portfolio_id,
                            sleeve_id,
                            account_id,
                            asset_id,
                            quantity: fui::decimal(&v, "quantity", "纳入量")?,
                        };
                        if let Some(i) = index {
                            let target = data
                                .inclusions
                                .get_mut(i)
                                .ok_or("纳入项已改变，请重新打开")?;
                            *target = inclusion;
                        } else {
                            data.inclusions.push(inclusion);
                        }
                    }
                    fui::services()
                        .save_finance_portfolio_plan(Some(id.clone()), data, today())
                        .await?;
                    Ok(Some(format!("/wealth/portfolios/{id}")))
                })
            })
        },
    )
}
