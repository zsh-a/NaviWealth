use super::*;

pub(super) fn dca_list() -> AnyElement {
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
pub(super) fn dca_form(id: Option<String>) -> AnyElement {
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
                fui::Field::money(
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
pub(super) fn dca_detail(id: String) -> AnyElement {
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
pub(super) fn dca_link(id: String, due: i64) -> AnyElement {
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
