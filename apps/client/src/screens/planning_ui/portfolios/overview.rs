use super::*;

pub(super) fn list_page() -> AnyElement {
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
pub(super) fn tree_form(
    id: String,
    draw: impl Fn(Stored<InvestmentPlan>) -> AnyElement + 'static,
) -> AnyElement {
    tree_mode(id, true, draw)
}
pub(super) fn tree_mode(
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
pub(super) fn create_form() -> AnyElement {
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
pub(super) fn plan_form(id: String) -> AnyElement {
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
pub(super) fn detail(id: String) -> AnyElement {
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
                let (snapshot, assets, receipts, accounts) = tokio::join!(
                    s.finance_portfolio_snapshot(id.clone(), today()),
                    s.wealth_assets(true),
                    s.finance_rebalance_receipts(id),
                    s.finance_accounts(true)
                );
                Ok((p, snapshot?, assets?, receipts?, accounts?))
            })
        },
        |(p, snapshot, assets, receipts, accounts)| {
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
                let quantity = if i.asset_id.is_some() {
                    i.quantity.normalize().to_string()
                } else {
                    let currency = accounts
                        .iter()
                        .find(|(a, _)| a.id == i.account_id)
                        .map(|(a, _)| a.currency.as_str());
                    format!(
                        "{} {}",
                        ui::money_for(i.quantity, currency.unwrap_or_default()),
                        currency.unwrap_or("币种待核对")
                    )
                };
                body = body.child(fui::row(
                    title,
                    sleeve,
                    quantity,
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
