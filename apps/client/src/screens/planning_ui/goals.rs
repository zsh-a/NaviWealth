use super::*;

pub(super) fn goal_list() -> AnyElement {
    load(
        "储蓄目标",
        |s| Box::pin(async move { s.finance_goals().await }),
        |rows| {
            let mut body = view()
                .gap_4()
                .child(nav("新建目标", "/plan/goals/new", "goal-create"));
            if rows.is_empty() {
                body = body.child(note(
                    "为一个用途设定目标，随后关联真实储蓄转账或证券买入；进度不会凭空增加。",
                ));
            }
            for g in rows {
                let route = format!("/plan/goals/{}", g.id);
                body = body.child(fui::row(
                    g.goal.name,
                    format!(
                        "已投入 {} / 目标 {} · {}",
                        ui::money_for(g.contributed, &g.goal.currency),
                        amount(g.goal.target, &g.goal.currency),
                        ui::ymd(g.goal.target_date)
                    ),
                    format!("余 {}", ui::money_for(g.remaining, &g.goal.currency)),
                    format!("goal-{}", g.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("储蓄目标", body.into_element())
        },
    )
}
pub(super) fn goal_form(id: Option<String>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "目标设置",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let goals = s.finance_goals().await?;
                let old = goals
                    .into_iter()
                    .find(|g| Some(&g.id) == id.as_ref())
                    .map(|g| g.goal);
                Ok((old, s.wealth_assets(false).await?))
            })
        },
        move |(old, assets)| {
            let mut choices = vec![("".into(), "现金储蓄 · 关联真实转账".into())];
            choices.extend(
                assets
                    .into_iter()
                    .map(|a| (a.id, format!("{} · {}", a.details.name, a.details.currency))),
            );
            let fields = vec![
                fui::Field::text(
                    "name",
                    "目标名称",
                    old.as_ref().map_or("", |g| g.name.as_str()),
                ),
                fui::Field::text(
                    "currency",
                    "目标币种",
                    old.as_ref().map_or("CNY", |g| g.currency.as_str()),
                ),
                fui::Field::money(
                    "target",
                    "目标金额",
                    old.as_ref()
                        .map(|g| g.target.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::date(
                    "date",
                    "目标日期",
                    old.as_ref()
                        .map(|g| ui::ymd(g.target_date))
                        .unwrap_or_else(|| ui::ymd(today() + 365 * 86400)),
                ),
                fui::Field::money(
                    "monthly",
                    "计划每月投入",
                    old.as_ref()
                        .map(|g| g.monthly_contribution.to_string())
                        .unwrap_or_else(|| "0".into()),
                )
                .help("这是计划假设；真实进度由已关联的转账或买入记录计算。"),
                fui::Field::choice(
                    "asset",
                    "投入类型",
                    old.as_ref()
                        .and_then(|g| g.asset_id.clone())
                        .unwrap_or_default(),
                    choices,
                ),
            ];
            let id = id.clone();
            fui::form("目标设置", fields, move |v| {
                let id = id.clone();
                Box::pin(async move {
                    let asset = fui::value(&v, "asset");
                    let draft = Goal {
                        name: fui::required(&v, "name", "目标名称")?,
                        currency: fui::required(&v, "currency", "币种")?,
                        target: fui::decimal(&v, "target", "目标金额")?,
                        target_date: fui::date(&v, "date", "目标日期")?,
                        monthly_contribution: fui::decimal(&v, "monthly", "每月投入")?,
                        asset_id: (!asset.is_empty()).then_some(asset),
                    };
                    let id = fui::services().save_finance_goal(id, draft).await?;
                    Ok(Some(format!("/plan/goals/{id}")))
                })
            })
        },
    )
}
pub(super) fn goal_detail(id: String) -> AnyElement {
    let lookup = id.clone();
    load(
        "目标进度",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let goal = s
                    .finance_goals()
                    .await?
                    .into_iter()
                    .find(|g| g.id == id)
                    .ok_or("目标已删除")?;
                let mut entries = Vec::new();
                for id in &goal.contribution_ids {
                    entries.push(s.finance_record(id).await?);
                }
                Ok((goal, entries))
            })
        },
        move |(g, entries)| {
            let mut body = view()
                .gap_4()
                .child(metric(
                    &g.goal.name,
                    amount(g.contributed, &g.goal.currency),
                    format!(
                        "目标 {} · 剩余 {} · {}",
                        ui::money_for(g.goal.target, &g.goal.currency),
                        ui::money_for(g.remaining, &g.goal.currency),
                        ui::ymd(g.goal.target_date)
                    ),
                ))
                .child(note(format!(
                    "计划每月 {}；此假设不会当作已完成投入。",
                    amount(g.goal.monthly_contribution, &g.goal.currency)
                )))
                .child(nav(
                    "关联实际投入",
                    format!("/plan/goals/{}/contribute", g.id),
                    "goal-contribute",
                ))
                .child(nav(
                    "修改目标",
                    format!("/plan/goals/{}/edit", g.id),
                    "goal-edit",
                ));
            for r in entries {
                let jid = r.id.clone();
                let gid = g.id.clone();
                body = body.child(fui::section(
                    ui::ymd(r.date),
                    view()
                        .gap_2()
                        .child(nav(
                            "查看真实投入记录",
                            format!("/activity/entry/{}", r.id),
                            "goal-journal",
                        ))
                        .child(command(
                            "解除目标关联",
                            "goal-unlink",
                            "目标关联已解除，真实记录保留",
                            move || {
                                let gid = gid.clone();
                                let jid = jid.clone();
                                Box::pin(async move {
                                    fui::services()
                                        .unlink_finance_goal_contribution(gid, jid)
                                        .await
                                })
                            },
                        ))
                        .into_element(),
                ));
            }
            body = body
                .child(nav("查看定投计划", "/plan/dca", "goal-dca"))
                .child(nav(
                    "删除未使用目标",
                    format!("/plan/goals/{}/delete", g.id),
                    "goal-delete",
                ));
            fui::page("目标进度", body.into_element())
        },
    )
}
pub(super) fn contribution_form(id: String) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "关联实际投入",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let g = s
                    .finance_goals()
                    .await?
                    .into_iter()
                    .find(|g| g.id == id)
                    .ok_or("目标不存在")?;
                Ok((g, s.finance_contribution_candidates(id).await?))
            })
        },
        move |(g, rows)| {
            if rows.is_empty() {
                return fui::page("关联实际投入",view().gap_4().child(note("还没有符合目标币种及投入类型的真实记录。先记录储蓄转账或证券买入，再回来关联；收入和期初余额不作为目标投入。" )).child(nav("查看流水","/activity","goal-no-candidates")).into_element());
            }
            let options = rows
                .into_iter()
                .map(|r| {
                    (
                        r.journal_id,
                        format!(
                            "{} · {} · 可关联 {}",
                            ui::ymd(r.date),
                            r.narration,
                            amount(r.eligible_amount, &r.currency)
                        ),
                    )
                })
                .collect();
            let id = g.id;
            fui::form(
                "关联实际投入",
                vec![
                    fui::Field::choice("journal", "真实投入记录", "", options),
                    fui::Field::money("amount", "计入此目标的金额", "")
                        .currency(move || g.goal.currency.clone())
                        .help("金额不得超过所选记录的实际投入，同一记录不能重复用于多个目标。"),
                ],
                move |v| {
                    let id = id.clone();
                    Box::pin(async move {
                        fui::services()
                            .contribute_finance_goal(
                                id.clone(),
                                fui::required(&v, "journal", "投入记录")?,
                                fui::decimal(&v, "amount", "投入金额")?,
                            )
                            .await?;
                        Ok(Some(format!("/plan/goals/{id}")))
                    })
                },
            )
        },
    )
}
