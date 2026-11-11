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
fn list_page() -> AnyElement {
    load(
        "投资配置",
        |s| Box::pin(async move { s.finance_portfolio_plans().await }),
        |rows| {
            let mut body = view().gap_4().child(nav(
                "新建投资配置",
                "/wealth/portfolios/new",
                "portfolio-create",
            ));
            if rows.is_empty() {
                body=body.child(note("按用途组织投资组合，再用策略分配资本。明确纳入真实持仓和现金，才能看到配置偏差并形成可执行的再平衡任务。"));
            }
            for p in rows {
                let route = format!("/wealth/portfolios/{}", p.id);
                body = body.child(fui::row(
                    p.data.name,
                    format!(
                        "{} 个投资组合 · {} 项纳入资产",
                        p.data.portfolios.len(),
                        p.data.inclusions.len()
                    ),
                    p.data.currency,
                    format!("portfolio-{}", p.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("投资配置", body.into_element())
        },
    )
}
fn tree_form(
    id: String,
    draw: impl Fn(Stored<InvestmentPlan>) -> AnyElement + 'static,
) -> AnyElement {
    tree_mode(id, true, draw)
}
fn tree_mode(
    id: String,
    freeze_draft: bool,
    draw: impl Fn(Stored<InvestmentPlan>) -> AnyElement + 'static,
) -> AnyElement {
    load_mode(
        "投资配置",
        freeze_draft,
        move |s| {
            let id = id.clone();
            Box::pin(async move {
                s.finance_portfolio_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("投资配置已删除".into())
            })
        },
        draw,
    )
}
fn create_form() -> AnyElement {
    fui::form(
        "新建投资配置",
        vec![
            fui::Field::text("name", "配置名称", ""),
            fui::Field::text("currency", "基准币种", "CNY"),
            fui::Field::text("portfolio", "第一个投资用途", ""),
            fui::Field::text("sleeve", "初始策略名称", "")
                .help("首个投资组合与首个策略各占 100%；后续添加同级项后再调整。"),
        ],
        |v| {
            Box::pin(async move {
                let draft = InvestmentPlan {
                    name: fui::required(&v, "name", "配置名称")?,
                    currency: fui::required(&v, "currency", "基准币种")?,
                    portfolios: vec![Portfolio {
                        id: lifeos::ids::new_id(),
                        name: fui::required(&v, "portfolio", "投资用途")?,
                        target_bps: 10000,
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
                    }],
                    inclusions: vec![],
                };
                let id = fui::services()
                    .save_finance_portfolio_plan(None, draft, today())
                    .await?;
                Ok(Some(format!("/wealth/portfolios/{id}")))
            })
        },
    )
}
fn plan_form(id: String) -> AnyElement {
    tree_form(id, |p| {
        fui::form(
            "投资配置设置",
            vec![
                fui::Field::text("name", "配置名称", p.data.name.clone()),
                fui::Field::text("currency", "基准币种", p.data.currency.clone())
                    .help("只改变估值展示币种；不改变真实账户、成本或成交。"),
            ],
            move |v| {
                let mut data = p.data.clone();
                let id = p.id.clone();
                Box::pin(async move {
                    data.name = fui::required(&v, "name", "名称")?;
                    data.currency = fui::required(&v, "currency", "基准币种")?;
                    fui::services()
                        .save_finance_portfolio_plan(Some(id.clone()), data, today())
                        .await?;
                    Ok(Some(format!("/wealth/portfolios/{id}")))
                })
            },
        )
    })
}
fn detail(id: String) -> AnyElement {
    let lookup = id.clone();
    load(
        "投资配置",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let p = s
                    .finance_portfolio_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("配置不存在")?;
                let (snapshot, assets, receipts) = tokio::join!(
                    s.finance_portfolio_snapshot(id.clone(), today()),
                    s.wealth_assets(true),
                    s.finance_rebalance_receipts(id)
                );
                Ok((p, snapshot?, assets?, receipts?))
            })
        },
        |(p, snapshot, assets, receipts)| {
            let mut body = view()
                .gap_4()
                .child(metric(
                    &p.data.name,
                    snapshot
                        .total_value
                        .map(|v| amount(v, &snapshot.currency))
                        .unwrap_or_else(|| "估值依据不足".into()),
                    "仅统计已明确纳入的独占资本；未纳入资产不参与此配置".into(),
                ))
                .child(nav(
                    "纳入持仓或现金",
                    format!("/wealth/portfolios/{}/include", p.id),
                    "portfolio-include",
                ))
                .child(nav(
                    "配置名称与币种",
                    format!("/wealth/portfolios/{}/edit", p.id),
                    "portfolio-edit",
                ));
            for warning in &snapshot.warnings {
                body = body.child(note(warning.clone()));
            }
            for missing in &snapshot.missing_values {
                body = body.child(note(format!("估值或数量不可用：{missing}")));
            }
            body = body.child(fui::section(
                "投资组合",
                nav(
                    "添加投资用途",
                    format!("/wealth/portfolios/{}/portfolio/new", p.id),
                    "portfolio-add-purpose",
                ),
            ));
            for child in &p.data.portfolios {
                let actual = snapshot
                    .allocations
                    .iter()
                    .find(|a| a.portfolio_id == child.id && a.sleeve_id.is_none());
                let path = format!("/wealth/portfolios/{}/portfolio/{}", p.id, child.id);
                body = body.child(fui::row(
                    child.name.clone(),
                    format!(
                        "目标 {}% · {} 个策略",
                        Decimal::from(child.target_bps) / Decimal::from(100),
                        child.sleeves.len()
                    ),
                    actual
                        .and_then(|a| a.actual_bps)
                        .map(|a| format!("实际 {}%", a / Decimal::from(100)))
                        .unwrap_or_else(|| "实际权重不可用".into()),
                    format!("portfolio-purpose-{}", child.id),
                    move || fui::navigate(path.clone()),
                ));
            }
            body = body.child(fui::section(
                "纳入资产",
                note("同一账户的现金或持仓可部分纳入，但全部配置合计不得超过真实可用量。"),
            ));
            for (index, i) in p.data.inclusions.iter().enumerate() {
                let title = i
                    .asset_id
                    .as_ref()
                    .and_then(|id| assets.iter().find(|a| &a.id == id))
                    .map(|a| a.details.name.clone())
                    .unwrap_or_else(|| "现金".into());
                let sleeve = p
                    .data
                    .portfolios
                    .iter()
                    .flat_map(|p| p.sleeves.iter())
                    .find(|s| s.id == i.sleeve_id)
                    .map(|s| s.name.clone())
                    .unwrap_or_else(|| "策略不可用".into());
                let path = format!("/wealth/portfolios/{}/include/{index}", p.id);
                body = body.child(fui::row(
                    title,
                    sleeve,
                    i.quantity.to_string(),
                    format!("portfolio-inclusion-{index}"),
                    move || fui::navigate(path.clone()),
                ));
            }
            body=body.child(fui::section("再平衡",note(if snapshot.transfers_pending{"先调整投资组合或策略之间的纳入资产；资本归属回到容忍范围后，再生成内部交易任务。"}else{"以下任务按真实估值与目标推导；成交必须由你手动记录。"})));
            for task in snapshot.tasks {
                let label = task
                    .asset_id
                    .as_ref()
                    .and_then(|id| assets.iter().find(|a| &a.id == id))
                    .map(|a| a.details.name.clone())
                    .unwrap_or_else(|| "现金".into());
                body = body.child(note(format!(
                    "{label} · {} {} · {}",
                    if task.delta_value > Decimal::ZERO {
                        "增加"
                    } else {
                        "减少"
                    },
                    amount(task.delta_value.abs(), &snapshot.currency),
                    task.reason
                )));
                if let Some(asset) = task.asset_id {
                    body = body.child(nav(
                        "记录实际成交",
                        format!(
                            "/wealth/assets/{asset}/record/{}",
                            if task.delta_value > Decimal::ZERO {
                                "buy"
                            } else {
                                "sell"
                            }
                        ),
                        "rebalance-record",
                    ));
                }
            }
            body = body.child(nav(
                "关联已记录的再平衡成交",
                format!("/wealth/portfolios/{}/rebalance", p.id),
                "rebalance-link",
            ));
            for receipt in receipts {
                let path = format!(
                    "/wealth/portfolios/{}/unlink/{}",
                    p.id, receipt.data.operation_id
                );
                body = body.child(fui::row(
                    "已关联再平衡成交".into(),
                    ui::ymd(receipt.data.recorded_on),
                    "撤销关联".into(),
                    format!("rebalance-receipt-{}", receipt.id),
                    move || fui::navigate(path.clone()),
                ));
            }
            body = body.child(nav(
                "删除未使用配置",
                format!("/wealth/portfolios/{}/delete", p.id),
                "portfolio-delete",
            ));
            fui::page("投资配置", body.into_element())
        },
    )
}
fn add_portfolio(id: String) -> AnyElement {
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
fn redistribute(weights: &[u32], index: usize, target: u32) -> Result<Vec<u32>, String> {
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
fn bps(v: &fui::Values, id: &str) -> Result<u32, String> {
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
fn portfolio_node(id: String, pid: String, action: Option<String>) -> AnyElement {
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
fn add_sleeve(id: String, pid: String) -> AnyElement {
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
fn sleeve_node(id: String, sid: String, action: Option<String>) -> AnyElement {
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
fn target_form(id: String, sid: String, index: Option<String>) -> AnyElement {
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
fn inclusion_form(id: String, index: Option<usize>) -> AnyElement {
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
            let fields = vec![
                fui::Field::choice("source", "真实持仓或现金", selected, options),
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
fn rebalance_form(id: String) -> AnyElement {
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
fn unlink_form(id: String, operation: String) -> AnyElement {
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
fn remove_node_form(id: String, purpose: bool, node: String) -> AnyElement {
    tree_form(id, move |p| {
        let source_portfolio = p
            .data
            .portfolios
            .iter()
            .find(|p| {
                if purpose {
                    p.id == node
                } else {
                    p.sleeves.iter().any(|s| s.id == node)
                }
            })
            .cloned();
        let Some(source) = source_portfolio else {
            return error_page();
        };
        let choices = p
            .data
            .portfolios
            .iter()
            .filter(|p| {
                if purpose {
                    p.id != node
                } else {
                    p.id == source.id
                }
            })
            .flat_map(|p| {
                p.sleeves
                    .iter()
                    .filter(|s| purpose || s.id != node)
                    .map(|s| (s.id.clone(), format!("{} / {}", p.name, s.name)))
            })
            .collect::<Vec<_>>();
        let node = node.clone();
        fui::form(
            if purpose {
                "移除投资用途"
            } else {
                "移除资本策略"
            },
            vec![
                fui::Field::choice("receiver", "接收资本的策略", "", choices)
                    .help("源配置的目标份额与纳入资产一起转移；真实账户、持仓及成交不会改写。"),
                fui::Field::choice(
                    "confirm",
                    "确认处理",
                    "keep",
                    vec![
                        ("keep".into(), "保留当前配置".into()),
                        ("remove".into(), "移除并转移资本".into()),
                    ],
                ),
            ],
            move |v| {
                let mut data = p.data.clone();
                let id = p.id.clone();
                let node = node.clone();
                Box::pin(async move {
                    if fui::value(&v, "confirm") != "remove" {
                        return Err("请选择移除并转移，或返回保留配置".into());
                    }
                    let receiver = fui::required(&v, "receiver", "接收策略")?;
                    let receiver_portfolio = data
                        .portfolios
                        .iter()
                        .find(|p| p.sleeves.iter().any(|s| s.id == receiver))
                        .map(|p| p.id.clone())
                        .ok_or("接收策略不存在")?;
                    if purpose {
                        if receiver_portfolio == node || data.portfolios.len() < 2 {
                            return Err("必须保留至少一个投资用途".into());
                        }
                        let index = data
                            .portfolios
                            .iter()
                            .position(|p| p.id == node)
                            .ok_or("源用途不存在")?;
                        let removed = data.portfolios.remove(index);
                        let receiving = data
                            .portfolios
                            .iter_mut()
                            .find(|p| p.id == receiver_portfolio)
                            .ok_or("接收用途不存在")?;
                        receiving.target_bps = receiving
                            .target_bps
                            .checked_add(removed.target_bps)
                            .ok_or("目标份额超出范围")?;
                        for i in &mut data.inclusions {
                            if i.portfolio_id == node {
                                i.portfolio_id = receiver_portfolio.clone();
                                i.sleeve_id = receiver.clone();
                            }
                        }
                    } else {
                        let portfolio = data
                            .portfolios
                            .iter_mut()
                            .find(|p| p.sleeves.iter().any(|s| s.id == node))
                            .ok_or("源策略不存在")?;
                        if portfolio.id != receiver_portfolio || portfolio.sleeves.len() < 2 {
                            return Err("接收策略须与源策略同属一个用途，且至少保留一个策略".into());
                        }
                        let index = portfolio
                            .sleeves
                            .iter()
                            .position(|s| s.id == node)
                            .ok_or("源策略不存在")?;
                        let removed = portfolio.sleeves.remove(index);
                        let receiving = portfolio
                            .sleeves
                            .iter_mut()
                            .find(|s| s.id == receiver)
                            .ok_or("接收策略不存在")?;
                        receiving.target_bps = receiving
                            .target_bps
                            .checked_add(removed.target_bps)
                            .ok_or("目标份额超出范围")?;
                        for i in &mut data.inclusions {
                            if i.sleeve_id == node {
                                i.sleeve_id = receiver.clone();
                            }
                        }
                    }
                    fui::services()
                        .save_finance_portfolio_plan(Some(id.clone()), data, today())
                        .await?;
                    Ok(Some(format!("/wealth/portfolios/{id}")))
                })
            },
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn complete_sibling_weights_stay_exact() {
        assert_eq!(
            redistribute(&[5000, 3000, 2000], 0, 4000).unwrap(),
            vec![4000, 3600, 2400]
        );
        assert_eq!(
            redistribute(&[10000, 0], 1, 3333).unwrap(),
            vec![6667, 3333]
        );
        assert_eq!(
            redistribute(&[0, 0, 10000], 2, 0).unwrap(),
            vec![5000, 5000, 0]
        );
        assert!(redistribute(&[10000], 0, 5000).is_err());
    }
}
