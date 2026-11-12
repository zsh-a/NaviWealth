use super::*;

pub(super) fn body(data: Today) -> AnyElement {
    let mut body = view().gap(move || px(ui::token("space-group")));
    if data.totals.is_empty() {
        body = body.child(ui::quiet_text("本月暂无收支记录"));
    }
    for (currency, income, expense) in &data.totals {
        body = body.child(
            view()
                .gap_5()
                .child(
                    view()
                        .gap_2()
                        .child(ui::quiet_text(format!(
                            "{}月结余",
                            chrono::Local::now().format("%-m")
                        )))
                        .child(ui::amount_text(
                            ui::money_for(*income - *expense, currency),
                            currency.clone(),
                            "type-surplus",
                        )),
                )
                .child(
                    view()
                        .flex_row()
                        .gap_5()
                        .child(cash_metric(
                            "收入",
                            *income,
                            ui::MoneySign::Inflow,
                            currency,
                        ))
                        .child(cash_metric(
                            "支出",
                            *expense,
                            ui::MoneySign::Outflow,
                            currency,
                        )),
                )
                .child(mini_pair(&data, currency)),
        );
    }
    let records = data
        .records
        .iter()
        .take(3)
        .cloned()
        .map(|r| {
            let id = r.id.clone();
            let path = format!("/activity/entry/{id}");
            let value = match r.kind {
                RecordKind::Expense => {
                    ui::format_money(r.amount, &r.currency, ui::MoneySign::Outflow)
                }
                RecordKind::Income => {
                    ui::format_money(r.amount, &r.currency, ui::MoneySign::Inflow)
                }
                _ => ui::money_for(r.amount, &r.currency),
            };
            ui::transaction_row(
                r.payee
                    .clone()
                    .or(r.category_name.clone())
                    .unwrap_or_else(|| r.kind.label().into()),
                r.account_name,
                r.category_name.as_deref().unwrap_or(r.kind.label()),
                value,
                data.currencies.row(r.currency, &r.account_id),
                format!("today-record-{id}"),
                move || fui::navigate(path.clone()),
            )
            .child(fui::record_highlight(&id))
            .into_element()
        })
        .collect::<Vec<_>>();
    body = body.child(fui::changed_fact(
        "/today".into(),
        view()
            .child(heading("最近流水"))
            .children(records)
            .child(ui::text_button(
                "全部流水 →",
                "today-all-records",
                || fui::navigate("/activity"),
                false,
            )),
    ));
    let mut pending: Vec<_> = data
        .actions
        .into_iter()
        .filter(|a| a.state == OccurrenceState::Due)
        .collect();
    pending.sort_by_key(|a| a.due);
    let mut upcoming = view().child(heading("接下来"));
    for a in pending.iter().take(2) {
        let path = planning_route(&a.source);
        upcoming = upcoming.child(fui::row(
            a.name.clone(),
            ui::ymd(a.due),
            format!("{} {}", ui::money_for(a.amount, &a.currency), a.currency),
            format!("today-action-{path}-{}", a.due),
            move || fui::navigate(path.clone()),
        ));
    }
    if pending.is_empty() {
        upcoming = upcoming.child(ui::quiet_text("本月安排已处理"));
    }
    body = body
        .child(upcoming)
        .child(fui::row(
            "财务收件箱".into(),
            String::new(),
            format!("{} 项待处理", data.issues.len()),
            "today-inbox".into(),
            || fui::navigate("/today/inbox"),
        ))
        .child(fui::row(
            "净资产".into(),
            String::new(),
            data.wealth
                .net_worth
                .map(|v| {
                    format!(
                        "{} {}",
                        ui::money_for(v, &data.wealth.base_currency),
                        data.wealth.base_currency
                    )
                })
                .unwrap_or_else(|| "待补全估值".into()),
            "today-wealth".into(),
            || fui::navigate("/wealth"),
        ))
        .child(fui::action("完成月结", "today-close", || {
            fui::navigate("/activity/close")
        }))
        .child(fui::action("导入账单", "today-import", || {
            fui::navigate("/activity/import")
        }));
    body.into_element()
}
fn heading(title: &str) -> impl Element {
    text(title.to_owned())
        .text_size(move || px(ui::token("type-section")))
        .font_weight(FontWeight::SEMIBOLD)
}
fn cash_metric(label: &str, value: Decimal, sign: ui::MoneySign, currency: &str) -> impl Element {
    let formatted = ui::format_money(value, currency, sign);
    let tone = formatted.clone();
    view().flex_1().gap_1().child(ui::quiet_text(label)).child(
        text(formatted)
            .text_size(move || px(ui::token("type-income")))
            .text_color(move || ui::money_tone(&tone))
            .tabular_nums()
            .font_weight(FontWeight::MEDIUM),
    )
}
fn mini_pair(data: &Today, currency: &str) -> AnyElement {
    let budgets = ui::budget_totals(&data.budgets).and_then(|m| m.get(currency).copied());
    let day_count = chrono::Local::now()
        .format("%d")
        .to_string()
        .parse()
        .unwrap_or(31);
    let daily = ui::daily_spending(&data.spending, currency, day_count);
    let mut pair = view().flex_row().gap_3();
    let budget = match budgets {
        Some((spent, limit)) => budget_card(spent, limit, currency),
        None => mini_card()
            .child(ui::quiet_text("预算可用"))
            .child(ui::quiet_text("尚未设置"))
            .child(ui::text_button(
                "设置预算",
                "today-set-budget",
                || fui::navigate("/plan/budgets"),
                false,
            )),
    };
    pair = pair.child(budget);
    if let Some(values) = daily {
        let Some((index, peak)) = ui::spending_peak(&values) else {
            return pair.child(empty_peak()).into_element();
        };
        pair = pair.child(
            mini_card()
                .child(ui::quiet_text(format!(
                    "单日最高 · {:02}.{:02}",
                    chrono::Local::now().format("%m"),
                    index + 1
                )))
                .child(ui::amount_text(
                    ui::money_for(peak, currency),
                    String::new(),
                    "type-mini",
                ))
                .child(ui::spending_chart(&values, currency))
                .child(ui::quiet_text(format!(
                    "本月 1—{day_count} 日 · {currency}"
                ))),
        );
    }
    pair.into_element()
}
fn mini_card() -> nsh_core::element::View {
    view()
        .flex_1()
        .min_w(px(0.0))
        .p_3()
        .gap_2()
        .rounded(move || px(ui::card_radius()))
        .border_1()
        .border_color(move || theme().border)
        .bg(move || theme().card)
}

fn budget_card(spent: Decimal, limit: Decimal, currency: &str) -> nsh_core::element::View {
    let status = ui::BudgetDisplay::new(spent, limit, currency);
    let usage_tone = status.clone();
    let balance_tone = status.clone();
    mini_card()
        .child(ui::quiet_text("预算可用"))
        .child(ui::amount_text(
            ui::money_for(limit - spent, currency),
            String::new(),
            "type-mini",
        ))
        .child(view().h(px(8.0)))
        .child(ui::progress_bar_state(status.progress, status.alert))
        .child(ui::quiet_text(status.usage).text_color(move || usage_tone.tone()))
        .child(when(
            move || spent > limit,
            move || {
                ui::quiet_text(balance_tone.balance.clone()).text_color(move || theme().destructive)
            },
        ))
}
fn empty_peak() -> nsh_core::element::View {
    mini_card()
        .test_id("today-spending-empty")
        .child(ui::quiet_text("单日最高"))
        .child(ui::quiet_text("本月暂无支出"))
}
#[cfg(test)]
#[path = "summary_tests.rs"]
mod tests;
