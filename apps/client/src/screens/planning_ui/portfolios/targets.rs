use super::*;

pub(super) fn target_form(id: String, sid: String, index: Option<String>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "资产目标",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let p = s
                    .finance_portfolio_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("配置不存在")?;
                Ok((p, s.wealth_assets(false).await?))
            })
        },
        move |(p, assets)| {
            let Some(sleeve) = p
                .data
                .portfolios
                .iter()
                .flat_map(|p| p.sleeves.iter())
                .find(|s| s.id == sid)
                .cloned()
            else {
                return error_page();
            };
            let selected = index.as_ref().and_then(|i| i.parse::<usize>().ok());
            let old = selected.and_then(|i| sleeve.targets.get(i));
            let mut choices = vec![("".into(), "现金".into())];
            choices.extend(
                assets
                    .iter()
                    .map(|a| (a.id.clone(), a.details.name.clone())),
            );
            let can_remove = selected.is_some() && sleeve.targets.len() > 1;
            let remove = fui::Field::choice(
                "remove",
                "处理方式",
                "keep",
                vec![
                    ("keep".into(), "保存目标配置".into()),
                    ("remove".into(), "移除此目标并转移权重".into()),
                ],
            )
            .show_when(move || can_remove);
            let removing = remove.value;
            let receivers = sleeve
                .targets
                .iter()
                .enumerate()
                .filter(|(i, _)| Some(*i) != selected)
                .map(|(i, t)| {
                    (
                        i.to_string(),
                        t.asset_id
                            .as_ref()
                            .and_then(|id| assets.iter().find(|a| &a.id == id))
                            .map(|a| a.details.name.clone())
                            .unwrap_or_else(|| "现金".into()),
                    )
                })
                .collect();
            let fields = vec![
                fui::Field::choice(
                    "asset",
                    "目标资产",
                    old.and_then(|t| t.asset_id.clone()).unwrap_or_default(),
                    choices,
                ),
                fui::Field::decimal(
                    "weight",
                    "策略内权重（%）",
                    old.map(|t| (Decimal::from(t.weight_bps) / Decimal::from(100)).to_string())
                        .unwrap_or_else(|| "0".into()),
                )
                .help("调整此项后，其余目标按比例分配至合计 100%；新增项先从 0% 开始。"),
                remove,
                fui::Field::choice("receiver", "接收目标权重", "", receivers)
                    .show_when(move || can_remove && removing.get() == "remove"),
            ];
            let sid = sid.clone();
            fui::form("资产目标", fields, move |v| {
                let mut data = p.data.clone();
                let id = p.id.clone();
                let sid = sid.clone();
                Box::pin(async move {
                    let sleeve = data
                        .portfolios
                        .iter_mut()
                        .flat_map(|p| p.sleeves.iter_mut())
                        .find(|s| s.id == sid)
                        .ok_or("策略已删除")?;
                    if fui::value(&v, "remove") == "remove" {
                        let selected = selected.ok_or("新增目标不能移除")?;
                        let receiver: usize = fui::required(&v, "receiver", "接收目标")?
                            .parse()
                            .map_err(|_| "接收目标无效")?;
                        if selected == receiver
                            || selected >= sleeve.targets.len()
                            || receiver >= sleeve.targets.len()
                            || sleeve.targets.len() < 2
                        {
                            return Err("请选择其他接收目标，且至少保留一个目标".into());
                        }
                        sleeve.targets[receiver].weight_bps = sleeve.targets[receiver]
                            .weight_bps
                            .checked_add(sleeve.targets[selected].weight_bps)
                            .ok_or("权重超出范围")?;
                        sleeve.targets.remove(selected);
                        fui::services()
                            .save_finance_portfolio_plan(Some(id.clone()), data, today())
                            .await?;
                        return Ok(Some(format!("/wealth/portfolios/{id}/sleeve/{sid}")));
                    }
                    let asset = fui::value(&v, "asset");
                    let asset_id = (!asset.is_empty()).then_some(asset);
                    let target = bps(&v, "weight")?;
                    let idx = if let Some(i) = selected {
                        if i >= sleeve.targets.len() {
                            return Err("目标已改变，请重新打开".into());
                        }
                        sleeve.targets[i].asset_id = asset_id;
                        i
                    } else {
                        if sleeve.targets.iter().any(|t| t.asset_id == asset_id) {
                            return Err("此资产已有目标，请返回编辑现有项".into());
                        }
                        sleeve.targets.push(AssetTarget {
                            asset_id,
                            weight_bps: 0,
                        });
                        sleeve.targets.len() - 1
                    };
                    let weights = redistribute(
                        &sleeve
                            .targets
                            .iter()
                            .map(|t| t.weight_bps)
                            .collect::<Vec<_>>(),
                        idx,
                        target,
                    )?;
                    for (t, w) in sleeve.targets.iter_mut().zip(weights) {
                        t.weight_bps = w;
                    }
                    fui::services()
                        .save_finance_portfolio_plan(Some(id.clone()), data, today())
                        .await?;
                    Ok(Some(format!("/wealth/portfolios/{id}/sleeve/{sid}")))
                })
            })
        },
    )
}
