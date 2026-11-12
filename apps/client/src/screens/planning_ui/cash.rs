use super::*;
use naviwealth_finance::{
    daily::RecordKind,
    models::{AccountCategory, AccountSide},
};

pub(super) fn render(p: Vec<String>) -> AnyElement {
    let area = p.get(1).map(String::as_str).unwrap_or("");
    let id = p.get(2).cloned();
    let action = p.get(3).map(String::as_str);
    match (area, id.as_deref(), action) {
        ("budgets", None, _) => budget_list(month()),
        ("budgets", Some("period"), Some(_)) => budget_list(p[3].clone()),
        ("budgets", Some("choose-month"), _) => budget_month_form(),
        ("budgets", Some("new"), _) => budget_form(None),
        ("budgets", Some(_), Some("edit")) => budget_form(id),
        ("budgets", Some(_), Some("delete")) => remove_page(
            "删除预算",
            PlanKind::Budget,
            id.unwrap(),
            "/plan/budgets".into(),
        ),
        ("budgets", Some(_), _) => budget_detail(id.unwrap()),
        ("recurring", None, _) => recurring_list(),
        ("recurring", Some("new"), _) => recurring_form(None),
        ("recurring", Some(_), Some("edit")) => recurring_form(id),
        ("recurring", Some(_), Some("delete")) => remove_page(
            "删除周期计划",
            PlanKind::Recurring,
            id.unwrap(),
            "/plan/recurring".into(),
        ),
        ("recurring", Some(_), _) => recurring_detail(id.unwrap()),
        ("liabilities", None, _) => loan_list(),
        ("liabilities", Some("new"), _) => loan_form(None),
        ("liabilities", Some(_), Some("edit")) => loan_form(id),
        ("liabilities", Some(_), Some("delete")) => loan_delete(id.unwrap()),
        ("liabilities", Some(_), Some("pay")) => loan_pay(
            id.unwrap(),
            p.get(4).and_then(|v| v.parse().ok()).unwrap_or(u32::MAX),
        ),
        ("liabilities", Some(_), _) => loan_detail(id.unwrap()),
        ("runway", Some("scenario"), Some("new")) => scenario_form(None),
        ("runway", Some("scenario"), Some(_)) => scenario_form(p.get(3).cloned()),
        ("runway", Some("currency"), Some(_)) => runway_page(p[3].clone()),
        ("runway", Some("select-currency"), _) => runway_currency_form(),
        ("runway", _, _) => runway_page("CNY".into()),
        _ => error_page(),
    }
}
fn budget_list(selected_month: String) -> AnyElement {
    let period = signal(selected_month);
    let data_period = period;
    // The month picker is an explicit route to keep the current period recoverable.
    load(
        "分类预算",
        move |s| {
            let m = data_period.get();
            Box::pin(async move {
                Ok((
                    s.finance_budgets(m).await?,
                    s.finance_categories(RecordKind::Expense).await?,
                ))
            })
        },
        move |(budgets, categories)| {
            let mut body = view()
                .gap_4()
                .child(note(format!(
                    "{} · 预算只统计对应分类、币种的真实支出；转账与期初余额不计入。",
                    period.get()
                )))
                .child(nav("设置分类预算", "/plan/budgets/new", "budget-create"))
                .child(nav(
                    "切换月份",
                    "/plan/budgets/choose-month",
                    "budget-period",
                ));
            if budgets.is_empty() {
                body = body.child(note("本月尚未设置预算。选择常用分类，为本月安排一个额度。"));
            }
            for b in budgets {
                let route = format!("/plan/budgets/{}", b.id);
                body = body.child(fui::row(
                    format!(
                        "{} · {}",
                        categories
                            .iter()
                            .find(|(id, _)| id == &b.budget.category_id)
                            .map(|(_, name)| name.clone())
                            .unwrap_or_else(|| "历史分类".into()),
                        b.budget.month
                    ),
                    format!(
                        "已花 {} / 额度 {}",
                        amount(b.spent, &b.budget.currency),
                        amount(b.budget.limit, &b.budget.currency)
                    ),
                    if b.remaining < Decimal::ZERO {
                        format!("超出 {}", ui::money(b.remaining.abs()))
                    } else {
                        format!("余 {}", ui::money(b.remaining))
                    },
                    format!("budget-{}", b.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("分类预算", body.into_element())
        },
    )
}
fn budget_month_form() -> AnyElement {
    fui::form(
        "选择预算月份",
        vec![
            fui::Field::text("month", "月份", month())
                .help("YYYY-MM；可查看历史预算或选择未来月份。"),
        ],
        |v| {
            Box::pin(async move {
                let m = fui::required(&v, "month", "月份")?;
                month_bounds(&m).map_err(|e| e.to_string())?;
                Ok(Some(format!("/plan/budgets/period/{m}")))
            })
        },
    )
}
fn budget_form(id: Option<String>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "设置预算",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let categories = s.finance_categories(RecordKind::Expense).await?;
                let existing = if let Some(id) = id {
                    Some(s.finance_budget(id).await?.budget)
                } else {
                    None
                };
                Ok((categories, existing))
            })
        },
        move |(categories, old)| {
            let old_month = old.as_ref().map_or_else(month, |b| b.month.clone());
            let old_category = old
                .as_ref()
                .map(|b| b.category_id.clone())
                .unwrap_or_default();
            let old_code = old.as_ref().map_or("CNY", |b| b.currency.as_str());
            let old_limit = old
                .as_ref()
                .map(|b| b.limit.to_string())
                .unwrap_or_default();
            let fields = vec![
                fui::Field::text("month", "预算月份", old_month)
                    .help("格式 YYYY-MM；同一月份、分类、币种保存时更新现有额度。"),
                fui::Field::choice("category", "支出分类", old_category, categories),
                fui::Field::text("currency", "币种", old_code),
                fui::Field::decimal("limit", "本月额度", old_limit),
            ];
            let previous = old.clone();
            fui::form("设置预算", fields, move |v| {
                let previous = previous.clone();
                Box::pin(async move {
                    let draft = Budget {
                        month: fui::required(&v, "month", "月份")?,
                        category_id: fui::required(&v, "category", "支出分类")?,
                        currency: fui::required(&v, "currency", "币种")?,
                        limit: fui::decimal(&v, "limit", "预算额度")?,
                    };
                    if previous.is_some_and(|p| {
                        p.month != draft.month
                            || p.category_id != draft.category_id
                            || p.currency != draft.currency
                    }) {
                        return Err("调整已有预算只修改额度；不同月份、分类或币种请新建预算".into());
                    }
                    let receipt = format!(
                        "额度已更新为 {}；已花与剩余额度已重新核对。",
                        amount(draft.limit, &draft.currency)
                    );
                    let id = fui::services().save_finance_budget(draft).await?;
                    fui::acknowledge(format!("/plan/budgets/{id}"), receipt);
                    fui::notice("预算额度已更新");
                    Ok(Some(format!("/plan/budgets/{id}")))
                })
            })
        },
    )
}
fn budget_detail(id: String) -> AnyElement {
    let lookup = id.clone();
    load(
        "预算详情",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let budget = s.finance_budget(id).await?;
                let mut rows = Vec::new();
                for jid in &budget.entry_ids {
                    rows.push(s.finance_record(jid).await?);
                }
                Ok((budget, rows))
            })
        },
        move |(b, rows)| {
            let edit = format!("/plan/budgets/{}/edit", b.id);
            let delete = format!("/plan/budgets/{}/delete", b.id);
            let mut body = view()
                .gap_4()
                .child(fui::changed_fact(
                    format!("/plan/budgets/{}", b.id),
                    metric(
                        "本月已花",
                        amount(b.spent, &b.budget.currency),
                        format!(
                            "额度 {} · 剩余 {}",
                            amount(b.budget.limit, &b.budget.currency),
                            amount(b.remaining, &b.budget.currency)
                        ),
                    ),
                ))
                .child(nav("调整额度", edit, "budget-edit"))
                .child(fui::section(
                    "贡献支出",
                    note("下列记录与预算统计使用同一精确集合。"),
                ));
            for record in rows {
                let route = format!("/activity/entry/{}", record.id);
                body = body.child(fui::row(
                    record.note.unwrap_or_else(|| record.kind.label().into()),
                    format!("{} · {}", ui::ymd(record.date), record.account_name),
                    amount(record.amount, &record.currency),
                    format!("budget-record-{}", record.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            body = body.child(nav("删除预算", delete, "budget-delete"));
            fui::page("预算详情", body.into_element())
        },
    )
}
fn recurring_list() -> AnyElement {
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
fn recurring_form(id: Option<String>) -> AnyElement {
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
                fui::Field::decimal(
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
fn recurring_detail(id: String) -> AnyElement {
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
pub(super) fn state(s: OccurrenceState) -> &'static str {
    match s {
        OccurrenceState::Due => "待处理",
        OccurrenceState::Posted => "已入账 / 已关联",
        OccurrenceState::Skipped => "已跳过",
    }
}
fn loan_list() -> AnyElement {
    load(
        "贷款与还款",
        |s| Box::pin(async move { s.finance_liabilities().await }),
        |rows| {
            let mut body = view().gap_4().child(nav(
                "添加贷款",
                "/wealth/liabilities/new",
                "liability-create",
            ));
            if rows.is_empty() {
                body=body.child(note("记录当前待还本金与合同假设，系统生成等额本金计划。后续每笔还款都连接真实现金账户。"));
            }
            for row in rows {
                let route = format!("/wealth/liabilities/{}", row.id);
                body = body.child(fui::row(
                    row.data.terms.name,
                    format!(
                        "{} 期 · 年利率 {}%{}",
                        row.data.terms.months,
                        row.data.terms.annual_rate * Decimal::from(100),
                        if row.data.archived {
                            " · 已归档"
                        } else {
                            ""
                        }
                    ),
                    amount(row.data.terms.principal, &row.data.terms.currency),
                    format!("liability-{}", row.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("贷款与还款", body.into_element())
        },
    )
}
fn loan_form(id: Option<String>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "贷款合同",
        move |services| {
            let id = lookup.clone();
            Box::pin(async move {
                Ok(services
                    .finance_liabilities()
                    .await?
                    .into_iter()
                    .find(|l| Some(&l.id) == id.as_ref())
                    .map(|l| l.data.terms))
            })
        },
        move |old| {
            let id = id.clone();
            fui::form("贷款合同",vec![fui::Field::text("name","贷款名称",old.as_ref().map_or("",|l|l.name.as_str())),fui::Field::text("currency","币种",old.as_ref().map_or("CNY",|l|l.currency.as_str())),fui::Field::decimal("principal","当前待还本金",old.as_ref().map(|l|l.principal.to_string()).unwrap_or_default()).help("本金作为债务期初余额，不会虚构现金收入。合同已发生还款时须先撤销还款才能修正。"),fui::Field::decimal("rate","合同年利率（%）",old.as_ref().map(|l|(l.annual_rate*Decimal::from(100)).to_string()).unwrap_or_default()),fui::Field::text("months","剩余期数（月）",old.as_ref().map(|l|l.months.to_string()).unwrap_or_else(||"12".into())),fui::Field::date("opened","本金记录日期",old.as_ref().map(|l|ui::ymd(l.opened_on)).unwrap_or_else(||ui::ymd(today()))),fui::Field::date("first","首次还款日",old.as_ref().map(|l|ui::ymd(l.first_due)).unwrap_or_else(||ui::ymd(today())))],move|v|{let id=id.clone();Box::pin(async move{let draft=LiabilityDraft{name:fui::required(&v,"name","名称")?,currency:fui::required(&v,"currency","币种")?,principal:fui::decimal(&v,"principal","本金")?,annual_rate:fui::decimal(&v,"rate","年利率")?.checked_div(Decimal::from(100)).ok_or("利率超出范围")?,months:fui::required(&v,"months","剩余期数")?.parse().map_err(|_|"期数须为正整数")?,opened_on:fui::date(&v,"opened","本金记录日期")?,first_due:fui::date(&v,"first","首次还款日")?};let id=if let Some(id)=id{fui::services().update_finance_liability(id.clone(),draft).await?;id}else{fui::services().create_finance_liability(draft).await?};Ok(Some(format!("/wealth/liabilities/{id}")))})})
        },
    )
}
fn loan_delete(id: String) -> AnyElement {
    fui::form(
        "删除未发生还款的贷款",
        vec![
            fui::Field::choice(
                "confirm",
                "确认处理",
                "keep",
                vec![
                    ("keep".into(), "保留贷款".into()),
                    ("delete".into(), "删除合同及其债务期初余额".into()),
                ],
            )
            .help("只允许没有还款和其他关联流水的贷款。已有记录请保留合同并核对。"),
        ],
        move |v| {
            let id = id.clone();
            Box::pin(async move {
                if fui::value(&v, "confirm") != "delete" {
                    return Err("请选择删除，或返回保留贷款".into());
                }
                fui::services().delete_finance_liability(id).await?;
                Ok(Some("/wealth/liabilities".into()))
            })
        },
    )
}

fn loan_detail(id: String) -> AnyElement {
    let lookup = id.clone();
    load(
        "还款计划",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let loan = s
                    .finance_liabilities()
                    .await?
                    .into_iter()
                    .find(|p| p.id == id)
                    .ok_or("贷款不存在")?;
                let schedule = s.finance_liability_schedule(id).await?;
                Ok((loan, schedule))
            })
        },
        move |(loan, schedule)| {
            let paid = schedule
                .iter()
                .filter(|i| i.state == OccurrenceState::Posted)
                .count();
            let remaining = schedule
                .iter()
                .filter(|i| i.state != OccurrenceState::Posted)
                .try_fold(Decimal::ZERO, |sum, i| sum.checked_add(i.principal));
            let mut body=view().gap_4().child(metric("剩余计划本金",remaining.map(|v|amount(v,&loan.data.terms.currency)).unwrap_or_else(||"金额超出范围".into()),format!("{} · 已还 {paid} / {} 期 · 等额本金，利息按计划余额计算",loan.data.terms.name,loan.data.terms.months))).child(note("这是按合同假设生成的计划；银行实际扣款请核对。本金与利息拆分记账，不会把本金计作消费。"));
            body = body.child(nav(
                "修正尚未还款的合同",
                format!("/wealth/liabilities/{}/edit", loan.id),
                "liability-edit",
            ));
            if paid == 0 {
                body = body.child(nav(
                    "删除尚未使用的合同",
                    format!("/wealth/liabilities/{}/delete", loan.id),
                    "liability-delete",
                ));
            }
            if paid == loan.data.terms.months as usize {
                let id = loan.id.clone();
                let archived = loan.data.archived;
                body = body.child(command(
                    if archived {
                        "恢复展示贷款"
                    } else {
                        "归档已清偿贷款"
                    },
                    "liability-archive",
                    "贷款展示状态已更新",
                    move || {
                        let id = id.clone();
                        Box::pin(async move {
                            fui::services()
                                .archive_finance_liability(id, !archived)
                                .await
                        })
                    },
                ));
            }
            for i in schedule {
                let mut row = view()
                    .gap_2()
                    .child(note(format!(
                        "第 {} 期 · {} · {}",
                        i.index + 1,
                        ui::ymd(i.due),
                        state(i.state)
                    )))
                    .child(note(format!(
                        "本金 {} + 利息 {} = {}",
                        ui::money(i.principal),
                        ui::money(i.interest),
                        amount(i.total, &loan.data.terms.currency)
                    )));
                if i.state == OccurrenceState::Due {
                    row = row.child(nav(
                        "记录还款",
                        format!("/wealth/liabilities/{}/pay/{}", loan.id, i.index),
                        "liability-pay",
                    ));
                } else {
                    let id = loan.id.clone();
                    let index = i.index;
                    row = row.child(command(
                        "撤销此期还款",
                        "liability-undo",
                        "还款已撤销；现金与债务余额已更新",
                        move || {
                            let id = id.clone();
                            Box::pin(async move {
                                fui::services().undo_finance_installment(id, index).await
                            })
                        },
                    ));
                    if let Some(jid) = i.journal_id {
                        row = row.child(nav(
                            "查看还款流水",
                            format!("/activity/entry/{jid}"),
                            "liability-journal",
                        ));
                    }
                }
                body = body.child(fui::section(format!("{}", i.index + 1), row.into_element()));
            }
            fui::page("还款计划", body.into_element())
        },
    )
}
fn loan_pay(id: String, index: u32) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "记录还款",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                let loans = s.finance_liabilities().await?;
                let loan = loans.into_iter().find(|l| l.id == id).ok_or("贷款不存在")?;
                let schedule = s.finance_liability_schedule(id).await?;
                let installment = schedule
                    .into_iter()
                    .find(|i| i.index == index)
                    .ok_or("还款期数不存在")?;
                let accounts = s
                    .finance_accounts(false)
                    .await?
                    .into_iter()
                    .filter(|(a, _)| {
                        a.side == AccountSide::Asset
                            && a.currency == loan.data.terms.currency
                            && matches!(
                                a.kind,
                                AccountCategory::Cash
                                    | AccountCategory::Bank
                                    | AccountCategory::Broker
                            )
                    })
                    .map(|(a, _)| (a.id, format!("{} · {}", a.name, a.currency)))
                    .collect::<Vec<_>>();
                Ok((loan, installment, accounts))
            })
        },
        move |(loan, i, accounts)| {
            let id = loan.id;
            fui::form(
                "记录还款",
                vec![
                    fui::Field::choice("account", "还款资金账户", "", accounts),
                    fui::Field::date("paid", "实际付款日期", ui::ymd(today()))
                        .help("保存会一次记入本金、利息与现金变动；不会发起银行扣款。"),
                    fui::Field::text("total", "核对还款总额", i.total.to_string())
                        .help("输入金额必须与本期本金加利息一致；合同变化需先核对计划。"),
                ],
                move |v| {
                    let id = id.clone();
                    Box::pin(async move {
                        if fui::decimal(&v, "total", "还款总额")? != i.total {
                            return Err("金额与本期计划不一致，请返回核对本金及利息".into());
                        }
                        fui::services()
                            .pay_finance_installment(
                                id.clone(),
                                index,
                                fui::required(&v, "account", "还款账户")?,
                                fui::date(&v, "paid", "付款日期")?,
                            )
                            .await?;
                        Ok(Some(format!("/wealth/liabilities/{id}")))
                    })
                },
            )
        },
    )
}
fn runway_page(selected_currency: String) -> AnyElement {
    load(
        "现金跑道",
        move |s| {
            let selected_currency = selected_currency.clone();
            Box::pin(async move {
                let (asof, currency) = (today(), selected_currency);
                let (a, b, scenarios) = tokio::join!(
                    s.finance_runway(asof, currency.clone(), 30),
                    s.finance_runway(asof, currency, 90),
                    s.finance_cash_scenarios()
                );
                Ok((a?, b?, scenarios?))
            })
        },
        |(short, long, scenarios)| {
            let mut body = view()
                .gap_4()
                .child(nav(
                    "选择现金币种",
                    "/plan/runway/select-currency",
                    "runway-currency",
                ))
                .child(metric(
                    "可用现金基线",
                    amount(long.starting_balance, &long.currency),
                    format!("截至 {} · 只合计同币种现金", ui::ymd(long.as_of)),
                ))
                .child(metric(
                    "30 天计划余额",
                    amount(short.predicted_balance, &short.currency),
                    format!(
                        "最低计划余额 {}",
                        amount(short.min_balance, &short.currency)
                    ),
                ))
                .child(metric(
                    "90 天计划余额",
                    amount(long.predicted_balance, &long.currency),
                    format!("最低计划余额 {}", amount(long.min_balance, &long.currency)),
                ));
            let mut balance = Some(long.starting_balance);
            let mut points = vec![(ui::ymd(long.as_of), balance)];
            for f in &long.flows {
                balance = balance.and_then(|v| v.checked_add(f.amount));
                points.push((ui::ymd(f.due), balance));
            }
            body = body.child(fui::cash_chart(points, "计划现金余额，非历史收益".into()));
            for a in &long.assumptions {
                body = body.child(note(a.clone()));
            }
            body = body.child(fui::section(
                "情景比较",
                nav(
                    "模拟一次变化",
                    "/plan/runway/scenario/new",
                    "scenario-create",
                ),
            ));
            for scenario in scenarios {
                match simulate_runway(&long, &scenario.data) {
                    Ok(result) => {
                        body = body.child(fui::row(
                            scenario.data.name,
                            format!(
                                "90 天基线 {} → 情景 {}",
                                ui::money(long.predicted_balance),
                                ui::money(result.predicted_balance)
                            ),
                            "调整".into(),
                            format!("scenario-{}", scenario.id),
                            {
                                let path = format!("/plan/runway/scenario/{}", scenario.id);
                                move || fui::navigate(path.clone())
                            },
                        ));
                    }
                    Err(e) => {
                        let path = format!("/plan/runway/scenario/{}", scenario.id);
                        body = body.child(fui::row(
                            scenario.data.name,
                            e.to_string(),
                            "调整".into(),
                            format!("scenario-{}", scenario.id),
                            move || fui::navigate(path.clone()),
                        ));
                    }
                }
            }
            body = body.child(fui::section(
                "未来现金流",
                note("来自尚未处理的周期收支、还款与定投假设。"),
            ));
            for f in long.flows {
                body = body.child(fui::row(
                    f.name,
                    ui::ymd(f.due),
                    amount(f.amount, &f.currency),
                    format!("flow-{}-{}", f.source_id, f.due),
                    || {},
                ));
            }
            fui::page("现金跑道", body.into_element())
        },
    )
}
fn scenario_form(id: Option<String>) -> AnyElement {
    let lookup = id.clone();
    load_form(
        "现金情景",
        move |s| {
            let id = lookup.clone();
            Box::pin(async move {
                Ok(s.finance_cash_scenarios()
                    .await?
                    .into_iter()
                    .find(|s| Some(&s.id) == id.as_ref())
                    .map(|s| s.data))
            })
        },
        move |old| {
            let id = id.clone();
            let editing = id.is_some();
            fui::form(
                "现金情景",
                vec![
                    fui::Field::text(
                        "name",
                        "情景名称",
                        old.as_ref().map_or("", |s| s.name.as_str()),
                    ),
                    fui::Field::choice(
                        "remove",
                        "处理方式",
                        "keep",
                        vec![
                            ("keep".into(), "保存情景假设".into()),
                            ("remove".into(), "删除此情景".into()),
                        ],
                    )
                    .show_when(move || editing),
                    fui::Field::text(
                        "currency",
                        "币种",
                        old.as_ref().map_or("CNY", |s| s.currency.as_str()),
                    ),
                    fui::Field::date(
                        "start",
                        "生效日期",
                        old.as_ref()
                            .map(|s| ui::ymd(s.starts_on))
                            .unwrap_or_else(|| ui::ymd(today())),
                    ),
                    fui::Field::decimal(
                        "once",
                        "一次性现金变化",
                        old.as_ref()
                            .map(|s| s.one_off_change.to_string())
                            .unwrap_or_else(|| "0".into()),
                    )
                    .help("收入为正、支出为负；仅是模拟假设，不会写入流水。"),
                    fui::Field::decimal(
                        "monthly",
                        "每月现金变化",
                        old.as_ref()
                            .map(|s| s.monthly_change.to_string())
                            .unwrap_or_else(|| "0".into()),
                    ),
                    fui::Field::text(
                        "months",
                        "持续月数",
                        old.as_ref()
                            .map(|s| s.months.to_string())
                            .unwrap_or_else(|| "12".into()),
                    ),
                ],
                move |v| {
                    let id = id.clone();
                    Box::pin(async move {
                        if fui::value(&v, "remove") == "remove" {
                            fui::services()
                                .remove_finance_plan(
                                    PlanKind::CashScenario,
                                    id.ok_or("情景尚未保存")?,
                                )
                                .await?;
                            return Ok(Some("/plan/runway".into()));
                        }
                        let draft = CashScenario {
                            name: fui::required(&v, "name", "情景名称")?,
                            currency: fui::required(&v, "currency", "币种")?,
                            starts_on: fui::date(&v, "start", "生效日期")?,
                            one_off_change: fui::decimal(&v, "once", "一次性变化")?,
                            monthly_change: fui::decimal(&v, "monthly", "每月变化")?,
                            months: fui::required(&v, "months", "持续月数")?
                                .parse()
                                .map_err(|_| "月数须为正整数")?,
                        };
                        fui::services()
                            .save_finance_cash_scenario(id, draft)
                            .await?;
                        Ok(Some("/plan/runway".into()))
                    })
                },
            )
        },
    )
}
fn runway_currency_form() -> AnyElement {
    load_form(
        "现金币种",
        |s| Box::pin(async move { s.wealth_cash_balances(today()).await }),
        |cash| {
            let mut currencies = cash
                .into_iter()
                .filter(|c| !c.liability)
                .map(|c| c.currency)
                .collect::<std::collections::BTreeSet<_>>();
            currencies.insert("CNY".into());
            fui::form(
                "现金币种",
                vec![
                    fui::Field::choice(
                        "currency",
                        "预测币种",
                        "CNY",
                        currencies.into_iter().map(|c| (c.clone(), c)).collect(),
                    )
                    .help("仅合计该币种现金；不假设未知汇率，也不把其他币种当作零。"),
                ],
                |v| {
                    Box::pin(async move {
                        Ok(Some(format!(
                            "/plan/runway/currency/{}",
                            fui::required(&v, "currency", "币种")?
                        )))
                    })
                },
            )
        },
    )
}
