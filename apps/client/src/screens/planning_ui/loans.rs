use super::*;

pub(super) fn loan_list() -> AnyElement {
    load(
        "贷款与还款",
        |s| {
            Box::pin(async move {
                let rows = s.finance_liabilities().await?;
                let cash = s.wealth_cash_balances(lifeos::ids::now_secs()).await?;
                Ok((rows, cash))
            })
        },
        |(rows, cash)| {
            let mut body = view().gap_4().child(nav(
                "添加贷款",
                "/wealth/liabilities/new",
                "liability-create",
            ));
            for c in cash
                .into_iter()
                .filter(|c| c.liability && !rows.iter().any(|l| l.data.account_id == c.account_id))
            {
                let route = format!("/wealth/accounts/{}", c.account_id);
                body = body.child(fui::row(
                    c.name,
                    "信用与借款账户".into(),
                    amount(c.amount.abs(), &c.currency),
                    format!("liability-account-{}", c.account_id),
                    move || fui::navigate(route.clone()),
                ));
            }
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
pub(super) fn loan_form(id: Option<String>) -> AnyElement {
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
            fui::form("贷款合同",vec![fui::Field::text("name","贷款名称",old.as_ref().map_or("",|l|l.name.as_str())),fui::Field::text("currency","币种",old.as_ref().map_or("CNY",|l|l.currency.as_str())),fui::Field::money("principal","当前待还本金",old.as_ref().map(|l|l.principal.to_string()).unwrap_or_default()).help("本金作为债务期初余额，不会虚构现金收入。合同已发生还款时须先撤销还款才能修正。"),fui::Field::decimal("rate","合同年利率（%）",old.as_ref().map(|l|(l.annual_rate*Decimal::from(100)).to_string()).unwrap_or_default()),fui::Field::text("months","剩余期数（月）",old.as_ref().map(|l|l.months.to_string()).unwrap_or_else(||"12".into())),fui::Field::date("opened","本金记录日期",old.as_ref().map(|l|ui::ymd(l.opened_on)).unwrap_or_else(||ui::ymd(today()))),fui::Field::date("first","首次还款日",old.as_ref().map(|l|ui::ymd(l.first_due)).unwrap_or_else(||ui::ymd(today())))],move|v|{let id=id.clone();Box::pin(async move{let draft=LiabilityDraft{name:fui::required(&v,"name","名称")?,currency:fui::required(&v,"currency","币种")?,principal:fui::decimal(&v,"principal","本金")?,annual_rate:fui::decimal(&v,"rate","年利率")?.checked_div(Decimal::from(100)).ok_or("利率超出范围")?,months:fui::required(&v,"months","剩余期数")?.parse().map_err(|_|"期数须为正整数")?,opened_on:fui::date(&v,"opened","本金记录日期")?,first_due:fui::date(&v,"first","首次还款日")?};let id=if let Some(id)=id{fui::services().update_finance_liability(id.clone(),draft).await?;id}else{fui::services().create_finance_liability(draft).await?};Ok(Some(format!("/wealth/liabilities/{id}")))})})
        },
    )
}
pub(super) fn loan_delete(id: String) -> AnyElement {
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

pub(super) fn loan_detail(id: String) -> AnyElement {
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
                        ui::money_for(i.principal, &loan.data.terms.currency),
                        ui::money_for(i.interest, &loan.data.terms.currency),
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
pub(super) fn loan_pay(id: String, index: u32) -> AnyElement {
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
                    fui::Field::money("total", "核对还款总额", i.total.to_string())
                        .currency(move || loan.data.terms.currency.clone())
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
