use super::*;

pub(super) fn budget_list(selected_month: String) -> AnyElement {
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
                        format!(
                            "超出 {}",
                            ui::money_for(b.remaining.abs(), &b.budget.currency)
                        )
                    } else {
                        format!("余 {}", ui::money_for(b.remaining, &b.budget.currency))
                    },
                    format!("budget-{}", b.id),
                    move || fui::navigate(route.clone()),
                ));
            }
            fui::page("分类预算", body.into_element())
        },
    )
}
pub(super) fn budget_month_form() -> AnyElement {
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
pub(super) fn budget_form(id: Option<String>) -> AnyElement {
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
            let title = old
                .as_ref()
                .map(|budget| {
                    let category = categories
                        .iter()
                        .find(|(id, _)| id == &budget.category_id)
                        .map(|(_, label)| label.as_str())
                        .unwrap_or("支出分类");
                    format!(
                        "调整预算 · {} · {} · {}",
                        budget.month, category, budget.currency
                    )
                })
                .unwrap_or_else(|| "设置预算".into());
            let edit_currency = old_code.to_owned();
            let fields = if old.is_some() {
                vec![
                    fui::Field::money("limit", "本月额度", old_limit)
                        .currency(move || edit_currency.clone())
                        .help("只调整额度；已有月份、分类和币种保持不变。"),
                ]
            } else {
                vec![
                    fui::Field::text("month", "预算月份", old_month)
                        .help("格式 YYYY-MM；同一月份、分类、币种保存时更新现有额度。"),
                    fui::Field::choice("category", "支出分类", old_category, categories),
                    fui::Field::text("currency", "币种", old_code),
                    fui::Field::money("limit", "本月额度", old_limit),
                ]
            };
            let previous = old.clone();
            fui::form(title, fields, move |v| {
                let previous = previous.clone();
                Box::pin(async move {
                    let limit = fui::decimal(&v, "limit", "预算额度")?;
                    let draft = match previous {
                        Some(budget) => Budget { limit, ..budget },
                        None => Budget {
                            month: fui::required(&v, "month", "月份")?,
                            category_id: fui::required(&v, "category", "支出分类")?,
                            currency: fui::required(&v, "currency", "币种")?,
                            limit,
                        },
                    };
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
pub(super) fn budget_detail(id: String) -> AnyElement {
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
