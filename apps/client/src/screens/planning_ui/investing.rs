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
fn goal_list() -> AnyElement {
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
                        ui::money(g.contributed),
                        amount(g.goal.target, &g.goal.currency),
                        ui::ymd(g.goal.target_date)
                    ),
                    format!("余 {}", ui::money(g.remaining)),
                    format!("goal-{}", g.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("储蓄目标", body.into_element())
        },
    )
}
fn goal_form(id: Option<String>) -> AnyElement {
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
                fui::Field::decimal(
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
                fui::Field::decimal(
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
fn goal_detail(id: String) -> AnyElement {
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
                        ui::money(g.goal.target),
                        ui::money(g.remaining),
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
fn contribution_form(id: String) -> AnyElement {
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
                    fui::Field::decimal("amount", "计入此目标的金额", "")
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
fn dca_list() -> AnyElement {
    load(
        "定投计划",
        |s| Box::pin(async move { s.finance_dca_plans().await }),
        |rows| {
            let mut body = view()
                .gap_4()
                .child(nav("新建定投", "/plan/dca/new", "dca-create"));
            if rows.is_empty() {
                body=body.child(note("先定义资产、资金账户、金额与期限；到期后手动成交，并选择真实买入记录完成本期。历史模拟不是保存前提。"));
            }
            for p in rows {
                let path = format!("/plan/dca/{}", p.id);
                body = body.child(fui::row(
                    p.data.name,
                    format!(
                        "每 {} 个月 · {} 个月期限{}",
                        p.data.interval_months,
                        p.data.months,
                        if p.data.paused { " · 已暂停" } else { "" }
                    ),
                    amount(p.data.amount, &p.data.currency),
                    format!("dca-{}", p.id),
                    move || fui::navigate(path.clone()),
                ));
            }
            fui::page("定投计划", body.into_element())
        },
    )
}
fn dca_form(id: Option<String>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "定投设置",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let old = s
                    .finance_dca_plans()
                    .await?
                    .into_iter()
                    .find(|g| Some(&g.id) == id.as_ref())
                    .map(|g| g.data);
                let (assets, accounts, goals) = tokio::join!(
                    s.wealth_assets(false),
                    s.finance_accounts(false),
                    s.finance_goals()
                );
                Ok((old, assets?, accounts?, goals?))
            })
        },
        move |(old, assets, accounts, goals)| {
            let assets = assets
                .into_iter()
                .map(|a| (a.id, format!("{} · {}", a.details.name, a.details.currency)))
                .collect();
            let accounts = accounts
                .into_iter()
                .filter(|(a, _)| {
                    a.side == AccountSide::Asset
                        && matches!(
                            a.kind,
                            AccountCategory::Cash | AccountCategory::Bank | AccountCategory::Broker
                        )
                })
                .map(|(a, _)| (a.id, format!("{} · {}", a.name, a.currency)))
                .collect();
            let mut goal_options = vec![("".into(), "不关联目标".into())];
            goal_options.extend(
                goals
                    .into_iter()
                    .filter(|g| g.goal.asset_id.is_some())
                    .map(|g| (g.id, g.goal.name)),
            );
            let fields = vec![
                fui::Field::text(
                    "name",
                    "计划名称",
                    old.as_ref().map_or("", |g| g.name.as_str()),
                ),
                fui::Field::choice(
                    "asset",
                    "定投资产",
                    old.as_ref().map_or("", |g| g.asset_id.as_str()),
                    assets,
                ),
                fui::Field::choice(
                    "account",
                    "资金账户",
                    old.as_ref().map_or("", |g| g.account_id.as_str()),
                    accounts,
                ),
                fui::Field::text(
                    "currency",
                    "币种",
                    old.as_ref().map_or("CNY", |g| g.currency.as_str()),
                ),
                fui::Field::decimal(
                    "amount",
                    "每期投入金额",
                    old.as_ref()
                        .map(|g| g.amount.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::date(
                    "first",
                    "首次到期日",
                    old.as_ref()
                        .map(|g| ui::ymd(g.first_due))
                        .unwrap_or_else(|| ui::ymd(today())),
                ),
                fui::Field::text(
                    "interval",
                    "间隔月数",
                    old.as_ref()
                        .map(|g| g.interval_months.to_string())
                        .unwrap_or_else(|| "1".into()),
                ),
                fui::Field::text(
                    "months",
                    "计划期限（月）",
                    old.as_ref()
                        .map(|g| g.months.to_string())
                        .unwrap_or_else(|| "12".into()),
                ),
                fui::Field::choice(
                    "goal",
                    "关联投资目标",
                    old.as_ref()
                        .and_then(|g| g.goal_id.clone())
                        .unwrap_or_default(),
                    goal_options,
                )
                .help("目标的资产与币种须一致；真实买入关联后才增加目标进度。"),
                fui::Field::choice(
                    "paused",
                    "计划状态",
                    if old.as_ref().is_some_and(|g| g.paused) {
                        "yes"
                    } else {
                        "no"
                    },
                    vec![
                        ("no".into(), "活动中".into()),
                        ("yes".into(), "暂停未来投入".into()),
                    ],
                ),
            ];
            let id = id.clone();
            fui::form("定投设置", fields, move |v| {
                let id = id.clone();
                Box::pin(async move {
                    let goal = fui::value(&v, "goal");
                    let draft = DcaPlan {
                        name: fui::required(&v, "name", "名称")?,
                        currency: fui::required(&v, "currency", "币种")?,
                        asset_id: fui::required(&v, "asset", "定投资产")?,
                        account_id: fui::required(&v, "account", "资金账户")?,
                        amount: fui::decimal(&v, "amount", "每期金额")?,
                        first_due: fui::date(&v, "first", "首次到期日")?,
                        interval_months: fui::required(&v, "interval", "间隔月数")?
                            .parse()
                            .map_err(|_| "间隔月数须为正整数")?,
                        months: fui::required(&v, "months", "期限")?
                            .parse()
                            .map_err(|_| "期限须为正整数")?,
                        goal_id: (!goal.is_empty()).then_some(goal),
                        paused: fui::value(&v, "paused") == "yes",
                    };
                    let id = fui::services().save_finance_dca(id, draft).await?;
                    Ok(Some(format!("/plan/dca/{id}")))
                })
            })
        },
    )
}
fn dca_detail(id: String) -> AnyElement {
    let lookup = id.clone();
    load(
        "定投进度",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let p = s
                    .finance_dca_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("定投计划不存在")?;
                let until = chrono::DateTime::from_timestamp(p.data.first_due, 0)
                    .and_then(|d| d.checked_add_months(chrono::Months::new(p.data.months)))
                    .ok_or("期限超出范围")?
                    .timestamp();
                let rows = s
                    .finance_dca_occurrences(p.data.first_due, until)
                    .await?
                    .into_iter()
                    .filter(|o| o.template_id == id)
                    .collect::<Vec<_>>();
                Ok((p, rows))
            })
        },
        move |(p, rows)| {
            let done = rows
                .iter()
                .filter(|o| o.state == OccurrenceState::Posted)
                .count();
            let mut body = view()
                .gap_4()
                .child(metric(
                    &p.data.name,
                    format!("{done} 期已完成"),
                    format!(
                        "每期 {} · 已完成只来自真实买入",
                        amount(p.data.amount, &p.data.currency)
                    ),
                ))
                .child(nav(
                    "编辑或暂停",
                    format!("/plan/dca/{}/edit", p.id),
                    "dca-edit",
                ))
                .child(nav(
                    "记录手动买入",
                    format!("/wealth/assets/{}/record/buy", p.data.asset_id),
                    "dca-buy",
                ));
            for o in rows {
                let mut line = view().gap_2().child(note(format!(
                    "{} · {} · {}",
                    ui::ymd(o.due),
                    amount(o.amount, &o.currency),
                    state(o.state)
                )));
                if o.state == OccurrenceState::Due {
                    let sid = p.id.clone();
                    let due = o.due;
                    line = line
                        .child(nav(
                            "关联本期真实买入",
                            format!("/plan/dca/{}/link/{}", p.id, o.due),
                            "dca-link",
                        ))
                        .child(command(
                            "本期跳过",
                            "dca-skip",
                            "本期已跳过；未写入交易",
                            move || {
                                let id = sid.clone();
                                Box::pin(async move {
                                    fui::services().skip_finance_dca_occurrence(id, due).await
                                })
                            },
                        ));
                } else {
                    let sid = p.id.clone();
                    let due = o.due;
                    line = line.child(command(
                        "撤销本期关联",
                        "dca-undo",
                        "计划关联已撤销；真实买入保留",
                        move || {
                            let id = sid.clone();
                            Box::pin(async move {
                                fui::services().undo_finance_dca_occurrence(id, due).await
                            })
                        },
                    ));
                    if let Some(jid) = o.journal_id {
                        line = line.child(nav(
                            "查看真实成交",
                            format!("/activity/entry/{jid}"),
                            "dca-journal",
                        ));
                    }
                }
                body = body.child(fui::section(ui::ymd(o.due), line.into_element()));
            }
            body = body.child(nav(
                "删除未使用定投",
                format!("/plan/dca/{}/delete", p.id),
                "dca-delete",
            ));
            fui::page("定投进度", body.into_element())
        },
    )
}
fn dca_link(id: String, due: i64) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "关联定投成交",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let p = s
                    .finance_dca_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("定投计划不存在")?;
                let operations = s
                    .wealth_operations(Some(p.data.asset_id.clone()))
                    .await?
                    .into_iter()
                    .filter(|o| {
                        o.details.kind == OperationKind::Buy
                            && o.details.cash_account_id.as_ref() == Some(&p.data.account_id)
                            && o.details.date >= due
                    })
                    .collect::<Vec<_>>();
                Ok((p, operations))
            })
        },
        move |(p, operations)| {
            if operations.is_empty() {
                return fui::page("关联定投成交",view().gap_4().child(note("还没有本期、同资产及资金账户的真实买入。请先记录实际成交，再返回关联。" )).child(nav("记录真实买入",format!("/wealth/assets/{}/record/buy",p.data.asset_id),"dca-link-create-buy")).into_element());
            }
            let choices = operations
                .into_iter()
                .map(|o| {
                    (
                        o.id,
                        format!(
                            "{} · {} 股 · 实际现金 {}",
                            ui::ymd(o.details.date),
                            o.details.quantity,
                            amount(o.cash_amount.abs(), &o.currency)
                        ),
                    )
                })
                .collect();
            let id = p.id;
            fui::form(
                "关联定投成交",
                vec![
                    fui::Field::choice("operation", "本期真实买入", "", choices)
                        .help("关联将完成本期计划，不会再写一笔买入，也不会发出券商订单。"),
                ],
                move |v| {
                    let id = id.clone();
                    Box::pin(async move {
                        fui::services()
                            .link_finance_dca_trade(
                                id.clone(),
                                due,
                                fui::required(&v, "operation", "成交记录")?,
                            )
                            .await?;
                        Ok(Some(format!("/plan/dca/{id}")))
                    })
                },
            )
        },
    )
}
fn fire_list() -> AnyElement {
    load(
        "FIRE 规划",
        |s| Box::pin(async move { s.finance_fire_plans().await }),
        |plans| {
            let mut body=view().gap_4().child(nav("新建 FIRE 规划","/plan/fire/new","fire-create")).child(note("以你输入的资本、支出、投入、提取率与实际回报假设计算。无需 AI 模型；不是收益预测或历史回测。"));
            for p in plans {
                let route = format!("/plan/fire/{}", p.id);
                body = body.child(fui::row(
                    p.data.name,
                    format!(
                        "{} 年 · 每月投入 {}",
                        p.data.years,
                        amount(p.data.monthly_contribution, &p.data.currency)
                    ),
                    "查看计算".into(),
                    format!("fire-{}", p.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("FIRE 规划", body.into_element())
        },
    )
}
fn fire_form(id: Option<String>, copy: bool) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "FIRE 假设",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                Ok(s.finance_fire_plans()
                    .await?
                    .into_iter()
                    .find(|p| Some(&p.id) == id.as_ref())
                    .map(|p| p.data))
            })
        },
        move |old| {
            let fields = vec![
                fui::Field::text(
                    "name",
                    "规划或情景名称",
                    old.as_ref()
                        .map(|p| {
                            if copy {
                                format!("{} · 情景", p.name)
                            } else {
                                p.name.clone()
                            }
                        })
                        .unwrap_or_default(),
                ),
                fui::Field::text(
                    "currency",
                    "币种",
                    old.as_ref().map_or("CNY", |p| p.currency.as_str()),
                ),
                fui::Field::decimal(
                    "capital",
                    "起始资本（用户假设）",
                    old.as_ref()
                        .map(|p| p.current_capital.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::decimal(
                    "expense",
                    "每月支出",
                    old.as_ref()
                        .map(|p| p.monthly_expense.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::decimal(
                    "income",
                    "每月收入",
                    old.as_ref()
                        .map(|p| p.monthly_income.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::decimal(
                    "contribution",
                    "每月投入",
                    old.as_ref()
                        .map(|p| p.monthly_contribution.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::decimal(
                    "return",
                    "年实际回报假设（%）",
                    old.as_ref()
                        .map(|p| (p.annual_real_return * Decimal::from(100)).to_string())
                        .unwrap_or_else(|| "0".into()),
                )
                .help("此参数由你设定，不代表行情预测。月增长率按年假设 ÷ 12 计算。"),
                fui::Field::decimal(
                    "withdrawal",
                    "年提取率（%）",
                    old.as_ref()
                        .map(|p| (p.withdrawal_rate * Decimal::from(100)).to_string())
                        .unwrap_or_else(|| "4".into()),
                ),
                fui::Field::text(
                    "years",
                    "计算年数",
                    old.as_ref()
                        .map(|p| p.years.to_string())
                        .unwrap_or_else(|| "30".into()),
                ),
            ];
            let id = if copy { None } else { id.clone() };
            fui::form(
                if copy {
                    "保存对比情景"
                } else {
                    "FIRE 假设"
                },
                fields,
                move |v| {
                    let id = id.clone();
                    Box::pin(async move {
                        let draft = FirePlan {
                            name: fui::required(&v, "name", "规划名称")?,
                            currency: fui::required(&v, "currency", "币种")?,
                            current_capital: fui::decimal(&v, "capital", "起始资本")?,
                            monthly_expense: fui::decimal(&v, "expense", "支出")?,
                            monthly_income: fui::decimal(&v, "income", "收入")?,
                            monthly_contribution: fui::decimal(&v, "contribution", "投入")?,
                            annual_real_return: fui::decimal(&v, "return", "年回报假设")?
                                .checked_div(Decimal::from(100))
                                .ok_or("假设超出范围")?,
                            withdrawal_rate: fui::decimal(&v, "withdrawal", "提取率")?
                                .checked_div(Decimal::from(100))
                                .ok_or("提取率超出范围")?,
                            years: fui::required(&v, "years", "年数")?
                                .parse()
                                .map_err(|_| "年数须为正整数")?,
                        };
                        let id = fui::services().save_finance_fire(id, draft).await?;
                        Ok(Some(format!("/plan/fire/{id}")))
                    })
                },
            )
        },
    )
}
fn fire_detail(id: String) -> AnyElement {
    let lookup = id.clone();
    load(
        "FIRE 计算",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                s.finance_fire_plans()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("规划不存在".into())
            })
        },
        |p| {
            let r = match calculate_fire(&p.data) {
                Ok(r) => r,
                Err(e) => return fui::page("计算未完成", note(e.to_string())),
            };
            let mut body = view()
                .gap_4()
                .child(metric(
                    "目标资本",
                    amount(r.target_capital, &p.data.currency),
                    "年支出 ÷ 提取率".into(),
                ))
                .child(metric(
                    "假设期末资本",
                    amount(r.projected_capital, &p.data.currency),
                    format!(
                        "{} 年 · 起始 {} · 每月投入 {}",
                        p.data.years,
                        ui::money(p.data.current_capital),
                        ui::money(p.data.monthly_contribution)
                    ),
                ))
                .child(note(format!(
                    "储蓄率 {} · 在此假设下{}",
                    r.savings_rate
                        .map(|s| format!("{}%", s * Decimal::from(100)))
                        .unwrap_or_else(|| "收入为零，无法计算".into()),
                    r.months_to_target
                        .map(|m| format!("约 {m} 个月达到目标"))
                        .unwrap_or_else(|| "期限内尚未达到目标".into())
                )))
                .child(fui::line_chart(
                    r.series
                        .into_iter()
                        .map(|(m, value)| (format!("{} 年", m / 12), Some(value)))
                        .collect(),
                    "用户假设下的资本路径".into(),
                ));
            for a in r.assumptions {
                body = body.child(note(a));
            }
            body = body
                .child(nav(
                    "调整假设",
                    format!("/plan/fire/{}/edit", p.id),
                    "fire-edit",
                ))
                .child(nav(
                    "保存一个对比情景",
                    format!("/plan/fire/{}/scenario", p.id),
                    "fire-scenario",
                ))
                .child(nav(
                    "删除规划",
                    format!("/plan/fire/{}/delete", p.id),
                    "fire-delete",
                ));
            fui::page(&p.data.name, body.into_element())
        },
    )
}
