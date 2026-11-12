use super::*;

pub(super) fn add_portfolio(id: String) -> AnyElement {
    tree_form(id, |p| {
        fui::form(
            "添加投资用途",
            vec![
                fui::Field::text("name", "用途名称", ""),
                fui::Field::text("sleeve", "初始策略名称", "")
                    .help("新增用途从 0% 开始；保存后调整权重，同级合计保持 100%。"),
            ],
            move |v| {
                let mut data = p.data.clone();
                let id = p.id.clone();
                Box::pin(async move {
                    let pid = lifeos::ids::new_id();
                    data.portfolios.push(Portfolio {
                        id: pid.clone(),
                        name: fui::required(&v, "name", "用途名称")?,
                        target_bps: 0,
                        sleeves: vec![Sleeve {
                            id: lifeos::ids::new_id(),
                            name: fui::required(&v, "sleeve", "策略名称")?,
                            target_bps: 10000,
                            tolerance_bps: 500,
                            targets: vec![AssetTarget {
                                asset_id: None,
                                weight_bps: 10000,
                            }],
                        }],
                    });
                    fui::services()
                        .save_finance_portfolio_plan(Some(id.clone()), data, today())
                        .await?;
                    Ok(Some(format!("/wealth/portfolios/{id}/portfolio/{pid}")))
                })
            },
        )
    })
}
/// Integer basis-point redistribution keeps all siblings and exactly 100%.
pub(super) fn redistribute(weights: &[u32], index: usize, target: u32) -> Result<Vec<u32>, String> {
    if target > 10000 || index >= weights.len() {
        return Err("目标权重须为 0–100%".into());
    }
    if weights.len() == 1 {
        if target != 10000 {
            return Err("唯一的同级项必须保持 100%".into());
        }
        return Ok(vec![10000]);
    }
    let remaining = 10000 - target;
    let sum = weights
        .iter()
        .enumerate()
        .filter(|(i, _)| *i != index)
        .map(|(_, w)| u64::from(*w))
        .sum::<u64>();
    let mut out = vec![0; weights.len()];
    out[index] = target;
    let mut used = 0;
    for (i, w) in weights.iter().enumerate() {
        if i != index {
            out[i] = (u64::from(*w) * u64::from(remaining))
                .checked_div(sum)
                .map(|v| v as u32)
                .unwrap_or_else(|| remaining / (weights.len() as u32 - 1));
            used += out[i];
        }
    }
    let mut remainder = remaining - used;
    for (i, w) in out.iter_mut().enumerate() {
        if i != index && remainder > 0 {
            *w += 1;
            remainder -= 1;
        }
    }
    Ok(out)
}
pub(super) fn bps(v: &fui::Values, id: &str) -> Result<u32, String> {
    let d = fui::decimal(v, id, "目标百分比")?
        .checked_mul(Decimal::from(100))
        .ok_or("权重超出范围")?;
    if d.fract() != Decimal::ZERO {
        return Err("权重最多保留两位小数".into());
    }
    d.to_u32()
        .filter(|v| *v <= 10000)
        .ok_or_else(|| "权重须为 0–100%".into())
}
pub(super) fn portfolio_node(id: String, pid: String, action: Option<String>) -> AnyElement {
    let freeze_draft = action.as_deref() == Some("edit");
    tree_mode(id, freeze_draft, move |p| {
        let Some(child) = p.data.portfolios.iter().find(|c| c.id == pid).cloned() else {
            return error_page();
        };
        if action.as_deref() == Some("edit") {
            let pid = pid.clone();
            return fui::form(
                "投资用途权重",
                vec![
                    fui::Field::text("name", "用途名称", child.name),
                    fui::Field::decimal(
                        "weight",
                        "目标占比（%）",
                        (Decimal::from(child.target_bps) / Decimal::from(100)).to_string(),
                    )
                    .help("其余同级用途按原比例重新分配，完整配置合计保持 100%。"),
                ],
                move |v| {
                    let mut data = p.data.clone();
                    let id = p.id.clone();
                    let pid = pid.clone();
                    Box::pin(async move {
                        let index = data
                            .portfolios
                            .iter()
                            .position(|c| c.id == pid)
                            .ok_or("用途已删除")?;
                        let weights = redistribute(
                            &data
                                .portfolios
                                .iter()
                                .map(|c| c.target_bps)
                                .collect::<Vec<_>>(),
                            index,
                            bps(&v, "weight")?,
                        )?;
                        for (c, w) in data.portfolios.iter_mut().zip(weights) {
                            c.target_bps = w;
                        }
                        data.portfolios[index].name = fui::required(&v, "name", "名称")?;
                        fui::services()
                            .save_finance_portfolio_plan(Some(id.clone()), data, today())
                            .await?;
                        Ok(Some(format!("/wealth/portfolios/{id}/portfolio/{pid}")))
                    })
                },
            );
        }
        let mut body = view()
            .gap_4()
            .child(note(format!(
                "投资用途目标 {}%",
                Decimal::from(child.target_bps) / Decimal::from(100)
            )))
            .child(nav(
                "调整名称与占比",
                format!("/wealth/portfolios/{}/portfolio/{}/edit", p.id, pid),
                "portfolio-purpose-edit",
            ))
            .child(nav(
                "添加策略",
                format!("/wealth/portfolios/{}/sleeve/new/{}", p.id, pid),
                "portfolio-sleeve-add",
            ));
        for sleeve in child.sleeves {
            let path = format!("/wealth/portfolios/{}/sleeve/{}", p.id, sleeve.id);
            body = body.child(fui::row(
                sleeve.name,
                format!(
                    "容忍偏差 {} 个百分点",
                    Decimal::from(sleeve.tolerance_bps) / Decimal::from(100)
                ),
                format!("{}%", Decimal::from(sleeve.target_bps) / Decimal::from(100)),
                format!("sleeve-{}", sleeve.id),
                move || fui::navigate(path.clone()),
            ));
        }
        if p.data.portfolios.len() > 1 {
            body = body.child(nav(
                "移除用途并转移资本",
                format!("/wealth/portfolios/{}/remove-purpose/{pid}", p.id),
                "portfolio-purpose-remove",
            ));
        }
        fui::page(child.name, body.into_element())
    })
}
pub(super) fn add_sleeve(id: String, pid: String) -> AnyElement {
    tree_form(id, move |p| {
        let pid = pid.clone();
        fui::form(
            "添加资本策略",
            vec![
                fui::Field::text("name", "策略名称", "")
                    .help("新增策略从 0% 开始，再调整完整同级配置。"),
            ],
            move |v| {
                let mut data = p.data.clone();
                let id = p.id.clone();
                let pid = pid.clone();
                Box::pin(async move {
                    let portfolio = data
                        .portfolios
                        .iter_mut()
                        .find(|p| p.id == pid)
                        .ok_or("投资用途不存在")?;
                    let sid = lifeos::ids::new_id();
                    portfolio.sleeves.push(Sleeve {
                        id: sid.clone(),
                        name: fui::required(&v, "name", "策略名称")?,
                        target_bps: 0,
                        tolerance_bps: 500,
                        targets: vec![AssetTarget {
                            asset_id: None,
                            weight_bps: 10000,
                        }],
                    });
                    fui::services()
                        .save_finance_portfolio_plan(Some(id.clone()), data, today())
                        .await?;
                    Ok(Some(format!("/wealth/portfolios/{id}/sleeve/{sid}")))
                })
            },
        )
    })
}
pub(super) fn sleeve_node(id: String, sid: String, action: Option<String>) -> AnyElement {
    let lookup = id;
    let freeze_draft = action.as_deref() == Some("edit");
    load_mode(
        "策略配置",
        freeze_draft,
        move |services| {
            let id = lookup.clone();
            Box::pin(async move {
                let p = services
                    .finance_portfolio_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("配置不存在")?;
                Ok((p, services.wealth_assets(true).await?))
            })
        },
        move |(p, assets)| {
            let Some((portfolio, sleeve)) = p.data.portfolios.iter().find_map(|portfolio| {
                portfolio
                    .sleeves
                    .iter()
                    .find(|s| s.id == sid)
                    .map(|s| (portfolio.clone(), s.clone()))
            }) else {
                return error_page();
            };
            if action.as_deref() == Some("edit") {
                let sid = sid.clone();
                let pid = portfolio.id.clone();
                return fui::form(
                    "策略配置",
                    vec![
                        fui::Field::text("name", "策略名称", sleeve.name),
                        fui::Field::decimal(
                            "weight",
                            "策略占比（%）",
                            (Decimal::from(sleeve.target_bps) / Decimal::from(100)).to_string(),
                        )
                        .help("其余同级策略按原比例重新分配；合计保持 100%。"),
                        fui::Field::decimal(
                            "tolerance",
                            "容忍偏差（百分点）",
                            (Decimal::from(sleeve.tolerance_bps) / Decimal::from(100)).to_string(),
                        ),
                    ],
                    move |v| {
                        let mut data = p.data.clone();
                        let id = p.id.clone();
                        let pid = pid.clone();
                        let sid = sid.clone();
                        Box::pin(async move {
                            let portfolio = data
                                .portfolios
                                .iter_mut()
                                .find(|p| p.id == pid)
                                .ok_or("用途不存在")?;
                            let index = portfolio
                                .sleeves
                                .iter()
                                .position(|s| s.id == sid)
                                .ok_or("策略不存在")?;
                            let weights = redistribute(
                                &portfolio
                                    .sleeves
                                    .iter()
                                    .map(|s| s.target_bps)
                                    .collect::<Vec<_>>(),
                                index,
                                bps(&v, "weight")?,
                            )?;
                            for (s, w) in portfolio.sleeves.iter_mut().zip(weights) {
                                s.target_bps = w;
                            }
                            portfolio.sleeves[index].name = fui::required(&v, "name", "名称")?;
                            portfolio.sleeves[index].tolerance_bps = bps(&v, "tolerance")?;
                            fui::services()
                                .save_finance_portfolio_plan(Some(id.clone()), data, today())
                                .await?;
                            Ok(Some(format!("/wealth/portfolios/{id}/sleeve/{sid}")))
                        })
                    },
                );
            }
            let mut body = view()
                .gap_4()
                .child(note(format!(
                    "策略份额 {}% · 容忍 {} 个百分点",
                    Decimal::from(sleeve.target_bps) / Decimal::from(100),
                    Decimal::from(sleeve.tolerance_bps) / Decimal::from(100)
                )))
                .child(nav(
                    "调整策略",
                    format!("/wealth/portfolios/{}/sleeve/{}/edit", p.id, sid),
                    "sleeve-edit",
                ))
                .child(nav(
                    "添加资产目标",
                    format!("/wealth/portfolios/{}/target/{}/new", p.id, sid),
                    "target-add",
                ));
            for (index, target) in sleeve.targets.iter().enumerate() {
                let path = format!("/wealth/portfolios/{}/target/{sid}/{index}", p.id);
                body = body.child(fui::row(
                    target
                        .asset_id
                        .as_ref()
                        .and_then(|id| assets.iter().find(|a| &a.id == id))
                        .map(|a| a.details.name.clone())
                        .unwrap_or_else(|| {
                            if target.asset_id.is_none() {
                                "现金".into()
                            } else {
                                "资产已不可用".into()
                            }
                        }),
                    "策略内目标权重".into(),
                    format!("{}%", Decimal::from(target.weight_bps) / Decimal::from(100)),
                    format!("target-{index}"),
                    move || fui::navigate(path.clone()),
                ));
            }
            if portfolio.sleeves.len() > 1 {
                body = body.child(nav(
                    "移除策略并转移资本",
                    format!("/wealth/portfolios/{}/remove-sleeve/{sid}", p.id),
                    "portfolio-sleeve-remove",
                ));
            }
            fui::page(sleeve.name, body.into_element())
        },
    )
}
