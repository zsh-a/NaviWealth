use super::*;

pub(super) fn recurring_list() -> AnyElement {
    load(
        "周期收支",
        |s| Box::pin(async move { s.finance_recurring().await }),
        |rows| {
            let mut body = view().gap_4().child(nav(
                "新建周期收支",
                "/plan/recurring/new",
                "recurring-create",
            ));
            if rows.is_empty() {
                body = body.child(note(
                    "为工资、房租或固定账单设置到期提醒。只有明确确认后才会记入流水。",
                ));
            }
            for row in rows {
                let route = format!("/plan/recurring/{}", row.id);
                body = body.child(fui::row(
                    row.data.name,
                    format!(
                        "每 {} 个月 · {}{}",
                        row.data.interval_months,
                        ui::ymd(row.data.first_due),
                        if row.data.paused { " · 已暂停" } else { "" }
                    ),
                    amount(row.data.amount, &row.data.currency),
                    format!("recurring-{}", row.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("周期收支", body.into_element())
        },
    )
}
pub(super) fn recurring_form(id: Option<String>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "周期收支设置",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let (accounts, expense, income, templates) = tokio::join!(
                    s.finance_accounts(false),
                    s.finance_categories(RecordKind::Expense),
                    s.finance_categories(RecordKind::Income),
                    s.finance_recurring()
                );
                let old = templates?
                    .into_iter()
                    .find(|p| Some(&p.id) == id.as_ref())
                    .map(|p| p.data);
                Ok((accounts?, expense?, income?, old))
            })
        },
        move |(accounts, expense, income, old)| {
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
            let kind = fui::Field::choice(
                "kind",
                "收支类型",
                if old.as_ref().is_some_and(|d| d.kind == FlowKind::Income) {
                    "income"
                } else {
                    "bill"
                },
                vec![
                    ("bill".into(), "固定账单".into()),
                    ("income".into(), "周期收入".into()),
                ],
            );
            let selected = kind.value;
            let fields = vec![
                fui::Field::text("name", "名称", old.as_ref().map_or("", |d| d.name.as_str())),
                kind,
                fui::Field::choice(
                    "account",
                    "资金账户",
                    old.as_ref().map_or("", |d| d.account_id.as_str()),
                    accounts,
                ),
                fui::Field::choice(
                    "expense",
                    "支出分类",
                    old.as_ref().map_or("", |d| d.category_id.as_str()),
                    expense,
                )
                .show_when(move || selected.get() == "bill"),
                fui::Field::choice(
                    "income",
                    "收入分类",
                    old.as_ref().map_or("", |d| d.category_id.as_str()),
                    income,
                )
                .show_when(move || selected.get() == "income"),
                fui::Field::text(
                    "currency",
                    "币种",
                    old.as_ref().map_or("CNY", |d| d.currency.as_str()),
                ),
                fui::Field::money(
                    "amount",
                    "每期金额",
                    old.as_ref()
                        .map(|d| d.amount.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::date(
                    "first",
                    "首次到期日",
                    old.as_ref()
                        .map(|d| ui::ymd(d.first_due))
                        .unwrap_or_else(|| ui::ymd(today())),
                ),
                fui::Field::text(
                    "interval",
                    "间隔月数",
                    old.as_ref()
                        .map_or("1".into(), |d| d.interval_months.to_string()),
                ),
                fui::Field::date(
                    "end",
                    "结束日期（可选）",
                    old.as_ref()
                        .and_then(|d| d.end_due)
                        .map(ui::ymd)
                        .unwrap_or_default(),
                ),
                fui::Field::choice(
                    "paused",
                    "计划状态",
                    if old.as_ref().is_some_and(|d| d.paused) {
                        "yes"
                    } else {
                        "no"
                    },
                    vec![
                        ("no".into(), "活动中".into()),
                        ("yes".into(), "暂停未来到期行动".into()),
                    ],
                )
                .help("已有处理记录时，修改金额或周期请暂停旧计划并新建，避免改写历史。"),
            ];
            let id = id.clone();
            fui::form("周期收支设置", fields, move |v| {
                let id = id.clone();
                Box::pin(async move {
                    let kind = if fui::required(&v, "kind", "收支类型")? == "income" {
                        FlowKind::Income
                    } else {
                        FlowKind::Bill
                    };
                    let end = fui::value(&v, "end");
                    let draft = Recurring {
                        name: fui::required(&v, "name", "名称")?,
                        kind,
                        account_id: fui::required(&v, "account", "资金账户")?,
                        category_id: fui::required(
                            &v,
                            if kind == FlowKind::Income {
                                "income"
                            } else {
                                "expense"
                            },
                            "分类",
                        )?,
                        currency: fui::required(&v, "currency", "币种")?,
                        amount: fui::decimal(&v, "amount", "金额")?,
                        first_due: fui::date(&v, "first", "首次到期日")?,
                        interval_months: fui::required(&v, "interval", "间隔月数")?
                            .parse()
                            .map_err(|_| "间隔月数须为正整数")?,
                        end_due: if end.is_empty() {
                            None
                        } else {
                            Some(fui::date(&v, "end", "结束日期")?)
                        },
                        paused: fui::value(&v, "paused") == "yes",
                    };
                    let saved = fui::services().save_finance_recurring(id, draft).await?;
                    Ok(Some(format!("/plan/recurring/{saved}")))
                })
            })
        },
    )
}
pub(super) fn recurring_detail(id: String) -> AnyElement {
    let lookup = id.clone();
    load(
        "周期收支",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let template = s
                    .finance_recurring()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("计划已删除")?;
                let start = template.data.first_due;
                let until = today().checked_add(366 * 86400).ok_or("日期超出范围")?;
                let rows = s
                    .finance_occurrences(start, until.max(start + 1))
                    .await?
                    .into_iter()
                    .filter(|o| o.template_id == id)
                    .collect::<Vec<_>>();
                Ok((template, rows))
            })
        },
        move |(template, rows)| {
            let mut body = view()
                .gap_4()
                .child(metric(
                    &template.data.name,
                    amount(template.data.amount, &template.data.currency),
                    if template.data.paused {
                        "已暂停；保留历史处理记录".into()
                    } else {
                        "到期行动需逐期明确确认，不会自动扣款".into()
                    },
                ))
                .child(nav(
                    "编辑或暂停",
                    format!("/plan/recurring/{}/edit", template.id),
                    "recurring-edit",
                ));
            for o in rows {
                let jid = o.journal_id.clone();
                body = body.child(fui::section(
                    ui::ymd(o.due),
                    view()
                        .gap_2()
                        .child(note(format!(
                            "{} · {}",
                            amount(o.amount, &o.currency),
                            state(o.state)
                        )))
                        .child(match o.state {
                            OccurrenceState::Due => {
                                let id = o.template_id.clone();
                                let sid = id.clone();
                                let due = o.due;
                                view()
                                    .gap_2()
                                    .child(command(
                                        "确认已发生并入账",
                                        "recurring-post",
                                        "周期收支已入账；账户余额已更新",
                                        move || {
                                            let id = id.clone();
                                            Box::pin(async move {
                                                fui::services()
                                                    .resolve_finance_occurrence(id, due, true)
                                                    .await?;
                                                Ok(())
                                            })
                                        },
                                    ))
                                    .child(command(
                                        "本期跳过",
                                        "recurring-skip",
                                        "本期已跳过",
                                        move || {
                                            let id = sid.clone();
                                            Box::pin(async move {
                                                fui::services()
                                                    .resolve_finance_occurrence(id, due, false)
                                                    .await?;
                                                Ok(())
                                            })
                                        },
                                    ))
                                    .into_element()
                            }
                            _ => {
                                let id = o.template_id.clone();
                                let due = o.due;
                                let mut actions = view().gap_2().child(command(
                                    "撤销本期处理",
                                    "recurring-undo",
                                    "本期处理已撤销；可重新确认",
                                    move || {
                                        let id = id.clone();
                                        Box::pin(async move {
                                            fui::services().undo_finance_occurrence(id, due).await
                                        })
                                    },
                                ));
                                if let Some(jid) = jid {
                                    actions = actions.child(nav(
                                        "查看真实流水",
                                        format!("/activity/entry/{jid}"),
                                        "recurring-journal",
                                    ));
                                }
                                actions.into_element()
                            }
                        })
                        .into_element(),
                ));
            }
            body = body.child(nav(
                "删除未使用计划",
                format!("/plan/recurring/{}/delete", template.id),
                "recurring-delete",
            ));
            fui::page("周期收支", body.into_element())
        },
    )
}
