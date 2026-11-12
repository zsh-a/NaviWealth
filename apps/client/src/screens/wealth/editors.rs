use super::*;

pub(super) fn destructive(
    label: &'static str,
    message: &'static str,
    id: &'static str,
    submit: impl Fn() -> fui::SaveFuture + 'static,
) -> AnyElement {
    fui::confirm(label.into(), message.into(), label.into(), id, submit)
}
pub(super) fn asset_editor(id: Option<String>) -> AnyElement {
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
pub(super) fn price_editor(id: String) -> AnyElement {
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
                    Field::money("wealth-price-value", "每单位价格", price).help(
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
                                ui::money_for(price, &item.details.currency),
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
pub(super) fn fx_editor() -> AnyElement {
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
