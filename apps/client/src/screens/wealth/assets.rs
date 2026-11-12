use super::*;

pub(super) fn asset_list() -> AnyElement {
    let services = fui::services();
    let include_archived = signal(false);
    let search = signal(String::new());
    fui::page(
        "资产",
        view()
            .gap_3()
            .child(
                view()
                    .flex_row()
                    .gap_2()
                    .child(fui::action("添加资产", "wealth-add-asset", || {
                        fui::navigate("/wealth/assets/new")
                    }))
                    .child(ui::choice_button(
                        "含已归档",
                        move || include_archived.get(),
                        move || include_archived.update(|v| *v = !*v),
                        "wealth-show-archived",
                    )),
            )
            .child(ui::text_field(
                "查找资产",
                "名称、代码或市场",
                search,
                "wealth-search",
            ))
            .child(loaded(
                move || {
                    let s = services.clone();
                    Box::pin(async move { s.wealth_assets(true).await })
                },
                move |data: Vec<WealthAsset>| {
                    dynamic(move || {
                        let query = search.get().trim().to_lowercase();
                        let filtered: Vec<_> = data
                            .iter()
                            .filter(|a| {
                                (include_archived.get() || !a.archived)
                                    && format!(
                                        "{} {} {}",
                                        a.details.name,
                                        a.details.symbol.as_deref().unwrap_or_default(),
                                        a.details.market.as_deref().unwrap_or_default()
                                    )
                                    .to_lowercase()
                                    .contains(&query)
                            })
                            .cloned()
                            .collect();
                        if filtered.is_empty() {
                            return note(if query.is_empty() {
                                "尚无资产。添加证券、房产或其他资产，再录入持仓与估值。"
                            } else {
                                "没有匹配资产，可修改关键词。"
                            });
                        }
                        view()
                            .children(filtered.into_iter().map(|a| {
                                let id = a.id.clone();
                                link(
                                    &a.details.name,
                                    &format!(
                                        "{} · {}{}{}",
                                        asset_kind(&a.details.kind),
                                        a.details.symbol.unwrap_or_else(|| "手动估值".into()),
                                        if a.archived { " · 已归档" } else { "" },
                                        a.details
                                            .market
                                            .map(|s| format!(" · {s}"))
                                            .unwrap_or_default()
                                    ),
                                    a.details.currency,
                                    &format!("wealth-asset-{id}"),
                                    format!("/wealth/assets/{id}"),
                                )
                            }))
                            .into_element()
                    })
                    .into_element()
                },
            )),
    )
}
#[derive(Clone, PartialEq)]
struct AssetDetail {
    asset: WealthAsset,
    snapshot: WealthSnapshot,
    prices: Vec<naviwealth_finance::models::AssetPrice>,
    operations: Vec<WealthOperation>,
    accounts: Vec<Account>,
}
pub(super) fn asset_detail(id: String) -> AnyElement {
    let services = fui::services();
    fui::page(
        "资产详情",
        loaded(
            move || {
                let s = services.clone();
                let id = id.clone();
                Box::pin(async move {
                    let asset = s.wealth_asset(id.clone()).await?;
                    let snapshot = s
                        .wealth_snapshot(lifeos::ids::now_secs(), asset.details.currency.clone())
                        .await?;
                    let prices = s.wealth_prices(id.clone()).await?;
                    let operations = s.wealth_operations(Some(id)).await?;
                    let accounts = s
                        .finance_accounts(true)
                        .await?
                        .into_iter()
                        .map(|(a, _)| a)
                        .collect();
                    Ok(AssetDetail {
                        asset,
                        snapshot,
                        prices,
                        operations,
                        accounts,
                    })
                })
            },
            move |data: AssetDetail| {
                let a = data.asset;
                let id = a.id.clone();
                let edit_id = id.clone();
                let record_id = id.clone();
                let price_id = id.clone();
                let archived = a.archived;
                let details = a.details;
                let mut body = view().gap_3().child(
                    view()
                        .flex_row()
                        .items_center()
                        .gap_2()
                        .child(
                            view()
                                .flex_1()
                                .gap_1()
                                .child(
                                    text(details.name.clone())
                                        .text_lg()
                                        .font_weight(FontWeight::SEMIBOLD),
                                )
                                .child(note(format!(
                                    "{} · {}{}",
                                    asset_kind(&details.kind),
                                    details.currency,
                                    details
                                        .symbol
                                        .as_ref()
                                        .map(|s| format!(" · {s}"))
                                        .unwrap_or_default()
                                ))),
                        )
                        .child(when(
                            move || !archived,
                            move || {
                                let edit_id = edit_id.clone();
                                fui::action("编辑", "wealth-edit-asset", move || {
                                    fui::navigate(format!("/wealth/assets/{edit_id}/edit"))
                                })
                            },
                        )),
                );
                if let Some(market) = details.market {
                    body = body.child(note(format!(
                        "市场 {market} · 手工记录持仓和价格，不连接券商执行"
                    )));
                }
                if !archived {
                    body = body.child(
                        view()
                            .flex_row()
                            .gap_2()
                            .child(fui::action("记录交易", "wealth-record", move || {
                                fui::navigate(format!("/wealth/assets/{record_id}/record"))
                            }))
                            .child(fui::action("更新估值", "wealth-price", move || {
                                fui::navigate(format!("/wealth/assets/{price_id}/price"))
                            })),
                    );
                } else {
                    body = body.child(note("资产已归档，持仓和历史仍计入财富。恢复后可继续记录。"));
                }
                if let Some(memo) = details.note {
                    body = body.child(note(memo));
                }
                body = body.child(fui::section(
                    "持仓与收益",
                    fui::changed_fact(
                        format!("/wealth/assets/{id}"),
                        view().children(
                            data.snapshot
                                .holdings
                                .into_iter()
                                .filter(|h| h.asset_id == id)
                                .map(|h| {
                                    let account = data
                                        .accounts
                                        .iter()
                                        .find(|a| a.id == h.account_id)
                                        .map(|a| a.name.clone())
                                        .unwrap_or_else(|| "持仓账户".into());
                                    view()
                                        .gap_1()
                                        .child(label_value(
                                            &account,
                                            amount(h.market_value, &h.currency),
                                        ))
                                        .child(note(format!(
                                            "数量 {} · 成本 {} {}",
                                            h.quantity.normalize(),
                                            ui::money_for(h.cost_basis, &h.currency),
                                            h.currency
                                        )))
                                        .child(note(format!(
                                            "未实现盈亏 {} · 已实现 {} · 净分红 {}",
                                            h.unrealized_pnl
                                                .map(ui::money)
                                                .unwrap_or_else(|| "待补价格".into()),
                                            ui::money_for(h.realized_pnl, &h.currency),
                                            ui::money_for(h.dividends, &h.currency)
                                        )))
                                        .child(ui::divider())
                                }),
                        ),
                    ),
                ));
                let mut price_curve = std::collections::BTreeMap::new();
                for p in data.prices.iter().rev() {
                    price_curve.insert(p.observed_on, p.per_unit);
                }
                if price_curve.len() > 1 {
                    body = body.child(fui::line_chart(
                        price_curve
                            .into_iter()
                            .map(|(date, price)| (ui::ymd(date), Some(price)))
                            .collect(),
                        format!("每单位价格 · {}", details.currency),
                        details.currency.clone(),
                    ));
                }
                body = body.child(fui::section(
                    "估值记录",
                    view()
                        .children(data.prices.iter().map(|p| {
                            label_value(
                                &ui::ymd(p.observed_on),
                                format!(
                                    "{} {} · {}",
                                    ui::money_for(p.per_unit, &details.currency),
                                    p.quote_currency,
                                    match p.source.as_deref() {
                                        Some("manual") | None => "手动记录",
                                        Some(source) => source,
                                    }
                                ),
                            )
                        }))
                        .child(when(
                            move || data.prices.is_empty(),
                            || note("暂无估值。更新价格只改变估值，不增加持仓数量。"),
                        )),
                ));
                let can_delete = data.operations.is_empty();
                body = body.child(fui::section(
                    "交易记录",
                    view().children(data.operations.into_iter().rev().map(operation_row)),
                ));
                let services = fui::services();
                let archive_id = a.id.clone();
                let delete_id = a.id;
                let busy = signal(false);
                let error = signal(String::new());
                body = body.child(fui::section(
                    "管理",
                    view()
                        .gap_2()
                        .child(ui::secondary_button(
                            if archived {
                                "恢复资产"
                            } else {
                                "归档资产"
                            },
                            move || {
                                if busy.get() {
                                    return;
                                }
                                busy.set(true);
                                let s = services.clone();
                                let id = archive_id.clone();
                                spawn(async move {
                                    let result = s.archive_wealth_asset(id, !archived).await;
                                    if !busy.try_set(false) {
                                        return;
                                    }
                                    match result {
                                        Ok(()) => {
                                            fui::notice(if archived {
                                                "资产已恢复"
                                            } else {
                                                "资产已归档，历史与余额保留"
                                            });
                                            fui::refresh();
                                        }
                                        Err(e) => {
                                            error.try_set(e);
                                        }
                                    }
                                });
                            },
                            "wealth-archive-asset",
                            Some(busy),
                        ))
                        .child(ui::error_line(error))
                        .child(when(
                            move || can_delete,
                            move || {
                                let delete_id = delete_id.clone();
                                destructive(
                                    "删除空资产",
                                    "仅没有交易记录的资产可以删除。有历史持仓的资产请归档。",
                                    "wealth-delete-asset",
                                    move || {
                                        let s = fui::services();
                                        let id = delete_id.clone();
                                        Box::pin(async move {
                                            s.delete_wealth_asset(id).await?;
                                            Ok(Some("/wealth/assets".into()))
                                        })
                                    },
                                )
                            },
                        ))
                        .child(when(
                            move || !can_delete,
                            || note("已有交易记录。归档资产可保留持仓与历史。"),
                        )),
                ));
                body.into_element()
            },
        ),
    )
}
pub(super) fn operation_row(op: WealthOperation) -> AnyElement {
    let id = op.id.clone();
    let subtitle = format!(
        "{} · {} {}",
        ui::ymd(op.details.date),
        op.details.quantity.normalize(),
        if op.details.kind == OperationKind::Split {
            "倍"
        } else {
            "单位"
        }
    );
    fui::row(
        op.details.kind.label().into(),
        subtitle,
        format!(
            "{} {}",
            ui::money_for(op.cash_amount, &op.currency),
            op.currency
        ),
        format!("wealth-operation-{id}"),
        move || fui::navigate(format!("/wealth/operations/{id}")),
    )
}
