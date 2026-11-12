use super::*;

#[derive(Clone, PartialEq)]
struct OperationEditor {
    operation: Option<WealthOperation>,
    assets: Vec<WealthAsset>,
    accounts: Vec<Account>,
    prefill: Option<String>,
}
pub(super) fn operation_editor(id: Option<String>, asset_prefill: Option<String>) -> AnyElement {
    operation_editor_kind(id, asset_prefill, None)
}
pub(super) fn operation_editor_kind(
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
            let selected_asset = asset_field.value;
            let currency_assets = data.assets.clone();
            let currency = move || {
                currency_assets
                    .iter()
                    .find(|a| a.id == selected_asset.get())
                    .map(|a| a.details.currency.clone())
                    .unwrap_or_default()
            };
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
                Field::money(
                    "wealth-trade-price",
                    "每单位价格／期初成本",
                    old.as_ref()
                        .map(|d| d.unit_price.to_string())
                        .unwrap_or_default(),
                )
                .currency(currency.clone())
                .show_when(move || matches!(kind_value.get().as_str(), "opening" | "buy" | "sell")),
                Field::money(
                    "wealth-trade-amount",
                    "分红总额",
                    old.as_ref()
                        .map(|d| d.amount.to_string())
                        .unwrap_or_default(),
                )
                .currency(currency.clone())
                .show_when(move || kind_value.get() == "dividend"),
                Field::money(
                    "wealth-trade-fees",
                    "费用／扣税",
                    old.as_ref()
                        .map(|d| d.fees.to_string())
                        .unwrap_or_else(|| "0".into()),
                )
                .currency(currency)
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
pub(super) fn operation_detail(id: String) -> AnyElement {
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
                        format!("{} {}", ui::money_for(d.amount, &op.currency), op.currency),
                    ));
                } else {
                    body = body
                        .child(label_value("单位数量", d.quantity.normalize().to_string()))
                        .child(label_value(
                            "每单位价格",
                            format!(
                                "{} {}",
                                ui::money_for(d.unit_price, &op.currency),
                                op.currency
                            ),
                        ));
                }
                body = body
                    .child(label_value(
                        "费用／扣税",
                        format!("{} {}", ui::money_for(d.fees, &op.currency), op.currency),
                    ))
                    .child(label_value(
                        "现金影响",
                        format!(
                            "{} {}",
                            ui::money_for(op.cash_amount, &op.currency),
                            op.currency
                        ),
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
