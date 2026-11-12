use super::*;

#[derive(Clone, PartialEq)]
struct Overview {
    snapshot: WealthSnapshot,
    history: Vec<WealthHistoryPoint>,
    assets: Vec<WealthAsset>,
    cash: Vec<CashBalance>,
    account_count: usize,
    liability_count: usize,
    plan_count: usize,
}
pub(super) fn overview() -> AnyElement {
    let services = fui::services();
    fui::page(
        "财富",
        loaded(
            move || {
                let s = services.clone();
                Box::pin(async move {
                    let base = s
                        .settings_get("finance.base_currency")
                        .await
                        .unwrap_or_else(|| "CNY".into());
                    let now = lifeos::ids::now_secs();
                    let snapshot = s.wealth_snapshot(now, base.clone()).await?;
                    let history = s.wealth_history(base).await?;
                    let assets = s.wealth_assets(false).await?;
                    let cash = s.wealth_cash_balances(now).await?;
                    let (accounts, liabilities, plans) = tokio::join!(
                        s.finance_accounts(false),
                        s.finance_liabilities(),
                        s.finance_portfolio_plans()
                    );
                    Ok(Overview {
                        snapshot,
                        history,
                        assets,
                        cash: cash.clone(),
                        account_count: accounts?.len(),
                        liability_count: {
                            let loans = liabilities?;
                            loans.len()
                                + cash
                                    .iter()
                                    .filter(|c| {
                                        c.liability
                                            && !loans
                                                .iter()
                                                .any(|l| l.data.account_id == c.account_id)
                                    })
                                    .count()
                        },
                        plan_count: plans?.len(),
                    })
                })
            },
            render,
        ),
    )
}
fn render(data: Overview) -> AnyElement {
    let v = data.snapshot;
    let allocation_groups = summary::allocations(&v);
    let asset_count = data.assets.len();
    let mut summary = view().gap_2().child(ui::quiet_text("净资产"));
    summary = summary.child(match v.net_worth {
        Some(value) => ui::amount_text(
            ui::money_for(value, &v.base_currency),
            v.base_currency.clone(),
            "type-net-worth",
        )
        .into_element(),
        None => text("暂不可估值").text_lg().into_element(),
    });
    // The delta compares known endpoints only; it is not investment return.
    let window = summary::history_window(data.history, v.as_of);
    let recent = window.points;
    let period = window.label;
    if let (Some(first), Some(last)) = (
        recent.first().and_then(|p| p.net_worth),
        recent.last().and_then(|p| p.net_worth),
    ) && recent.len() >= 3
    {
        let delta = ui::format_money(last - first, &v.base_currency, ui::MoneySign::Inflow);
        let tone = delta.clone();
        summary = summary.child(
            text(format!(
                "{period} {delta}{}",
                if first > Decimal::ZERO {
                    (last - first)
                        .checked_div(first)
                        .and_then(|v| v.checked_mul(Decimal::from(100)))
                        .map(|v| format!(" · {}%", v.round_dp(2)))
                        .unwrap_or_default()
                } else {
                    String::new()
                }
            ))
            .tabular_nums()
            .text_size(move || px(ui::token("type-caption")))
            .text_color(move || ui::money_tone(&tone)),
        );
    }
    let destinations = view().grid().grid_cols(4).gap_2().children(
        [
            ("资产", asset_count, "wealth-assets", "/wealth/assets"),
            (
                "账户",
                data.account_count,
                "wealth-accounts",
                "/wealth/accounts",
            ),
            (
                "负债",
                data.liability_count,
                "wealth-liabilities",
                "/wealth/liabilities",
            ),
            (
                "组合",
                data.plan_count,
                "wealth-portfolios",
                "/wealth/portfolios",
            ),
        ]
        .map(|(label, count, id, path)| {
            ui::press_target(move || fui::navigate(path))
                .test_id(id)
                .label(format!("{label}，{count} 项，打开"))
                .flex_row()
                .items_center()
                .justify_center()
                .gap_1()
                .rounded(move || theme().radius)
                .bg(move || theme().secondary)
                .child(
                    text(format!("{label} {count}"))
                        .text_size(move || px(ui::token("type-caption"))),
                )
        }),
    );
    let mut body = view()
        .gap(move || px(ui::token("space-group")))
        .child(summary)
        .child(destinations);
    if !v.missing_prices.is_empty() || !v.missing_fx.is_empty() {
        body = body.child(fui::section(
            "估值待补全",
            view()
                .child(ui::quiet_text(format!(
                    "缺 {} 项价格 · {} 组汇率",
                    v.missing_prices.len(),
                    v.missing_fx.len()
                )))
                .children(
                    v.holdings
                        .iter()
                        .filter(|h| h.quantity > Decimal::ZERO && h.market_price.is_none())
                        .map(|h| {
                            link(
                                &h.name,
                                "补充价格",
                                h.quantity.normalize().to_string(),
                                &format!("wealth-missing-{}", h.asset_id),
                                format!("/wealth/assets/{}/price", h.asset_id),
                            )
                        }),
                )
                .child(when(
                    move || !v.missing_fx.is_empty(),
                    || {
                        fui::action("补充汇率", "wealth-missing-fx", || {
                            fui::navigate("/wealth/fx")
                        })
                    },
                )),
        ));
    }
    match allocation_groups {
        Ok(groups) => {
            for group in groups {
                body = body.child(allocation(group));
            }
        }
        Err(e) => {
            body = body.child(note(e));
        }
    }
    if !recent.is_empty() {
        body = body.child(fui::history_chart(
            recent
                .into_iter()
                .map(|p| (ui::ymd(p.as_of), p.net_worth))
                .collect(),
            format!("净资产 · {period}"),
            v.base_currency.clone(),
        ));
    }
    body = body.child(fui::section(
        "持仓",
        view()
            .children(
                v.holdings
                    .into_iter()
                    .filter(|h| h.quantity != Decimal::ZERO)
                    .map(|h| {
                        let account = data
                            .cash
                            .iter()
                            .find(|c| c.account_id == h.account_id)
                            .map(|c| c.name.clone())
                            .unwrap_or_else(|| "持仓账户".into());
                        holding_row(h, account)
                    }),
            )
            .child(when(
                move || asset_count == 0,
                || note("添加资产与持仓后，查看结构与估值。"),
            )),
    ));
    body = body.child(fui::section(
        "账户",
        view().children(data.cash.into_iter().map(|c| {
            let path = format!("/wealth/accounts/{}", c.account_id);
            fui::row(
                c.name,
                c.currency.clone(),
                ui::money_for(c.amount, &c.currency),
                format!("wealth-cash-{}", c.account_id),
                move || fui::navigate(path.clone()),
            )
        })),
    ));
    body.child(link(
        "汇率",
        "",
        String::new(),
        "wealth-fx",
        "/wealth/fx".into(),
    ))
    .into_element()
}
pub(super) fn holding_row(h: Holding, account: String) -> AnyElement {
    let id = h.asset_id.clone();
    let value = h
        .market_value
        .map(|v| ui::money_for(v, &h.currency))
        .unwrap_or_else(|| "待估值".into());
    let subtitle = format!("{} 份 · {account}", ui::money_for(h.quantity, "JPY"));
    let secondary = h.unrealized_pnl.map(|pnl| {
        let amount = ui::format_money(pnl, &h.currency, ui::MoneySign::Inflow);
        let percentage = if h.cost_basis > Decimal::ZERO {
            pnl.checked_div(h.cost_basis)
                .and_then(|p| p.checked_mul(Decimal::from(100)))
                .map(|v| format!(" / {}%", v.round_dp(2)))
                .unwrap_or_default()
        } else {
            String::new()
        };
        format!("{amount}{percentage}")
    });
    ui::transaction_amount_row(
        h.name,
        subtitle,
        "投资",
        ui::RowAmount {
            inline_unit: None,
            value,
            currency: h.currency,
            secondary,
        },
        format!("holding-{}-{}", h.account_id, id),
        move || fui::navigate(format!("/wealth/assets/{id}")),
    )
    .into_element()
}

pub(super) fn allocation(group: summary::Allocation) -> impl Element {
    let summary::Allocation {
        wealth: c,
        investment,
        cash,
        missing,
    } = group;
    let partial = missing > 0;
    let known_caption = format!(
        "已知资产 {} {} · {missing} 项持仓缺价",
        ui::money_for(c.assets, &c.currency),
        c.currency
    );
    let r = ui::ratio(investment, c.assets);
    view()
        .gap_3()
        .child(
            text(format!(
                "资产构成 · {}{}",
                c.currency,
                if partial { " · 部分缺价" } else { "" }
            ))
            .text_size(move || px(ui::token("type-section")))
            .font_weight(FontWeight::SEMIBOLD),
        )
        .child(
            view()
                .style_when(move || partial, |s| s.hidden())
                .flex_row()
                .gap_1()
                .h(move || px(ui::token("bar-allocation-height")))
                .child(
                    view()
                        .w(relative(r))
                        .h_full()
                        .rounded(px(2.0))
                        .bg(move || theme().primary),
                )
                .child(view().flex_1().h_full().rounded(px(2.0)).bg(move || {
                    theme()
                        .color("data-cash-surface")
                        .unwrap_or_else(|| theme().secondary)
                })),
        )
        .child(
            view()
                .flex_row()
                .gap_3()
                .child(
                    view()
                        .flex_1()
                        .gap_1()
                        .child(ui::quiet_text(if partial {
                            "已知投资"
                        } else {
                            "投资"
                        }))
                        .child(ui::amount_text(
                            ui::money_for(investment, &c.currency),
                            String::new(),
                            "type-allocation",
                        )),
                )
                .child(
                    view()
                        .flex_1()
                        .gap_1()
                        .child(ui::quiet_text(if partial {
                            "已知现金"
                        } else {
                            "现金"
                        }))
                        .child(ui::amount_text(
                            ui::money_for(cash, &c.currency),
                            String::new(),
                            "type-allocation",
                        )),
                ),
        )
        .child(when(
            move || partial,
            move || ui::quiet_text(known_caption.clone()),
        ))
        .child(
            view()
                .flex_row()
                .items_baseline()
                .child(ui::quiet_text("负债").flex_1())
                .child(ui::amount_text(
                    ui::money_for(c.liabilities, &c.currency),
                    String::new(),
                    "type-caption",
                )),
        )
}
