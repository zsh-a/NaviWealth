//! Native wealth workspace: authored assets, exact positions, valuations and trades.
use crate::{finance_ui as fui, ui};
use fui::Field;
use naviwealth_finance::{
    models::{Account, AccountSide},
    wealth::*,
};
use nsh_base::theme;
use nsh_core::prelude::*;
use rust_decimal::Decimal;
use std::{future::Future, pin::Pin};

type Fetch<T> = Pin<Box<dyn Future<Output = Result<T, String>>>>;
/// Form dependencies load once. A background refresh cannot erase an authored draft.
fn loaded_form<T: Clone + PartialEq + 'static>(
    title: impl Into<String>,
    fetch: impl Fn() -> Fetch<T> + 'static,
    display: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    let title = title.into();
    let value = signal(None::<T>);
    let error = signal(String::new());
    let retry = signal(0u64);
    effect(move || {
        retry.get();
        error.set(String::new());
        let task = fetch();
        spawn(async move {
            match task.await {
                Ok(v) => {
                    value.try_set(Some(v));
                }
                Err(e) => {
                    error.try_set(e);
                }
            }
        });
    });
    dynamic(move || match value.get() {
        Some(v) => display(v),
        None => fui::page(
            title.clone(),
            view()
                .gap_3()
                .child(note("正在读取表单所需资料…"))
                .child(ui::error_line(error))
                .child(when(
                    move || !error.get().is_empty(),
                    move || {
                        fui::action("重新读取", "wealth-form-retry", move || {
                            retry.update(|v| *v += 1)
                        })
                    },
                )),
        ),
    })
    .into_element()
}
fn loaded<T: Clone + PartialEq + 'static>(
    fetch: impl Fn() -> Fetch<T> + 'static,
    display: impl Fn(T) -> AnyElement + 'static,
) -> AnyElement {
    let value = signal(None::<T>);
    let error = signal(String::new());
    let loading = signal(true);
    let retry = signal(0u64);
    let serial = signal(0u64);
    let version = use_context::<crate::state::DataVersion>()
        .expect("data version")
        .0;
    effect(move || {
        version.get();
        retry.get();
        serial.update(|v| *v += 1);
        let current = serial.get_untracked();
        loading.set(true);
        error.set(String::new());
        let task = fetch();
        spawn(async move {
            let result = task.await;
            if serial.try_get() != Some(current) {
                return;
            }
            match result {
                Ok(v) => {
                    value.try_set(Some(v));
                }
                Err(e) => {
                    error.try_set(e);
                }
            }
            loading.try_set(false);
        });
    });
    view()
        .gap_3()
        .child(when(
            move || loading.get(),
            || {
                text("正在读取财富数据…")
                    .text_sm()
                    .text_color(move || theme().muted_foreground)
            },
        ))
        .child(when(
            move || !error.get().is_empty(),
            move || {
                view()
                    .gap_2()
                    .child(ui::error_line(error))
                    .child(fui::action("重新读取", "wealth-retry", move || {
                        retry.update(|v| *v += 1)
                    }))
            },
        ))
        .child(dynamic(move || match value.get() {
            Some(v) => display(v),
            None => view().into_element(),
        }))
        .into_element()
}
fn optional(s: String) -> Option<String> {
    let s = s.trim();
    (!s.is_empty()).then(|| s.to_owned())
}
fn amount(value: Option<Decimal>, currency: &str) -> String {
    value
        .map(|v| format!("{} {currency}", ui::money(v)))
        .unwrap_or_else(|| "暂不可估值".into())
}
fn note(s: impl Into<String>) -> AnyElement {
    text(s.into())
        .text_sm()
        .text_color(move || theme().muted_foreground)
        .into_element()
}
fn asset_kind(kind: &str) -> &'static str {
    match kind {
        "stock" => "股票",
        "etf" => "ETF",
        "mutual_fund" => "基金",
        "bond" => "债券",
        "crypto" => "数字资产",
        "cash" => "现金资产",
        "real_estate" => "房产",
        "vehicle" => "车辆",
        _ => "其他资产",
    }
}
fn kind_key(kind: OperationKind) -> &'static str {
    match kind {
        OperationKind::Opening => "opening",
        OperationKind::Buy => "buy",
        OperationKind::Sell => "sell",
        OperationKind::Dividend => "dividend",
        OperationKind::Split => "split",
    }
}
fn operation_kind(key: &str) -> Result<OperationKind, String> {
    match key {
        "opening" => Ok(OperationKind::Opening),
        "buy" => Ok(OperationKind::Buy),
        "sell" => Ok(OperationKind::Sell),
        "dividend" => Ok(OperationKind::Dividend),
        "split" => Ok(OperationKind::Split),
        _ => Err("请选择交易类型".into()),
    }
}
fn label_value(label: &str, value: String) -> AnyElement {
    view()
        .flex_row()
        .gap_3()
        .py_2()
        .child(
            text(label.to_owned())
                .text_sm()
                .text_color(move || theme().muted_foreground)
                .flex_1(),
        )
        .child(text(value).text_sm().tabular_nums().text_right())
        .into_element()
}
fn link(title: &str, subtitle: &str, value: String, id: &str, path: String) -> AnyElement {
    fui::row(title.into(), subtitle.into(), value, id.into(), move || {
        fui::navigate(path.clone())
    })
}

pub fn render(path: String) -> AnyElement {
    let parts: Vec<_> = path.trim_matches('/').split('/').collect();
    match parts.as_slice() {
        ["wealth"] => overview(),
        ["wealth", "assets"] => asset_list(),
        ["wealth", "assets", "new"] => asset_editor(None),
        ["wealth", "assets", id, "edit"] => asset_editor(Some((*id).into())),
        ["wealth", "assets", id, "price"] => price_editor((*id).into()),
        ["wealth", "assets", id, "record"] => operation_editor(None, Some((*id).into())),
        ["wealth", "assets", id, "record", kind] => {
            operation_editor_kind(None, Some((*id).into()), operation_kind(kind).ok())
        }
        ["wealth", "assets", id] => asset_detail((*id).into()),
        ["wealth", "operations", "new"] => operation_editor(None, None),
        ["wealth", "operations", id, "edit"] => operation_editor(Some((*id).into()), None),
        ["wealth", "operations", id] => operation_detail((*id).into()),
        ["wealth", "fx"] => fx_editor(),
        _ => fui::page(
            "财富",
            view()
                .gap_3()
                .child(note("这个财富页面不存在，请返回财富总览。"))
                .child(fui::action("财富总览", "wealth-home", || {
                    fui::navigate("/wealth")
                })),
        ),
    }
}
#[derive(Clone, PartialEq)]
struct Overview {
    snapshot: WealthSnapshot,
    history: Vec<WealthHistoryPoint>,
    assets: Vec<WealthAsset>,
}
fn overview() -> AnyElement {
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
                    let snapshot = s
                        .wealth_snapshot(lifeos::ids::now_secs(), base.clone())
                        .await?;
                    let history = s.wealth_history(base).await?;
                    let assets = s.wealth_assets(false).await?;
                    Ok(Overview {
                        snapshot,
                        history,
                        assets,
                    })
                })
            },
            move |data: Overview| {
                let asset_count = data.assets.len();
                let v = data.snapshot;
                let mut body = view().gap_3().child(
                    view()
                        .flex_row()
                        .gap_2()
                        .child(fui::action("资产", "wealth-assets", || {
                            fui::navigate("/wealth/assets")
                        }))
                        .child(fui::action("账户", "wealth-accounts", || {
                            fui::navigate("/wealth/accounts")
                        }))
                        .child(fui::action("负债", "wealth-liabilities", || {
                            fui::navigate("/wealth/liabilities")
                        }))
                        .child(fui::action("组合", "wealth-portfolios", || {
                            fui::navigate("/wealth/portfolios")
                        })),
                );
                body = body.child(fui::metric(
                    "净资产".into(),
                    amount(v.net_worth, &v.base_currency),
                    format!("截至 {} · 按已记录价格和汇率", ui::ymd(v.as_of)),
                ));
                if !v.missing_prices.is_empty() || !v.missing_fx.is_empty() {
                    body = body.child(fui::section(
                        "估值待补全",
                        view()
                            .gap_1()
                            .child(note(format!(
                                "缺少 {} 项持仓价格 · {} 组汇率；补齐后显示完整净资产",
                                v.missing_prices.len(),
                                v.missing_fx.len()
                            )))
                            .children(
                                v.holdings
                                    .iter()
                                    .filter(|h| {
                                        h.quantity > Decimal::ZERO && h.market_price.is_none()
                                    })
                                    .map(|h| {
                                        link(
                                            &h.name,
                                            "补充价格，持仓数量保持不变",
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
                body = body.child(fui::section(
                    "按币种",
                    view().children(v.currencies.iter().map(|c| {
                        view()
                            .gap_1()
                            .child(label_value(
                                &c.currency,
                                format!("净额 {}", ui::money(c.net)),
                            ))
                            .child(note(format!(
                                "资产 {} · 负债 {}",
                                ui::money(c.assets),
                                ui::money(c.liabilities)
                            )))
                            .child(ui::divider())
                    })),
                ));
                if data.history.len() > 1 {
                    body = body.child(fui::line_chart(
                        data.history
                            .into_iter()
                            .map(|p| (ui::ymd(p.as_of), p.net_worth))
                            .collect(),
                        format!("净资产 · {} · 记录时点", v.base_currency),
                    ));
                }
                body=body.child(fui::section("持仓",view().children(v.holdings.into_iter().filter(|h|h.quantity!=Decimal::ZERO).map(holding_row)).child(when(move||asset_count==0,||note("先建立资产，再记录期初持仓或买入；账户中的现金会单独计入财富。")))));
                body = body.child(link(
                    "汇率",
                    "补充有日期依据的手动汇率",
                    String::new(),
                    "wealth-fx",
                    "/wealth/fx".into(),
                ));
                body.into_element()
            },
        ),
    )
}
fn holding_row(h: Holding) -> AnyElement {
    let id = h.asset_id.clone();
    fui::row(
        h.name,
        format!(
            "持有 {} · 成本 {} {}",
            h.quantity.normalize(),
            ui::money(h.cost_basis),
            h.currency
        ),
        amount(h.market_value, &h.currency),
        format!("holding-{}-{}", h.account_id, id),
        move || fui::navigate(format!("/wealth/assets/{id}")),
    )
}
fn asset_list() -> AnyElement {
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
fn asset_detail(id: String) -> AnyElement {
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
                                            ui::money(h.cost_basis),
                                            h.currency
                                        )))
                                        .child(note(format!(
                                            "未实现盈亏 {} · 已实现 {} · 净分红 {}",
                                            h.unrealized_pnl
                                                .map(ui::money)
                                                .unwrap_or_else(|| "待补价格".into()),
                                            ui::money(h.realized_pnl),
                                            ui::money(h.dividends)
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
                                    ui::money(p.per_unit),
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
fn operation_row(op: WealthOperation) -> AnyElement {
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
        format!("{} {}", ui::money(op.cash_amount), op.currency),
        format!("wealth-operation-{id}"),
        move || fui::navigate(format!("/wealth/operations/{id}")),
    )
}
fn destructive(
    label: &'static str,
    message: &'static str,
    id: &'static str,
    submit: impl Fn() -> fui::SaveFuture + 'static,
) -> AnyElement {
    fui::confirm(label.into(), message.into(), label.into(), id, submit)
}
fn asset_editor(id: Option<String>) -> AnyElement {
    let services = fui::services();
    let editing = id.is_some();
    loaded_form(
        if editing {
            "编辑资产"
        } else {
            "添加资产"
        },
        move || {
            let s = services.clone();
            let id = id.clone();
            Box::pin(async move {
                match id {
                    Some(id) => s.wealth_asset(id).await.map(Some),
                    None => Ok(None),
                }
            })
        },
        move |asset: Option<WealthAsset>| {
            let id = asset.as_ref().map(|a| a.id.clone());
            let data = asset.map(|a| a.details).unwrap_or(AssetDraft {
                kind: "stock".into(),
                name: String::new(),
                market: None,
                symbol: None,
                currency: "CNY".into(),
                note: None,
            });
            let fields = vec![
                Field::text("wealth-asset-name", "资产名称", data.name),
                Field::choice(
                    "wealth-asset-kind",
                    "资产类别",
                    data.kind,
                    [
                        "stock",
                        "etf",
                        "mutual_fund",
                        "bond",
                        "crypto",
                        "cash",
                        "real_estate",
                        "vehicle",
                        "other",
                    ]
                    .into_iter()
                    .map(|k| (k.into(), asset_kind(k).into()))
                    .collect(),
                ),
                Field::text("wealth-asset-currency", "估值币种", data.currency)
                    .help("使用 CNY、USD、HKD 等币种代码；已有交易后不能更改。"),
                Field::text(
                    "wealth-asset-market",
                    "证券市场（可选）",
                    data.market.unwrap_or_default(),
                )
                .help("例如 us、hk、cn。填写市场时需同时填写证券代码。"),
                Field::text(
                    "wealth-asset-symbol",
                    "证券代码（可选）",
                    data.symbol.unwrap_or_default(),
                ),
                Field::text(
                    "wealth-asset-note",
                    "备注（可选）",
                    data.note.unwrap_or_default(),
                ),
            ];
            fui::form(
                if editing {
                    "编辑资产"
                } else {
                    "添加资产"
                },
                fields,
                move |values| {
                    let id = id.clone();
                    Box::pin(async move {
                        let draft = AssetDraft {
                            kind: fui::required(&values, "wealth-asset-kind", "资产类别")?,
                            name: fui::required(&values, "wealth-asset-name", "资产名称")?,
                            market: optional(fui::value(&values, "wealth-asset-market")),
                            symbol: optional(fui::value(&values, "wealth-asset-symbol")),
                            currency: fui::required(&values, "wealth-asset-currency", "币种")?,
                            note: optional(fui::value(&values, "wealth-asset-note")),
                        };
                        let saved = fui::services().save_wealth_asset(id, draft).await?;
                        fui::notice("资产已保存，可记录持仓或更新估值");
                        Ok(Some(format!("/wealth/assets/{}", saved.id)))
                    })
                },
            )
        },
    )
}
fn price_editor(id: String) -> AnyElement {
    let services = fui::services();
    loaded_form(
        "更新估值",
        move || {
            let s = services.clone();
            let id = id.clone();
            Box::pin(async move {
                let a = s.wealth_asset(id.clone()).await?;
                let prices = s.wealth_prices(id).await?;
                Ok((a, prices))
            })
        },
        move |(asset, prices): (WealthAsset, Vec<naviwealth_finance::models::AssetPrice>)| {
            let price = prices
                .first()
                .map(|p| p.per_unit.to_string())
                .unwrap_or_default();
            let id = asset.id;
            let target = format!("/wealth/assets/{id}");
            fui::form(
                format!("{} · 更新估值", asset.details.name),
                vec![
                    Field::decimal("wealth-price-value", "每单位价格", price).help(
                        "只更新资产价格，不增加持仓。房产、车辆等数量为 1 时，填写完整估值。",
                    ),
                    Field::date("wealth-price-date", "估值日期", ui::today_text()),
                    Field::text("wealth-price-currency", "币种", asset.details.currency)
                        .help("应与资产估值币种一致。"),
                ],
                move |v| {
                    let id = id.clone();
                    let target = target.clone();
                    Box::pin(async move {
                        let price = fui::decimal(&v, "wealth-price-value", "每单位价格")?;
                        let date = fui::date(&v, "wealth-price-date", "估值日期")?;
                        let item = fui::services().wealth_asset(id.clone()).await?;
                        if fui::required(&v, "wealth-price-currency", "币种")?.to_uppercase()
                            != item.details.currency
                        {
                            return Err("请使用资产设定的估值币种".into());
                        }
                        fui::services()
                            .save_wealth_price(id, price, date, Some("manual".into()))
                            .await?;
                        fui::notice("估值已更新，持仓数量保持不变");
                        fui::acknowledge(
                            target.clone(),
                            format!(
                                "每单位价格已更新为 {} {}；持仓数量不变。",
                                ui::money(price),
                                item.details.currency
                            ),
                        );
                        Ok(Some(target))
                    })
                },
            )
        },
    )
}
fn fx_editor() -> AnyElement {
    fui::form(
        "补充汇率",
        vec![
            Field::text("wealth-fx-from", "原币种", "USD"),
            Field::text("wealth-fx-to", "目标币种", "CNY"),
            Field::decimal("wealth-fx-rate", "1 原币种折合目标币种", "")
                .help("例如 1 USD = 7.20 CNY，填写 7.20。手动汇率会纳入加密备份与同步。"),
            Field::date("wealth-fx-date", "汇率日期", ui::today_text()),
        ],
        move |v| {
            Box::pin(async move {
                let from = fui::required(&v, "wealth-fx-from", "原币种")?;
                let to = fui::required(&v, "wealth-fx-to", "目标币种")?;
                let rate = fui::decimal(&v, "wealth-fx-rate", "汇率")?;
                let date = fui::date(&v, "wealth-fx-date", "汇率日期")?;
                fui::services().save_wealth_fx(from, to, rate, date).await?;
                fui::notice("汇率已保存，财富估值已重新计算");
                Ok(Some("/wealth".into()))
            })
        },
    )
}
#[derive(Clone, PartialEq)]
struct OperationEditor {
    operation: Option<WealthOperation>,
    assets: Vec<WealthAsset>,
    accounts: Vec<Account>,
    prefill: Option<String>,
}
fn operation_editor(id: Option<String>, asset_prefill: Option<String>) -> AnyElement {
    operation_editor_kind(id, asset_prefill, None)
}
fn operation_editor_kind(
    id: Option<String>,
    asset_prefill: Option<String>,
    kind_prefill: Option<OperationKind>,
) -> AnyElement {
    let services = fui::services();
    let editing = id.is_some();
    loaded_form(
        if editing {
            "编辑交易"
        } else {
            "记录交易"
        },
        move || {
            let s = services.clone();
            let id = id.clone();
            let prefill = asset_prefill.clone();
            Box::pin(async move {
                let operation = match id {
                    Some(id) => Some(s.wealth_operation(id).await?),
                    None => None,
                };
                let assets = s.wealth_assets(true).await?;
                let accounts = s
                    .finance_accounts(true)
                    .await?
                    .into_iter()
                    .map(|(a, _)| a)
                    .collect();
                Ok(OperationEditor {
                    operation,
                    assets,
                    accounts,
                    prefill,
                })
            })
        },
        move |data: OperationEditor| {
            if data.assets.is_empty() {
                return view()
                    .gap_3()
                    .child(note("先建立资产，再记录期初持仓、买卖或分红。"))
                    .child(fui::action(
                        "添加资产",
                        "wealth-trade-create-asset",
                        || fui::navigate("/wealth/assets/new"),
                    ))
                    .into_element();
            }
            if data
                .accounts
                .iter()
                .all(|a| a.archived || a.side != AccountSide::Asset)
            {
                return view()
                    .gap_3()
                    .child(note("请先添加持仓账户和同币种结算账户。"))
                    .child(fui::action(
                        "添加账户",
                        "wealth-trade-create-account",
                        || fui::navigate("/wealth/accounts/new"),
                    ))
                    .into_element();
            }
            let saved_id = data.operation.as_ref().map(|o| o.id.clone());
            let old = data.operation.map(|o| o.details);
            let initial_asset = old
                .as_ref()
                .map(|d| d.asset_id.clone())
                .or(data.prefill)
                .unwrap_or_default();
            let initial_kind = old
                .as_ref()
                .map(|d| d.kind)
                .or(kind_prefill)
                .unwrap_or(OperationKind::Buy);
            let asset_field = Field::choice(
                "wealth-trade-asset",
                "资产",
                initial_asset,
                data.assets
                    .iter()
                    .filter(|a| !a.archived || old.as_ref().is_some_and(|d| d.asset_id == a.id))
                    .map(|a| {
                        (
                            a.id.clone(),
                            format!(
                                "{} · {}{}",
                                a.details.name,
                                a.details.currency,
                                if a.archived { " · 已归档" } else { "" }
                            ),
                        )
                    })
                    .collect(),
            );
            let kind = Field::choice(
                "wealth-trade-kind",
                "交易类型",
                kind_key(initial_kind),
                [
                    OperationKind::Opening,
                    OperationKind::Buy,
                    OperationKind::Sell,
                    OperationKind::Dividend,
                    OperationKind::Split,
                ]
                .into_iter()
                .map(|k| (kind_key(k).into(), k.label().into()))
                .collect(),
            );
            let kind_value = kind.value;
            let account_options: Vec<_> = data
                .accounts
                .iter()
                .filter(|a| a.side == AccountSide::Asset)
                .map(|a| {
                    (
                        a.id.clone(),
                        format!(
                            "{} · {}{}",
                            a.name,
                            a.currency,
                            if a.archived { " · 已归档" } else { "" }
                        ),
                    )
                })
                .collect();
            let fields = vec![
                asset_field,
                kind,
                Field::choice(
                    "wealth-trade-account",
                    "持仓账户",
                    old.as_ref()
                        .map(|d| d.account_id.clone())
                        .unwrap_or_default(),
                    account_options.clone(),
                )
                .help("证券、房产或其他资产归属的账户。已有交易不能换到其他持仓账户。"),
                Field::choice(
                    "wealth-trade-cash",
                    "结算账户",
                    old.as_ref()
                        .and_then(|d| d.cash_account_id.clone())
                        .unwrap_or_default(),
                    account_options,
                )
                .show_when(move || matches!(kind_value.get().as_str(), "buy" | "sell" | "dividend"))
                .help("现金收付使用此账户，须与资产估值币种一致。"),
                Field::date(
                    "wealth-trade-date",
                    "记录日期",
                    old.as_ref()
                        .map(|d| ui::ymd(d.date))
                        .unwrap_or_else(ui::today_text),
                ),
                Field::decimal(
                    "wealth-trade-quantity",
                    "数量／拆股比例",
                    old.as_ref()
                        .map(|d| d.quantity.to_string())
                        .unwrap_or_default(),
                )
                .show_when(move || kind_value.get() != "dividend")
                .help("期初与买卖填写单位数量；拆股填新股数÷旧股数，例如 1 拆 2 填 2。"),
                Field::decimal(
                    "wealth-trade-price",
                    "每单位价格／期初成本",
                    old.as_ref()
                        .map(|d| d.unit_price.to_string())
                        .unwrap_or_default(),
                )
                .show_when(move || matches!(kind_value.get().as_str(), "opening" | "buy" | "sell")),
                Field::decimal(
                    "wealth-trade-amount",
                    "分红总额",
                    old.as_ref()
                        .map(|d| d.amount.to_string())
                        .unwrap_or_default(),
                )
                .show_when(move || kind_value.get() == "dividend"),
                Field::decimal(
                    "wealth-trade-fees",
                    "费用／扣税",
                    old.as_ref()
                        .map(|d| d.fees.to_string())
                        .unwrap_or_else(|| "0".into()),
                )
                .show_when(move || matches!(kind_value.get().as_str(), "buy" | "sell" | "dividend"))
                .help("买入费用计入成本，卖出及分红扣除费用后计入现金。"),
                Field::text(
                    "wealth-trade-note",
                    "备注（可选）",
                    old.as_ref()
                        .and_then(|d| d.note.clone())
                        .unwrap_or_default(),
                ),
            ];
            fui::form(
                if editing {
                    "编辑交易"
                } else {
                    "记录交易"
                },
                fields,
                move |v| {
                    let id = saved_id.clone();
                    Box::pin(async move {
                        let kind =
                            operation_kind(&fui::required(&v, "wealth-trade-kind", "交易类型")?)?;
                        let uses_cash = matches!(
                            kind,
                            OperationKind::Buy | OperationKind::Sell | OperationKind::Dividend
                        );
                        let draft = OperationDraft {
                            kind,
                            asset_id: fui::required(&v, "wealth-trade-asset", "资产")?,
                            account_id: fui::required(&v, "wealth-trade-account", "持仓账户")?,
                            cash_account_id: if uses_cash {
                                Some(fui::required(&v, "wealth-trade-cash", "结算账户")?)
                            } else {
                                None
                            },
                            date: fui::date(&v, "wealth-trade-date", "日期")?,
                            quantity: if kind != OperationKind::Dividend {
                                fui::decimal(&v, "wealth-trade-quantity", "数量或拆股比例")?
                            } else {
                                Decimal::ZERO
                            },
                            unit_price: if matches!(
                                kind,
                                OperationKind::Opening | OperationKind::Buy | OperationKind::Sell
                            ) {
                                fui::decimal(&v, "wealth-trade-price", "每单位价格")?
                            } else {
                                Decimal::ZERO
                            },
                            fees: if uses_cash {
                                fui::decimal(&v, "wealth-trade-fees", "费用")?
                            } else {
                                Decimal::ZERO
                            },
                            amount: if kind == OperationKind::Dividend {
                                fui::decimal(&v, "wealth-trade-amount", "分红总额")?
                            } else {
                                Decimal::ZERO
                            },
                            note: optional(fui::value(&v, "wealth-trade-note")),
                        };
                        let saved = fui::services().save_wealth_operation(id, draft).await?;
                        fui::notice(format!(
                            "{}已保存，余额与持仓已更新",
                            saved.details.kind.label()
                        ));
                        Ok(Some(format!("/wealth/assets/{}", saved.details.asset_id)))
                    })
                },
            )
        },
    )
}
fn operation_detail(id: String) -> AnyElement {
    let services = fui::services();
    fui::page(
        "交易详情",
        loaded(
            move || {
                let s = services.clone();
                let id = id.clone();
                Box::pin(async move {
                    let op = s.wealth_operation(id).await?;
                    let asset = s.wealth_asset(op.details.asset_id.clone()).await?;
                    let accounts = s
                        .finance_accounts(true)
                        .await?
                        .into_iter()
                        .map(|(a, _)| a)
                        .collect::<Vec<_>>();
                    Ok((op, asset, accounts))
                })
            },
            move |(op, asset, accounts): (WealthOperation, WealthAsset, Vec<Account>)| {
                let id = op.id.clone();
                let edit_id = id.clone();
                let delete_id = id;
                let d = op.details;
                let asset_id = d.asset_id.clone();
                let account_name = |id: &str| {
                    accounts
                        .iter()
                        .find(|a| a.id == id)
                        .map(|a| a.name.clone())
                        .unwrap_or_else(|| "账户不可用".into())
                };
                let mut body = view()
                    .gap_3()
                    .child(
                        view()
                            .flex_row()
                            .items_center()
                            .gap_2()
                            .child(
                                text(format!("{} · {}", asset.details.name, d.kind.label()))
                                    .text_lg()
                                    .font_weight(FontWeight::SEMIBOLD)
                                    .flex_1(),
                            )
                            .child(fui::action("编辑", "wealth-edit-operation", move || {
                                fui::navigate(format!("/wealth/operations/{edit_id}/edit"))
                            })),
                    )
                    .child(label_value("记录日期", ui::ymd(d.date)))
                    .child(label_value("持仓账户", account_name(&d.account_id)));
                if let Some(cash) = &d.cash_account_id {
                    body = body.child(label_value("结算账户", account_name(cash)));
                }
                if d.kind == OperationKind::Split {
                    body = body
                        .child(label_value(
                            "拆股比例",
                            format!("{} 倍", d.quantity.normalize()),
                        ))
                        .child(note("拆股改变持仓数量，原始成本总额保持不变。"));
                } else if d.kind == OperationKind::Dividend {
                    body = body.child(label_value(
                        "分红总额",
                        format!("{} {}", ui::money(d.amount), op.currency),
                    ));
                } else {
                    body = body
                        .child(label_value("单位数量", d.quantity.normalize().to_string()))
                        .child(label_value(
                            "每单位价格",
                            format!("{} {}", ui::money(d.unit_price), op.currency),
                        ));
                }
                body = body
                    .child(label_value(
                        "费用／扣税",
                        format!("{} {}", ui::money(d.fees), op.currency),
                    ))
                    .child(label_value(
                        "现金影响",
                        format!("{} {}", ui::money(op.cash_amount), op.currency),
                    ));
                if let Some(memo) = d.note {
                    body = body.child(note(memo));
                }
                body=body.child(link("查看资产","持仓、成本与估值",String::new(),"wealth-operation-asset",format!("/wealth/assets/{asset_id}"))).child(destructive("删除交易","删除后将重新计算后续持仓和 FIFO 成本。若会导致后续卖出超出持仓，将保留原记录。","wealth-delete-operation",move||{let id=delete_id.clone();let asset_id=asset_id.clone();Box::pin(async move{fui::services().delete_wealth_operation(id).await?;fui::notice("交易已删除，余额与持仓已重新计算");Ok(Some(format!("/wealth/assets/{asset_id}")))})}));
                body.into_element()
            },
        ),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        finance_ui::{Feedback, Navigation},
        state::{DataVersion, Services},
    };
    use naviwealth_finance::models::{AccountCategory, NewAccount};
    use nsh_engine::{EngineConfig, Root};
    use nsh_testing::Headless;

    #[component]
    fn WealthJourney() -> impl IntoElement {
        provide_context(Services::shared());
        provide_context(DataVersion(signal(0)));
        let routes = signal(vec!["/wealth/assets/new".to_owned()]);
        let feedback = signal(String::new());
        provide_context(Navigation(routes));
        provide_context(Feedback(feedback));
        view()
            .flex_1()
            .child(dynamic(move || {
                render(
                    routes
                        .get()
                        .last()
                        .cloned()
                        .unwrap_or_else(|| "/wealth/assets".into()),
                )
            }))
            .child(text(move || feedback.get()))
    }

    #[test]
    fn native_asset_opening_price_and_correction_keep_quantity_and_return_to_live_detail() {
        crate::enable_test_mode();
        let services = Services::shared();
        let broker = services
            .runtime
            .block_on(services.create_account(
                NewAccount::custody(AccountCategory::Broker, "持仓交互账户", "CNY"),
                None,
            ))
            .unwrap();
        let mut app = Headless::start(EngineConfig::new(Root::of::<WealthJourney>())).unwrap();
        app.wait_for("id:wealth-asset-name").unwrap();
        app.type_text("id:wealth-asset-name", "海图交互资产")
            .unwrap();
        app.press("id:finance-form-save").unwrap();
        app.wait_for("text:海图交互资产").unwrap();
        app.wait_for("id:wealth-record").unwrap();
        let asset = services
            .runtime
            .block_on(services.wealth_assets(false))
            .unwrap()
            .into_iter()
            .find(|a| a.details.name == "海图交互资产")
            .unwrap();
        app.press("id:wealth-record").unwrap();
        app.wait_for("id:wealth-trade-kind").unwrap();
        app.press("id:wealth-trade-kind").unwrap();
        app.press("id:wealth-trade-kind-opening").unwrap();
        app.press("id:wealth-trade-account").unwrap();
        app.press(&format!("id:wealth-trade-account-{}", broker.id))
            .unwrap();
        app.type_text("id:wealth-trade-quantity", "2").unwrap();
        app.type_text("id:wealth-trade-price", "100").unwrap();
        app.press("id:finance-form-save").unwrap();
        app.wait_for("id:wealth-price").unwrap();
        app.wait_for("text:数量 2 · 成本 200.00 CNY").unwrap();
        for price in ["120", "130"] {
            app.press("id:wealth-price").unwrap();
            app.wait_for("id:wealth-price-value").unwrap();
            app.clear("id:wealth-price-value").unwrap();
            app.type_text("id:wealth-price-value", price).unwrap();
            app.press("id:finance-form-save").unwrap();
            app.wait_for("id:wealth-record").unwrap();
            app.wait_for("text:数量 2 · 成本 200.00 CNY").unwrap();
        }
        let snapshot = services
            .runtime
            .block_on(services.wealth_snapshot(lifeos::ids::now_secs(), "CNY".into()))
            .unwrap();
        let h = snapshot
            .holdings
            .iter()
            .find(|h| h.asset_id == asset.id)
            .unwrap();
        assert_eq!(h.quantity, Decimal::from(2));
        assert_eq!(h.market_value, Some(Decimal::from(260)));
        assert_eq!(h.cost_basis, Decimal::from(200));
        assert_eq!(
            services
                .runtime
                .block_on(services.wealth_operations(Some(asset.id.clone())))
                .unwrap()
                .len(),
            1
        );
        let operation = services
            .runtime
            .block_on(services.wealth_operations(Some(asset.id.clone())))
            .unwrap()
            .remove(0);
        app.press(&format!("id:wealth-operation-{}", operation.id))
            .unwrap();
        app.press("id:wealth-edit-operation").unwrap();
        app.wait_for("id:wealth-trade-quantity").unwrap();
        app.clear("id:wealth-trade-quantity").unwrap();
        app.type_text("id:wealth-trade-quantity", "3").unwrap();
        app.press("id:finance-form-save").unwrap();
        app.wait_for("text:数量 3 · 成本 300.00 CNY").unwrap();
        app.press(&format!("id:wealth-operation-{}", operation.id))
            .unwrap();
        app.press("id:wealth-edit-operation").unwrap();
        app.wait_for("id:wealth-trade-quantity").unwrap();
        app.clear("id:wealth-trade-quantity").unwrap();
        app.type_text("id:wealth-trade-quantity", "4").unwrap();
        app.press("id:finance-form-cancel").unwrap();
        app.wait_for("id:finance-form-discard").unwrap();
        app.press("id:finance-form-discard").unwrap();
        app.wait_for("text:3").unwrap();
        app.press("id:wealth-delete-operation").unwrap();
        app.wait_for("id:finance-confirm-submit").unwrap();
        app.press("id:finance-confirm-submit").unwrap();
        app.wait_for("id:wealth-record").unwrap();
        assert!(
            services
                .runtime
                .block_on(services.wealth_operations(Some(asset.id)))
                .unwrap()
                .is_empty()
        );
    }
}
