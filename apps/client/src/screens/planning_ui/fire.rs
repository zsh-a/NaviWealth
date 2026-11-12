use super::*;

pub(super) fn fire_list() -> AnyElement {
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
pub(super) fn fire_form(id: Option<String>, copy: bool) -> AnyElement {
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
                fui::Field::money(
                    "capital",
                    "起始资本（用户假设）",
                    old.as_ref()
                        .map(|p| p.current_capital.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::money(
                    "expense",
                    "每月支出",
                    old.as_ref()
                        .map(|p| p.monthly_expense.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::money(
                    "income",
                    "每月收入",
                    old.as_ref()
                        .map(|p| p.monthly_income.to_string())
                        .unwrap_or_default(),
                ),
                fui::Field::money(
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
pub(super) fn fire_detail(id: String) -> AnyElement {
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
                        ui::money_for(p.data.current_capital, &p.data.currency),
                        ui::money_for(p.data.monthly_contribution, &p.data.currency)
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
                    p.data.currency.clone(),
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
