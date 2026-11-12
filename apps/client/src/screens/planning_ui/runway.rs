use super::*;

pub(super) fn runway_page(selected_currency: String) -> AnyElement {
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
            body = body.child(fui::cash_chart(
                points,
                "计划现金余额，非历史收益".into(),
                long.currency.clone(),
            ));
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
                                ui::money_for(long.predicted_balance, &long.currency),
                                ui::money_for(result.predicted_balance, &long.currency)
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
pub(super) fn scenario_form(id: Option<String>) -> AnyElement {
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
                    fui::Field::money(
                        "once",
                        "一次性现金变化",
                        old.as_ref()
                            .map(|s| s.one_off_change.to_string())
                            .unwrap_or_else(|| "0".into()),
                    )
                    .help("收入为正、支出为负；仅是模拟假设，不会写入流水。"),
                    fui::Field::money(
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
pub(super) fn runway_currency_form() -> AnyElement {
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
